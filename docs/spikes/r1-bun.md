# R1 / R3 / R6 - Bun Android runtime (fragment for `docs/limitations.md`)

Task 3 of the M0 runtime spike. Task 5 assembles this fragment into
`docs/limitations.md`; this file is the source of truth for R1, R3 and R6 as
measured through the **Bun binary itself**, and nothing else in the repo should
summarise them independently. (Task 4 measures R2/R6 through `opencode serve`;
that is a different binary and a different question.)

**Authoritative evidence:** workflow `m0-bun.yml`, run **37011349761**
(green, 2026-10-02), triggered by a push of commit `3a8206e`. Per-API artifacts
`bun-probe-logs-30`, `bun-probe-logs-34`, `bun-probe-logs-35`, aggregate
`r1-bun-summary`, and the binary inspection artifact `bun-fetch-info`
(retention 30 days). Probe source: `scripts/bun-probe-device.sh`. Fetch/verify
source: `scripts/probe-bun.sh`. Log assertions: `scripts/assert-bun-log.sh`.
Jobs: harness self-test `110851580996`, fetch/verify `110851580999`, API 30
`110851655875`, API 34 `110851655940`, API 35 `110851655905`, report
`110852226814`.

**Repeat runs:** **37010025261** (green, 2026-10-02) and **37010539013**
(green, 2026-10-02) re-ran the byte-identical probe on freshly created
emulators. All five probes passed on API 30 and API 34 in every run, and the JIT
signal was `POSITIVE` on all three API levels in every run. The one moving part
is API 35 TLS: it **passed** in 37010539013 and **failed at DNS** in 37010025261
and 37011349761 (see R3 and Caveat 8). The raw logs below are from the
authoritative run 37011349761.

## The entries for `docs/limitations.md`, verbatim

```
## R1 - JIT present and enabled on Android
Verdict: CONFIRMED present in the adb `shell` SELinux domain on API 30, API 34 and API 35 independently; NOT verified in an app (`untrusted_app_*`) domain (this line is a summary; the per-API lines below are the result and are never collapsed into it)
API 30: JIT_SIGNAL=POSITIVE JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=7f44adc3f000-7f44edc3f000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN; EXIT=0
API 34: JIT_SIGNAL=POSITIVE JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=71aa92204000-71aad2204000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN; EXIT=0
API 35: JIT_SIGNAL=POSITIVE JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=74db4b60c000-74db8b60c000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN; EXIT=0
Consequence: Bun's JavaScriptCore does compile JavaScript to executable memory in the shell/test domain on every API level measured, so M2 may rely on JIT there. The app-domain W^X gate stays OPEN: no run here executed in an `untrusted_app_*` domain, and the performance/throughput question is likewise OPEN. An in-app JIT measurement is still required before a packaged app's performance path is assumed. See caveats 1, 2, 5 and 9.

## R3 - TLS to the public internet using the system CA store
Verdict: WORKS on API 30 (3/3 runs) and API 34 (3/3 runs); on API 35 it WORKS when DNS resolves (1/3 runs) and FAILED AT DNS, never at TLS, in the other 2/3 runs (this line is a summary; the per-API lines below are the result and are never collapsed into it)
API 30: PROBE=tls STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=41 EXPECTED="200" OBSERVED="200"; EXIT=0
API 34: PROBE=tls STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=807 EXPECTED="200" OBSERVED="200"; EXIT=0
API 35: PROBE=tls STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=86 EXPECTED="200" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com"; EXIT=0
Consequence: a `200` from `fetch("https://api.github.com")` requires a completed TLS handshake whose certificate validated against the system trust store, so the Android CA-store path is exercised and works on API 30 and API 34 and (when DNS resolves) on API 35. The API 35 failures are name-resolution failures at the emulator/network layer, before any TLS handshake, so they do not test the CA store and must not be read as "TLS is broken on API 35". The API 35 DNS flake is recorded, not smoothed over.

## R6 - RAM footprint and cold start
Verdict: low and roughly flat across API levels, but measured on `bun --version` and a sleeping minimal Bun process, not on a served workload (this line is a summary; the per-API lines below are the result and are never collapsed into it)
API 30: COLD_START_MS_MEDIAN=7 COLD_START_MS_SAMPLES=" 6 6 7 7 7" COLD_START_CLOCK=date-ns COLD_START_N=5; RSS_VMHWM_KB=27156; EXIT=0
API 34: COLD_START_MS_MEDIAN=55 COLD_START_MS_SAMPLES=" 63 26 101 47 55" COLD_START_CLOCK=date-ns COLD_START_N=5; RSS_VMHWM_KB=27456; EXIT=0
API 35: COLD_START_MS_MEDIAN=48 COLD_START_MS_SAMPLES=" 61 52 33 30 48" COLD_START_CLOCK=date-ns COLD_START_N=5; RSS_VMHWM_KB=28544; EXIT=0
Consequence: Bun 1.4.2 starts and holds steady in an order-of-magnitude envelope of ~26-29 MB peak RSS on the x86_64 emulator, with cold start in the single- to low-double-digit tens of milliseconds. This is the runtime's own floor, not the server's footprint. Task 4's `opencode serve` health/RSS measurement is the R6 number that gates M2; this entry only establishes that the runtime itself is not the obstacle.
```

