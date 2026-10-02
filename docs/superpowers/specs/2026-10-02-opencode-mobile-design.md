# opencode-mobile Design Spec

**Date:** 2026-10-02
**Repo:** `Exodi-dio/opencode-mobile` (public)
**Upstream:** `anomalyco/opencode` (MIT, formerly `sst/opencode`), default branch `dev`, **pinned at `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`**, release `v1.18.34`. Exact pin re-verified and recorded in `UPSTREAM.md` at M0 and re-checked each milestone.
**Status:** Conversational design approved (Sections 1-5). Written spec pending maintainer review.

> **For agentic workers:** This spec travels with the implementation plan. Every claim of "verified" in this document means "verified by a named green GitHub Actions run", never "verified locally". See Section 2 for why local verification is impossible.

---

## 1. Goal and intent

**Intended outcome:** An Android app that is the **backend tier** of a native opencode mobile client. It provides a real Linux shell environment on the device, bundles **real upstream opencode** (not a reimplementation), and **automatically starts its own `opencode serve` instance when the app opens**. A separate GUI — built later, in a later step — connects to that server as an ordinary opencode client.

**Why this shape:** opencode's own architecture is already client/server. The TUI is merely a client talking to `opencode serve`. So the future GUI is not bolted on; it is a first-class client using an officially supported HTTP interface with an OpenAPI 3.1 spec. The backend is not a stand-in for opencode — it is opencode itself, serving its own first-party client.

**Who it is for:** opencode users who want an always-available agent backend on Android, and the author of the follow-on native GUI.

**Success criteria:**
- Opening the app results in a healthy `opencode serve` reachable on localhost, with no manual step, no login prompt, and no network requirement beyond the LLM provider the user configures.
- **M0 proves real opencode runs on Android.** A full session (create → prompt → streamed reply → tool call → file written to workspace) completes against a mock LLM on a cloud emulator. This is the project's central result.
- Every milestone **M1-M5** ends with a green workflow and a downloadable debug APK artifact. **M0 is a spike and has no APK**; it ends with its GO/NO-GO report instead.
- Bionic-only executables, zero proot, zero root, no GMS/Firebase, F-Droid friendly.
- Bounded, honest limitations: every unverifiable claim and every cloud substitute is written down in `docs/limitations.md` rather than glossed.

**Explicit non-promises** (agreed with maintainer, recorded so they are never quietly dropped):
- **Zero bugs is not promised.** The commitment is green CI, deterministic tests, and honest reporting of failures.
- **Zero local compute is not promised and is not the goal.** The device renders pixels and runs the agent; that is the point of the product. "Cloud only" applies to *developing* it, not to *running* it.
- **arm64 is not executed in CI.** See Section 8.

**Said vs assumed:**
- Said by maintainer: separate repo (not a fork of or addition to `opencode-android`); a Termux-like Linux environment with opencode built **in**; auto-starts its own server on app open; independent; lightweight; backend for a later GUI; the goal is strategically a real opencode mobile port; localhost by default with an explicit LAN opt-in; never use the maintainer's hardware to build.
- Assumed and locked: `Native Bionic, zero proot` with a pre-planned compatibility escape hatch; full upstream-identical opencode binary first, serve-only slim build only as fallback; bundle payload in the APK, arm64-only for release; `termux-emulator` for VT parsing; GitHub Actions as the sole verification authority.
- **Maintainer hardware constraint:** 1.5 GB RAM free at all times. See Section 2.

---

## 2. Constraints — the maintainer's device is not a build machine

The maintainer's only machine is an Android phone with **~1.5 GB RAM free at all times**. Gradle alone wants 2-4 GB; the Android SDK/NDK is several GB; an emulator needs KVM and far more. There is therefore **no local build, test, or verification path of any kind.**

**Hard rules for every agent and contributor working this repo:**
1. **Never run `./gradlew`, Gradle, the Android SDK/NDK toolchain, an emulator, Docker, `bun install`, or any package manager on the maintainer's device.** Not once, not "just to check", not for a fast incremental compile.
2. Local commands are limited to: reading and editing files, `git`, and `gh` API calls. Package installation is prohibited.
3. **Do not perform large checkouts on the device.** Pull upstream sources through sparse `gh api` / raw-file fetches, not `git clone`. The opencode repo is far too large to clone locally.
4. **CI is the only oracle.** A claim of "verified" is valid only with a specific green workflow run ID. Local file-level checks are recorded as `GRADLE_UNAVAILABLE` / `NOT_EXECUTED`, never as passes.
5. The workflow for each task is: edit files → `git push` → read the Actions run back over the API → fix what CI reports. Iteration happens in CI, not on the phone.
6. Never add a doc, script, or workflow step that requires a local computer, a physical phone, or a local emulator.

