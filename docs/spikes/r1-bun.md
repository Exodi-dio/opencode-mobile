# R1 / R3 / R6 - Bun Android runtime (fragment for `docs/limitations.md`)

Task 3 of the M0 runtime spike. Task 5 assembles this fragment into
`docs/limitations.md`; this file is the source of truth for R1, R3 and R6 as
measured through the **Bun binary itself**, and nothing else in the repo should
summarise them independently. (Task 4 measures R2/R6 through `opencode serve`;
that is a different binary and a different question.)

**Authoritative evidence:** workflow `m0-bun.yml`, run **37034863849**
(green, 2026-10-02, commit `50f7f46`). Per-API artifacts
`bun-probe-logs-30`, `bun-probe-logs-34`, `bun-probe-logs-35`, aggregate
`r1-bun-summary`, and the binary inspection artifact `bun-fetch-info`
(retention 30 days). Probe source: `scripts/bun-probe-device.sh`. Fetch/verify
source: `scripts/probe-bun.sh`. Log assertions: `scripts/assert-bun-log.sh`.
Jobs: harness self-test `110930439169`, fetch/verify `110930439561`, API 30
`110930619078`, API 34 `110930619240`, API 35 `110930619151`, report
`110931278122`.

**Superseded:** run **37011349761** (green, 2026-10-02) reported
`JIT_SIGNAL=POSITIVE` on all three API levels and that claim is **withdrawn**.
Its probe read `/proc/self/maps` only inside the process that ran the hot loop.
This run adds a control process that runs no hot loop, and that control shows
the same `[anon:JSJITCode]` region - so the old signal measured that Bun maps a
writable-executable JIT heap, not that the loop was compiled. The derivation is
unchanged in spirit but its input set is not; R1 is now **OPEN**. Runs
**37010025261** and **37010539013** ran the older probe and are superseded for
the same reason. Their R3 and R6 observations are unaffected (the R3
conclusion is now stated more weakly, and R6 is now reported net of a measured
harness floor).

## The entries for `docs/limitations.md`, verbatim