## R1 - what the "JIT signal" is, and why it is not a timing guess

The brief forbids inferring JIT from a timing number. This probe does not. It
records two independent facts and derives a third:

1. **Build identity.** `bun --version` prints `1.4.2`; `bun --revision` prints
   `1.4.2+744846f84` (identical on all three API levels). This is Bun's own
   reported build string.
2. **A hot loop that cannot be deleted.** The engine-usable probe runs
   `let s=0;for(let i=0;i<3e7;i++){s=(s+i*3)|0}console.log("done",s)`. It prints
   a value (`done -918471104`) that is identical on all three API levels, so the
   loop really executed; an earlier draft that used a side-effect-free
   `for(...){}` was changed precisely because a JIT is allowed to eliminate it.
3. **An in-binary mapping.** Immediately after that loop, the same Bun process
   reads `/proc/self/maps` from inside itself and reports every executable
   mapping. All three API levels show an executable, **writable** anonymous
   region whose name is `[anon:JSJITCode]` - JavaScriptCore's own JIT code
   region (`exec_anon=3`, `w_and_x=1`). That is a direct in-binary signal, not
   a timing inference.

`JIT_SIGNAL` is derived from that observed string in
`scripts/bun-probe-device.sh` (`*JSJITCode*` -> `POSITIVE`), and the derivation
itself is asserted in the workflow's `harness-self-test` job, so it cannot go
vacuous. `JIT_DETERMINATION` is deliberately **not** a Boolean: it is
`SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN`, because the mapping is measured in the
`adb shell` domain (`u:r:shell:s0`, `UID=2000`) and says nothing about whether a
packaged `untrusted_app_*` process is allowed to map `W|X` memory.

### Upstream caveats (from the primary source)

PR `oven-sh/bun#29675` ("android support", base `main`, head
`claude/android-support`) is **closed, not merged** (`state=closed`,
`merged=false`, `merged_at=null`, closed 2026-04-26; its head is 36 commits
ahead of and 3244 behind `main`), so it is a design record, not the merge that
shipped Android support. Its body is nevertheless the upstream statement of the
caveats that apply here: Android had **no upstream runtime test coverage / no
test platform**, and JIT `W^X` was **"not yet verified at runtime."** The
shipped 1.4.2 packages exist regardless - `@oven/bun-linux-x64-android@1.4.2`
and `@oven/bun-linux-aarch64-android@1.4.2` both resolve with
`os:["android"]`, and both were integrity-verified here (see below) - so the
in-binary signal above is the first runtime check that the caveat is at least
satisfied in the shell domain.

