# M0 Runtime Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or disprove that real upstream opencode runs on Android, by building an Android target of the upstream binary and executing it on a cloud emulator — producing a written GO/NO-GO verdict on risks R1, R2, R3, R4, R6.

**Architecture:** No Android app is written in M0. The upstream `opencode` binary is cross-compiled for `linux-arm64-android` and `linux-x64-android` by a small patch to opencode's own `build.ts`, then pushed onto a KVM emulator with `adb` and executed directly. This answers every runtime question at near-zero cost — no APK, no Gradle, no `jniLibs` packaging. Five probes run in CI and their outputs are consolidated into a written verdict.

**Tech Stack:** GitHub Actions · `ubuntu-latest` runner · Bun 1.4.2 · Android SDK cmdline-tools + emulator (KVM) · `adb` · Node.js for repo-side scripts · opencode upstream at `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`

**Spec:** `docs/superpowers/specs/2026-10-02-opencode-mobile-design.md` — the plan argues from the spec; executors read both.

> **Note on TDD in M0:** M0's deliverable is an *answer*, not a feature. Its verification is assertion-based CI gates (a probe fails the workflow if its condition is unmet) rather than unit tests, because there is no product code to unit-test yet. TDD applies in full from M1 onward. Where M0 does contain real logic — the probe-result classifier — it is written test-first, in Task 6.

## Global Constraints

These apply to every task. Values are copied verbatim from the spec; do not re-derive or "improve" them.

- **Upstream pin:** `anomalyco/opencode`, branch `dev`, commit `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`, release `v1.18.34`. Re-verify and record in `UPSTREAM.md` in Task 1.
- **Build Bun version: `1.4.2`.** Required — Bun only gained the `aarch64-linux-android` compile target after PR oven-sh/bun#29675. An older Bun cannot produce these artifacts.
- **Never build or test on the maintainer's device.** No `./gradlew`, Gradle, Android SDK/NDK toolchain, emulator, Docker, `bun install`, or any package manager. No large checkouts — use sparse fetches. The maintainer has ~1.5 GB RAM free; Gradle alone wants 2–4 GB.
- **CI is the only oracle.** A claim of "verified" is valid only with a specific green workflow run ID. Local file-level checks are recorded as `NOT_EXECUTED`, never as passes.
- **Target artifact names** produced by the patched build: `opencode-linux-arm64-android` (shipped) and `opencode-linux-x64-android` (CI-only, never shipped).
- **Bun Android ARM64 binary:** `@oven/bun-linux-aarch64-android`, version `1.4.2`, unpacked size `87,007,476` bytes.
- **Emulator API matrix:** API 30, 34, and latest (35). All three must run the probes; results are reported **per API level** and never aggregated into a single pass/fail.
- **x86_64 is what executes; arm64 is what ships.** Any statement generalising x86_64 emulator results to arm64 devices is prohibited.
- **Secrets:** no API keys. TLS probes target public endpoints that require no credentials.
- **Attribution:** the repo is independent, not built by or affiliated with the opencode team. Upstream MIT `LICENSE` and credit are preserved. Every vendored or fetched artifact records its source commit and license in `UPSTREAM.md`.

## Review Focus

Five input classes the spec implies that no M0 task's assertions directly exercise — the things most likely to produce a false "it works". Each is pinned by a test in the task that owns the relevant code.

1. **W^X and JIT behaviour varies by API level.** Android tightened executable-memory policy across releases. A probe that passes on API 30 proves nothing about API 34 or 35. *A reasonable person would expect the verdict to state per-API results and to refuse a single green summary.*
2. **x86_64 results do not transfer to arm64.** The executed binary is x86_64; the shipped one is arm64. *A reasonable person would expect every claim tagged with the ABI it was actually measured on, and no arm64 performance claim at all.*
3. **A pushed standalone binary is not a `jniLibs`-installed binary.** In the app, the payload is installed by the package manager into `nativeLibraryDir` with different SELinux labels, sibling-path resolution, and permissions. *A reasonable person would expect M0's success not to be reported as proof that the packaged app will exec.*
4. **Emulator numbers are not a device budget.** A KVM emulator shares the runner's CPU; a phone's big.LITTLE scheduler, thermal limits, and battery behaviour are absent. *A reasonable person would expect cold-start and RAM figures labelled as emulator-derived and explicitly not a product performance budget.*
5. **`adb shell` process lifetime is not Android app process lifetime.** The phantom-process killer, foreground-service rules, and background execution limits never fire for a process launched over `adb`. *A reasonable person would expect the verdict to state that "it ran for 10 minutes in the spike" says nothing about surviving on a phone.*