```
## R1 - JIT present and enabled on Android
Verdict: OPEN on API 30, API 34 and API 35. Bun maps a writable-executable JavaScriptCore JIT region ([anon:JSJITCode]) in the adb `shell` SELinux domain on every API level measured, but a control process that runs no hot loop maps the same region, so this evidence does NOT show that a hot loop was compiled and does not license relying on JIT. The app-domain (untrusted_app_*) question is also unmeasured.
API 30: JIT_SIGNAL=INCONCLUSIVE JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_DETERMINATION=OPEN JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=78e24bfc0000-78e28bfc0000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=79967ab1d000-7996bab1d000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"; EXIT=0
API 34: JIT_SIGNAL=INCONCLUSIVE JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_DETERMINATION=OPEN JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=787b255c3000-787b655c3000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=770011808000-770051808000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"; EXIT=0
API 35: JIT_SIGNAL=INCONCLUSIVE JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_DETERMINATION=OPEN JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=7bab05e82000-7bab45e82000 rwxp 00000000 00:00 0                          [anon:JSJITCode]" JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=741a0863e000-741a4863e000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"; EXIT=0
Consequence: no claim about JIT compiling on Android may be made from this evidence, in any SELinux domain. M2 may not assume JIT is present, enabled or permitted on Android until an in-app measurement (see caveats 1 and 2) or a tier-level measurement closes this. Performance and throughput questions are likewise OPEN. See caveats 1, 2 and 3.

## R3 - TLS to the public internet (x86_64 emulator)
Verdict: WORKS on API 30 - two independent hosts completed a handshake with a publicly-trusted certificate (HTTP 200) and an untrusted certificate was REFUSED with a certificate-specific error, which is the negative control that proves validation is on. API 34 and API 35 are UNMEASURED for TLS in this run: all three hosts failed name resolution, which is below Bun entirely. TRUST-STORE SOURCE (Android system store vs a Bun-bundled store): OPEN on all API levels.
API 30: PROBE=tls STATUS=PASS ... OBSERVED="DNS=ok STATUS=200" TLS_DNS=ok; PROBE=tls-host2 STATUS=PASS ... OBSERVED="STATUS=200"; PROBE=tls-badcert STATUS=PASS ... OBSERVED="FETCH_ERROR: self signed certificate code=DEPTH_ZERO_SELF_SIGNED_CERT" TLS_BADCERT_VERDICT=CERT_REJECTED; EXIT=0
API 34: PROBE=tls STATUS=FAIL EXIT=9 ... OBSERVED="DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com" TLS_DNS=ENOTFOUND; PROBE=tls-host2 STATUS=FAIL ... OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND example.com"; PROBE=tls-badcert ... OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND" TLS_BADCERT_VERDICT=DNS_UNRESOLVED; EXIT=0
API 35: PROBE=tls STATUS=FAIL EXIT=9 ... OBSERVED="DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com" TLS_DNS=ENOTFOUND; PROBE=tls-host2 STATUS=FAIL ... OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND example.com"; PROBE=tls-badcert ... OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND" TLS_BADCERT_VERDICT=DNS_UNRESOLVED; EXIT=0
Consequence: a completed TLS handshake with a publicly-trusted certificate works on the x86_64 emulator (measured on API 30), and certificate validation is demonstrably enabled there (an untrusted certificate is refused, not accepted). It is NOT established which trust store Bun reads: `/system/etc/security/cacerts` exists on all three images (CASTORE_COUNT 138/134/145) but nothing here shows Bun opens that directory - a Mozilla store bundled in the binary would produce identical results. Where name resolution failed (all three hosts, `getaddrinfo ENOTFOUND`) no TLS result exists at all and the run says so rather than recording a pass. The name-resolution failures are recorded, not smoothed over, and they vary by API level and by run: see Caveat 8.

## R6 - RAM footprint and cold start (x86_64 emulator)
Verdict: low and roughly flat across API levels, measured on `bun --version` and a sleeping minimal Bun process rather than a served workload; and the cold-start figures are dominated by the harness's own clock fork, so only the small net-of-floor part is attributable to Bun (this line is a summary; the per-API lines below are the result and are never collapsed into it)
API 30: RSS_VMHWM_KB=26620; COLD_START_MS_MEDIAN=11 COLD_START_MS_SAMPLES=" 12 11 11 11 6" COLD_START_HARNESS_FLOOR_MS=6 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 6 8 17 4 3" COLD_START_MS_NET_OF_FLOOR=5 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR; EXIT=0
API 34: RSS_VMHWM_KB=27560; COLD_START_MS_MEDIAN=98 COLD_START_MS_SAMPLES=" 171 119 98 46 80" COLD_START_HARNESS_FLOOR_MS=20 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 59 15 17 31 20" COLD_START_MS_NET_OF_FLOOR=78 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR; EXIT=0
API 35: RSS_VMHWM_KB=28160; COLD_START_MS_MEDIAN=22 COLD_START_MS_SAMPLES=" 38 19 22 59 15" COLD_START_HARNESS_FLOOR_MS=15 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 15 19 19 13 10" COLD_START_MS_NET_OF_FLOOR=7 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR; EXIT=0
Consequence: Bun 1.4.2 holds steady in an order-of-magnitude envelope of ~26-28 MB peak RSS on the x86_64 emulator. Cold start is NOT publishable as "7 ms" or "48 ms": taking the timestamp itself forks date and awk, and the null baseline for that fork costs 6-20 ms on these images. Net of the baseline, Bun's own contribution to a `bun --version` run is 5 ms (API 30), 78 ms (API 34) and 7 ms (API 35) - and on API 30 and API 35 the raw medians are within a few ms of the floor, so most of the published figure was the instrument. This is the runtime's own floor, not the server's footprint: Task 4's `opencode serve` health/RSS measurement is the R6 number that gates M2.
```

## R1 - what the "JIT signal" is, and why it is OPEN

The brief forbids inferring JIT from a timing number. This probe does not. It
reads `/proc/self/maps` from inside two different Bun processes and derives a
signal from the difference:

1. **Build identity.** `bun --version` prints `1.4.2`; `bun --revision` prints
   `1.4.2+744846f84` (identical on all three API levels). This is Bun's own
   reported build string.
2. **A hot loop that cannot be deleted.** The engine-usable probe runs
   `let s=0;for(let i=0;i<3e7;i++){s=(s+i)|0}console.log("done",s)`. It prints a
   value (`done -918471104`) identical on all three API levels, so the loop
   really executed; an earlier draft that used a side-effect-free `for(...){}`
   was changed precisely because a JIT is allowed to eliminate it.
3. **The loop process's mapping.** The process that ran the loop reads its own
   `/proc/self/maps` and reports every executable mapping. All three API levels
   show an executable, **writable** anonymous region named `[anon:JSJITCode]`
   (`exec_anon=3`, `w_and_x=1`).
4. **The control process's mapping.** A *second* Bun process whose entire
   program is "read `/proc/self/maps` and print the executable mappings" - no
   loop, no allocation, no compilation - reports **the same shape on the same
   API level**: `exec_anon=3 exec_file=7 w_and_x=1 sample=<...> [anon:JSJITCode]`.

Point 4 is why R1 is OPEN. JavaScriptCore reserves and names its JIT code
region when the code cache is constructed, i.e. before any JavaScript is
compiled, so a region named `[anon:JSJITCode]` in `/proc/self/maps` distinguishes
neither "a hot loop was compiled" nor "it was not". The region exists in a
process that compiled nothing.