## R1 - the shipped binaries (fetch and verify)

`scripts/probe-bun.sh` (CI-only) downloads both packages from the npm registry
and verifies each tarball's SHA-512 against npm's published integrity before
extracting. `bun-fetch-info` from run 37011349761 (also present in every green
run) contains:

| | x86_64-android (runs on the emulator) | aarch64-android (shipped target, inspected only) |
|---|---|---|
| package | `@oven/bun-linux-x64-android@1.4.2` | `@oven/bun-linux-aarch64-android@1.4.2` |
| npm integrity | `sha512-6HC5tzcC79113n2IHCTJMWv+HsQImv4ZFEK2XpYLxY6HbT8tM4cUM2Zv1bHZBQsS3jv/zYBamDJ1UX7If0d5tw==` | `sha512-3mZKO2rhsNgbAUtAHC1UKUlF2zTxFraDZT/Elv8wzyH0fJL9h+Iv3TgB9lO63w89PRn3eFe+NRA1bhVgikKNPQ==` |
| ELF | `ELF 64-bit LSB pie executable, x86-64 ... interpreter /system/bin/linker64, BuildID[sha1]=5ff2150f6bb37f7354f0e09fae3b33d9b5f39ca5, not stripped` | `ELF 64-bit LSB pie executable, ARM aarch64 ... interpreter /system/bin/linker64, BuildID[sha1]=69943ba2fedf06be7f2fa76deaa37675cb49e64d, not stripped` |
| NEEDED | `libc.so`, `libm.so`, `libdl.so` | `libc.so`, `libm.so`, `libdl.so` |
| size (bytes) | 89,426,104 | 86,800,440 |
| sha256 (extracted file) | `12222610d9a72265ecb5955e09e009bc2b32cd9624427f8a76bec34965917054` | `f2970336bfccf36e4e8a408b25c627122f210e941672f184198c31f4dbd377a0` |

The plan's figures for the arm64 size (87,007,476) and the "1.4.2 is the first
release with an Android target" framing are superseded by what was actually
fetched: the values above are the measured ones. The arm64 binary was **never
executed** - this harness boots only x86_64 emulators - so every runtime claim
in this file is x86_64.

## Raw per-API results (authoritative run 37011349761)

Three verdicts, reported separately and never collapsed.

### API 30 (Android 11) - job `bun probe (API 30)` (110851655875)

```
BUNPROBE=1 API_LEVEL=30 ANDROID_RELEASE="11" SDK="30" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=138 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=49 EXPECTED="1.4.2" OBSERVED="1.4.2"
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=61 EXPECTED="2" OBSERVED="2"
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=26 EXPECTED="done" OBSERVED="done -918471104"
PROBE=tls STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=41 EXPECTED="200" OBSERVED="200"
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=13 EXPECTED="android x64" OBSERVED="android x64"
COLD_START_MS_SAMPLES=" 6 6 7 7 7" COLD_START_MS_MEDIAN=7 COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=27156 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=7f44adc3f000-7f44edc3f000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=POSITIVE JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN JIT_BASIS="JIT signal is the [anon:JSJITCode] executable mapping read from /proc/self/maps inside the running Bun process, not a timing inference; it is measured in the adb shell SELinux domain, so W^X in untrusted_app_* is unverified and the app-domain and performance questions stay open; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

### API 34 (Android 14) - job `bun probe (API 34)` (110851655940)

```
BUNPROBE=1 API_LEVEL=34 ANDROID_RELEASE="14" SDK="34" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=134 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=112 EXPECTED="1.4.2" OBSERVED="1.4.2"
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=190 EXPECTED="2" OBSERVED="2"
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=327 EXPECTED="done" OBSERVED="done -918471104"
PROBE=tls STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=807 EXPECTED="200" OBSERVED="200"
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=135 EXPECTED="android x64" OBSERVED="android x64"
COLD_START_MS_SAMPLES=" 63 26 101 47 55" COLD_START_MS_MEDIAN=55 COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=27456 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=71aa92204000-71aad2204000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=POSITIVE JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN JIT_BASIS="JIT signal is the [anon:JSJITCode] executable mapping read from /proc/self/maps inside the running Bun process, not a timing inference; it is measured in the adb shell SELinux domain, so W^X in untrusted_app_* is unverified and the app-domain and performance questions stay open; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