---

### Task 1: Upstream pin, build patch, and Android artifact build in CI

**Files:**
- Create: `UPSTREAM.md`
- Create: `patches/opencode-android-target.patch`
- Create: `scripts/fetch-upstream.sh`
- Create: `.github/workflows/m0-build.yml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - GitHub Actions artifact `opencode-android-binaries` containing `opencode-linux-arm64-android/bin/opencode` and `opencode-linux-x64-android/bin/opencode`.
  - `UPSTREAM.md` recording the pinned SHA, Bun version, and the exact patch rationale.
  - This task's artifact `opencode-android-binaries` is consumed by **Task 4** only. Task 3 deliberately uses the npm Bun package instead, so that a Bun-level failure is distinguishable from an opencode-level failure.

- [ ] **Step 1: Create `UPSTREAM.md` with the verified pin**

Record: repo `anomalyco/opencode`, default branch `dev`, pinned commit `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`, release `v1.18.34`, license MIT, and the build Bun version `1.4.2` with the reason (PR oven-sh/bun#29675 added the `aarch64-linux-android` target). Add a section "Pinned upstream files read" listing `packages/opencode/script/build.ts` (the file this repo patches) and `packages/core/src/ripgrep/binary.ts`, each with the commit and the specific line ranges that were read. State that no module is ever implemented from memory.

- [ ] **Step 2: Verify the pin still resolves before relying on it**

Run:
```bash
gh api repos/anomalyco/opencode/commits/dev --jq '.sha'
```
Expected: exactly `1ddb0873aee50d209d1a8d7f91b89c5daf692d49`.

If it does not match, **stop** and report to the maintainer. Do not silently re-pin — a moved `dev` invalidates every line of the spec's Section 3 evidence table, which must be re-read and the spec amended.

- [ ] **Step 3: Write `scripts/fetch-upstream.sh`**

A CI-only helper (it clones opencode, so it must **never** be run on the maintainer's device). It must: take the SHA as `$1`, `git clone --filter=blob:none` upstream into a temp dir, `git checkout "$1"`, and print the checkout path. It must refuse to run if `$CI` is not `true`, so an accidental local invocation fails loudly instead of exhausting the device's RAM.

- [ ] **Step 4: Write `patches/opencode-android-target.patch` against `build.ts`**

Five edits, exactly as follows, against `packages/opencode/script/build.ts` at the pinned commit:

1. Widen the target type: `abi?: "musl" | "android"`.
2. Append two entries to `allTargets`:
   ```ts
   { os: "linux", arch: "arm64", abi: "android" },
   { os: "linux", arch: "x64", abi: "android" },
   ```
3. `FFF_LIBC` (line ~193): map `"android"` to `"gnu"`. Bionic is the closer match to the glibc branch of `@ff-labs/fff-bun`, and `"gnu"` is the existing non-musl default.
4. `OPENCODE_LIBC` (line ~199): map `"android"` to `"glibc"`, so the native-spawn logic takes its existing default branch. **Document this as a decision, not a fact**, in `UPSTREAM.md`, together with the fallback: if native process spawning misbehaves in Task 4, the alternative is `"musl"` and Task 4's assertions are re-run with it.
5. Add **no** smoke-test change. The host-side smoke test (line ~211) only runs binaries matching the runner's own platform, so it will correctly skip Android targets. The Android smoke test is Tasks 3 and 4's job, running on the emulator. Note this explicitly in `UPSTREAM.md`.

The artifact name is derived automatically: the `name` array (line ~146) filters `Boolean`, so `abi: "android"` yields `opencode-linux-arm64-android`; `compile.target` (line ~177) then becomes `bun-linux-arm64-android`. No further edits are needed. Verify this derivation is what the patch produces rather than assuming it.

- [ ] **Step 5: Validate the patch applies cleanly, in CI only**

Add a `patch-verify` job to `m0-build.yml` that fetches upstream and runs `git apply --check`. Expected: exit 0, no output.

This step's assertion: **the patch applies to the pinned commit.** A failure here means the pin moved — stop and report.

- [ ] **Step 6: Write `.github/workflows/m0-build.yml`**

Jobs, in order:

- `patch-verify` — Step 5's check.
- `build-android` — matrix over `[arm64, x64]`. Installs Bun `1.4.2` pinned. Runs `scripts/fetch-upstream.sh` with the SHA, applies the patch, runs `bun install`, then `bun run script/build.ts` (or the documented equivalent single-target invocation) producing both Android artifacts. Uploads `opencode-android-binaries` with a retention of 14 days.

Assertions in this job, each of which must fail the workflow:
- Both artifact paths exist and are non-empty.
- `file <artifact>` reports an `ELF 64-bit LSB` executable for `aarch64` / `x86-64` as appropriate.
- `readelf -d <artifact>` shows **no** `libc.so.6` and **no** `ld-linux-*` — proving Bionic linkage, not glibc.
- `readelf -lW <artifact>` shows `Align` of `0x4000` (16 KB) on `LOAD` segments, per the spec's page-alignment requirement.

- [ ] **Step 7: Run the workflow and read the result back over the API**

```bash
git push origin main
gh run list --workflow m0-build.yml --limit 1
gh run view <run-id> --log-failed
```

Expected: green, with `opencode-android-binaries` downloadable. Record the run ID in the task report as the evidence for this task. If any assertion fails, fix and re-run — **do not** record this task complete on a red run.

- [ ] **Step 8: Commit**

```bash
git add UPSTREAM.md patches/ scripts/ .github/workflows/m0-build.yml
git commit -m "build: cross-compile opencode for android-arm64 and android-x64"
```

---

### Task 2: PTY feasibility probe (risk R4)

Independent of Task 1 and cheap; run it second because its answer can change M2's scope.

**Files:**
- Create: `native/ptyprobe/main.c`
- Create: `.github/workflows/m0-pty.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `docs/limitations.md` entry stating the R4 verdict (`PTY_AVAILABLE` or `PTY_UNAVAILABLE`) with the raw `errno` and `strerror` text. Task 6 reads this verdict.

