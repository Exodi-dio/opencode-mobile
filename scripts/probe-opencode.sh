#!/usr/bin/env bash
# probe-opencode.sh - R2/R6 opencode-serve probe. Runs on the CI host with
# adb on PATH, against a booted x86_64 emulator.
#
# Usage: probe-opencode.sh <api-level> <out-dir> <path-to-opencode-binary>
#
# Emits <out-dir>/opencode-<api-level>.log (asserted by
# scripts/assert-opencode-log.sh), <out-dir>/opencode-server-<api>.log (the
# full pulled stderr/stdout of the server), and <out-dir>/r2-native-<api>.txt
# (the sorted, de-duplicated native-module failure lines with a classification
# column). A crash or a timeout is a FINDING and ends in EXIT=0; a harness
# break exits non-zero with no well-formed log.
#
# The server outcome vocabulary (never aggregate these across API levels):
#   HEALTHY      - /global/health returned {"healthy":true,...}, process
#                  stayed alive >= 60 s after becoming healthy, and one more
#                  health check at that point succeeded.
#   CRASH        - the server process died before/while we waited for health;
#                  the fatal signal from logcat is preserved when visible.
#   DIED_EARLY   - healthy once, then the process died inside the 60 s window.
#   TIMEOUT      - 120 s elapsed and the process was still alive but never
#                  answered a healthy response.
set -uo pipefail

api="${1:?api level}"
out="${2:?out dir}"
bin="${3:?opencode binary}"
sha=$(sha256sum "$bin" | cut -d' ' -f1)

mkdir -p "$out"
log="$out/opencode-$api.log"
serverlog="$out/opencode-server-$api.log"
r2list="$out/r2-native-$api.txt"

# Environment facts. SDK comes from the device, API_LEVEL from the matrix;
# assert-opencode-log.sh cross-checks them, so record both faithfully.
sdk=$(adb shell "getprop ro.build.version.sdk" | tr -d '\r')
release=$(adb shell "getprop ro.build.version.release" | tr -d '\r')
abi=$(adb shell "getprop ro.product.cpu.abi" | tr -d '\r')

if [ "$sdk" != "$api" ]; then
  { echo "OPENCODE_PROBE=1 API_LEVEL=$api SDK=\"$sdk\" ABI=\"$abi\" ANDROID_RELEASE=\"$release\" BIN_SHA256=$sha"
    echo 'OPENCODE_VERDICT=HARNESS_BROKEN'
    echo "EXIT=4"
  } > "$log"
  echo "::error::device SDK $sdk != matrix API level $api"
  exit 4
fi

adb push "$bin" /data/local/tmp/opencode >/dev/null
adb shell chmod 755 /data/local/tmp/opencode

# Boot the server detached so it survives adb hangups.
pid=$(adb shell "sh -c 'nohup /data/local/tmp/opencode serve --port 4096 --hostname 127.0.0.1 > /data/local/tmp/opencode-server.log 2>&1 < /dev/null & echo \$!'" | tr -d '\r' | tail -1)

adb forward tcp:4096 tcp:4096

alive() { adb shell "kill -0 $pid" >/dev/null 2>&1; }