### API 35 (Android 15) - job `bun probe (API 35)` (110851655905)

```
BUNPROBE=1 API_LEVEL=35 ANDROID_RELEASE="15" SDK="35" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=145 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=46 EXPECTED="1.4.2" OBSERVED="1.4.2"
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=50 EXPECTED="2" OBSERVED="2"
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=113 EXPECTED="done" OBSERVED="done -918471104"
PROBE=tls STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=86 EXPECTED="200" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com"
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=72 EXPECTED="android x64" OBSERVED="android x64"
COLD_START_MS_SAMPLES=" 61 52 33 30 48" COLD_START_MS_MEDIAN=48 COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=28544 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=74db4b60c000-74db8b60c000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=POSITIVE JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN JIT_BASIS="JIT signal is the [anon:JSJITCode] executable mapping read from /proc/self/maps inside the running Bun process, not a timing inference; it is measured in the adb shell SELinux domain, so W^X in untrusted_app_* is unverified and the app-domain and performance questions stay open; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

`PROBE=platform` returning `android x64` is the direct check that Bun's Android
support landed as documented and that the ABI is what the fetch step expected.
`CASTORE_DIR=present` with a non-zero `CASTORE_COUNT` (138/134/145) is recorded
as context for R3, not as proof that Bun reads that directory; the `200` is the
proof. The `EXIT=` line is appended by the workflow (`echo EXIT=$?`) after the
probe's own final line, so a crash (e.g. 139) stays distinguishable from the
probe's own verdict. A `FAIL` probe is not a red job: the probe exits `0` once
every probe has been attempted and recorded.

## What "red" means for these risks

The brief's point is that a red workflow and a Bun-level failure are different
events, so the harness keeps them apart:

- the device program exits `4` with `BUN_PROBE_VERDICT=HARNESS_BROKEN` only when
  Bun is missing or the harness itself cannot run; a probe that crashes, times
  out or fails is recorded as `STATUS=CRASH|TIMEOUT|FAIL` with its signal and
  raw output, and still reaches `BUN_PROBE_VERDICT=COMPLETE`;
- `scripts/assert-bun-log.sh` accepts `PASS`, `FAIL`, `CRASH` and `TIMEOUT` as
  findings and rejects only broken output (no verdict line, two verdict lines,
  a verdict that contradicts the appended `EXIT=`, a probe that never reported,
  a probe reported twice, an unknown `STATUS`, a log from the wrong API level,
  no output at all);
- the `report` job fails on a **missing** API level - absence of evidence is
  never a result - and emits `::warning::` for a finding such as
  `API35:tls=FAIL` while staying green;
- the `harness-self-test` job proves both halves of that contract before any
  emulator boots (run 37011349761, job 110851580996, green in 11 s): 14 assertion
  cases behave as specified (4 accepted findings, 10 rejected broken logs), plus
  the real device probe run against a stub bun
  in three shapes (happy, segfaulting, missing). The JIT-signal derivation is
  itself one of the asserted cases.

One earlier run is recorded because the distinction is what makes it readable:
run **37009258321** had every probe green on all three API levels but its
`report` job was red on a `case`-syntax bug (`PASS|")` instead of `PASS|"")`).
That was a harness fault in the summary, not a Bun result; it is not cited as
evidence.

## Caveats - what this result does not establish

1. **Measured in the `shell` SELinux domain, not an app domain.** Every log is
   `SELINUX_CTX="u:r:shell:s0"` (`UID=2000`, `adb shell`). A packaged opencode
   runs as its own `untrusted_app_*` domain with its own `execute`/`execmem`
   policy. The R1 signal proves JIT compiles **in the shell domain**; it does
   **not** prove an app may map `W|X`. That is the single most important gap in
   this evidence, and it is exactly what an in-app probe (M1) must measure.