`JIT_SIGNAL` is therefore derived with the control as part of the input:

| loop process | control process | `JIT_SIGNAL` | why |
|---|---|---|---|
| `JSJITCode` present | absent | `POSITIVE` | the region appears only in the process that ran the hot loop, so it is attributable |
| `JSJITCode` present | present | `INCONCLUSIVE` | the region exists with no hot loop at all; presence proves nothing about compilation |
| clean read, `exec_anon=0` | any | `NONE` | no executable anonymous mapping at all |
| unreadable / unrecognised | any | `INCONCLUSIVE` | nothing was observed |

`JIT_DETERMINATION` is `SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN` only when the
signal is `POSITIVE`, and `OPEN` otherwise. All three API levels came out
`present/present` -> `INCONCLUSIVE` -> `OPEN`.

### Why the derivation cannot go vacuous

It is derived in `scripts/bun-probe-device.sh` and asserted **in all four
directions** by the workflow's `harness-self-test`, which runs the *real*
on-device script against a stub `bun` generated in four shapes:

| stub shape | `JIT_MAPS_OBSERVED` / `JIT_MAPS_CONTROL` | required result |
|---|---|---|
| `fakebun-good` | loop `JSJITCode`, control `exec_anon=0` | `JIT_SIGNAL=POSITIVE JIT_DETERMINATION=SHELL_DOMAIN_CONFIRMED_APP_DOMAIN_OPEN` |
| `fakebun-nojit` | `exec_anon=0` on both | `JIT_SIGNAL=NONE JIT_DETERMINATION=OPEN` |
| `fakebun-mapsfail` | maps read exits non-zero on both | `JIT_SIGNAL=INCONCLUSIVE JIT_DETERMINATION=OPEN` |
| `fakebun-jitincontrol` | `JSJITCode` on both | `JIT_SIGNAL=INCONCLUSIVE JIT_DETERMINATION=OPEN` |

Replacing the derivation with an unconditional `jit_signal=POSITIVE` - the
mutation the previous version of this file would have survived - now fails
`harness-self-test` at the `fakebun-nojit` case. The happy-path stub is also
required to report `STATUS=PASS` for all seven probes, so a stub whose dispatch
has drifted from the device script cannot leave the self-test green having
verified nothing, and `TLS_DNS=ok` / `TLS_BADCERT_VERDICT=CERT_REJECTED` are
asserted there too, so the R3 classification is derived in CI as well.

Separately, `scripts/assert-bun-log.sh` requires each measurement line to appear
**exactly once with a well-formed value**, so a log in which the JIT read, the
RSS read or the cold-start loop produced nothing is rejected rather than
reported with an empty cell. `RSS_VMHWM_KB=unavailable` (an unreadable
`/proc/<pid>/status`) is explicitly rejected, and so is a log with those lines
stripped.

### Upstream caveats (from the primary source)

PR `oven-sh/bun#29675` ("android support", base `main`, head
`claude/android-support` @ `a305e1fe`) is **closed, not merged** (`state=closed`,
`merged=false`, `merged_at=null`, created 2026-04-24, closed 2026-04-26; its head
is 35 commits ahead of and 3244 behind `main`), so it is a design record, not the
merge that shipped Android support. Its body is nevertheless the upstream
statement of the caveats that apply here: **"No test platforms"** - running
Android tests needs an emulator - and **"Not yet verified at runtime - binary
structure is correct but needs device/emulator testing for JIT W^X, mimalloc TLS,
io_uring fallback."** The shipped 1.4.2 packages exist regardless -
`@oven/bun-linux-x64-android@1.4.2` and `@oven/bun-linux-aarch64-android@1.4.2`
both resolve with `os:["android"]`, and both were integrity-verified here (see
below) - so this run is the first runtime check of the W^X caveat on the actual
binary, and its answer is that the mapping exists but is not attributable to
compilation.

## R1 - the shipped binaries (fetch and verify)

`scripts/probe-bun.sh` (CI-only) downloads both packages from the npm registry
and verifies each tarball's SHA-512 against npm's published integrity before
extracting. `bun-fetch-info` from run 37034863849 contains:

