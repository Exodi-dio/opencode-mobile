#!/usr/bin/env bash
# Assert that a Bun Android probe log is a well-formed *result*.
#
# This script owns the red/green distinction for the R1/R3/R6 probe, exactly as
# assert-pty-log.sh does for R4:
#
#   A probe that CRASHED, FAILED or TIMED OUT is a FINDING and is ACCEPTED here.
#   A log that is malformed - wrong API level, missing or duplicated probes, no
#   verdict, a verdict that contradicts the exit code, a missing measurement, no
#   output at all - is a HARNESS FAILURE and is rejected.
#
# A green workflow therefore means "the harness ran and recorded what happened",
# never "Bun worked". The harness-self-test job in m0-bun.yml proves both halves
# of that contract against synthetic fixtures, so these assertions cannot
# silently go vacuous.
#
# Usage: assert-bun-log.sh <log> <api-level>
set -euo pipefail

log="${1:?usage: assert-bun-log.sh <log> <api-level>}"
api="${2:?usage: assert-bun-log.sh <log> <api-level>}"

fail() {
  echo "::error::bun-probe log $log: $*" >&2
  exit 1
}

[ -s "$log" ] || fail "log is missing or empty"

# The API level is interpolated into several patterns below, so it must be a
# plain integer before it is trusted as one.
case "$api" in
  '' | *[!0-9]*) fail "requested api level '$api' is not a plain integer" ;;
esac

# 1. The log must be from the API level it claims to be.
grep -qE "^BUNPROBE=1 API_LEVEL=${api}( |\$)" "$log" ||
  fail "no BUNPROBE header for API level $api"

# 1b. The API level is host-supplied (the workflow matrix) and the device's own
#     SDK is read separately with getprop. A leg booted with the wrong system
#     image would be labelled with the matrix level and pass everything else,
#     so the two must agree - both here and in the device's own
#     API_LEVEL_MISMATCH record.
grep -qE "^BUNPROBE=1 .*( |\$)SDK=\"${api}\"( |\$)" "$log" ||
  fail "the device's own SDK is not $api (API_LEVEL comes from the matrix, SDK from getprop; a mismatch means the wrong system image)"
if grep -qE '(^|[[:space:]])API_LEVEL_MISMATCH=[^ ]+' "$log"; then
  fail "the device recorded $(grep -oE '(^|[[:space:]])API_LEVEL_MISMATCH=[^ ]+' "$log" | tr -d ' ') - the leg ran on a different API level than the matrix asked for"
fi

# 2. Exactly one verdict, and it must be COMPLETE. HARNESS_BROKEN means the
#    probe never ran; that is not a result and never passes.
verdicts=$(grep -cE '^BUN_PROBE_VERDICT=' "$log" || true)
[ "$verdicts" -eq 1 ] || fail "expected exactly one BUN_PROBE_VERDICT line, found $verdicts"
verdict=$(grep -E '^BUN_PROBE_VERDICT=' "$log" | cut -d= -f2)
[ "$verdict" = "COMPLETE" ] ||
  fail "verdict is '$verdict', not COMPLETE; this log is not a result"

# 3. Exactly one outer EXIT line (appended by the workflow), and it must agree
#    with the COMPLETE verdict. A COMPLETE log that exited non-zero is a
#    contradiction: the probe script did not actually finish.
exits=$(grep -cE '^EXIT=[0-9]+$' "$log" || true)
[ "$exits" -eq 1 ] || fail "expected exactly one EXIT= line, found $exits"
exit_code=$(grep -E '^EXIT=[0-9]+$' "$log" | cut -d= -f2)
[ "$exit_code" -eq 0 ] ||
  fail "verdict COMPLETE contradicts EXIT=$exit_code (the probe script did not finish)"

# 4. Exactly the expected probes, each exactly once. A missing probe is a
#    harness failure; absence of evidence is never a result.
expected_probes="version js-engine engine-usable tls tls-host2 tls-badcert platform"
for name in $expected_probes; do
  count=$(grep -cE "^PROBE=${name} " "$log" || true)
  [ "$count" -eq 1 ] ||
    fail "expected exactly one PROBE=$name line, found $count"
done

# 5. No unexpected probe names.
actual=$(grep -E '^PROBE=' "$log" | sed -E 's/^PROBE=([^ ]+).*/\1/' | sort)
want=$(printf '%s\n' $expected_probes | sort)
[ "$actual" = "$want" ] ||
  fail "probe set mismatch (got [$(printf '%s' "$actual" | tr '\n' ' ')], want [$(printf '%s' "$want" | tr '\n' ' ')])"