2. **x86_64 emulator, not arm64 hardware.** The executing binary was the
   x86_64-android build on an x86_64 system image. The arm64 Android binary was
   fetched, hash-verified and inspected, but never run. Nothing here is an arm64
   measurement.
3. **Not a `jniLibs`-installed binary.** The probe ran from `/data/local/tmp`
   with `/data/local/tmp` ownership and SELinux label, not from an app's
   `nativeLibraryDir`. Path resolution and labels differ.
4. **AOSP policies, not OEM policies.** The emulator runs AOSP SELinux policy.
   An OEM that further restricts execmem for apps would change the app-domain
   answer for that device only.
5. **The JIT signal is a mapping, not a measurement.** `[anon:JSJITCode]`
   proves a JSC JIT code region exists and is writable-executable at that
   instant. It does **not** measure which tier compiled (Baseline/DFG/FTL),
   throughput, or whether W^X is enforced by a later API-35+ `execmem`/`mseal`
   path for a different domain. The performance question is OPEN, as the brief
   requires.
6. **Cold start is `bun --version`, emulator-derived.** Five samples per API
   level, median reported; the spread is large (API 34: 26-101 ms) because the
   value is dominated by emulator scheduling, not Bun. It is not `opencode serve`
   startup and it is not a device budget.
7. **RSS is a minimal sleeping Bun.** `VmHWM` is sampled ~3 s into a process
   whose only work is `await new Promise(r => setTimeout(r, 8000))`. It is the
   runtime's floor (~26-29 MB), not the footprint of the server or of a loaded
   project. Task 4's measurement is the R6 gate.
8. **The API 35 TLS failures are DNS, not TLS.** `getaddrinfo ENOTFOUND` occurs
   before a socket is opened, so the attempt never reaches certificate
   validation. Across the three runs API 35 TLS passed once and DNS-failed
   twice. The successful `200`s on API 30/34 (and the passing API 35 run) are
   the CA-store evidence; the flake is attributed to the emulator/CI network
   layer and is left visible rather than retried away.
9. **"JIT works" is scoped to this binary and this domain.** Nothing here shows
   upstream `opencode`'s own bundled/native modules, WebView, or Bun FFI are
   unaffected by Android's execmem policy. Those are R2/Task 4 questions.
10. **The upstream caveat source is a closed PR.** `oven-sh/bun#29675` was
    closed without merging, so its caveats are a proposal's caveats, not a
    changelog entry for 1.4.2. The runtime measurement above stands on its own
    regardless.

## Supplementary observation (NOT part of the recorded verdict)

There is no app-domain or arm64 observation to add here. Recording one would
require building or running an APK or an arm64 image, which the M0 spike's
constraints (and this task's 1.5 GB host budget) forbid. The honest statement is
therefore that the app-domain and arm64 gaps are real and unmeasured, not that
they were informally checked. Contrast with R4's fragment, where an informal
on-device observation was possible because the maintainer's phone could run the
probe directly.

## What would change these verdicts

- An in-app probe (M1's first instrumentation job) failing to map `W|X` in
  `untrusted_app_*` on a real device would falsify R1's app-domain hope; only
  then would the JIT verdict be downgraded for packaged apps.
- A TLS/`api.github.com` failure on API 30 or API 34, or a TLS-layer (not DNS)
  failure on API 35, would change R3. The current API 35 flake is DNS.
- Task 4's `opencode serve` RSS/health numbers, which are the R6 gate; a served
  workload materially above the runtime floor would change the memory verdict.
- A later run disagreeing with runs 37010025261 / 37010539013 / 37011349761 on
  the JIT signal would be recorded by Task 5's reproducibility pass as `FLAKY`,
  not smoothed over.
