#!/usr/bin/env bash
# Assert that a Bun Android probe log is a well-formed *result*.
#
# This script owns the red/green distinction for the R1/R3/R6 probe, exactly as
# assert-pty-log.sh does for R4:
#
#   A probe that CRASHED, FAILED or TIMED OUT is a FINDING and is ACCEPTED here.
#   A log that is malformed - wrong API level, missing or duplicated probes, no
#   verdict, a verdict that contradicts the exit code, no output at all - is a
#   HARNESS FAILURE and is rejected.
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

# 1. The log must be from the API level it claims to be.
grep -qE "^BUNPROBE=1 API_LEVEL=${api}( |\$)" "$log" ||
  fail "no BUNPROBE header for API level $api"

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

# 4. Exactly the five expected probes, each exactly once. A missing probe is a
#    harness failure; absence of evidence is never a result.
expected_probes="version js-engine engine-usable tls platform"
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

echo "valid bun-probe result for API $api: verdict=$verdict exit=$exit_code"
