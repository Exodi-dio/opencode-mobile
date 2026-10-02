# R2 - Native modules, `opencode serve` health, and the arm64 qemu leg

Task 4 of the M0 runtime spike. This file is the source of truth for R2
(opencode binary health on Android) and the arm64 link-level leg; Task 5
assembles `docs/limitations.md`.

**Authoritative evidence:** workflow `m0-opencode.yml`, run **37060325440**
(green, 2026-10-02, commit `234e7cf`). Second full-green run
**37063930012** (green, commit `aa2916a`) adds the qemu `-strace`/`-d unimp`
fields cited below. Per-API artifacts `opencode-probe-logs-{30,34,35}`,
`arm64-link-level`, `r2-opencode-summary` (30-day retention). Probe:
`scripts/probe-opencode.sh`. Assertions: `scripts/assert-opencode-log.sh`,
`scripts/assert-arm64-link.sh`. Sysroot: `scripts/qemu-arm64-sysroot.sh`.

## Server health (the central M0 question)

Real opencode **does** start and serve on Android via the x86_64 binary,
on all three probed API levels. Observed verdicts (never collapsed):

| API level | verdict | time to healthy (ms) | alive >= 60 s after healthy | fatal signal | R2 native failures in stderr |
|---|---|---|---|---|---|
| 30 | `HEALTHY` | 3420 | yes | none (exit 0) | 0 |
| 34 | `HEALTHY` | 6025 | yes | none (exit 0) | 0 |
| 35 | `HEALTHY` | 5582 | yes | none (exit 0) | 0 |

The server banner was the only stderr output: `Warning: OPENCODE_SERVER_PASSWORD
is not set; server is unsecured.` and `opencode server listening on
http://127.0.0.1:4096` (`SERVER_LOG_LINES=2`, `TIME_TO_HEALTHY_MS` measured
from server launch to the first healthy `GET /global/health`).

## R2 enumeration

Searched the full server stderr for `Failed to load native binding`,
`Cannot find module`, `.node`, ELF/dlopen errors, and ripgrep spawn errors.
**No native-module load failure appeared on any API level** (`R2_FAILURES=0`
on 30/34/35). Classification (load-bearing vs optional) is trivially empty:
there is nothing to classify - `opencode serve` reached `HEALTHY` without any
evident native binding failure on the server startup path.
The ripgrep suspicion from Task 1 (opencode's ripgrep table has no
`*-android` key, so a `Failed to spawn ripgrep` / platform-not-supported
error was plausible): **not observed** in `opencode serve` stderr. The serve
startup path does not touch ripgrep, so this remains a risk for the agent
search paths, not a serving one. Honest statement: no ripgrep error was
recorded, and no healthy ripgrep spawn was verified either.

## Startup mishaps recorded (harness-relevant)

- The first probe attempt crashed with
  `/data/local/tmp: EROFS: read-only file system, mkdir '/.local'` because
  `HOME` was unset on the emulator shell => the binary treats the missing
  HOME as `/`. Verdict: `CRASH` (signal restored to 0: process exited
  non-fatally, no `Fatal signal` line in logcat).
- With `HOME=/data/local/tmp`, the binary retried with
  `/data/local/tmp: EEXIST: file already exists, mkdir ...` — specifically it
  wants to `mkdir` the path *named like the binary itself*
  (`/data/local/tmp/opencode` when the binary is `/data/local/tmp/opencode`).
  Resolved by running the binary **as `/data/local/tmp/opencode-bin`** with
  `HOME=/data/local/tmp/oc`. Quirk recorded for downstream work: opencode
  resolves a data-dir path adjacent to (or named like) its executable and
  will crash if that name collides with the executable, or if HOME is
  `/`/unset.

## arm64 / qemu-user leg (LINK_LEVEL_ONLY)

This result is **LINK_LEVEL_ONLY** and must never be cited as "opencode works
on arm64": qemu-user is expected to break Bun's JIT.

- The sysroot assembled: x86_64 runner executed the real Bionic aarch64
  `linker64` from a public arm64 Android image (waydroid LineageOS 20,
  sha256 verified), and the linker runs — a direct
  `linker64 --describe <binary>` invocation executed inside the guest and
  printed its own argument error, which proves the arm64 ELF loads and the
  interpreter resolves.
- `opencode --version` under `qemu-aarch64`: exit code **1**, empty stdout,
  empty stderr, empty guest syscall trace (`-strace` empty, `-d unimp`
  empty). The guest does not reach main; consistent with Bun's expected
  behaviour on qemu-user, but it is recorded as observed, not explained.
  `ARM64_VERSION_EXIT=1`, `ARM64_PRESERVED_ERROR=""`, labelled
  `ARM64_LABEL=LINK_LEVEL_ONLY`.

## Verdict summary

- R2 on the server startup path: `opencode serve` becomes healthy with zero
  visible native-module failures (x86_64, API 30/34/35).
- arm64: link-level only; version string not obtainable under qemu-user 8.2.
- R6 numbers (time-to-healthy): median-ish 3.4–6.0 s cold start observed
  across API levels; peak RSS not measured in this task.