- [ ] **Step 1: Write the probe program `native/ptyprobe/main.c`**

A single translation unit that, in order, attempts and reports each of:
1. `open("/dev/ptmx", O_RDWR)` — report `errno`/`strerror` on failure.
2. `grantpt`/`unlockpt` on the resulting fd.
3. `ptsname` to obtain the slave path, then `open` the slave.
4. `forkpty()` — report `errno`/`strerror` on failure.
5. In the child, `_exit(0)`; in the parent, `waitpid` and report the child's exit status.

Print one machine-readable line per step in the form `STEP=<n> RESULT=OK|FAIL ERRNO=<n> MSG=<strerror>`, then a final line `PTY_VERDICT=AVAILABLE|UNAVAILABLE`. Exit `0` when verdict is `AVAILABLE`, exit `3` when `UNAVAILABLE` — **a non-zero exit here is the expected, informative outcome, not a broken build**, and the workflow must treat exit `3` as a recorded result rather than a failure.

Also print `getuid()`, `geteuid()`, and `API level` read from `ro.build.version.sdk` so the verdict is attributable to a specific API level.

- [ ] **Step 2: Write `.github/workflows/m0-pty.yml`**

Matrix `api-level: [30, 34, 35]`. Builds `main.c` with the NDK for `x86_64` (CI-only ABI; see Review Focus #2), boots the matching KVM emulator, `adb push`es the binary to `/data/local/tmp/ptyprobe`, `chmod 755`, runs it, and captures stdout to `pty-<api-level>.log`.

Assertions, **per API level**, all of which must be satisfied for the workflow to be green:
- The binary built and ran on all three API levels.
- Exactly one `PTY_VERDICT=` line is present per log.
- If any level reports `UNAVAILABLE`, the workflow **still succeeds** but writes a `::warning::` annotation naming the API levels where PTY is unavailable.

A red workflow here means the *harness* broke (build failure, emulator failure, missing verdict line) — not that PTY is unavailable. Distinguishing those two is the whole point of this task.

- [ ] **Step 3: Run and read back per-API results**

```bash
git push origin main && gh run view <run-id>
gh api repos/Exodi-dio/opencode-mobile/actions/artifacts --jq '.artifacts[].name'
```

Download the logs artifact and confirm one verdict per API level. Expected: three verdicts, possibly differing. A single result is a **harness bug**, not a finding.

- [ ] **Step 4: Record the verdict**

Write to `docs/limitations.md`:

```
## R4 - PTY availability
Verdict: <AVAILABLE|UNAVAILABLE>
API 30: <raw step results>
API 34: <raw step results>
API 35: <raw step results>
Consequence: M2 proceeds / M2 is dropped per spec Section 10.
```

State per-API results separately. Never collapse to one verdict.

- [ ] **Step 5: Commit**

```bash
git add native/ptyprobe/main.c .github/workflows/m0-pty.yml docs/limitations.md
git commit -m "spike: determine PTY availability per Android API level"
```

---

### Task 3: Bun Android runtime probe (risks R1, R6)

**Files:**
- Create: `scripts/probe-bun.sh`
- Create: `.github/workflows/m0-bun.yml`

**Interfaces:**
- Consumes: nothing from Task 1 (uses the npm Bun package, not the opencode build).
- Produces: `bun-probe` logs per API level, and a measured `COLD_START_MS` / `RSS_KB` for Bun. Task 6 consolidates.

- [ ] **Step 1: Write `scripts/probe-bun.sh`**

Downloads `@oven/bun-linux-aarch64-android@1.4.2` and `@oven/bun-linux-x64-android@1.4.2` from the npm registry, verifies the tarball's SHA-512 against the value npm publishes, extracts, and prints the resulting binary path.

CI-only: it must refuse to run unless `$CI` is `true`, for the same RAM reason as Task 1's fetch script.

- [ ] **Step 2: Write `.github/workflows/m0-bun.yml`**

Matrix `api-level: [30, 34, 35]`, and for each, push the **x86_64-android** Bun binary to `/data/local/tmp/bun` and run, capturing each result as its own log line:

| Probe | Assertion |
|---|---|
| `bun --version` | Prints `1.4.2`. A crash or `Segmentation fault` is a **finding**, not a harness failure — record and continue. |
| `bun -e 'console.log(1+1)'` | Prints `2`. Proves the JS engine executes at all. |
| `bun -e 'for(let i=0;i<3e7;i++){}; console.log("done")'` under 30 s | Proves the engine is *usable*. Whether this is JIT-compiled or interpreted is **not** determinable from timing alone — see Step 4. |
| `bun -e 'fetch("https://api.github.com").then(r=>console.log(r.status))'` | **Proves R3.** Expect `200` without credentials. Any TLS/DNS failure is the R3 finding. |
| `bun -e 'console.log(process.platform, process.arch)'` | Expect `android` and `x64`. **This is a direct check of whether Bun's Android support landed as documented.** |

Plus cold-start and memory measurement: time `bun --version` over 5 runs (report median), and read peak RSS via `/proc/<pid>/status` `VmHWM` during a sleep in a Bun process.

- [ ] **Step 3: Run and collect per-API results**

Expected: five probe results per API level, three API levels. Report per level. Any probe that crashes is recorded with its signal number (`adb shell` reports `Fatal signal 11` etc.) — **preserve the raw output**, because the signal is the finding.

- [ ] **Step 4: Determine JIT presence honestly**

Do **not** infer JIT from a timing number. Instead record, as two separate facts: (a) Bun's own reported build/revision string from `bun --version`, and (b) whether the PR's own caveats apply. In `docs/limitations.md` write R1's verdict as a bounded statement — e.g. "JIT presence on Android is unconfirmed; PR oven-sh/bun#29675 states Android has no upstream runtime test coverage and lists JIT W^X as unverified" — and mark the performance question **OPEN** unless a positive in-binary signal is found. An unconfirmed JIT is a legitimate M0 outcome; a guessed one is not.

- [ ] **Step 5: Commit**

```bash
git add scripts/probe-bun.sh .github/workflows/m0-bun.yml docs/limitations.md
git commit -m "spike: probe bun android runtime, TLS, and cold start per API level"
```

---

### Task 4: opencode serve health and native-module probe (risks R2, R6)

The central question: does **real opencode** start and serve on Android.

**Files:**
- Create: `scripts/probe-opencode.sh`
- Create: `.github/workflows/m0-opencode.yml`

**Interfaces:**
- Consumes: artifact `opencode-android-binaries` from Task 1.
- Produces: per-API `opencode-probe` logs, a measured `TIME_TO_HEALTHY_MS`, and the R2 native-module failure enumeration. Task 6 consolidates both.

- [ ] **Step 1: Write `.github/workflows/m0-opencode.yml`**

Matrix `api-level: [30, 34, 35]`, plus one `arch: arm64` job under **qemu-user** on the runner (see below). Downloads `opencode-android-binaries`, pushes the x86_64-android binary to `/data/local/tmp/opencode`, `chmod 755`.

- [ ] **Step 2: Boot the server and health-gate it**

Run, in background on the emulator:
```
/data/local/tmp/opencode serve --port 4096 --hostname 127.0.0.1
```
Then poll `GET /global/health` from the host via `adb forward tcp:4096 tcp:4096` + `curl`, every 250 ms, up to a **120 s** timeout. Record `TIME_TO_HEALTHY_MS` and whether `/global/health` returned `{"healthy":true,...}`.

Assertions:
- The binary executed at all. **A crash here is the M0 finding, not a harness failure** — capture the full logcat and stderr, and preserve the fatal signal number.
- The process stayed alive for **at least 60 s** after becoming healthy. A server that serves once then dies is a failed verdict.

- [ ] **Step 3: Enumerate R2 — which native modules fail to load**

From the same run, collect the full stderr and extract every native-module load failure. Specifically search for `Failed to load native binding`, `Cannot find module`, `.node`, and any `ELF` / `dlopen` errors. Produce a sorted, de-duplicated list.

Write the list to `docs/limitations.md` under R2, and for each entry classify it as:
- **load-bearing** — the server cannot become healthy without it;
- **optional** — the server is healthy without it (e.g. TUI-only or image-processing modules).

This classification is the input to the spec's slim-build fallback decision, so it must come from observed behaviour, not from reading `package.json`.

- [ ] **Step 4: Run the arm64 job under qemu-user, and label it correctly**

Add one job that runs the `linux-arm64-android` binary under `qemu-aarch64` on the runner, executing at minimum `opencode --version`.

Assertions:
- The binary loads its ELF, resolves its interpreter, and reaches `main` far enough to print a version string, or fails with a captured, preserved error.

**Label the result `LINK_LEVEL_ONLY` in the artifact and in `docs/limitations.md` in every case, successful or not.** A successful qemu run is explicitly **not** behavioural evidence, because qemu-user is expected to break Bun's JIT. Never let a green qemu job be cited as "opencode works on arm64".

- [ ] **Step 5: Run and collect**

Expected: three per-API x86_64 results plus one arm64 qemu result. Record per level; do not aggregate.

- [ ] **Step 6: Commit**

```bash
git add scripts/probe-opencode.sh .github/workflows/m0-opencode.yml docs/limitations.md
git commit -m "spike: run opencode serve on emulator, enumerate native module failures"
```

---

### Task 5: Reproducibility and provenance check

Guards against the most embarrassing M0 failure: a result that cannot be reproduced or traced.

**Files:**
- Modify: `UPSTREAM.md`
- Modify: `docs/limitations.md`
- Create: `.github/workflows/m0-repro.yml`

**Interfaces:**
- Consumes: artifacts and logs from Tasks 1, 3, and 4.
- Produces: a `M0-REPORT.md` and a provenance block in `UPSTREAM.md`. Task 6 consumes nothing further; this task's report *is* the deliverable Task 6 verifies.

- [ ] **Step 1: Re-run Task 3's and Task 4's workflows a second time**

Assertions: both produce the same verdicts. **Any verdict that changes between two identical runs is a flake and must be recorded as `FLAKY`**, not smoothed over — flakiness in the runtime is itself a finding about whether the runtime is safe to ship.

- [ ] **Step 2: Record provenance for every fetched artifact in `UPSTREAM.md`**

For each of: Bun Android binaries, `termux-emulator`, and any other vendored item — record source, exact version, license, and the commit or tag. Confirm upstream opencode's MIT `LICENSE` is retained and that the repo states plainly it is independent and not affiliated with the opencode team.

- [ ] **Step 3: Write `M0-REPORT.md`**

Structure it as: the four GO criteria from the spec's M0 row, each with its evidence and run ID; then per-risk verdicts for R1, R2, R3, R4, R6; then every Review Focus caveat that applies, restated as a limitation on the verdict; then the explicit list of what M0 did **not** establish.

The final section must state plainly, as explicit non-findings:
- Emulator results are **not** a device performance budget (Review Focus #4).
- `adb`-launched process lifetime is **not** Android app process lifetime (Review Focus #5).
- A binary `adb push`ed to `/data/local/tmp` is **not** the same execution environment as a `jniLibs`-installed payload in `nativeLibraryDir` — different SELinux label, different sibling-path resolution, different permissions, and no foreground-service or phantom-process-killer involvement (Review Focus #3). **M0 success therefore does not establish that the packaged app can execute its payload.** This is the single most likely way M0's green result gets over-read, so it must appear in the report as its own numbered non-finding.
- Nothing was verified on real arm64 hardware (Review Focus #2).

- [ ] **Step 4: Commit**

```bash
git add UPSTREAM.md docs/limitations.md M0-REPORT.md .github/workflows/m0-repro.yml
git commit -m "spike: M0 reproducibility run and consolidated report"
```

---

### Task 6: GO/NO-GO verdict, test-first

**Files:**
- Create: `scripts/classify-verdict.sh`
- Create: `scripts/test/classify-verdict.bats`
- Modify: `M0-REPORT.md`
- Modify: `docs/limitations.md`

**Interfaces:**
- Consumes: the probe logs and artifacts from Tasks 2, 3, and 4; the report from Task 5.
- Produces: the final GO/NO-GO line in `M0-REPORT.md`, and the gate that decides whether M1 starts.

- [ ] **Step 1: Write the failing test `scripts/test/classify-verdict.bats`**

Using `bats` (pinned version in CI), cover exactly these cases, because each encodes a judgement that must not be made by eye:

| Case | Input | Expected |
|---|---|---|
| All three API levels healthy | 3 `TIME_TO_HEALTHY_MS` values, all `healthy:true`, none `FLAKY` | `GO` |
| Any API level unhealthy | one `healthy:false` | `NO_GO` |
| Flaky between runs | identical input, one run differs | `NO_GO` + `FLAKY` marker |
| Only 2 of 3 API levels produced results | missing a level | `NO_GO` + `HARNESS_BROKEN` |
| arm64 qemu green but x86_64 red | mixed | `NO_GO` (x86_64 governs) |
| PTY unavailable | `PTY_VERDICT=UNAVAILABLE` on any level | `GO_WITH_M2_DROPPED` |
| PTY available | `PTY_VERDICT=AVAILABLE` on all levels | `GO` |

The fourth case is deliberate: a missing result is a **broken harness**, and the script must refuse to emit `GO` rather than treating absence as success.

- [ ] **Step 2: Run the tests to verify they fail**

Run in CI (`bats` is not installed on the maintainer's device and must not be):
```bash
bats scripts/test/classify-verdict.bats
```
Expected: all cases fail — `classify-verdict.sh` does not exist yet.

- [ ] **Step 3: Implement `scripts/classify-verdict.sh`**

Reads the probe logs as arguments and prints one line: `<VERDICT> <markers>`, where `VERDICT` is one of `GO`, `GO_WITH_M2_DROPPED`, `NO_GO` and `markers` is a comma-separated list drawn from `FLAKY`, `HARNESS_BROKEN`, `PTY_UNAVAILABLE`, `ARM64_QEMU_ONLY`.

Hard rule to implement: **absence of evidence is never success.** Any missing API level yields `HARNESS_BROKEN` and cannot produce `GO`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats scripts/test/classify-verdict.bats`
Expected: all cases pass.

- [ ] **Step 5: Run the classifier on M0's real logs and write the verdict into `M0-REPORT.md`**

The verdict line goes at the top of `M0-REPORT.md`, with the run IDs of every probe that fed it.

If the verdict is `NO_GO`, **stop and report to the maintainer** with the failing criterion and its evidence. Do not begin M1. Per the spec, a `NO_GO` means a risk needs a design change, which means the spec is amended first.

- [ ] **Step 6: Commit**

```bash
git add scripts/ M0-REPORT.md docs/limitations.md
git commit -m "spike: M0 GO/NO-GO verdict"
```
