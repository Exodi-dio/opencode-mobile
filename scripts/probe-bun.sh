#!/usr/bin/env bash
# Fetch the @oven/bun-linux-{x64,aarch64}-android binaries at a pinned version
# from the npm registry, verify each tarball against the SHA-512 the registry
# publishes for that exact version, extract them, and print the binary path(s).
#
# CI ONLY. Each tarball is ~37 MB compressed and ~83-85 MB unpacked. Running
# this on the maintainer's memory-constrained phone is deliberately blocked;
# the CI=true guard is not decorative.
#
# Usage:
#   CI=true ./scripts/probe-bun.sh            # both architectures (default)
#   CI=true ./scripts/probe-bun.sh x64        # print only the x64 path
#   CI=true ./scripts/probe-bun.sh arm64      # print only the arm64 path
#
# stdout carries one binary path per line and nothing else; all progress and
# errors go to stderr.
set -euo pipefail

if [ "${CI:-}" != "true" ]; then
  echo "error: probe-bun.sh must only run in CI (CI=${CI:-<unset>}, expected CI=true)." >&2
  echo "       It downloads the ~83 MB Bun Android runtime and will exhaust a small device." >&2
  exit 1
fi

version="${BUN_VERSION:-1.4.2}"
arch="${1:-both}"

case "$arch" in
  x64)            pkgs="bun-linux-x64-android" ;;
  arm64 | aarch64) pkgs="bun-linux-aarch64-android" ;;
  both)           pkgs="bun-linux-x64-android bun-linux-aarch64-android" ;;
  *)
    echo "usage: CI=true $0 [x64|arm64|both]" >&2
    exit 2
    ;;
esac

for tool in curl tar openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool not found: $tool" >&2
    exit 1
  fi
done

workdir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bun-android-$version"
mkdir -p "$workdir"

for pkg in $pkgs; do
  meta="https://registry.npmjs.org/@oven/$pkg/$version"
  tarball="https://registry.npmjs.org/@oven/$pkg/-/$pkg-$version.tgz"
  tgz="$workdir/$pkg-$version.tgz"
  dest="$workdir/$pkg"

  # Read the integrity from the registry's own version document rather than
  # trusting a value typed into this script: the pin is the version, and npm
  # is authoritative for what that version's bytes hash to.
  doc="$(curl -fsSL "$meta")"
  expected="$(printf '%s' "$doc" | grep -o '"integrity":"sha512-[A-Za-z0-9+/=]*"' | head -1 | sed 's/.*"integrity":"//; s/"$//')"
  if [ -z "$expected" ]; then
    echo "error: no sha512 integrity published for @oven/$pkg@$version" >&2
    exit 1
  fi

  echo "fetching @oven/$pkg@$version ..." >&2
  curl -fsSL "$tarball" -o "$tgz"

  actual="sha512-$(openssl dgst -sha512 -binary "$tgz" | openssl base64 -A)"
  if [ "$actual" != "$expected" ]; then
    echo "error: integrity mismatch for @oven/$pkg@$version" >&2
    echo "  published: $expected" >&2
    echo "  computed : $actual" >&2
    exit 1
  fi
  echo "verified @oven/$pkg@$version integrity: $actual" >&2

  rm -rf "$dest"
  mkdir -p "$dest"
  tar -xzf "$tgz" -C "$dest"

  bin="$dest/package/bin/bun"
  if [ ! -f "$bin" ]; then
    echo "error: expected binary at $bin after extracting $pkg@$version" >&2
    find "$dest" -maxdepth 4 -type f >&2
    exit 1
  fi
  chmod 755 "$bin"

  printf '%s\n' "$bin"
done
