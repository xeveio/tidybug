#!/bin/bash
# Run the TidyBugCore test suites one at a time, each under a hard time limit,
# with live (line-buffered) output.
#
# Why: on CI a test that blocks inside a synchronous system call can't be
# interrupted by Swift Testing's .timeLimit, and non-TTY output is buffered,
# so a hang used to print nothing until the job timed out. Here a hung suite is
# killed (with its whole process group) and reported by name.
#
# Usage: scripts/ci-test.sh            (SUITE_TIME_LIMIT=seconds, default 120)
set -uo pipefail
cd "$(dirname "$0")/../Packages/TidyBugCore"
LIMIT=${SUITE_TIME_LIMIT:-120}

# limit <seconds> <cmd...>: run cmd in its own process group; SIGKILL the group
# on timeout and exit 124.
limit() {
  perl -e '
    my $t = shift;
    my $pid = fork();
    if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 124 };
    alarm $t;
    waitpid($pid, 0);
    exit($? >> 8);
  ' "$@"
}

group() { [ -n "${CI:-}" ] && echo "::group::$1" || echo "── $1"; }
endgroup() { [ -n "${CI:-}" ] && echo "::endgroup::"; return 0; }
err() { [ -n "${CI:-}" ] && echo "::error title=$1::$2" || echo "✘ $1: $2"; }

group "Build tests"
swift build --build-tests || { err "Build failed" "swift build --build-tests failed"; exit 1; }
endgroup

suites=$(limit 120 swift test list --skip-build 2>/dev/null \
  | sed -n 's#^TidyBugCoreTests\.\([A-Za-z0-9_]*\)/.*#\1#p' | sort -u)
if [ -z "$suites" ]; then
  err "Could not list tests" "'swift test list' failed or hung — the test bundle may be blocking at launch"
  exit 1
fi

fail=0
for s in $suites; do
  group "$s"
  start=$(date +%s)
  # `script` gives the test process a pseudo-terminal so output streams live.
  limit "$LIMIT" script -q /dev/null swift test --skip-build --filter "TidyBugCoreTests.$s"
  rc=$?
  endgroup
  dur=$(( $(date +%s) - start ))
  if [ $rc -eq 124 ]; then
    err "Hung test suite" "$s did not finish within ${LIMIT}s"; fail=1
  elif [ $rc -ne 0 ]; then
    err "Failing test suite" "$s failed (exit $rc)"; fail=1
  else
    echo "✔ $s (${dur}s)"
  fi
done
exit $fail