| | x86_64-android (runs on the emulator) | aarch64-android (shipped target, inspected only) |
|---|---|---|
| package | `@oven/bun-linux-x64-android@1.4.2` | `@oven/bun-linux-aarch64-android@1.4.2` |
| npm integrity | `sha512-6HC5tzcC79113n2IHCTJMWv+HsQImv4ZFEK2XpYLxY6HbT8tM4cUM2Zv1bHZBQsS3jv/zYBamDJ1UX7If0d5tw==` | `sha512-3mZKO2rhsNgbAUtAHC1UKUlF2zTxFraDZT/Elv8wzyH0fJL9h+Iv3TgB9lO63w89PRn3eFe+NRA1bhVgikKNPQ==` |
| npm shasum (sha1, tarball) | `afd127a97482d23a73c277f880fae49fc7838547` | `52563a8a2a66c5c7816dfa915c866915c8e5adb1` |
| ELF | `ELF 64-bit LSB pie executable, x86-64 ... interpreter /system/bin/linker64, BuildID[sha1]=5ff2150f6bb37f7354f0e09fae3b33d9b5f39ca5, not stripped` | `ELF 64-bit LSB pie executable, ARM aarch64 ... interpreter /system/bin/linker64, BuildID[sha1]=69943ba2fedf06be7f2fa76deaa37675cb49e64d, not stripped` |
| NEEDED | `libc.so`, `libm.so`, `libdl.so` | `libc.so`, `libm.so`, `libdl.so` |
| size (bytes) | 89,426,104 | 86,800,440 |
| sha256 (extracted file) | `12222610d9a72265ecb5955e09e009bc2b32cd9624427f8a76bec34965917054` | `f2970336bfccf36e4e8a408b25c627122f210e941672f184198c31f4dbd377a0` |

Two different quantities are in play here, and the plan recorded the one this
run does not measure. `docs/superpowers/specs/...` and `.../plans/...` both state
an arm64 unpacked size of **87,007,476** bytes, citing npm's
`versions[1.4.2].dist.unpackedSize`. That is the size of the whole **package**
(2 files), not of the `bun` binary in it. Re-read from the registry on
2026-10-02, `unpackedSize` is 89,426,500 (x64) and 86,800,842 (arm64), while the
`bin/bun` files this run extracted and hashed are 89,426,104 and 86,800,440 -
each about 400 bytes smaller, the second file. So the plan's figure is stale
rather than a competing measurement, and Task 5 should cite the size of the
binary (86,800,440 bytes, 82.8 MB) with the package figure alongside it rather
than repeat 87,007,476. Both integrity strings in the table above were
re-read from the registry on 2026-10-02 and match the ones `scripts/probe-bun.sh`
verified, so this run's verification and the published metadata agree. The
arm64 binary was **never executed** - this harness boots only x86_64 emulators -
so every runtime claim in this file is x86_64.

## Raw per-API results (authoritative run 37034863849)

Three verdicts, reported separately and never collapsed. `RAW[<probe>][<n>]`
records preserve each probe's complete output; `OBSERVED=` is its first line.

### API 30 (Android 11) - job `bun probe (API 30)` (110930619078)

