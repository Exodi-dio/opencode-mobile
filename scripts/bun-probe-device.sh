#!/system/bin/sh
# Runs ON the Android device (POSIX sh; Android's /system/bin/sh).
#
# Emits machine-readable lines and NEVER aborts on a probe failure: a crashed
# Bun probe is a finding, and the remaining probes must still run. The workflow
# appends the final EXIT= line after this script returns.
#
# Env supplied by the caller: API_LEVEL. BUN defaults to /data/local/tmp/bun.
#
# Every measurement line emitted below is REQUIRED by scripts/assert-bun-log.sh
# (exactly one occurrence, well-formed value). A probe that produced no value
# must therefore make the log REJECTED, not silently green: `RSS_VMHWM_KB` is
# reachable as `unavailable` (an unreadable /proc/<pid>/status), and a log with
# no JIT observation at all would otherwise be an accepted "result".
#
# This file is also executed by the no-emulator harness-self-test on the CI
# runner against a stub `bun`, so it must stay POSIX and must not require any
# Android-only utility to reach its verdict lines.

BUN="${BUN:-/data/local/tmp/bun}"
API_LEVEL="${API_LEVEL:-unknown}"
cd /data/local/tmp 2>/dev/null || true

# Single-line, quote-safe form of a command's output, for OBSERVED= fields.
escape() {
  printf '%s' "$1" | tr -d '\r' | sed -n '1p' | sed 's/"/'"'"'/g'
}

# The COMPLETE output of a command, one record per line, prefixed
# RAW[<label>][<n>]. A truncated first line is a lossy summary of a crash
# report, so the full text is always preserved separately. The prefix is
# deliberately NOT `PROBE=`: assert-bun-log.sh counts lines starting with
# `PROBE=` as probes, and raw records would be counted as extra probes.
raw_block() {
  rlabel="$1"
  rbody="$2"
  [ -n "$rbody" ] || return 0
  printf '%s\n' "$rbody" | awk -v p="RAW[$rlabel]" '{ printf "%s[%d] %s\n", p, NR, $0 }'
}

# --- environment header ------------------------------------------------------
release=$(getprop ro.build.version.release 2>/dev/null)
sdk=$(getprop ro.build.version.sdk 2>/dev/null)
abi=$(getprop ro.product.cpu.abi 2>/dev/null)
if [ -z "$abi" ]; then
  # getprop is absent when the harness-self-test runs this script on the CI
  # runner with a stub bun. uname -m is the same fact from a different source,
  # and assert-bun-log.sh requires x86_64 either way: this harness only ever
  # executes the x86_64-android binary.
  abi=$(uname -m 2>/dev/null)
fi
[ -n "$abi" ] || abi=unavailable
selinux=$(cat /proc/self/attr/current 2>/dev/null)
[ -n "$selinux" ] || selinux=unavailable
if [ -d /system/etc/security/cacerts ]; then
  castore_dir=present
  castore_count=$(ls /system/etc/security/cacerts 2>/dev/null | wc -l | tr -d ' ')
else
  castore_dir=absent
  castore_count=0
fi
# API_LEVEL comes from the workflow matrix; SDK comes from the device. If they
# disagree, this leg booted the wrong system image and every number below would
# be filed under the wrong API level, so say so on the face of the log instead of
# labelling it with the requested level.
mismatch=""
if [ "$API_LEVEL" != "unknown" ] && [ -n "$sdk" ] && [ "$API_LEVEL" != "$sdk" ]; then
  mismatch=" API_LEVEL_MISMATCH=${API_LEVEL}-vs-${sdk}"
fi
echo "BUNPROBE=1 API_LEVEL=$API_LEVEL ANDROID_RELEASE=\"$release\" SDK=\"$sdk\" ABI=\"$abi\" SELINUX_CTX=\"$selinux\" CASTORE_DIR=$castore_dir CASTORE_COUNT=$castore_count BUN=$BUN$mismatch"

if [ ! -x "$BUN" ]; then
  echo "BUN_PROBE_VERDICT=HARNESS_BROKEN MISSING_BINARY=$BUN"
  exit 4
