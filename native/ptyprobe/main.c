/*
 * ptyprobe - risk R4: can an unprivileged Android process allocate a
 * pseudo-terminal?
 *
 * A "Termux-like" terminal in the app needs /dev/ptmx, grantpt/unlockpt,
 * ptsname, and forkpty(). Android 10+ tightened SELinux around devpts and
 * removed TIOCSTI, so nobody knows whether a normal unrooted app can still
 * allocate one. This probe answers it on a real device image instead of
 * guessing.
 *
 * Output contract (consumed by scripts/assert-pty-log.sh and by Task 6):
 *   PTYPROBE=1 UID=.. EUID=.. GID=.. API_LEVEL=.. ... SELINUX_CTX=".."
 *   STEP=<n> RESULT=OK|FAIL ERRNO=<n> MSG="<strerror>" DETAIL="<what was tried>"
 *   CHILD_PID=.. CHILD_EXITS=.. CHILD_SIGNALED=.. CHILD_TERMINATED_BY_SIGNAL=..
 *   STEPS_FAILED=<n>
 *   PTY_VERDICT=AVAILABLE|UNAVAILABLE      <- final line of the program's output
 *
 * Exit status:
 *   0  PTY_VERDICT=AVAILABLE
 *   3  PTY_VERDICT=UNAVAILABLE   <- an expected, informative outcome. The
 *      workflow records it as a result and stays green; it is NOT a broken
 *      harness. Do not "fix" this by returning 0.
 *
 * Honest scope of what this measures: the process runs under whatever SELinux
 * domain the caller has. When launched via `adb shell` that domain is
 * `shell`, which is more privileged than an app's `untrusted_app_*`. The
 * printed UID/EUID/SELINUX_CTX exist so the verdict can never be read without
 * knowing which domain produced it.
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pty.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/system_properties.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PTY_MASTER_PATH "/dev/ptmx"
#define SLAVE_PATH_MAX 128
#define CHILD_EXIT_STDIN_NOT_TTY 42
#define EXIT_PTY_UNAVAILABLE 3

static int failures = 0;
static int simulate_forkpty_fail = 0;

/* One machine-readable line per step. MSG is always strerror(err). */
static void report(int step, int ok, int err, const char *detail) {
  printf("STEP=%d RESULT=%s ERRNO=%d MSG=\"%s\" DETAIL=\"%s\"\n", step,
         ok ? "OK" : "FAIL", err, strerror(err), detail);
  fflush(stdout);
  if (!ok) failures++;
}

/* A missing or unreadable property leaves the field empty rather than lying. */
static void read_property(const char *name, char *out, size_t out_size) {
  out[0] = '\0';
  if (__system_property_get(name, out) <= 0) out[0] = '\0';
  out[out_size - 1] = '\0';
}

static void read_selinux_context(char *out, size_t out_size) {
  int fd;
  ssize_t n;

  snprintf(out, out_size, "unknown");
  fd = open("/proc/self/attr/current", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    snprintf(out, out_size, "unreadable(errno=%d)", errno);
    return;
  }
  n = read(fd, out, out_size - 1);
  close(fd);
  if (n <= 0) {
    snprintf(out, out_size, "unreadable(errno=%d)", errno);
    return;
  }
  out[n] = '\0';
  while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == ' ')) out[--n] = '\0';
}