**Cloud budget awareness:** Actions minutes are finite. The emulator matrix (Section 8) is the dominant cost and is deliberately restricted to a small API-level matrix on `workflow_dispatch` plus nightly, rather than on every push.

---

## 3. Verified upstream facts

These were read from source or the npm registry, not recalled. Re-verify at M0 and record in `UPSTREAM.md`.

| Fact | Evidence |
|---|---|
| opencode is built with `bun build --compile`, one self-contained executable per target. No `node_modules` needed at runtime. | `packages/opencode/script/build.ts` |
| Build targets are a literal array `{ os, arch, abi?, avx2? }[]`; the artifact name is derived from those fields. Adding a platform is a one-entry change. | `build.ts:53-114`, `:146-156` |
| `compile.target` is derived as `name.replace(pkg.name, "bun")`, so an `opencode-linux-arm64-android` artifact implies Bun target `bun-linux-arm64-android`. | `build.ts:177` |
| The **web UI is embedded** into the compiled binary (`opencode-web-ui.gen.ts`), so `opencode web` works straight from the binary with no extra assets. | `build.ts:50`, `:184`, `:189` |
| The TUI worker and the tree-sitter worker are compiled in as additional entrypoints. | `build.ts:160-191` |
| The compiled binary launches with `--use-system-ca`. | `build.ts:179` |
| `opencode serve` is a headless HTTP server, OpenAPI 3.1 at `/doc`, default `127.0.0.1:4096`, `--hostname`/`--port`/`--cors` flags. | upstream docs, Server page |
| Health probe is `GET /global/health` → `{ healthy: true, version: string }`. | upstream docs |
| Both `opencode serve` and `opencode web` honour `OPENCODE_SERVER_PASSWORD` (HTTP basic; user defaults to `opencode`, override with `OPENCODE_SERVER_USERNAME`). | upstream docs |
| ripgrep is bundled inside the opencode artifact and extracted to a temp dir at runtime. | `packages/core/src/ripgrep/binary.ts` |
| Native napi deps resolved at runtime: `@parcel/watcher`, `@opentui/core`, `@ff-labs/fff-bun`; installed with `--os="*" --cpu="*"` to pull every platform variant. | `build.ts:141-143` |
| `FFF_LIBC` and `OPENCODE_LIBC` are compile-time defines currently binary `musl`/`gnu`. An Android target needs a third value or a documented mapping. | `build.ts:193`, `:199-200` |
| The in-build smoke test only runs for the **current** platform and skips abi-specific targets, so an Android build would ship with **no** runtime self-test. This repo must add one. | `build.ts:211-221` |
| Bun ships official Android ARM64 binaries: `@oven/bun-linux-aarch64-android`, latest **1.4.2**, unpacked **87,007,476 bytes (83.0 MB)**. | npm registry, `dist-tags.latest`, `versions[1.4.2].dist.unpackedSize` |
| Bun added `aarch64-linux-android` as a build target via PR oven-sh/bun#29675, which passed CI. Related request issue #29778 was closed `not_planned`, and the PR notes explicitly acknowledge **no Android runtime test coverage in CI**. | oven-sh/bun PR #29675, issue #29778 |
| The Android binary links Bionic directly: `NEEDED = libc/libm/liblog/libdl`. | PR #29675 description |

**Consequence:** the Android port is a *small patch to upstream's own build matrix*, not a hand-assembled bundle. Upgrades are a pin bump plus a re-run, not an ongoing fork.

---

## 4. Architecture

Three layers, with the ownership boundary drawn deliberately.

### Layer 1 — Runtime (upstream's code, mostly disposable)

An `opencode` executable produced by `bun build --compile --target=bun-linux-arm64-android`, built by a **small patch to `packages/opencode/script/build.ts`**: one entry in `allTargets` (`{ os: "linux", arch: "arm64", abi: "android" }`), an `android` case for `FFF_LIBC`/`OPENCODE_LIBC`, and an Android smoke-test path. `libc` in the generated `package.json` becomes `android`.