healthy_body=""
t0=$(date +%s%3N)
healthy=0
crashed=0
HEALTH_TIMEOUT="${OPENCODE_HEALTH_TIMEOUT_S:-120}"
t0s=$(date +%s)
while [ $(( $(date +%s) - t0s )) -lt "$HEALTH_TIMEOUT" ]; do
  if ! alive; then crashed=1; break; fi
  body=$(curl -sf --max-time 2 http://127.0.0.1:4096/global/health 2>/dev/null)
  if [ -n "$body" ] && echo "$body" | grep -q '"healthy":[[:space:]]*true'; then
    healthy=1
    healthy_body="$body"
    break
  fi
  sleep 0.25
done
t_healthy=$(( $(date +%s%3N) - t0 ))

# The server's own stderr/stdout always travels with the result.
adb pull /data/local/tmp/opencode-server.log "$serverlog" >/dev/null 2>&1 || : > "$serverlog"

# Preserve the fatal signal, if the process died. The number is the finding.
fatal_signal=0
adb logcat -b crash -d > "$out/opencode-$api-crash.txt" 2>/dev/null || : > "$out/opencode-$api-crash.txt"
if [ "$crashed" = "1" ] || ! alive; then
  sig=$(grep -oE 'Fatal signal [0-9]+' "$out/opencode-$api-crash.txt" | head -1 | grep -oE '[0-9]+')
  [ -n "$sig" ] && fatal_signal="$sig"
fi

healthy_60s="no"
if [ "$healthy" = "1" ]; then
  # Stay alive at least 60 s after becoming healthy: poll every 10 s, and
  # confirm health once more when the 60 s have elapsed.
  stayed=1
  ALIVE_WINDOW="${OPENCODE_ALIVE_WINDOW_S:-60}"
  end=$(( $(date +%s) + $ALIVE_WINDOW ))
  while [ $(( $(date +%s) )) -lt "$end" ]; do
    sleep 10
    if ! alive; then stayed=0; break; fi
  done
  if [ "$stayed" = "1" ]; then
    body2=$(curl -sf --max-time 2 http://127.0.0.1:4096/global/health 2>/dev/null)
    if [ -n "$body2" ] && echo "$body2" | grep -q '"healthy":[[:space:]]*true'; then
      healthy_60s="yes"
    else
      stayed=0
    fi
  fi
  if [ "$stayed" = "0" ]; then
    verdict="DIED_EARLY"
  else
    verdict="HEALTHY"
  fi
else
  if [ "$crashed" = "1" ]; then
    verdict="CRASH"
  else
    if alive; then
      verdict="TIMEOUT"
    else
      verdict="CRASH"
    fi
  fi
fi
[ "$healthy" != "1" ] && t_healthy=-1

# R2 enumeration: every native-module load failure in the server log,
# sorted and de-duplicated, classified from observed behaviour: with a
# HEALTHY verdict the server survived them, so they are optional; otherwise
# they are load-bearing. Also watch for the ripgrep platform-table hole the
# plan flagged ("Failed to spawn ripgrep" / platform not supported).
{
  grep -oE 'Failed to load native binding[^"]*|Cannot find module[^"]*|Cannot find native[^"]*|\.node[^" ]*|[Ee][Ll][Ff][^"]*|dlopen[^"]*|Failed to spawn ripgrep[^"]*|ripgrep.*not supported[^"]*|does not support.*platform[^"]*' \
    "$serverlog" 2>/dev/null | sort -u | while read -r line; do
      mode=optional
      [ "$verdict" != "HEALTHY" ] && mode=load-bearing
      printf '%s\t%s\n' "$mode" "$line"
    done
} > "$r2list"

r2count=$(wc -l < "$r2list" | tr -d ' ')

adb shell "kill $pid" >/dev/null 2>&1 || true
adb forward --remove tcp:4096 tcp:4096 >/dev/null 2>&1 || true
abstract() { head -c 200 "$1" | tr '\n' ' '; }
{
  echo "OPENCODE_PROBE=1 API_LEVEL=$api SDK=\"$sdk\" ABI=\"$abi\" ANDROID_RELEASE=\"$release\" BIN_SHA256=$sha"
  echo "PID=$pid"
  echo "SERVER_LOG_LINES=$(wc -l < "$serverlog" | tr -d ' ')"
  echo "TIME_TO_HEALTHY_MS=$t_healthy"
  echo "HEALTHY_BODY=\"$(echo "$healthy_body" | head -c 160)\""
  echo "HEALTHY_AFTER_60S=$healthy_60s"
  echo "FATAL_SIGNAL=$fatal_signal"
  echo "R2_FAILURES=$r2count"
  n=0
  while IFS= read -r l; do n=$((n+1)); [ "$n" -le 8 ] && echo "R2[$n]=\"$l\""; done < "$r2list"
  echo "OPENCODE_VERDICT=$verdict"
  echo "EXIT=0"
} > "$log"

echo "verdict=$verdict t_healthy=$t_healthy r2=$r2count signal=$fatal_signal"