fi

# --- timing primitive --------------------------------------------------------
# toybox date(1) does not implement %N on most Android releases, so detect the
# clock instead of assuming it, and record which one was used: it sets the
# resolution of every timing figure below. Note that reading it costs a fork,
# which is why a harness floor is measured and published below.
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
#
# RAW_OUT holds the last probe's COMPLETE raw output, so the classification steps
# below can read it instead of re-running the probe.
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
  raw_block "$name" "$out"
  RAW_OUT="$out"
}

# --- the seven probes -------------------------------------------------------
probe version       "1.4.2"       30 "$BUN" --version
probe js-engine     "2"           30 "$BUN" -e 'console.log(1+1)'
# The loop accumulates and prints an observable value. The brief's bare
# `for(...){}` has no side effect and a JIT may delete it entirely, which would
# let the probe pass without executing the loop - a vacuous assertion. Printing
# `s` makes the loop unremovable. The 30 s budget and the `done` marker are the
# brief's.
probe engine-usable "done"        30 "$BUN" -e 'let s=0;for(let i=0;i<3e7;i++){s=(s+i)|0}console.log("done",s)'
# R3, primary host. A DNS-only control is resolved in the SAME process
# immediately before the fetch, so `tls=FAIL` is attributable: DNS=ENOTFOUND is a
# resolver failure (never reaches certificate validation) and DNS=ok is a CA/TLS
# failure, which would be a real R3 finding. A catch is deliberate: without it an
# unhandled rejection reports nothing useful and may hang.
probe tls           "200"         30 "$BUN" -e 'const host="api.github.com";let D="unavailable";try{const dns=require("dns");await new Promise((res,rej)=>dns.lookup(host,(e,a)=>e?rej(e):res(a)));D="ok"}catch(e){D=(e&&e.code==="ENOTFOUND")?"ENOTFOUND":"unavailable"}try{const r=await fetch("https://"+host);console.log("DNS="+D+" STATUS="+r.status)}catch(e){console.log("DNS="+D+" FETCH_ERROR: "+(e&&e.message));process.exit(9)}'
# Captured before the next probe overwrites RAW_OUT.
tls_out="$RAW_OUT"
# R3, second independent host (different name, different certificate chain and
# CDN). One host's success cannot establish that name resolution, the handshake
# and certificate validation work in general.
probe tls-host2     "200"         30 "$BUN" -e 'try{const r=await fetch("https://example.com/");console.log("STATUS="+r.status)}catch(e){console.log("FETCH_ERROR: "+(e&&e.message));process.exit(9)}'
# R3, negative control: a certificate that must NOT validate. A `200` here would
# be worse than no result - it would mean certificate validation is off, or that
# the endpoint is trusted for a reason we do not understand. PASS here means the
# request FAILED, which is the expected outcome; the verdict line below says
# which failure it was, so a DNS failure cannot masquerade as a rejection.
probe tls-badcert   "FETCH_ERROR" 30 "$BUN" -e 'try{const r=await fetch("https://self-signed.badssl.com/");console.log("UNEXPECTED_STATUS:"+r.status)}catch(e){const c=(e&&e.cause)?e.cause:e;console.log("FETCH_ERROR: "+((e&&e.message)||"unknown")+" code="+((c&&c.code)||(c&&c.message)||"unknown"))}'
badcert_out="$RAW_OUT"
probe platform      "android x64" 30 "$BUN" -e 'console.log(process.platform, process.arch)'

# --- R3 classification ------------------------------------------------------
tls_dns=$(printf '%s\n' "$tls_out" | sed -n 's/^DNS=\([A-Za-z_]*\).*/\1/p' | head -1)
[ -n "$tls_dns" ] || tls_dns=unavailable
echo "TLS_DNS=$tls_dns TLS_DNS_RULE=\"a tls probe whose observation starts DNS=ENOTFOUND never reached certificate validation (resolver failure); a tls failure with DNS=ok DID reach it and is an R3 finding; DNS=unavailable means the process died before the DNS control printed\""

