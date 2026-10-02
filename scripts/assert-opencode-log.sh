#!/usr/bin/env bash
# assert-opencode-log.sh - the red/green distinction for R2/R6, exactly as
# assert-bun-log.sh / assert-pty-log.sh own theirs.
#
#   A probe that CRASHED, TIMED OUT or DIED_EARLY is a FINDING and is
#   ACCEPTED here. A log that is malformed - wrong API level, no verdict, a
#   missing measurement, a verdict contradicting its fields, or no server log
#   at all - is a HARNESS FAILURE and is rejected.
#
# Usage: assert-opencode-log.sh <log> <api-level> [server-log]
set -uo pipefail

log="${1:?usage: assert-opencode-log.sh <log> <api-level> [server-log]}"
api="${2:?usage}"
serverlog="${3:-}"

fail() { echo "::error::opencode-probe log $log: $*" >&2; exit 1; }

[ -s "$log" ] || fail "log is missing or empty"
case "$api" in '' | *[!0-9]*) fail "api level '$api' not an integer" ;; esac

grep -qE "^OPENCODE_PROBE=1 API_LEVEL=${api}( |\$)" "$log" || fail "no OPENCODE_PROBE header for API level $api"
grep -qE "^OPENCODE_PROBE=1 .*( |\$)SDK=\"${api}\"( |\$)" "$log" || fail "device SDK is not $api"
if grep -qE '(^|[[:space:]])API_LEVEL_MISMATCH=' "$log"; then fail "device recorded API_LEVEL_MISMATCH"; fi

verdicts=$(grep -cE '^OPENCODE_VERDICT=' "$log" || true)
[ "$verdicts" -eq 1 ] || fail "expected exactly one OPENCODE_VERDICT, found $verdicts"
verdict=$(grep -E '^OPENCODE_VERDICT=' "$log" | cut -d= -f2)
case "$verdict" in
  HEALTHY | CRASH | DIED_EARLY | TIMEOUT) ;;
  *) fail "unknown verdict '$verdict' (HARNESS_BROKEN is never a result)" ;;
esac

grep -qE '^EXIT=0' "$log" || fail "EXIT is not 0"
tms=$(grep -oE 'TIME_TO_HEALTHY_MS=[^ ]+' "$log" | head -1 | cut -d= -f2)
[ -n "$tms" ] || fail "no TIME_TO_HEALTHY_MS"
grep -qE '^HEALTHY_AFTER_60S=(yes|no)' "$log" || fail "no HEALTHY_AFTER_60S"
grep -qE '^FATAL_SIGNAL=[0-9]+' "$log" || fail "no FATAL_SIGNAL"
grep -qE '^R2_FAILURES=[0-9]+' "$log" || fail "no R2_FAILURES"
r2=$(grep -oE '^R2_FAILURES=[0-9]+' "$log" | cut -d= -f2)
inline=$(grep -cE '^R2\[[0-9]+\]=' "$log" || true)
[ "$r2" -gt 8 ] && cap=8 || cap=$r2
[ "$inline" -eq "$cap" ] || fail "R2_FAILURES=$r2 but $inline R2[n] lines"

case "$verdict" in
  HEALTHY)
    [ "$tms" != "-1" ] || fail "HEALTHY with TIME_TO_HEALTHY_MS=-1"
    grep -qE '^HEALTHY_AFTER_60S=yes' "$log" || fail "HEALTHY but the process died inside the 60 s window"
    grep -qE '^HEALTHY_BODY="[^"]*"healthy":' "$log" || fail "HEALTHY but HEALTHY_BODY has no healthy JSON"
    ;;
  CRASH)
    [ "$tms" = "-1" ] || fail "CRASH with a health timestamp"
    ;;
  DIED_EARLY)
    [ "$tms" != "-1" ] || fail "DIED_EARLY with no health timestamp"
    grep -qE '^HEALTHY_AFTER_60S=no' "$log" || fail "DIED_EARLY but HEALTHY_AFTER_60S=yes"
    ;;
  TIMEOUT)
    [ "$tms" = "-1" ] || fail "TIMEOUT with a health timestamp"
    fs=$(grep -oE '^FATAL_SIGNAL=[0-9]+' "$log" | cut -d= -f2)
    [ "$fs" = "0" ] || fail "TIMEOUT with a signal"
    ;;
  esac

if [ -n "$serverlog" ]; then
  [ -s "$serverlog" ] || fail "server log $serverlog missing/empty (a probe that captures no server output has captured nothing)"
fi

echo "PASS: $log (verdict=$verdict)"
