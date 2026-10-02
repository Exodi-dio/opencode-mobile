#!/usr/bin/env bash
# Clone anomalyco/opencode at a pinned commit and print the checkout path.
#
# CI ONLY. This clones the entire opencode monorepo; running it on a
# memory-constrained machine will exhaust it. The CI=true guard below is
# deliberate, not decorative.
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "error: fetch-upstream.sh must only run in CI (CI=${CI:-<unset>}, expected CI=true)." >&2
  echo "       It clones the full opencode monorepo and will exhaust a small device." >&2
  exit 1
fi

sha="${1:-}"
if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "usage: CI=true $0 <40-character-commit-sha>" >&2
  exit 1
fi

dest="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/opencode-upstream"
if [ -e "$dest" ]; then
  echo "error: $dest already exists; refusing to reuse or clobber it." >&2
  exit 1
fi

# --no-checkout: with --filter=blob:none a bare clone checks out the default
# branch and pays to fetch that whole tree's blobs before we ask for a
# different commit. Staying on the commit avoids paying twice.
echo "cloning anomalyco/opencode (blobless) ..." >&2
git clone --filter=blob:none --no-checkout --quiet https://github.com/anomalyco/opencode.git "$dest" >&2

echo "checking out $sha ..." >&2
git -C "$dest" checkout --quiet "$sha" >&2

# stdout carries the path and nothing else; all progress went to stderr.
printf '%s\n' "$dest"