```
BUNPROBE=1 API_LEVEL=30 ANDROID_RELEASE="11" SDK="30" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=138 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=29 EXPECTED="1.4.2" OBSERVED="1.4.2"
RAW[version][1] 1.4.2
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=40 EXPECTED="2" OBSERVED="2"
RAW[js-engine][1] 2
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=29 EXPECTED="done" OBSERVED="done -918471104"
RAW[engine-usable][1] done -918471104
PROBE=tls STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=91 EXPECTED="200" OBSERVED="DNS=ok STATUS=200"
RAW[tls][1] DNS=ok STATUS=200
PROBE=tls-host2 STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=43 EXPECTED="200" OBSERVED="STATUS=200"
RAW[tls-host2][1] STATUS=200
PROBE=tls-badcert STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=297 EXPECTED="FETCH_ERROR" OBSERVED="FETCH_ERROR: self signed certificate code=DEPTH_ZERO_SELF_SIGNED_CERT"
RAW[tls-badcert][1] FETCH_ERROR: self signed certificate code=DEPTH_ZERO_SELF_SIGNED_CERT
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=114 EXPECTED="android x64" OBSERVED="android x64"
RAW[platform][1] android x64
TLS_DNS=ok TLS_DNS_RULE="a tls probe whose observation starts DNS=ENOTFOUND never reached certificate validation (resolver failure); a tls failure with DNS=ok DID reach it and is an R3 finding; DNS=unavailable means the process died before the DNS control printed"
TLS_BADCERT_VERDICT=CERT_REJECTED TLS_BADCERT_ENDPOINT=https://self-signed.badssl.com/ TLS_BADCERT_RULE="the untrusted certificate must be REFUSED: NOT_REJECTED means it was accepted, which would mean certificate validation is off or the endpoint is trusted for an unknown reason; CERT_REJECTED means the refusal names a certificate, so validation is ON; REFUSED_UNCLASSIFIED means the request failed without naming a reason - combined with tls-host2 PASS on the same network (valid certificate accepted, untrusted certificate refused) that still establishes that validation is ON; DNS_UNRESOLVED and NO_TLS_RESULT prove nothing either way"
COLD_START_MS_SAMPLES=" 12 11 11 11 6" COLD_START_MS_MEDIAN=11 COLD_START_MS_NET_OF_FLOOR=5 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 6 8 17 4 3" COLD_START_HARNESS_FLOOR_MS=6 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=26620 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
RAW[version-line][1] 1.4.2
RAW[revision][1] 1.4.2+744846f84
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
RAW[jit-control][1] JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=79967ab1d000-7996bab1d000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=79967ab1d000-7996bab1d000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
RAW[jit-loop][1] hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=78e24bfc0000-78e28bfc0000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=78e24bfc0000-78e28bfc0000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=INCONCLUSIVE JIT_DETERMINATION=OPEN JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_RULE="JIT_SIGNAL is derived, never hardcoded: POSITIVE requires [anon:JSJITCode] in the hot-loop process AND its absence in a control process that ran no hot loop; a control process that also shows the region yields INCONCLUSIVE because JSC reserves that region at code-cache construction; NONE requires a clean read with exec_anon=0; every other shape is INCONCLUSIVE. JIT_DETERMINATION is OPEN unless the signal is POSITIVE. The signal is measured in the adb shell SELinux domain, so W^X in untrusted_app_* stays unverified; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

### API 34 (Android 14) - job `bun probe (API 34)` (110930619240)

```
BUNPROBE=1 API_LEVEL=34 ANDROID_RELEASE="14" SDK="34" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=134 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=52 EXPECTED="1.4.2" OBSERVED="1.4.2"
RAW[version][1] 1.4.2
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=274 EXPECTED="2" OBSERVED="2"
RAW[js-engine][1] 2
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=94 EXPECTED="done" OBSERVED="done -918471104"
RAW[engine-usable][1] done -918471104
PROBE=tls STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=194 EXPECTED="200" OBSERVED="DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com"
RAW[tls][1] DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com
PROBE=tls-host2 STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=732 EXPECTED="200" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND example.com"
RAW[tls-host2][1] FETCH_ERROR: getaddrinfo ENOTFOUND example.com
PROBE=tls-badcert STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=195 EXPECTED="FETCH_ERROR" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND"
RAW[tls-badcert][1] FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=131 EXPECTED="android x64" OBSERVED="android x64"
RAW[platform][1] android x64
TLS_DNS=ENOTFOUND TLS_DNS_RULE="a tls probe whose observation starts DNS=ENOTFOUND never reached certificate validation (resolver failure); a tls failure with DNS=ok DID reach it and is an R3 finding; DNS=unavailable means the process died before the DNS control printed"
TLS_BADCERT_VERDICT=DNS_UNRESOLVED TLS_BADCERT_ENDPOINT=https://self-signed.badssl.com/ TLS_BADCERT_RULE="the untrusted certificate must be REFUSED: NOT_REJECTED means it was accepted, which would mean certificate validation is off or the endpoint is trusted for an unknown reason; CERT_REJECTED means the refusal names a certificate, so validation is ON; REFUSED_UNCLASSIFIED means the request failed without naming a reason - combined with tls-host2 PASS on the same network (valid certificate accepted, untrusted certificate refused) that still establishes that validation is ON; DNS_UNRESOLVED and NO_TLS_RESULT prove nothing either way"
COLD_START_MS_SAMPLES=" 171 119 98 46 80" COLD_START_MS_MEDIAN=98 COLD_START_MS_NET_OF_FLOOR=78 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 59 15 17 31 20" COLD_START_HARNESS_FLOOR_MS=20 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=27560 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
RAW[version-line][1] 1.4.2
RAW[revision][1] 1.4.2+744846f84
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
RAW[jit-control][1] JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=770011808000-770051808000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=770011808000-770051808000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
RAW[jit-loop][1] hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=787b255c3000-787b655c3000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=787b255c3000-787b655c3000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=INCONCLUSIVE JIT_DETERMINATION=OPEN JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_RULE="JIT_SIGNAL is derived, never hardcoded: POSITIVE requires [anon:JSJITCode] in the hot-loop process AND its absence in a control process that ran no hot loop; a control process that also shows the region yields INCONCLUSIVE because JSC reserves that region at code-cache construction; NONE requires a clean read with exec_anon=0; every other shape is INCONCLUSIVE. JIT_DETERMINATION is OPEN unless the signal is POSITIVE. The signal is measured in the adb shell SELinux domain, so W^X in untrusted_app_* stays unverified; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

### API 35 (Android 15) - job `bun probe (API 35)` (110930619151)

