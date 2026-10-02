# R4 - PTY availability (fragment for `docs/limitations.md`)

Task 2 of the M0 runtime spike. Task 5 assembles this fragment into
`docs/limitations.md`; this file is the source of truth for R4 and nothing else
in the repo should summarise R4 independently.

**Authoritative evidence:** workflow `m0-pty.yml`, run **36998915751**
(green, 2026-10-02). Per-API artifacts `pty-probe-logs-30`, `pty-probe-logs-34`,
`pty-probe-logs-35`, aggregate `r4-pty-summary` (retention 30 days).
Probe source: `native/ptyprobe/main.c`. Log assertions:
`scripts/assert-pty-log.sh`.

**Repeat run:** **37000707941** (green) re-ran the byte-identical probe on
freshly created emulators and returned `PTY_VERDICT=AVAILABLE`, all five steps
`OK`, on all three API levels again - no `FLAKY` marker. The raw logs below are
from run 36998915751; run 37000707941 differs only in the probe's own PIDs
(30: `CHILD_PID=1929`, 34: `CHILD_PID=2021`, 35: `CHILD_PID=1879`) and the
slave/master paths, which the emulator assigns fresh each boot.

## The entry for `docs/limitations.md`, verbatim

```
## R4 - PTY availability
Verdict: AVAILABLE on API 30, API 34 and API 35 independently (this line is a summary; the per-API lines below are the result and are never collapsed into it)
API 30: STEP=1 RESULT=OK ERRNO=0 MSG="Success"; STEP=2 RESULT=OK ERRNO=0 MSG="Success"; STEP=3 RESULT=OK ERRNO=0 MSG="Success"; STEP=4 RESULT=OK ERRNO=0 MSG="Success"; STEP=5 RESULT=OK ERRNO=0 MSG="Success"; STEPS_FAILED=0; PTY_VERDICT=AVAILABLE; EXIT=0
API 34: STEP=1 RESULT=OK ERRNO=0 MSG="Success"; STEP=2 RESULT=OK ERRNO=0 MSG="Success"; STEP=3 RESULT=OK ERRNO=0 MSG="Success"; STEP=4 RESULT=OK ERRNO=0 MSG="Success"; STEP=5 RESULT=OK ERRNO=0 MSG="Success"; STEPS_FAILED=0; PTY_VERDICT=AVAILABLE; EXIT=0
API 35: STEP=1 RESULT=OK ERRNO=0 MSG="Success"; STEP=2 RESULT=OK ERRNO=0 MSG="Success"; STEP=3 RESULT=OK ERRNO=0 MSG="Success"; STEP=4 RESULT=OK ERRNO=0 MSG="Success"; STEP=5 RESULT=OK ERRNO=0 MSG="Success"; STEPS_FAILED=0; PTY_VERDICT=AVAILABLE; EXIT=0
Consequence: M2 proceeds - an unrooted app can allocate a PTY on every API level measured. Gated on R4 and therefore no longer gated off, but see the caveats: the emulated result is from the adb `shell` SELinux domain, and x86_64 emulator results do not transfer to arm64 hardware (spec Section 10, Review Focus #2 and #3).
```

## Raw per-API results

Three verdicts, reported separately and never collapsed.

### API 30 (Android 11) - run 36998915751, job `pty probe (API 30)` (110811867026)

```
PTYPROBE=1 UID=2000 EUID=2000 GID=2000 PID=1897 API_LEVEL=30 ANDROID_RELEASE="11" ABI="x86_64" SELINUX_CTX="u:r:shell:s0"
STEP=1 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/ptmx O_RDWR"
STEP=2 RESULT=OK ERRNO=0 MSG="Success" DETAIL="grantpt+unlockpt ioctl TIOCSPTLCK"
STEP=3 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/pts/0 O_RDWR|O_NOCTTY"
STEP=4 RESULT=OK ERRNO=0 MSG="Success" DETAIL="forkpty"
CHILD_PID=1907 CHILD_EXITS=0 CHILD_SIGNALED=0 CHILD_TERMINATED_BY_SIGNAL=0 CHILD_TTY="/dev/pts/1"
STEP=5 RESULT=OK ERRNO=0 MSG="Success" DETAIL="waitpid and child status"
STEPS_FAILED=0
PTY_VERDICT=AVAILABLE
EXIT=0
```

### API 34 (Android 14) - run 36998915751, job `pty probe (API 34)` (110811866864)

