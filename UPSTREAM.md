# Upstream

`opencode-mobile` does not reimplement opencode. It runs the real
[anomalyco/opencode](https://github.com/anomalyco/opencode) CLI compiled to an Android
binary and embedded in the app. This file records exactly which upstream we depend on,
how we build it, and every place we deviate from it.

## Pin

| | |
| --- | --- |
| Repository | `anomalyco/opencode` |
| Default branch | `dev` |
| Pinned commit | `1ddb0873aee50d209d1a8d7f91b89c5daf692d49` |
| Release | `v1.18.34` (`packages/opencode/package.json` → `"version": "1.18.34"`) |
| License | MIT |
| Build Bun version | `1.4.2` |

Every build reads the pin from `.github/workflows/m0-build.yml` → `env.UPSTREAM_SHA`.
`scripts/fetch-upstream.sh` checks the pin out, the `patch-verify` job asserts
`git rev-parse HEAD` equals it, and then runs `git apply --check` on our patch against it.
If the pin has moved, `patch-verify` goes red — that is the intended alarm, not something
to re-pin around. Re-pinning invalidates the evidence table in the M0 spec, which has to
be re-read and the spec amended by hand.

`dev` head was verified to be exactly `1ddb0873aee50d209d1a8d7f91b89c5daf692d49` on
2026-10-02, before the patch was written.

## Why Bun 1.4.2

Bun only learned to be a cross-compilation *target* for Android recently. The upstream
work is [oven-sh/bun#29675](https://github.com/oven-sh/bun/pull/29675) "Add
aarch64-linux-android target", which added `--abi=android` to Bun's own build and wired
`bun build --compile --target=bun-linux-arm64-android`. That PR was closed unmerged
(2026-04-26) and the work landed piecemeal — the release-publishing half is
[oven-sh/bun#31553](https://github.com/oven-sh/bun/pull/31553) (merged 2026-05-29), the
`--compile` PIE fix is [oven-sh/bun#38246](https://github.com/oven-sh/bun/pull/38246)
(merged 2026-08-14). Verified directly against the tag:

- `oven-sh/bun` release `bun-v1.4.2` ships `bun-linux-aarch64-android.zip` and
  `bun-linux-x64-android.zip`.
- `src/options_types/compile_target.rs` at tag `bun-v1.4.2` accepts an `android` token
  (line 310) and its error text names the canonical spelling:
  `"invalid target, android only exists with linux (use bun-linux-arm64-android)"`
  (line 394). Segment order is not significant — the parser splits on `-` and matches
  OS/arch/libc independently (lines 263–316).
- Cross-compiled standalone executables fetch the target runtime from npm as
  `@oven/bun-{os}-{arch}{libc}` (line 64 comment, lines 120–169). Both
  `https://registry.npmjs.org/@oven/bun-linux-aarch64-android/-/bun-linux-aarch64-android-1.4.2.tgz`
  and `.../bun-linux-x64-android-1.4.2.tgz` were confirmed to return HTTP 200.

Upstream opencode's own `packageManager` field is `bun@1.3.14`, and
`packages/script/src/index.ts` hard-fails unless the running Bun satisfies `^1.3.14`.
`1.4.2` satisfies it, so we pin `1.4.2` — not `1.3.14`, which has no Android target.

## The patch

`patches/opencode-android-target.patch`, against `packages/opencode/script/build.ts` only.
Five changes, in the order the brief specifies them:

1. **Widen the target type** — `abi?: "musl"` becomes `abi?: "musl" | "android"`.
2. **Append two `allTargets` entries** — `{ os: "linux", arch: "arm64", abi: "android" }`
   and `{ os: "linux", arch: "x64", abi: "android" }`.
3. **`FFF_LIBC`** — no code change was required, and none was made. Line 193 reads
   `item.abi === "musl" ? "musl" : "gnu"`, whose non-musl arm is already `"gnu"`, which
   is the value the brief asks for. The ternary was read, not assumed; writing an
   equivalent expression would be a diff with no behaviour behind it.
4. **`OPENCODE_LIBC`** — map `"android"` to `"glibc"`. See the decision note below.
5. **Smoke test** — no change, deliberately. Line 211 guards on
   `item.os === process.platform && item.arch === process.arch && !item.abi`; the Android
   entries set `abi`, so on a Linux runner they skip the smoke test. Android is not
   silently un-smoke-tested — the Android smoke test is Task 3's and Task 4's job and
   runs on the emulator.

### Artifact naming is derived, not hardcoded

The brief says to verify the name derivation rather than assume it. Traced through the
patched file: `name` is built from `pkg.name` (`"opencode"`), the OS (`"linux"` — the
`win32` → `windows` rewrite at line 149 does not fire), `item.arch`, `undefined` for the
baseline slot, and `item.abi`, with `.filter(Boolean)` at line 154 dropping the
`undefined`s. So `abi: "android"` yields `opencode-linux-arm64-android` and
`opencode-linux-x64-android`, each into its own `dist/<name>/bin/`. `compile.target`
(line 177) is `name.replace(pkg.name, "bun")`, i.e. `bun-linux-arm64-android` and
`bun-linux-x64-android` — exactly the strings Bun 1.4.2's parser accepts.

One consequence falls out for free and is worth knowing: `dist/<name>/package.json` (line
232) will carry `"libc": ["android"]`, which npm does not recognise. That file exists to
drive `npm install` platform selection on the release path; we never publish to npm, so
it is inert here.

### Decision, not fact: `"android"` → `"glibc"` for `OPENCODE_LIBC`

`OPENCODE_LIBC` (line 199) previously passed `item.abi` through verbatim. With
`abi: "android"` that would bake the literal string `"android"` into the binary, so we
map it to `"glibc"` instead and opencode's libc-dependent code paths take the branch they
already have for glibc. The only consumer of the constant in this repo is
`packages/core/src/filesystem/watcher.ts:28-31`, which builds a
`@parcel/watcher-${platform}-${arch}-${libc}` require string; on Android the platform
segment is `android` and no such prebuild exists either way, so the `try/catch` around it
degrades to "no native watcher". The value is not load-bearing for correctness here — but
`"android"` in a variable named `*_LIBC` would be a lie that future readers trip over, and
the adjacent `OPENTUI_LIBC` define has the identical shape.

**This is a choice, not a verified fact.** Nothing has run this binary on Android yet, and
`@opentui/core`'s own use of `OPENTUI_LIBC` was not read at this pin (it is a published
dependency, not vendored source), so its reaction to `"glibc"` on a Bionic device is
assumed from the glibc branch being the non-musl default. If Task 4 finds native process
spawning misbehaving, the fallback is to build with `abi: "musl"` instead and re-run
Task 4's assertions under that pin. The patch is structured so that change is a two-line
edit to `allTargets`.

`process.env.OPENTUI_LIBC` (line 200) had the identical bug and got the identical fix
via the same new `libc` local. That is one edit beyond the brief's list; leaving it would
have baked `"android"` into a define OpenTUI reads.

### Deviation from a minimal patch: `OPENCODE_TARGET_FILTER`

The brief asks for two Android targets and nothing else. `build.ts` cannot express that:
unfiltered it builds all twelve targets including `win32` and `darwin`, and its only
existing filter, `singleFlag`, selects the **host** platform — which is useless when
cross-compiling to Android from a Linux runner. So the patch adds:

```
OPENCODE_TARGET_FILTER=opencode-linux-arm64-android,opencode-linux-x64-android
```

A comma-separated list of `allTargets` entry names. When it is unset, `targetFilter` is
empty and the expression short-circuits, so upstream behaviour is preserved exactly.
To support this, the `name` array literal (lines 146–155) is hoisted out of the build
loop into a `targetName(item)` function above the filter — otherwise the filter would have
to duplicate the naming rules and the two could drift.

**This is a deviation from a minimal patch.** It exists because the alternative is
building Windows and macOS binaries on every CI run, and because `OPENCODE_TARGET_FILTER`
is what lets one job emit both Android binaries: a single `build.ts` invocation writes
each target into its own `dist/` subdirectory, so a `[arm64, x64]` matrix would repeat
identical work for no extra coverage.

### What the patch deliberately does not do

- No smoke-test change (item 5 above).
- No `@opentui/core` or `@parcel/watcher` native rebuild for Android. build.ts runs
  `bun install --os="*" --cpu="*"` for those three packages precisely so they resolve to
  prebuilds rather than compiling; nothing was added for Android.
- No ripgrep change. See the known gap below.

## What the build actually produces

Measured by the `Assert android binaries` step in `.github/workflows/m0-build.yml`. Both
targets come out of one `build.ts` invocation, each in its own `dist/` subdirectory:

| | arm64 | x64 |
| --- | --- | --- |
| path | `dist/opencode-linux-arm64-android/bin/opencode` | `dist/opencode-linux-x64-android/bin/opencode` |
| size | 165,279,488 B (157.6 MiB) | 167,923,744 B (160.1 MiB) |
| `file` | `ELF 64-bit LSB pie executable, ARM aarch64, ... dynamically linked` | `ELF 64-bit LSB pie executable, x86-64, ... dynamically linked` |
| `PT_INTERP` | `/system/bin/linker64` | `/system/bin/linker64` |
| `DT_NEEDED` | `libc.so`, `libm.so`, `libdl.so` | `libc.so`, `libm.so`, `libdl.so` |
| `PT_LOAD` align | `0x4000` (R E), `0x10000` (RW) | `0x4000` (R E), `0x4000` (RW) |

Two things worth writing down because they are not what the brief predicted:

- **The `DT_NEEDED` list is Bionic, and it is minimal.** No `libc.so.6`, no
  `ld-linux-*`; the interpreter is Android's own `/system/bin/linker64`. This matches
  what oven-sh/bun#29675 reported (`NEEDED = libc/libm/liblog/libdl`).
- **The arm64 data segment is `0x10000`, not `0x4000`.** The M0 brief asked the assertion
  to check for `Align` of exactly `0x4000` on `LOAD` segments. x64 happens to emit
  `0x4000` for both, but arm64 emits `0x4000` for the R E segment and `0x10000` (64 KB =
  four 16 KB pages) for the RW segment. 64 KB is *stronger* than the 16 KB
  `max-page-size` Android 15+ requires, and satisfies it. The assertion therefore checks
  what the requirement actually is: every `LOAD` segment's `p_align` is a positive
  multiple of `0x4000`. It still fails hard on `0x1000` (4 KB) and `0x2000` (8 KB),
  which are the alignments that actually break on a 16 KB device. Checked for equality to
  `0x4000` instead, the assertion would have rejected a better-aligned binary — a bug in
  the assertion, not in the artifact.

Nothing here has been run on a device. Every claim above is from `file`/`readelf` on the
CI runner.

## Known gap for Task 4: ripgrep's platform table

`packages/core/src/ripgrep/binary.ts` builds its download key from
`` `${process.arch}-${process.platform}` `` (line 100) and looks it up in the `PLATFORM`
table (lines 15–23), which has keys `arm64-darwin`, `arm64-linux`, `x64-darwin`,
`x64-linux`, `arm64-win32`, `ia32-win32`, `x64-win32` — and no `*-android` entry. Bun
reports `process.platform === "android"` on Android, so the lookup yields `undefined` and
line 102 throws `unsupported platform for ripgrep: arm64-android`.

This patch does not fix it, because that is upstream source, not build configuration, and
the brief scopes this task to `build.ts`. It is recorded here so Task 4 does not
rediscover it: on device, expect ripgrep-dependent features (grep tool, `@` file search)
to fail until either a `*-android` entry is added or opencode falls back to a bundled
binary.

## Pinned upstream files read

Everything below was read at commit `1ddb0873aee50d209d1a8d7f91b89c5daf692d49` via the
GitHub API. Line numbers refer to those exact blobs.

**`packages/opencode/script/build.ts`** — 252 lines. The file this repo patches.
Read in full; the ranges that carry the patch are:

- 19–24 — the `singleFlag` / `baselineFlag` / `skipInstall` / `sourcemaps` /
  `skipEmbedWebUi` flag parsing.
- 26–50 — `createEmbeddedWebUIBundle`, including the `../../app` path at line 28.
- 53–58 — the `allTargets` element type, the widened `abi` union.
- 59–114 — every `allTargets` entry, including the win32 block the Android entries follow.
- 116–135 — target selection; the `singleFlag` host-platform filter, reindented by the patch.
- 137–144 — `rm -rf dist` and the three `bun install --os="*" --cpu="*"` calls.
- 145–157 — the `name` array and `.filter(Boolean)`, hoisted to `targetName`.
- 159–181 — `Bun.build`, including `compile.target` at line 177 and the `execArgv` at 179.
- 182–201 — `files`, `entrypoints`, and the whole `define` block: `FFF_LIBC` at 193,
  `OPENCODE_LIBC` at 199, `process.env.OPENTUI_LIBC` at 200.
- 204–221 — the darwin ad-hoc codesign and the host-only smoke test guard at line 211.
- 223–238 — `dist/<name>/package.json` generation, the `libc: [item.abi]` field at 232.
- 241–250 — the `Script.release` tar/zip + `gh release upload` block, which we must not
  enter (no `OPENCODE_RELEASE` in our workflow).

**`packages/core/src/ripgrep/binary.ts`** — 132 lines. Read in full. The ranges that
matter to this project:

- 13–23 — the `RipgrepBinary` namespace and the `PLATFORM` table. No Android entry.
- 91–123 — `Service.of({ filepath })`: the system-`rg` short-circuit, the cached download,
  and the `platformKey` lookup at line 100 with its throw at line 102.
- 51–89 — `extract`, to confirm the archive handling is platform-independent.

Also read at the same commit, for the same reason (build invocation, dependency
installation, and libc/channel semantics rather than guesswork):

- `package.json` (repo root) — `packageManager: "bun@1.3.14"`, `workspaces`,
  `postinstall`, `patchedDependencies`.
- `packages/opencode/package.json` — `"build": "bun run script/build.ts"`. CI invokes the
  script directly as `./packages/opencode/script/build.ts` from the repo root, which is
  what upstream's own `.github/workflows/publish.yml` does (the file has a
  `#!/usr/bin/env bun` shebang and is committed mode 755) and is equivalent to
  `bun run script/build.ts` from `packages/opencode`. The script `process.chdir`s itself
  into `packages/opencode`, so both forms produce `dist/` in the same place.
- `packages/script/src/index.ts` (77 lines) — the Bun version gate and how
  `Script.version` / `Script.channel` are derived.
- `packages/core/src/filesystem/watcher.ts` — 140 lines; the `OPENCODE_LIBC` consumer at
  lines 20–36.
- `packages/app/vite.js` (48 lines) — the `OPENCODE_CHANNEL` → `dev|beta|prod` mapping at
  lines 8–13.
- `.github/actions/setup-bun/action.yml` and `.github/workflows/publish.yml` — upstream's
  own build job, which is the model for our `build-android` job.

And, at tag `bun-v1.4.2` of `oven-sh/bun` rather than at the opencode pin:

- `src/options_types/compile_target.rs` (466 lines) — lines 40–46 (host libc detection),
  51–72 (`Libc` and its npm suffix), 120–188 (target → npm tarball URL), 231–245
  (`is_supported`), 247–346 (the token parser), 386–408 (the error messages quoted above).

**No module here is ever implemented from memory.** If it is not in the list above with a
line range, it was not read, and it does not get relied on.

## CI-only scripts

`scripts/fetch-upstream.sh` clones the whole opencode monorepo. It refuses to run unless
`$CI` is exactly `true`, so an accidental local invocation fails in one line instead of
exhausting a memory-constrained device. Same rule for any future script in `scripts/` that
clones or installs.

Two deliberate choices in that script:

- `git clone --filter=blob:none --no-checkout`. With `--filter=blob:none`, a plain clone
  still checks out the default branch and pays to fetch that tree's blobs before we ask
  for a different commit. `--no-checkout` avoids paying for two trees.
- Progress goes to stderr and only the checkout path goes to stdout, so
  `path=$(./scripts/fetch-upstream.sh "$SHA")` in a workflow `run:` block captures the
  path and nothing else.

## Reproducing a build locally

Do not. Run the workflow. The device this repo is developed on has ~1.5 GB of free RAM and
cannot clone opencode, install its dependencies, or link a Bun runtime. `.github/workflows/m0-build.yml`
is the only supported build path.