We do not hand-maintain a JS bundle. We add a platform to the project's official build matrix, so the artifact is regenerated from pinned upstream source on every release.

### Layer 2 — Environment (Bionic, zero proot)

This is Termux's own model, and it is why Termux is fast: no `proot`, no rootfs, no ptrace. Real POSIX paths inside app-private storage, Bionic libc, NDK-built binaries.

- `busybox` provides `sh` plus coreutils, so the shell works with no extra downloads.
- `git` and `ripgrep` are NDK-built for `arm64-v8a`.
- **Escape hatch, pre-planned:** if a native dependency cannot be built for Bionic, vendor a minimal compatibility shim or replace that single dependency. Falling back to a full proot glibc rootfs is explicitly **not** an option — it would violate the lightweight goal (300 MB+ download, ptrace overhead on every syscall).

`ripgrep` additionally replaces opencode's bundled glibc/musl binary, since that binary cannot execute under Bionic.

### Layer 3 — Host (our Kotlin app)

Owns the files, supervises the process, auto-starts the server, decides reachability, renders the terminal. This layer is durable; layers 1 and 2 are regenerated from pins.

### Why not a Kotlin reimplementation

`opencode-android` (a sibling repo) is porting opencode's agent loop to native Kotlin. That approach yields a genuinely small, fast APK but forfeits byte-for-byte upstream behaviour and must track upstream indefinitely. This repo takes the opposite bet: **ship upstream itself**, and spend the engineering budget on the environment, process supervision, and reliability. If the bet fails, `opencode-android` remains the fallback and the two repos stay independent.

---

## 5. Components

Gradle multi-module from M1. **Pure-Kotlin discipline:** modules marked *pure* contain zero `android.*` imports, so their tests run as fast JVM tests with no emulator and no local machine.

| Module | Responsibility | Android? |
|---|---|---|
| `:native` | NDK builds: `busybox`, `git`, `ripgrep` for `arm64-v8a` + `x86_64`; Bionic rebuilds of opencode's napi deps | NDK only |
| `:runtime` | The opencode artifact: pin, checksum, provenance, extraction of non-exec assets | no |
| `:core:env` | Environment layout: `HOME`, `PATH`, workspace roots, storage budget, free-space precheck | **pure** |
| `:core:supervisor` | Spawn, health-gate, classify-failure, backoff-restart, log ring buffer | **pure** |
| `:core:reach` | Bind policy, auth token generation, LAN toggle, URL + QR payload | **pure** |
| `:app` | Compose UI: terminal, server status, LAN toggle, address/QR, crash diagnostics | yes |

`:core:supervisor` and `:core:reach` are pure by design: process supervision and bind/auth policy are where the real bugs live, and deterministic JVM tests can hammer them exhaustively for free.

**Terminal rendering: reuse `termux-emulator`,** the VT100 engine Termux itself uses, rather than hand-rolling a VT parser. Its optional JNA dependency is excluded to keep the app native-only. License is Apache-2.0 per `termux/termux-emulator`; **confirm the exact license and pin the commit in `UPSTREAM.md` at M1** before vendoring. Hand-writing a VT parser would be months of edge cases for no benefit.

---

## 6. Data flow and Android runtime

### 6.1 The W^X storage problem dictates the payload layout

Android grants an app exactly **one** guaranteed-executable location: `nativeLibraryDir`. Files an app writes into its own storage receive an SELinux label that forbids `exec`. One fact, and it determines everything:

- **Executables ship in `jniLibs`** and are installed, never app-written. They are executables wearing a `.so` name — Termux's trick. This requires `android:extractNativeLibs="true"` / `useLegacyPackaging = true`, which is the only reliable exec path under W^X on targetSdk 29+.
  - `libopencode.so` — Bun runtime + embedded JS bundle (~83 MB Bun + bundle; expect ~125 MB)
  - `libgit.so`, `librg.so`, `libbusybox.so`
- **Non-executable data ships in `assets`** and is extracted to app storage normally: CA bundles, config templates, non-exec assets.

Layout under `files/`:

```
files/home/                 $HOME
  .config/opencode/         config, auth
  .local/share/opencode/    sessions, sqlite db
  .cache/opencode/          transient
  workspace/                default project root for sessions
```