```
BUNPROBE=1 API_LEVEL=35 ANDROID_RELEASE="15" SDK="35" ABI="x86_64" SELINUX_CTX="u:r:shell:s0" CASTORE_DIR=present CASTORE_COUNT=145 BUN=/data/local/tmp/bun
PROBE=version STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=39 EXPECTED="1.4.2" OBSERVED="1.4.2"
RAW[version][1] 1.4.2
PROBE=js-engine STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=52 EXPECTED="2" OBSERVED="2"
RAW[js-engine][1] 2
PROBE=engine-usable STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=60 EXPECTED="done" OBSERVED="done -918471104"
RAW[engine-usable][1] done -918471104
PROBE=tls STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=90 EXPECTED="200" OBSERVED="DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com"
RAW[tls][1] DNS=ENOTFOUND FETCH_ERROR: getaddrinfo ENOTFOUND api.github.com
PROBE=tls-host2 STATUS=FAIL EXIT=9 SIGNAL=0 ELAPSED_MS=59 EXPECTED="200" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND example.com"
RAW[tls-host2][1] FETCH_ERROR: getaddrinfo ENOTFOUND example.com
PROBE=tls-badcert STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=320 EXPECTED="FETCH_ERROR" OBSERVED="FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND"
RAW[tls-badcert][1] FETCH_ERROR: getaddrinfo ENOTFOUND self-signed.badssl.com code=ENOTFOUND
PROBE=platform STATUS=PASS EXIT=0 SIGNAL=0 ELAPSED_MS=89 EXPECTED="android x64" OBSERVED="android x64"
RAW[platform][1] android x64
TLS_DNS=ENOTFOUND TLS_DNS_RULE="a tls probe whose observation starts DNS=ENOTFOUND never reached certificate validation (resolver failure); a tls failure with DNS=ok DID reach it and is an R3 finding; DNS=unavailable means the process died before the DNS control printed"
TLS_BADCERT_VERDICT=DNS_UNRESOLVED TLS_BADCERT_ENDPOINT=https://self-signed.badssl.com/ TLS_BADCERT_RULE="the untrusted certificate must be REFUSED: NOT_REJECTED means it was accepted, which would mean certificate validation is off or the endpoint is trusted for an unknown reason; CERT_REJECTED means the refusal names a certificate, so validation is ON; REFUSED_UNCLASSIFIED means the request failed without naming a reason - combined with tls-host2 PASS on the same network (valid certificate accepted, untrusted certificate refused) that still establishes that validation is ON; DNS_UNRESOLVED and NO_TLS_RESULT prove nothing either way"
COLD_START_MS_SAMPLES=" 38 19 22 59 15" COLD_START_MS_MEDIAN=22 COLD_START_MS_NET_OF_FLOOR=7 COLD_START_HARNESS_FLOOR_MS_SAMPLES=" 15 19 19 13 10" COLD_START_HARNESS_FLOOR_MS=15 COLD_START_FLOOR_STATUS=ABOVE_HARNESS_FLOOR COLD_START_CLOCK=date-ns COLD_START_N=5
RSS_VMHWM_KB=28160 RSS_SOURCE=/proc/<pid>/status RSS_NOTE="peak RSS of a sleeping bun process, sampled ~3s after start"
RAW[version-line][1] 1.4.2
RAW[revision][1] 1.4.2+744846f84
BUN_VERSION_LINE="1.4.2" BUN_REVISION="1.4.2+744846f84"
RAW[jit-control][1] JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=741a0863e000-741a4863e000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_CONTROL="JIT_CONTROL exec_anon=3 exec_file=7 w_and_x=1 sample=741a0863e000-741a4863e000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
RAW[jit-loop][1] hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=7bab05e82000-7bab45e82000 rwxp 00000000 00:00 0                          [anon:JSJITCode]
JIT_MAPS_OBSERVED="hot=1539553984 exec_anon=3 exec_file=7 w_and_x=1 sample=7bab05e82000-7bab45e82000 rwxp 00000000 00:00 0                          [anon:JSJITCode]"
JIT_SIGNAL=INCONCLUSIVE JIT_DETERMINATION=OPEN JIT_LOOP_STATE=present JIT_CONTROL_STATE=present JIT_RULE="JIT_SIGNAL is derived, never hardcoded: POSITIVE requires [anon:JSJITCode] in the hot-loop process AND its absence in a control process that ran no hot loop; a control process that also shows the region yields INCONCLUSIVE because JSC reserves that region at code-cache construction; NONE requires a clean read with exec_anon=0; every other shape is INCONCLUSIVE. JIT_DETERMINATION is OPEN unless the signal is POSITIVE. The signal is measured in the adb shell SELinux domain, so W^X in untrusted_app_* stays unverified; PR oven-sh/bun#29675 (closed, unmerged) states Android has no upstream runtime test platform and lists JIT W^X as not runtime-verified; see docs/spikes/r1-bun.md"
BUN_PROBE_VERDICT=COMPLETE
EXIT=0
```