# A refusal is established BEHAVIOURALLY - the same network accepts a valid
# certificate (tls-host2) and refuses this one - and the message only says which
# refusal it was. A generic "fetch failed" with no certificate in it is still a
# refusal; it is recorded as such rather than being called a certificate error
# the evidence does not show.
case "$badcert_out" in
  *UNEXPECTED_STATUS*) bcv=NOT_REJECTED ;;
  *ENOTFOUND*)         bcv=DNS_UNRESOLVED ;;
  *CERT*|*SELF_SIGNED*|*VERIF*|*ertificate*|*erify*|*SSL*|*ssl*|*self.signed*) bcv=CERT_REJECTED ;;
  *FETCH_ERROR*)       bcv=REFUSED_UNCLASSIFIED ;;
  *)                   bcv=NO_TLS_RESULT ;;
esac
echo "TLS_BADCERT_VERDICT=$bcv TLS_BADCERT_ENDPOINT=https://self-signed.badssl.com/ TLS_BADCERT_RULE=\"the untrusted certificate must be REFUSED: NOT_REJECTED means it was accepted, which would mean certificate validation is off or the endpoint is trusted for an unknown reason; CERT_REJECTED means the refusal names a certificate, so validation is ON; REFUSED_UNCLASSIFIED means the request failed without naming a reason - combined with tls-host2 PASS on the same network (valid certificate accepted, untrusted certificate refused) that still establishes that validation is ON; DNS_UNRESOLVED and NO_TLS_RESULT prove nothing either way\""

# --- cold start: median of 5 runs of `bun --version` -------------------------
# Harness floor FIRST: the same bracketing with nothing between the two clock
# reads. The measured interval for `bun --version` includes the cost of taking
# its own closing timestamp (two forks of date/awk), so a raw median that is not
# distinguishable from this floor is a measurement floor, not Bun's startup.
fsamples=""
i=0
while [ "$i" -lt 5 ]; do
  a=$(now_ms); b=$(now_ms)
  fsamples="$fsamples $((b - a))"
  i=$((i + 1))
done
fmedian=$(printf '%s\n' $fsamples | sort -n | sed -n '3p')

samples=""
i=0
while [ "$i" -lt 5 ]; do
  t0=$(now_ms); "$BUN" --version >/dev/null 2>&1; t1=$(now_ms)
  samples="$samples $((t1 - t0))"
  i=$((i + 1))
done
median=$(printf '%s\n' $samples | sort -n | sed -n '3p')
net=$((median - fmedian))
if [ "$net" -le 0 ]; then
  floor_status=INDISTINGUISHABLE_FROM_HARNESS_FLOOR
else
  floor_status=ABOVE_HARNESS_FLOOR
fi
echo "COLD_START_MS_SAMPLES=\"$samples\" COLD_START_MS_MEDIAN=$median COLD_START_MS_NET_OF_FLOOR=$net COLD_START_HARNESS_FLOOR_MS_SAMPLES=\"$fsamples\" COLD_START_HARNESS_FLOOR_MS=$fmedian COLD_START_FLOOR_STATUS=$floor_status COLD_START_CLOCK=$CLOCK COLD_START_N=5"

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
raw_block version-line "$ver"
raw_block revision "$rev"
echo "BUN_VERSION_LINE=\"$(escape "$ver")\" BUN_REVISION=\"$(escape "$rev")\""