int main(int argc, char **argv) {
  int i;
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--simulate-forkpty-failure") == 0) {
      simulate_forkpty_fail = 1;
    }
  }
  char api_level[PROP_VALUE_MAX];
  char release[PROP_VALUE_MAX];
  char abi[PROP_VALUE_MAX];
  char build_fingerprint[PROP_VALUE_MAX];
  char build_id[PROP_VALUE_MAX];
  char ctx[256];
  char detail[256];
  char slave_path[SLAVE_PATH_MAX];
  char child_name[SLAVE_PATH_MAX];
  int master = -1;
  int slave = -1;
  int pty_master = -1;
  int step1_errno = 0;
  pid_t pid = -1;

  read_property("ro.build.version.sdk", api_level, sizeof(api_level));
  read_property("ro.build.version.release", release, sizeof(release));
  read_property("ro.product.cpu.abi", abi, sizeof(abi));
  read_property("ro.build.fingerprint", build_fingerprint, sizeof(build_fingerprint));
  read_property("ro.build.id", build_id, sizeof(build_id));
  read_selinux_context(ctx, sizeof(ctx));

  /* Attribution: the verdict is only meaningful next to the API level, the
   * ABI, build identity, and the security domain that produced it. */
  printf("PTYPROBE=1 UID=%u EUID=%u GID=%u PID=%ld API_LEVEL=%s "
         "ANDROID_RELEASE=\"%s\" ABI=\"%s\" BUILD_FINGERPRINT=\"%s\" BUILD_ID=\"%s\" SELINUX_CTX=\"%s\"\n",
         (unsigned)getuid(), (unsigned)geteuid(), (unsigned)getgid(),
         (long)getpid(), api_level[0] ? api_level : "unknown",
         release[0] ? release : "unknown", abi[0] ? abi : "unknown",
         build_fingerprint[0] ? build_fingerprint : "unknown",
         build_id[0] ? build_id : "unknown", ctx);
  fflush(stdout);

  /* Step 1: allocate a master via /dev/ptmx. */
  errno = 0;
  master = open(PTY_MASTER_PATH, O_RDWR);
  if (master < 0) {
    step1_errno = errno;
    report(1, 0, errno, "open " PTY_MASTER_PATH " O_RDWR");
  } else {
    report(1, 1, 0, "open " PTY_MASTER_PATH " O_RDWR");
  }

  /* Step 2: grantpt + unlockpt (bionic's grantpt is a no-op; unlockpt is
   * ioctl TIOCSPTLCK, which is what actually unlocks the slave). */
  if (master < 0) {
    report(2, 0, step1_errno, "SKIPPED: step 1 produced no master fd");
  } else if (grantpt(master) != 0) {
    report(2, 0, errno, "grantpt");
  } else if (unlockpt(master) != 0) {
    report(2, 0, errno, "unlockpt ioctl TIOCSPTLCK");
  } else {
    report(2, 1, 0, "grantpt+unlockpt ioctl TIOCSPTLCK");
  }

  /* Step 3: ptsname, then open the slave. O_NOCTTY so this probe does not
   * steal a controlling terminal from the shell that launched it. */
  slave_path[0] = '\0';
  child_name[0] = '\0';
  if (master < 0) {
    report(3, 0, step1_errno, "SKIPPED: no master fd");
  } else {
    errno = 0;
    const char *name = ptsname(master);
    if (name == NULL) {
      report(3, 0, errno, "ptsname ioctl TIOCGPTN");
    } else {
      snprintf(slave_path, sizeof(slave_path), "%s", name);
      errno = 0;
      slave = open(slave_path, O_RDWR | O_NOCTTY);
      /* Captured before snprintf, which is free to touch errno. */
      int open_errno = errno;
      snprintf(detail, sizeof(detail), "open %s O_RDWR|O_NOCTTY", slave_path);
      if (slave < 0) {
        report(3, 0, open_errno, detail);
      } else {
        report(3, 1, 0, detail);
      }
    }
  }

  /* Step 4: forkpty - the call the Termux-like feature actually needs. It is
   * independent of steps 1-3, so it is always attempted: when /dev/ptmx was
   * denied above, its own errno is the interesting datum. */
  errno = 0;
  if (simulate_forkpty_fail) {
    pid = -1;
    errno = EAGAIN;
  } else {
    pid = forkpty(&pty_master, child_name, NULL, NULL);
  }
  if (pid < 0) {
    report(4, 0, errno, "forkpty");
  } else {
    report(4, 1, 0, "forkpty");
  }

  /* Step 5: the child verifies it really landed on a tty (bionic's forkpty
   * child already calls login_tty, i.e. setsid + TIOCSCTTY, and _exit(1)s if
   * that fails, so a non-zero status here is a real finding). The parent
   * reaps it and reports the raw status. */
  if (pid == 0) {
    /* Child: forkpty already made us a session leader on the slave. */
    int on_tty = isatty(STDIN_FILENO) && isatty(STDOUT_FILENO) &&
                 isatty(STDERR_FILENO);
    _exit(on_tty ? 0 : CHILD_EXIT_STDIN_NOT_TTY);
  }

  if (pid > 0) {
    int status = 0;
    pid_t reaped = waitpid(pid, &status, 0);
    if (reaped < 0) {
      report(5, 0, errno, "waitpid");
    } else {
      int child_ok = WIFEXITED(status) && WEXITSTATUS(status) == 0;
      /* A non-zero child status is a failure with no errno of its own: the
       * child did get an exit status, it just was not the one we wanted. */
      printf("CHILD_PID=%ld CHILD_EXITS=%d CHILD_SIGNALED=%d "
             "CHILD_TERMINATED_BY_SIGNAL=%d CHILD_TTY=\"%s\"\n",
             (long)pid, WIFEXITED(status) ? WEXITSTATUS(status) : -1,
             WIFSIGNALED(status) ? 1 : 0,
             WIFSIGNALED(status) ? WTERMSIG(status) : 0,
             child_name[0] ? child_name : "none");
      fflush(stdout);
      if (child_ok) {
        report(5, 1, 0, "waitpid and child status");
      } else if (WIFEXITED(status)) {
        snprintf(detail, sizeof(detail),
                 "child exited %d instead of 0: forkpty gave it no controlling "
                 "tty (setsid+TIOCSCTTY failed)",
                 WEXITSTATUS(status));
        report(5, 0, 0, detail);
      } else {
        snprintf(detail, sizeof(detail), "child terminated by signal %d",
                 WTERMSIG(status));
        report(5, 0, 0, detail);
      }
    }
  } else {
    /* pid < 0: forkpty failed; step 5 must still be reported */
    report(5, 0, errno, "SKIPPED: forkpty returned no pid");
  }

  if (slave >= 0) close(slave);
  if (master >= 0) close(master);
  if (pty_master >= 0) close(pty_master);

  printf("STEPS_FAILED=%d\n", failures);
  fflush(stdout);
  printf("PTY_VERDICT=%s\n", failures == 0 ? "AVAILABLE" : "UNAVAILABLE");
  fflush(stdout);

  return failures == 0 ? 0 : EXIT_PTY_UNAVAILABLE;
}