`PROBE=platform` returning `android x64` is the direct check that Bun's Android
support landed as documented and that the ABI is what the fetch step expected.
The header's `SDK` (from `getprop ro.build.version.sdk`) matches the requested
API level on all three legs, and no leg carries `API_LEVEL_MISMATCH`; that
cross-check is asserted, because a leg booted from the wrong system image would
otherwise be filed under the requested level. `CASTORE_DIR=present` with a
non-zero `CASTORE_COUNT` (138/134/145) is recorded as context only - it is
**not** evidence about which trust store Bun reads. The `EXIT=` line is appended
by the workflow after the probe's own final line, so a crash (e.g. 139) stays
distinguishable from the probe's own verdict. A `FAIL` probe is not a red job:
the probe exits `0` once every probe has been attempted and recorded.

## What "red" means for these risks

The brief's point is that a red workflow and a Bun-level failure are different
events, so the harness keeps them apart:

- the device program exits `4` with `BUN_PROBE_VERDICT=HARNESS_BROKEN` only when
  Bun is missing or the harness itself cannot run; a probe that crashes, times
  out or fails is recorded as `STATUS=CRASH|TIMEOUT|FAIL` with its signal and its
  complete raw output, and still reaches `BUN_PROBE_VERDICT=COMPLETE`;
- `scripts/assert-bun-log.sh` accepts `PASS`, `FAIL`, `CRASH` and `TIMEOUT` as
  findings and rejects only broken output: no verdict line, two verdict lines, a
  verdict that contradicts the appended `EXIT=`, a probe that never reported, a
  probe reported twice, an unknown `STATUS`, a log from the wrong API level, a
  device whose own SDK disagrees with the requested API level, **a missing
  measurement** (`RSS_VMHWM_KB=unavailable`, a stripped measurement line, four
  cold-start samples instead of five, no harness floor, a `JIT_SIGNAL` or
  `TLS_BADCERT_VERDICT` outside its documented set), output that was reported but
  not preserved, or no output at all;
- the `report` job fails on a **missing** API level - absence of evidence is never
  a result - and emits `::warning::` for findings such as `API34:tls=FAIL` while
  staying green;
- the `harness-self-test` job proves both halves of that contract before any
  emulator boots (run 37034863849, job 110930439169, green): **28 assertion
  cases** (6 accepted findings, 22 rejected broken logs) plus the real on-device
  probe script run against stub buns in **seven numbered cases** - five
  executable stubs (happy, no-JIT, maps-read-failure, JIT-region-in-the-control,
  segfaulting) and two negative environment cases (wrong-system-image,
  missing-binary) - each required to derive the verdict its shape implies.

One earlier run is recorded because the distinction is what makes it readable:
run **37009258321** had every probe green on all three API levels but its
`report` job was red on a `case`-syntax bug (`PASS|")` instead of `PASS|"")`).
That was a harness fault in the summary, not a Bun result. Run **37033759629**
is the first run of the closed-vacuity harness: its self-test went red because
the new SDK cross-check rejected the stub logs - `getprop` does not exist on the
CI runner, so `SDK` was empty. The stub environment now ships a `getprop`, and
that run produced no Bun information either.

## Caveats - what this result does not establish

1. **The JIT region is not attributable to compilation.** The control process -
   a Bun program that only reads `/proc/self/maps` - shows the same
   `[anon:JSJITCode]` mapping as the hot-loop process on all three API levels.
   Presence therefore shows that Bun *maps* a writable-executable JIT heap, not
   that any JavaScript was compiled into it. Nothing here establishes which tier
   ran (Baseline/DFG/FTL), or that compilation happens at all on Android.
   Distinguishing them needs a per-region residency signal - the `Rss` line for
   that mapping in `/proc/self/smaps`, which would read 0 for a region that is
   reserved but never committed and non-zero once code is written into it, but
   whether JavaScriptCore actually commits that lazily on Android is a
   behavioural assumption this run did not test - or a JSC-internal counter.
   Neither is measured here.
2. **Measured in the `shell` SELinux domain, not an app domain.** Every log is
   `SELINUX_CTX="u:r:shell:s0"` (an `adb shell` session). A packaged opencode
   runs as its own `untrusted_app_*` domain with its own `execute`/`execmem`
   policy. Even a *confirmed* JIT signal here would not prove an app may map
   `W|X`; that remains the single most important gap in this evidence, and it is
   exactly what an in-app probe (M1) must measure.
3. **x86_64 emulator, not arm64 hardware.** The executing binary was the
   x86_64-android build on an x86_64 system image. The arm64 Android binary was
   fetched, hash-verified and inspected, but never run. Nothing here is an arm64
   measurement.
4. **Not a `jniLibs`-installed binary.** The probe ran from `/data/local/tmp`
   with `/data/local/tmp` ownership and SELinux label, not from an app's
   `nativeLibraryDir`. Path resolution and labels differ.
