#!/usr/bin/env bash
#
# assert-pty-log.sh - validate one native/ptyprobe log.
#
#   usage: assert-pty-log.sh <log> [expected-api-level]
#   exit 0: the log is a well-formed probe result. BOTH verdicts are accepted:
#           PTY_UNAVAILABLE is a finding, not a harness failure.
#   exit 1: the harness is broken (missing/garbled probe output, wrong API
#           level, a probe exit code that contradicts the verdict it printed).
#
# This script is the whole red/green distinction for risk R4. It must never
# reject a log merely because PTY was unavailable; it must always reject a log
# the probe did not produce. `.github/workflows/m0-pty.yml` proves both halves
# of that with synthetic fixtures before it boots an emulator.

set -uo pipefail

log=${1:-}
expected_api=${2:-}

errors=0
fail() {
  errors=$((errors + 1))
  echo "::error::${log}: $1"
}
pass() {
  echo "PASS: $1"
}

count() {
  # count <extended-regexp>; prints the number of matching lines
  grep -cE "$1" "$log" || true
}

if [ -z "$log" ]; then
  echo "::error::assert-pty-log.sh: no log path given"
  exit 1
fi
if [ ! -s "$log" ]; then
  fail "log is missing or empty - the probe did not run"
  exit 1
fi

# 1. attribution header, so no verdict can be read without knowing which API
#    level, ABI and SELinux domain produced it.
if [ "$(count '^PTYPROBE=1 UID=[0-9]+ EUID=[0-9]+ GID=[0-9]+ ')" = "1" ]; then
  pass "header present"
else
  fail "expected exactly one 'PTYPROBE=1 UID=.. EUID=.. GID=..' header line"
fi

# 2. the API level the emulator reported must be the one we asked for,
#    otherwise the verdict is attributed to the wrong image.
api_lines=$(count '^PTYPROBE=1 .*API_LEVEL=')
if [ "$api_lines" != "1" ]; then
  fail "expected exactly one API_LEVEL= field in the header, found $api_lines"
else
  if [ -n "$expected_api" ]; then
    if grep -qE "^PTYPROBE=1 .*API_LEVEL=$expected_api( |\$)" "$log"; then
      pass "API level is $expected_api"
    else
      fail "probe ran on API $(grep -oE 'API_LEVEL=[^ ]*' "$log" | head -1), expected $expected_api"
    fi
  else
    pass "API level reported ($(grep -oE 'API_LEVEL=[^ ]*' "$log" | head -1))"
  fi
fi

# 3. exactly one verdict. Its absence or duplication is a broken harness.
verdicts=$(count '^PTY_VERDICT=(AVAILABLE|UNAVAILABLE)$')
if [ "$verdicts" != "1" ]; then
  fail "expected exactly 1 PTY_VERDICT= line, found $verdicts"
  exit 1
fi
verdict=$(grep -oE '^PTY_VERDICT=(AVAILABLE|UNAVAILABLE)$' "$log" | cut -d= -f2)
pass "exactly one verdict: $verdict"

# 4. all five steps reported, in the documented line shape. A step that never
#    reported is not a passing step.
for n in 1 2 3 4 5; do
  shape="^STEP=$n RESULT=(OK|FAIL) ERRNO=[0-9]+ MSG=\"[^\"]*\" DETAIL=\".*\"$"
  found=$(count "$shape")
  if [ "$found" != "1" ]; then
    fail "expected exactly 1 well-formed 'STEP=$n' line, found $found"
  fi
done
if [ "$errors" = "0" ]; then
  pass "steps 1-5 each reported exactly one well-formed line"
fi

# 5. a FAIL must carry a real errno, or the log is not evidence of anything.
#    STEP=5 is the documented exception: the child's exit status is not an
#    errno, so it legitimately reports ERRNO=0.
while IFS= read -r line; do
  step=$(printf '%s' "$line" | sed -n 's/^STEP=\([0-9]*\) .*/\1/p')
  errno_val=$(printf '%s' "$line" | sed -n 's/.* ERRNO=\([0-9]*\) .*/\1/p')
  if [ "$errno_val" = "0" ] && [ "$step" != "5" ]; then
    fail "STEP=$step reports RESULT=FAIL with ERRNO=0 - a failure must name its errno"
  fi
done < <(grep -E '^STEP=[1-5] RESULT=FAIL ' "$log" || true)

# 6. the probe's exit code must agree with the verdict it printed: 0 for
#    AVAILABLE, 3 for UNAVAILABLE. Anything else (e.g. 139 from a segfault)
#    means the probe crashed, which is a harness failure, not an R4 finding.
exit_lines=$(count '^EXIT=[0-9]+$')
if [ "$exit_lines" != "1" ]; then
  fail "expected exactly 1 'EXIT=<n>' line captured after the run, found $exit_lines"
else
  exit_code=$(grep -oE '^EXIT=[0-9]+$' "$log" | cut -d= -f2)
  expected_exit=0
  [ "$verdict" = "UNAVAILABLE" ] && expected_exit=3
  if [ "$exit_code" = "$expected_exit" ]; then
    pass "exit code $exit_code agrees with $verdict"
  else
    fail "probe exited $exit_code but printed $verdict (expected $expected_exit) - the probe crashed"
    exit 1
  fi
fi

# 7. the verdict must be derived from the step results, never asserted beside
#    them: AVAILABLE only if all five steps are OK.
if [ "$verdict" = "AVAILABLE" ]; then
  oks=$(count '^STEP=[1-5] RESULT=OK ')
  if [ "$oks" = "5" ]; then
    pass "AVAILABLE is backed by 5/5 OK steps"
  else
    fail "PTY_VERDICT=AVAILABLE but only $oks/5 steps reported OK"
    exit 1
  fi
else
  fails=$(count '^STEP=[1-5] RESULT=FAIL ')
  if [ "$fails" -ge 1 ]; then
    pass "UNAVAILABLE is backed by $fails failing step(s)"
  else
    fail "PTY_VERDICT=UNAVAILABLE but no step reported FAIL"
    exit 1
  fi
fi

# 8. a passing step 5 must carry the child's raw status.
if [ "$(count '^STEP=5 RESULT=OK ')" = "1" ]; then
  if [ "$(count '^CHILD_PID=[0-9]+ CHILD_EXITS=')" = "1" ]; then
    pass "child exit status reported"
  else
    fail "STEP=5 is OK but no CHILD_PID=/CHILD_EXITS= line was recorded"
  fi
fi

if [ "$errors" -ne 0 ]; then
  echo "::error::${log}: HARNESS_BROKEN - $errors problem(s) with the probe output"
  echo "--- log ---"
  cat "$log"
  exit 1
fi

echo "ptyprobe log accepted: API=${expected_api:-$(grep -oE 'API_LEVEL=[^ ]*' "$log" | head -1 | cut -d= -f2)} verdict=$verdict"