### 6.2 Cold start

```
MainActivity
  -> bootstrap     verify payload checksums; create layout; extract non-exec assets; precheck free space
  -> start service  LifecycleService (foreground, correct FGS type for API 34+)
  -> spawn          opencode serve --port 4096 --hostname 127.0.0.1
  -> health gate    poll GET /global/health until 200 or timeout
  -> ready          UI shows status, address, QR; terminal enabled
```

- The service starts from the activity, not from a background scheduler: the requirement is "when I open the app", not "always running". The notification carries an explicit **Stop** action.
- **Supervisor rules:** exponential backoff on crash; a **restart cap** that surfaces "crashed N times" as a visible state instead of an infinite respawn loop; full stderr/stdout capture into a bounded ring buffer surfaced in the UI.
- **LAN toggle is implemented as kill-and-respawn** with `--hostname 0.0.0.0` and a fresh 32-character password. Deliberately *not* a live rebind: respawning means there is no half-configured, partially-rewired state to reason about or test.
- A password is set **even on localhost**, so the future in-app GUI authenticates identically in both modes. One code path, not two.

### 6.3 Reachability and auth

- Default: `--hostname 127.0.0.1`. Not reachable off-device.
- LAN is **opt-in only**, behind an explicit toggle in the UI.
- On enabling LAN: generate a 32-char password from a CSPRNG, persist it in the Android Keystore, respawn on `0.0.0.0`, and display the URL plus a QR code for scanning.
- The LAN IP is re-resolved on every toggle and on network-change events, since Android reassigns addresses freely.
- **Honest caveat to document:** the server speaks plain HTTP. On a trusted home LAN this is acceptable; it is **not** protected against an attacker who can read unicast traffic. Do not describe it as secure on an untrusted network. See `docs/limitations.md`.
- LAN exposure is never enabled silently, never persisted across restarts, and is visibly indicated in the notification while active.

---

## 7. Risk register

The honest part. These are the things most likely to be wrong.

**R1 — JSC JIT on Android (highest severity).** Bun's Android target is new and has **no upstream runtime test coverage**. JavaScriptCore on Android is expected to run **interpreter-only**, because Android 10+ forbids writable-and-executable anonymous memory. Expect opencode to work but be slower than on desktop. This is a performance risk, not a correctness one, and it is unmeasurable until it runs. M0 must measure cold-start time and stream latency and record the numbers.

**R2 — napi native dependencies (highest likelihood of blocking).** `@parcel/watcher` (file watching), `@opentui/core` (TUI renderer), `@ff-labs/fff-bun`, `tree-sitter-bash`, `tree-sitter-powershell`, `photon-node`, `bonjour-service` have **no Bionic builds** and must be rebuilt with the NDK. Some are optional and can be stubbed; a load-bearing one that will not build for Bionic is the most likely cause of project-level failure.

> **Settled strategy:** build the **full upstream-identical** binary first, maximizing parity and matching what upstream itself tests. If and only if R2 blocks that, fall back to a **serve-only slim build** — a `bun build --compile` whose entrypoint excludes the TUI, dropping `@opentui/core` and the embedded TUI worker, shrinking both APK size and native-dep surface. The slim build is a **documented divergence from upstream** and therefore **must** pass the conformance harness (Section 8) proving it is still wire-compatible. The choice is recorded in `docs/limitations.md` either way.

**R3 — CA certificates.** opencode launches with `--use-system-ca`. If Bun's TLS does not read Android's CA layout (`/system/etc/security/cacerts`), **every LLM provider call fails on TLS** and the app looks broken in a confusing way. M0 must probe TLS to a real provider host, not assume it.

**R4 — PTY availability (largest unknown; gates the Termux-like claim).** A Termux-like terminal needs a real pseudo-terminal: `forkpty()`, `/dev/ptmx`, job control, `SIGWINCH`. Android 10+ tightened SELinux around `devpts` and removed `TIOCSTI`. **Whether a normal unrooted app can allocate a PTY is not known with confidence.** This single assumption carries the "Termux-like" framing.
  Mitigating fact: **`opencode serve` requires no TTY at all.** A hard "no" on PTY leaves the primary deliverable — the server backend for the GUI — completely intact, costing only the interactive-terminal feature. M2 is therefore explicitly gated on this answer.