5. **AOSP policies, not OEM policies.** The emulator runs AOSP SELinux policy.
   An OEM that further restricts execmem for apps would change the app-domain
   answer for that device only.
6. **Which trust store Bun uses is OPEN.** R3 shows a publicly-trusted
   certificate validating and an untrusted one refused, on the x86_64 emulator.
   It does not show that `/system/etc/security/cacerts` was read; a Mozilla
   store bundled in the binary is observationally identical. Closing this needs
   an open-file/`strace` view of the process, or a test root CA that is installed
   only on the device.
7. **R3's TLS result exists on API 30 only in this run.** On API 34 and API 35
   every host failed name resolution, so those legs carry **no** TLS result and
   `TLS_BADCERT_VERDICT=DNS_UNRESOLVED` is explicitly not counted as a rejection.
   Across the four runs that produced TLS rows, the primary-host probe
   (`api.github.com`, which needs a successful handshake to return 200)
   succeeded on API 30 5/5, API 34 4/5 and API 35 2/5 - so each API level's R3
   rests on fewer runs than this table's single row suggests, and only API 30 is
   consistent.
8. **The name-resolution failures vary by API level and run, and the reason is
   not established.** The classification rule is applied, not a conclusion:
   `TLS_DNS=ENOTFOUND` (from `dns.lookup` in the same process, immediately
   before the fetch) means the request never reached a socket, so it says nothing
   about TLS; `TLS_DNS=ok` with a failed fetch would be a real R3 finding; no
   such case occurred. On this run's API 34 and API 35 legs *all three* hosts
   failed identically, which locates the failure below Bun (the emulator's
   resolver) rather than in Bun. Why the resolver works on some legs and not
   others - netd, DNS-over-HTTPS, Private DNS, all of which are API-level
   dependent, on a shared CI network with one Bun build and one revision - is not
   measured, and is not attributed to "network flake" as if that were a cause.
   Task 5's reproducibility pass should treat the per-API resolvability as
   `FLAKY`.
9. **Cold start is `bun --version`, emulator-derived, and floor-dominated.** Five
   samples per API level, median reported, plus a null baseline of five runs of
   the same clock bracket with no work between the two reads. The baseline costs
   6-20 ms on these images, so the raw medians (11 / 98 / 22 ms) overstate Bun's
   own cost by roughly that much, and on API 30 and API 35 the whole figure is
   within a few ms of the instrument. It is not `opencode serve` startup and it
   is not a device budget.
10. **RSS is a minimal sleeping Bun.** `VmHWM` is sampled ~3 s into a process
    whose only work is `await new Promise(r => setTimeout(r, 8000))`. It is the
    runtime's floor (~26-28 MB), not the footprint of the server or of a loaded
    project. Task 4's measurement is the R6 gate.
11. **"JIT works" is not claimed at all in this run,** so the scope caveats about
    upstream `opencode`'s bundled/native modules, WebView and Bun FFI being
    unaffected by Android's execmem policy are moot here; those are R2/Task 4
    questions.
12. **The upstream caveat source is a closed PR.** `oven-sh/bun#29675` was
    closed without merging, so its caveats are a proposal's caveats, not a
    changelog entry for 1.4.2. The runtime measurement above stands on its own
    regardless.

## Supplementary observation (NOT part of the recorded verdict)

There is no app-domain or arm64 observation to add here. Recording one would
require building or running an APK or an arm64 image, which the M0 spike's
constraints (and this task's 1.5 GB host budget) forbid. The honest statement is
therefore that the app-domain and arm64 gaps are real and unmeasured, not that
they were informally checked. The gaps are left visible in Caveats 2, 3 and 4
rather than closed with a plausible guess.

## What would change these verdicts

- A per-region residency measurement - `Rss` for the `[anon:JSJITCode]` mapping
  in `/proc/self/smaps`, or the same control comparison in an app domain - that
  separates "reserved" from "committed" would either restore a real `POSITIVE`
  for R1 (region committed only after the hot loop) or confirm `NONE`. That is
  the single cheapest measurement still missing, and it needs no APK.
- An in-app probe (M1's first instrumentation job) failing to map `W|X` in
  `untrusted_app_*` on a real device would settle the app-domain half of R1
  regardless of what the shell domain shows.
- A root CA installed only on the device image, or an `open()`/`strace` view of
  the fetch, would establish *which* trust store R3 exercised and close the last
  OPEN in R3.
- A TLS-layer failure (`TLS_DNS=ok` with a certificate error) on any API level
  would change R3. The classification makes that distinction explicit, so it will
  be visible the first time it happens.
- Task 4's `opencode serve` RSS/health numbers, which are the R6 gate; a served
  workload materially above the runtime floor would change the memory verdict.