```
PTYPROBE=1 UID=2000 EUID=2000 GID=2000 PID=1562 API_LEVEL=34 ANDROID_RELEASE="14" ABI="x86_64" SELINUX_CTX="u:r:shell:s0"
STEP=1 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/ptmx O_RDWR"
STEP=2 RESULT=OK ERRNO=0 MSG="Success" DETAIL="grantpt+unlockpt ioctl TIOCSPTLCK"
STEP=3 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/pts/0 O_RDWR|O_NOCTTY"
STEP=4 RESULT=OK ERRNO=0 MSG="Success" DETAIL="forkpty"
CHILD_PID=1564 CHILD_EXITS=0 CHILD_SIGNALED=0 CHILD_TERMINATED_BY_SIGNAL=0 CHILD_TTY="/dev/pts/1"
STEP=5 RESULT=OK ERRNO=0 MSG="Success" DETAIL="waitpid and child status"
STEPS_FAILED=0
PTY_VERDICT=AVAILABLE
EXIT=0
```

### API 35 (Android 15) - run 36998915751, job `pty probe (API 35)` (110811866978)

```
PTYPROBE=1 UID=2000 EUID=2000 GID=2000 PID=1420 API_LEVEL=35 ANDROID_RELEASE="15" ABI="x86_64" SELINUX_CTX="u:r:shell:s0"
STEP=1 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/ptmx O_RDWR"
STEP=2 RESULT=OK ERRNO=0 MSG="Success" DETAIL="grantpt+unlockpt ioctl TIOCSPTLCK"
STEP=3 RESULT=OK ERRNO=0 MSG="Success" DETAIL="open /dev/pts/0 O_RDWR|O_NOCTTY"
STEP=4 RESULT=OK ERRNO=0 MSG="Success" DETAIL="forkpty"
CHILD_PID=1421 CHILD_EXITS=0 CHILD_SIGNALED=0 CHILD_TERMINATED_BY_SIGNAL=0 CHILD_TTY="/dev/pts/1"
STEP=5 RESULT=OK ERRNO=0 MSG="Success" DETAIL="waitpid and child status"
STEPS_FAILED=0
PTY_VERDICT=AVAILABLE
EXIT=0
```

The `EXIT=` line is appended by the workflow (`echo EXIT=$?`) after the probe's
own final line, so a crash (e.g. 139) stays distinguishable from the probe's
own verdict.

## What "red" means for this risk

The brief's whole point is that a red workflow and an unavailable PTY are
different events, so the harness is built to keep them apart:

- the probe exits `0` for `PTY_VERDICT=AVAILABLE` and `3` for
  `PTY_VERDICT=UNAVAILABLE`;
- `scripts/assert-pty-log.sh` accepts **both** verdicts and rejects only broken
  output (no verdict line, two verdict lines, a step that never reported, a
  probe exit code that contradicts its own verdict, a log from the wrong API
  level, a `FAIL` step that names no errno, no output at all);
- the `report` job fails on a **missing** API level - absence of evidence is
  never a result - and emits `::warning::R4: PTY_VERDICT=UNAVAILABLE on ...`
  while staying green;
- the `harness-self-test` job proves both halves of that contract on synthetic
  fixtures before any emulator boots (run 36998915751, job 110811866748, green
  in 6 s): 2 fixtures accepted, 8 fixtures rejected. If that job ever goes
  green because an assertion went vacuous, the assertions are wrong.

Two earlier runs are recorded here because the distinction is what makes them
readable: run **36998208576** (red, `setup-ndk` 404 on the sdkmanager revision
spelling) and run **36998391048** (red, the emulator script block turned out to
run under `dash`, not bash). Both were harness faults. Neither says anything
about PTY, and neither is cited as evidence.

## Caveats - what this result does not establish

1. **Measured in the `shell` SELinux domain, not an app domain.** Every log
   above is `UID=2000 EUID=2000 SELINUX_CTX="u:r:shell:s0"` - the `adb shell`
   domain, which has explicit `allow shell devpts:chr_file rw_file_perms;`. A
   packaged app runs in `untrusted_app_*`, which is a different domain with a
   different rule set. `::warning::` is only emitted for `UNAVAILABLE`, so this
   caveat has to be read, not skimmed past.
