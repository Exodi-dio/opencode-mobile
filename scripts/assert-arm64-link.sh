#!/usr/bin/env bash
# assert-arm64-link.sh - the assert for the arm64 qemu-user leg. This leg is
# LINK_LEVEL_ONLY in every case, green or not: it can neither confirm nor deny
# that opencode works on real arm64 hardware. What it must never be is
# malformed.
set -uo pipefail

log="${1:?usage: assert-arm64-link.sh <log>}"
fail() { echo "::error::arm64 link log: $*" >&2; exit 1; }

[ -s "$log" ] || fail "log missing/empty"
grep -qE '^ARM64_LABEL=LINK_LEVEL_ONLY$' "$log" || fail "missing ARM64_LABEL=LINK_LEVEL_ONLY"
grep -qE '^ARM64_VERSION_EXIT=[0-9]+$' "$log" || fail "no exit code"
if grep -qE '^ARM64_VERSION_LINE="1\.18\.' "$log"; then
  : # version printed - acceptable, still LINK_LEVEL_ONLY
elif grep -qE '^ARM64_PRESERVED_ERROR=' "$log"; then
  : # failed with the error preserved - acceptable, still LINK_LEVEL_ONLY
else
  fail "neither a version string nor a preserved error"
fi
echo "PASS: $log"