# 6. Every probe line must be structurally well-formed and carry a known status.
#    CRASH/FAIL/TIMEOUT are valid statuses here; that is the point of the guard.
while IFS= read -r line; do
  printf '%s' "$line" | grep -qE ' STATUS=(PASS|FAIL|CRASH|TIMEOUT) EXIT=[0-9]+ SIGNAL=[0-9]+ ELAPSED_MS=[0-9]+ EXPECTED="[^"]*" OBSERVED="[^"]*"' ||
    fail "malformed probe line: $line"
done < <(grep -E '^PROBE=' "$log")

# 7. Every measurement the report job and docs/spikes/r1-bun.md quote must be
#    present, exactly once, with a well-formed value. Without this pass a run
#    that measured nothing is indistinguishable from one that measured
#    everything: RSS_VMHWM_KB=unavailable is a reachable outcome of the device
#    script (an unreadable /proc/<pid>/status), and the report's unanchored
#    `grep -o 'RSS_VMHWM_KB=[^ ]+'` turns that into an empty table cell instead
#    of an error. Absence of a measurement is a harness failure, not a result.
require_once() {
  key="$1"
  re="$2"
  n=$( { grep -oE "(^|[[:space:]])${key}=${re}([[:space:]]|\$)" "$log" || true; } | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] ||
    fail "expected exactly one ${key}=<${re}> record, found $n"
}
require_once ABI '"x86_64"'
require_once RSS_VMHWM_KB '[0-9]+'
require_once COLD_START_MS_MEDIAN '[0-9]+'
require_once COLD_START_HARNESS_FLOOR_MS '[0-9]+'
require_once COLD_START_MS_NET_OF_FLOOR '-?[0-9]+'
require_once COLD_START_FLOOR_STATUS '(ABOVE_HARNESS_FLOOR|INDISTINGUISHABLE_FROM_HARNESS_FLOOR)'
require_once BUN_VERSION_LINE '"[^"]*"'
require_once JIT_MAPS_OBSERVED '"[^"]*"'
require_once JIT_MAPS_CONTROL '"[^"]*"'
require_once JIT_SIGNAL '(POSITIVE|NONE|INCONCLUSIVE)'
require_once JIT_DETERMINATION '(OPEN|SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN)'
require_once TLS_DNS '(ok|ENOTFOUND|unavailable)'
require_once TLS_BADCERT_VERDICT '(CERT_REJECTED|NOT_REJECTED|DNS_UNRESOLVED|REFUSED_UNCLASSIFIED|NO_TLS_RESULT)'

# 8. Cold start must be a median of exactly 5 integer samples, published raw.
samples_line=$(grep -oE 'COLD_START_MS_SAMPLES="[^"]*"' "$log" || true)
[ "$(printf '%s\n' "$samples_line" | grep -c . || true)" -eq 1 ] ||
  fail "expected exactly one COLD_START_MS_SAMPLES record, found $(printf '%s' "$samples_line" | grep -c . || true)"
samples=$(printf '%s' "$samples_line" | sed 's/^[^"]*"//; s/"$//')
sample_count=$(printf '%s\n' $samples | grep -c . || true)
[ "$sample_count" -eq 5 ] ||
  fail "COLD_START_MS_SAMPLES must hold 5 samples, found $sample_count: [$samples]"
for s in $samples; do
  case "$s" in
    '' | *[!0-9]*) fail "COLD_START_MS_SAMPLES contains a non-integer sample: [$s]" ;;
  esac
done

# 9. Every probe that produced output also preserved it verbatim as RAW[]
#    records. The brief's Step 3 ("preserve the raw output, because the signal
#    is the finding") is otherwise satisfied only by a crash's SIGSEGV number:
#    a multi-line stack trace is truncated to OBSERVED="" first line.
while IFS= read -r line; do
  pname=$(printf '%s' "$line" | sed -nE 's/^PROBE=([^ ]+) .*/\1/p')
  pobs=$(printf '%s' "$line" | sed -nE 's/^.* OBSERVED="([^"]*)"$/\1/p')
  [ -n "$pobs" ] || continue
  raws=$(grep -cE "^RAW\[${pname}\]\[[0-9]+\] " "$log" || true)
  [ "$raws" -ge 1 ] ||
    fail "probe $pname reported output but no RAW[$pname][n] records were preserved"
done < <(grep -E '^PROBE=' "$log")

echo "valid bun-probe result for API $api: verdict=$verdict exit=$exit_code"