# --- JIT: a control process, then the hot-loop process ----------------------
# The observation is read twice, from two different Bun processes:
#
#   JIT_MAPS_CONTROL   a Bun process that ONLY reads /proc/self/maps
#   JIT_MAPS_OBSERVED  the Bun process that ran the hot loop
#
# JavaScriptCore reserves its JIT code region when the code cache is
# constructed, so a region named [anon:JSJITCode] can exist in a process that
# never compiled anything hot. Presence in the loop process alone therefore does
# not show that the loop was compiled; presence in the control process means the
# region is there anyway. Both are read from inside the process, so neither is a
# timing inference.
maps_control=$("$BUN" -e 'const tag="JIT_CONTROL";const lines=require("fs").readFileSync("/proc/self/maps","utf8").split("\n");let anon=0,file=0,wx=0,sample="";for(const l of lines){if(!l)continue;const p=l.trim().split(/\s+/);const perms=p[1]||"";if(perms.indexOf("x")<0)continue;const path=p.length>5?p.slice(5).join(" "):"";if(path===""||path.charAt(0)==="["){anon++;if(sample==="")sample=l.trim()}else{file++}if(perms.indexOf("w")>=0)wx++}console.log(tag+" exec_anon="+anon+" exec_file="+file+" w_and_x="+wx+" sample="+sample)' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  maps_control="UNREADABLE(rc=$rc): $(escape "$maps_control")"
fi
raw_block jit-control "$maps_control"
echo "JIT_MAPS_CONTROL=\"$(escape "$maps_control")\""

maps=$("$BUN" -e 'function hot(n){let s=0;for(let i=0;i<n;i++){s=(s+i*3)|0}return s}const h=hot(3e7);const lines=require("fs").readFileSync("/proc/self/maps","utf8").split("\n");let anon=0,file=0,wx=0,sample="";for(const l of lines){if(!l)continue;const p=l.trim().split(/\s+/);const perms=p[1]||"";if(perms.indexOf("x")<0)continue;const path=p.length>5?p.slice(5).join(" "):"";if(path===""||path.charAt(0)==="["){anon++;if(sample==="")sample=l.trim()}else{file++}if(perms.indexOf("w")>=0)wx++}console.log("hot="+h+" exec_anon="+anon+" exec_file="+file+" w_and_x="+wx+" sample="+sample)' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  maps="UNREADABLE(rc=$rc): $(escape "$maps")"
fi
raw_block jit-loop "$maps"
echo "JIT_MAPS_OBSERVED=\"$(escape "$maps")\""

# Classification of one maps observation. JSJITCode wins over exec_anon=0:
# a region that is present is present, whatever the counter says.
jit_state() {
  case "$1" in
    *JSJITCode*) printf 'present' ;;
    *exec_anon=0*) printf 'absent' ;;
    *) printf 'unknown' ;;
  esac
}
loop_state=$(jit_state "$maps")
control_state=$(jit_state "$maps_control")

#   loop    control   signal        why
#   present absent    POSITIVE      the region appears only in the process that
#                                   ran the hot loop, so it is attributable
#   present present   INCONCLUSIVE  the region exists with no hot loop at all,
#                                   so presence does not show the loop compiled
#   absent  *          NONE          a clean read found no executable anonymous
#                                   mapping in the loop process: a confident no
#   *       *          INCONCLUSIVE  unreadable or unrecognised observation
if [ "$loop_state" = present ] && [ "$control_state" = absent ]; then
  jit_signal=POSITIVE
elif [ "$loop_state" = absent ]; then
  jit_signal=NONE
else
  jit_signal=INCONCLUSIVE
fi
if [ "$jit_signal" = "POSITIVE" ]; then
  jit_determination=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN
else
  jit_determination=OPEN
fi
echo "JIT_SIGNAL=$jit_signal JIT_DETERMINATION=$jit_determination JIT_LOOP_STATE=$loop_state JIT_CONTROL_STATE=$control_state JIT_RULE=\"JIT_SIGNAL is derived, never hardcoded: POSITIVE requires [anon:JSJITCode] in the hot-loop process AND its absence in a control process that ran no hot loop; a control process that also shows the region yields INCONCLUSIVE because JSC reserves that region at code-cache construction; NONE requires a clean read with exec_anon=0; every other shape is INCONCLUSIVE. JIT_DETERMINATION is OPEN unless the signal is POSITIVE. The signal is measured in the adb shell SELinux domain, so W^X in untrusted_app_* stays unverified; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md\""

# --- verdict -----------------------------------------------------------------
# COMPLETE means "every probe was attempted and its outcome recorded". It says
# nothing about whether Bun worked. A crashed probe is still COMPLETE.
echo "BUN_PROBE_VERDICT=COMPLETE"
exit 0