2. **x86_64 emulator, not arm64 hardware** (Review Focus #2). Nothing here is an
   arm64 measurement. R4 is a permission question rather than a performance one,
   so the transfer is reasonable - but it is a transfer.
3. **Not a `jniLibs`-installed binary** (Review Focus #3). The probe ran from
   `/data/local/tmp`, a world-`radio`-group node, with different SELinux labels
   and sibling-path resolution than `nativeLibraryDir`.
4. **AOSP policies, not OEM policies.** The emulator runs the AOSP `devpts`
   policy. A vendor that denies `devpts` to apps would change the answer for
   that device only.
5. **What "available" does not cover.** The probe proves `/dev/ptmx` opens,
   `unlockpt` (`TIOCSPTLCK`) and `ptsname` (`TIOCGPTN`) succeed, the slave
   opens, `forkpty` succeeds, and the child holds a controlling tty
   (`setsid` + `TIOCSCTTY`). It does **not** test `SIGWINCH` delivery,
   `TIOCSWINSZ` resize, or job control - those belong to M2's
   `termux-emulator` work. `TIOCSTI` is expected to be gone on Android 10+ by
   AOSP policy (`neverallowxperm * devpts:chr_file ioctl TIOCSTI;`) and was
   deliberately not probed, because a failure there is a known fact, not a
   finding.
6. **Step 2's `grantpt` half is vacuous on Bionic, by implementation.**
   `libc/bionic/pty.cpp` is literally `int grantpt(int) { return 0; }` - it
   cannot fail. The part of step 2 that carries evidence is `unlockpt`
   (`ioctl TIOCSPTLCK`), and that ioctl is what unlocks the slave. A green
   `STEP=2` therefore means "TIOCSPTLCK succeeded", not "both calls were
   meaningfully exercised". `unlockpt` alone is also enough to invalidate a PTY
   result: without it the slave stays locked and `open(ptsname)` fails.
7. **Two runs, identical verdict.** Runs 36998915751 and 37000707941 agree on
   all three API levels, so R4 is not flaky. Task 5's reproducibility pass is
   still the formal check for the spike as a whole.

## Supplementary observation (NOT part of the recorded verdict)

The `shell`-domain caveat above is the real gap in the recorded evidence, so
one observation was made outside CI to probe the app domain directly. It is
recorded separately because it is a different ABI, a different domain, a real
device, and it did not come from the authoritative run.

Observed on the maintainer's own phone, API 34 / Android 14, `arm64-v8a`,
HONOR GFY-LX2P, `user` build, from a Termux process whose own context is
`u:r:untrusted_app_27:s0:c117,c257,c512,c768` - i.e. an ordinary unrooted app:

```
$ cat /proc/self/attr/current
u:r:untrusted_app_27:s0:c117,c257,c512,c768
$ ls -Z /dev/ptmx
u:object_r:ptmx_device:s0 /dev/ptmx
$ script -qec 'echo PTY_CHILD_OK; tty' /dev/null
PTY_CHILD_OK
/dev/pts/29
```

`script` allocates the pair with `forkpty(3)`, and the child read its own
controlling terminal back as `/dev/pts/29` via `readlink("/proc/self/fd/0")` -
so the fd really is a tty and really is the pty slave. Meanwhile `ls /dev/pts`
is denied to the same domain, so the denial is on the `devpts` *directory*
while `/dev/ptmx` (`ptmx_device`) and the slave device node stay openable: an
app does not need to enumerate `/dev/pts` to get a pty.

This is consistent with AOSP's own policy, which from `refs/heads/android13-release`
onwards (`system/sepolicy`, `private/app.te`) contains:

```
allow appdomain devpts:chr_file { getattr read write ioctl };
```

with, on `refs/heads/main`'s `private/domain.te`:
`allow domain devpts:dir search;` and
`neverallowxperm * devpts:chr_file ioctl TIOCSTI;`. The
same `appdomain devpts` line is **absent** from `private/app.te` on
`refs/heads/android11-release` and `android12-release` (both files fetched
successfully; 2 069 and 4 218 bytes, zero `devpts` matches), so where API 30
apps get their `devpts` access was not established. **The API 30 app-domain
path therefore rests on the emulator run plus this policy reading, not on a
direct app-domain measurement.**

## What would change this verdict

- An in-app probe (M1's first instrumentation job) failing to open `/dev/ptmx`
  or to run `TIOCSPTLCK` in `untrusted_app_*` on a real device. That is the
  one measurement M0 structurally cannot make, because M0 ships no APK.
- An OEM policy that denies `devpts` to apps.
- Task 5's second run disagreeing with run 36998915751 (would be recorded as
  `FLAKY`, not smoothed over).
