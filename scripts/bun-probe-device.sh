#!/system/bin/sh
# Runs ON the Android device (POSIX sh; Android's /system/bin/sh).
#
# Emits machine-readable lines and NEVER aborts on a probe failure: a crashed
# Bun probe is a finding, and the remaining probes must still run. The workflow
# appends the final EXIT= line after this script returns.
#
# Env supplied by the caller: API_LEVEL. BUN defaults to /data/local/tmp/bun.
#
# This file is also executed by the no-emulator harness-self-test on the CI
# runner against a stub `bun`, so it must stay POSIX and must not require any
# Android-only utility to reach its verdict lines.

BUN="${BUN:-/data/local/tmp/bun}"
API_LEVEL="${API_LEVEL:-unknown}"
cd /data/local/tmp 2>/dev/null || true

escape() {
  printf '%s' "$1" | tr -d '\r' | sed -n '1p' | sed 's/"/'"'"'/g'
}

# --- environment header ------------------------------------------------------
release=$(getprop ro.build.version.release 2>/dev/null)
sdk=$(getprop ro.build.version.sdk 2>/dev/null)
abi=$(getprop ro.product.cpu.abi 2>/dev/null)
selinux=$(cat /proc/self/attr/current 2>/dev/null)
[ -n "$selinux" ] || selinux=unavailable
if [ -d /system/etc/security/cacerts ]; then
  castore_dir=present
  castore_count=$(ls /system/etc/security/cacerts 2>/dev/null | wc -l | tr -d ' ')
else
  castore_dir=absent
  castore_count=0
fi
echo "BUNPROBE=1 API_LEVEL=$API_LEVEL ANDROID_RELEASE=\"$release\" SDK=\"$sdk\" ABI=\"$abi\" SELINUX_CTX=\"$selinux\" CASTORE_DIR=$castore_dir CASTORE_COUNT=$castore_count BUN=$BUN"

if [ ! -x "$BUN" ]; then
  echo "BUN_PROBE_VERDICT=HARNESS_BROKEN MISSING_BINARY=$BUN"
  exit 4
fi

# --- timing primitive --------------------------------------------------------
# toybox date(1) does not implement %N on most Android releases, so detect the
# clock instead of assuming it, and record which one was used: it sets the
# resolution of every timing figure below.
CLOCK=proc-uptime-cs
date_probe=$(date +%s%N 2>/dev/null)
if printf '%s' "$date_probe" | grep -Eq '^[0-9]+$' && [ "${#date_probe}" -ge 13 ]; then
  CLOCK=date-ns
  now_ms() { date +%s%N | awk '{printf "%d", $1/1000000}'; }
else
  now_ms() { awk '{printf "%d", $1*10}' /proc/uptime; }
fi

# toybox provides timeout(1). Fall back to unbounded execution if it is absent,
# so a missing utility cannot silently turn every probe into a failure.
if ! command -v timeout >/dev/null 2>&1; then
  echo "WARNING=no-timeout-on-device PROBES=UNBOUNDED"
  timeout() { shift; "$@"; }
fi

# --- probe runner ------------------------------------------------------------
# probe <name> <expected-substring> <timeout-seconds> <cmd...>
probe() {
  name="$1"; expect="$2"; budget="$3"; shift 3
  t0=$(now_ms)
  out=$(timeout "$budget" "$@" 2>&1)
  rc=$?
  t1=$(now_ms)
  ms=$((t1 - t0))
  signal=0
  if [ "$rc" -gt 128 ]; then
    signal=$((rc - 128))
    status=CRASH
  elif [ "$rc" -eq 124 ]; then
    status=TIMEOUT
  elif [ "$rc" -ne 0 ]; then
    status=FAIL
  else
    status=PASS
  fi
  if [ "$status" = "PASS" ] && [ -n "$expect" ]; then
    printf '%s' "$out" | grep -qF "$expect" || status=FAIL
  fi
  obs=$(escape "$out")
  printf 'PROBE=%s STATUS=%s EXIT=%s SIGNAL=%s ELAPSED_MS=%s EXPECTED="%s" OBSERVED="%s"\n' \
    "$name" "$status" "$rc" "$signal" "$ms" "$expect" "$obs"
}