**R5 — Process death.** `opencode serve` is a child process and Android kills backgrounded apps. Mitigations: foreground service with the correct FGS type for API 34+; classify `SIGKILL` as the phantom-process killer rather than a crash; back off; on repeated kills, deep-link the user to battery-optimisation settings.

**R6 — Disk and RAM.** APK realistically **120-200 MB** (Bun Android alone is 83.0 MB unpacked). Server RAM footprint is unmeasured; M0 records it. This is a real cost of "real opencode, bundled, no download", accepted knowingly.

---

## 8. Testing and cloud CI

### 8.1 The arm64 honesty gap

**GitHub Actions runners are x86_64. There is no ARM emulator.** Therefore:

- **`linux-x64-android`** is added to the build matrix: CI-only, never shipped, and it is what actually **executes** in CI.
- **`linux-arm64-android`** is the shipped target. It is **built and inspected** in CI — ELF class checks, `readelf` verification, 16 KB page alignment (`-Wl,-z,max-page-size=16384`), dynamic-linker and `NEEDED` assertions confirming Bionic linkage — but it is **not executed**.

This gap is real and is never papered over. Two things narrow it: x86_64 and arm64 exercise the **same Bun Android runtime and the same Bionic**, differing only at ISA level; and the arm64 binary additionally gets a **`qemu-aarch64` smoke run** to prove it links and reaches `main`. qemu-user is expected to break Bun's JIT, so that is recorded as **link-level proof, not behavioural proof**. Any arm64-only behaviour claim is prohibited unless a human tests on real hardware.

### 8.2 The proof loop (entirely in cloud)

1. KVM-enabled emulator (API 30 / 34 / latest) installs the **x86_64** debug APK.
2. Launch; wait for `GET /global/health`.
3. Mock LLM server runs on the runner, reached from the emulator via the host loopback alias `10.0.2.2`. Recorded fixtures + scripted tool-call streams, so tests are deterministic and need **no API keys**.
4. **Full session end-to-end:** create session → send prompt → streamed assistant reply → tool call → **verify a file actually lands in the workspace on the emulator filesystem**.
5. `conformance.yml` runs upstream opencode (native x86_64 Linux) on the same runner as an **oracle** and diffs OpenAPI responses for identical requests — tool outputs, edit/patch results, permission decisions, config resolution. Fails on divergence.
6. Artifacts uploaded on every run: logcat, screenshots, screenrecord mp4, UI hierarchy dumps, ANR traces.

**If step 4 passes, real upstream opencode genuinely runs on Android.** That is the single most important result in this project and the gate for calling M1 complete.

### 8.3 Test layers

- **Pure JVM** — `:core:supervisor` (spawn/health/backoff/restart-cap/failure-classification), `:core:reach` (bind policy, token generation, LAN toggle state machine), `:core:env` (layout, PATH, prechecks). No emulator, fast, deterministic.
- **Robolectric** — Android-coupled logic without a device.
- **Instrumented on x86_64 emulator** — payload bootstrap, W^X exec of shipped executables, real `opencode serve` startup, LAN toggle rebind, auth rejection, terminal rendering (gated on R4).
- **Conformance** — differential vs upstream oracle, as above.
- **`upstream-watch.yml`** (nightly) — detects new upstream releases, diffs the OpenAPI spec and tool schemas, opens an issue. Keeps the pin honest.

### 8.4 Required workflows

`ci.yml` (ktlint, detekt, unit tests, Robolectric, debug APK for both ABIs, ELF + 16 KB alignment checks) · `emulator.yml` (matrix above, on `workflow_dispatch` + nightly to protect minutes) · `conformance.yml` (differential oracle) · `scenarios.yml` (scripted E2E with video and logs) · `upstream-watch.yml` · `release.yml` (signed APK via Secrets, checksums, SBOM, GitHub Release, fastlane metadata for F-Droid).

---

## 9. Error handling — deny-safe and diagnostic

The failure that matters most is **the Bun Android runtime failing to start at all**, which R1 makes plausible. That is not a retry loop; it is a dead app with no explanation. Therefore:

- **Non-zero exit inside the startup window → classified as `RUNTIME_INIT_FAILURE`, not a crash.** The supervisor stops retrying and surfaces the stderr tail with a plain-language cause. A blind respawn loop would hide the one error that actually matters.
- **Known napi load failures** → stderr signature mapped to a documented remediation, because raw NAPI errors are unreadable to a user.
- **Never report "ready" without a green health gate.** On timeout, show diagnostics, not a false success.
- **Pre-spawn:** verify payload checksums and free space; refuse to start rather than corrupt state.
- **Repeated `SIGKILL`** → identify as the phantom-process killer, back off, then offer a deep link to battery-optimisation settings.
- **Out of memory:** read the process memory class and size supervisor buffers accordingly; log the ceiling.
- **TLS failure (R3)** → distinct message pointing at the CA bundle, not a generic network error.
- **Unreachable LAN address after a network change** → re-resolve, and if the server is up but unreachable, say so specifically.

---

## 10. Milestones

Risk-first ordering. **M0 is a spike and a hard gate: no other work starts until it is green**, because M0 is where R1, R2, R3, and R4 stop being opinions.

| Milestone | Contents | Exit gate |
|---|---|---|
| **M0** — spike | PTY feasibility (R4) · Bun Android boots on the emulator · `bun --version` runs · napi dep load failures enumerated (R2) · CA/TLS reachability (R3) · JIT present or absent (R1) · cold-start time and RAM measured | **GO/NO-GO.** GO requires all four of: Bun Android runs; `opencode serve` starts and answers `/global/health`; TLS to a real provider host succeeds; and R2's blocking set is fully enumerated. Findings, measurements, and a patched build script land in `docs/limitations.md` and `UPSTREAM.md`. |
| **M1** | Host + environment + payload bootstrap + `serve` on localhost + CI emulator E2E with mock LLM | Full session completes on the emulator (Section 8.2 step 4). Debug APK artifact downloadable. |
| **M2** | Terminal UI + `termux-emulator` | **Gated on M0's R4 answer.** If PTY is unavailable, M2 is dropped, recorded in `docs/limitations.md`, and work proceeds to M3. |
| **M3** | LAN toggle + auth + QR + reachability tests | LAN bind, auth accept/reject, and rebind verified on the emulator. |
| **M4** | Parity hardening: Bionic rebuilds of native deps (R2), or documented slim-build fallback; conformance vs upstream oracle | **Zero divergence** on the covered conformance endpoint set (`/global/health`, `/project`, `/session` CRUD, `/session/:id/message`, `/session/:id/abort`, `/file*`, `/find*`, `/config`, `/agent`, `/command`, `/event`). Every endpoint in that set that is *not* covered must be named explicitly in `docs/limitations.md` — silence is not coverage. |
| **M5** | R8, baseline profile, signed release, F-Droid metadata, docs complete | Signed artifact + SBOM + checksums; `docs/limitations.md` current. |

Process: small commits, a PR per milestone, `docs/parity.md` updated per decision, questions to the maintainer limited to architecture-level trade-offs — never hardware, never local-machine questions.

---

## 11. Attribution, branding, and licensing

- Keep upstream opencode's `LICENSE` (MIT) and attribution. Record the pinned commit in `UPSTREAM.md`.
- This is an independent project, **not built by the opencode team and not affiliated with them**. State this plainly in the README. Do not claim official status; do not remove upstream credit.
- Vendored third-party code (`termux-emulator`, `busybox`, `ripgrep`, `git`) is pinned by commit with license recorded in `UPSTREAM.md`.
- `bun` itself is MIT, redistributed as part of the compiled artifact.

---

## 12. Non-goals and open questions

**Non-goals:** the native GUI (a separate later step); a Kotlin reimplementation of opencode (`opencode-android` covers that); proot, root, or a glibc rootfs; GMS/Firebase; on-device manual QA steps as a *requirement* for the build to be considered green.

**Open questions, to be answered by M0 rather than by guesswork:**
1. Can an unrooted app allocate a PTY? (R4 — gates M2.)
2. Does JSC JIT function on Android, or is it interpreter-only? (R1 — determines acceptable performance.)
3. Do opencode's napi dependencies build for Bionic, and which are load-bearing? (R2 — may force the slim fallback.)
4. Does Bun read Android's CA store? (R3 — blocks all provider calls if not.)
5. What are real cold-start time and steady-state RAM for `opencode serve` on a phone? (R6 — sets the product's performance budget.)