# --- the five probes ---------------------------------------------------------
probe version       "1.4.2"       30 "$BUN" --version
probe js-engine     "2"           30 "$BUN" -e 'console.log(1+1)'
# The loop accumulates and prints an observable value. The brief's bare
# `for(...){}` has no side effect and a JIT may delete it entirely, which would
# let the probe pass without executing the loop - a vacuous assertion. Printing
# `s` makes the loop unremovable. The 30 s budget and the `done` marker are the
# brief's.
probe engine-usable "done"        30 "$BUN" -e 'let s=0;for(let i=0;i<3e7;i++){s=(s+i)|0}console.log("done",s)'
# R3. A catch is deliberate: without it an unhandled rejection reports nothing
# useful and may hang. FETCH_ERROR is the R3 finding and is preserved verbatim.
probe tls           "200"         30 "$BUN" -e 'try{const r=await fetch("https://api.github.com");console.log(r.status)}catch(e){console.log("FETCH_ERROR: "+(e&&e.message));process.exit(9)}'
probe platform      "android x64" 30 "$BUN" -e 'console.log(process.platform, process.arch)'

# --- cold start: median of 5 runs of `bun --version` -------------------------
samples=""
i=0
while [ "$i" -lt 5 ]; do
  t0=$(now_ms); "$BUN" --version >/dev/null 2>&1; t1=$(now_ms)
  samples="$samples $((t1 - t0))"
  i=$((i + 1))
done
median=$(printf '%s\n' $samples | sort -n | sed -n '3p')
echo "COLD_START_MS_SAMPLES=\"$samples\" COLD_START_MS_MEDIAN=$median COLD_START_CLOCK=$CLOCK COLD_START_N=5"

# --- peak RSS (VmHWM) of a bun process while it sleeps -----------------------
"$BUN" -e 'await new Promise(r=>setTimeout(r,8000))' >/dev/null 2>&1 &
pid=$!
sleep 3
rss=unavailable
if [ -r "/proc/$pid/status" ]; then
  rss=$(grep '^VmHWM:' "/proc/$pid/status" | awk '{print $2}')
fi
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
echo "RSS_VMHWM_KB=${rss:-unavailable} RSS_SOURCE=/proc/<pid>/status RSS_NOTE=\"peak RSS of a sleeping bun process, sampled ~3s after start\""

# --- R6/R1 build strings, recorded as facts ----------------------------------
ver=$("$BUN" --version 2>&1); rc=$?
[ "$rc" -eq 0 ] || ver="UNREADABLE(rc=$rc)"
rev=$("$BUN" --revision 2>&1); rc=$?
[ "$rc" -eq 0 ] || rev="UNSUPPORTED(rc=$rc)"
echo "BUN_VERSION_LINE=\"$(escape "$ver")\" BUN_REVISION=\"$(escape "$rev")\""

# --- JIT: an observation, explicitly NOT a determination ---------------------
# A hot loop encourages any JIT to map executable pages, then /proc/self/maps is
# read from inside the process. Executable anonymous mappings are consistent
# with runtime code generation, but they are NOT proof: they can come from
# Bionic/JSC trampolines, and the `shell` domain's execmem policy is not the app
# domain's. This is why JIT_DETERMINATION stays OPEN; see docs/spikes/r1-bun.md.
maps=$("$BUN" -e 'function hot(n){let s=0;for(let i=0;i<n;i++){s=(s+i*3)|0}return s}const h=hot(3e7);const lines=require("fs").readFileSync("/proc/self/maps","utf8").split("\n");let anon=0,file=0,wx=0,sample="";for(const l of lines){if(!l)continue;const p=l.trim().split(/\s+/);const perms=p[1]||"";if(perms.indexOf("x")<0)continue;const path=p.length>5?p.slice(5).join(" "):"";if(path===""||path.charAt(0)==="["){anon++;if(sample==="")sample=l.trim()}else{file++}if(perms.indexOf("w")>=0)wx++}console.log("hot="+h+" exec_anon="+anon+" exec_file="+file+" w_and_x="+wx+" sample="+sample)' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  maps="UNREADABLE(rc=$rc): $(escape "$maps")"
fi
echo "JIT_MAPS_OBSERVED=\"$(escape "$maps")\""
echo "JIT_DETERMINATION=OPEN JIT_BASIS=\"no positive in-binary signal settles whether JIT is active on Android; PR oven-sh/bun#29675 states Android has no upstream runtime test coverage and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md\""

# --- verdict -----------------------------------------------------------------
# COMPLETE means "every probe was attempted and its outcome recorded". It says
# nothing about whether Bun worked. A crashed probe is still COMPLETE.
echo "BUN_PROBE_VERDICT=COMPLETE"
exit 0
