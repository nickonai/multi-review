#!/usr/bin/env bash
# Run one external reviewer CLI with a fixed timeout and failure isolation.
#
# Usage:
#   run-external-reviewer.sh <reviewer-name> --cwd <dir> [--stdin <file>] -- <command> [args...]
#
# No environment variables are read. The working directory is always
# /tmp/multi-review and the per-reviewer timeout is always 900 seconds.
# Results are written to <reviewer>.out / .status / .meta inside the working
# directory. The wrapper always exits 0 so one failed reviewer does not cancel
# the others. Exit 0 therefore says NOTHING about the review: the caller must read
# <reviewer>.status (ok | empty | exit_N | timeout | not_found | stdin_missing |
# no_python) and <reviewer>.meta. Only "ok" with a non-empty .out is a review.

set -euo pipefail

usage() {
  echo "Usage: run-external-reviewer.sh <reviewer-name> --cwd <dir> [--stdin <file>] -- <command> [args...]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
REVIEWER_NAME="$1"
shift

REVIEWER_CWD=""
STDIN_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cwd) REVIEWER_CWD="${2:-}"; shift 2 ;;
    --stdin) STDIN_FILE="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

if [ "$#" -eq 0 ]; then
  echo "Missing reviewer command" >&2
  exit 2
fi

WORKDIR="/tmp/multi-review"
TIMEOUT_SECONDS=900

mkdir -p "$WORKDIR"

# Find a Python interpreter. Most systems have python3; Git Bash on Windows
# often exposes it as python. If neither exists, fail in a non-blocking way so
# the orchestrating agent knows to call the reviewer CLI directly (see the
# fallback notes in references/fallback.md) instead of getting stuck.
PYTHON_BIN="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON_BIN" ]; then
  printf 'no_python\n' > "$WORKDIR/$REVIEWER_NAME.status"
  printf 'python3/python not found on PATH; run this reviewer CLI directly without the wrapper.\n' \
    > "$WORKDIR/$REVIEWER_NAME.out"
  echo "$REVIEWER_NAME: no_python — call the CLI directly (no timeout wrapper available)" >&2
  exit 0
fi

"$PYTHON_BIN" - "$TIMEOUT_SECONDS" "$WORKDIR" "$REVIEWER_NAME" "$REVIEWER_CWD" "$STDIN_FILE" "$@" <<'PY'
import os
import shlex
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
workdir = sys.argv[2]
reviewer_name = sys.argv[3]
reviewer_cwd = sys.argv[4]
stdin_file = sys.argv[5]
command = sys.argv[6:]

out_path = os.path.join(workdir, f"{reviewer_name}.out")
status_path = os.path.join(workdir, f"{reviewer_name}.status")
meta_path = os.path.join(workdir, f"{reviewer_name}.meta")

started = time.time()
status = "ok"
returncode = 0
output = ""

def write_result():
    elapsed = int(time.time() - started)

    with open(out_path, "w", encoding="utf-8", errors="replace") as handle:
        handle.write(output)

    with open(status_path, "w", encoding="utf-8") as handle:
        handle.write(status + "\n")

    with open(meta_path, "w", encoding="utf-8") as handle:
        handle.write(f"reviewer={reviewer_name}\n")
        handle.write(f"status={status}\n")
        handle.write(f"returncode={returncode}\n")
        handle.write(f"elapsed_seconds={elapsed}\n")
        handle.write(f"timeout_seconds={timeout_seconds}\n")
        if stdin_file:
            handle.write(f"stdin_file={stdin_file}\n")
        if reviewer_cwd:
            handle.write(f"cwd={reviewer_cwd}\n")
        handle.write("command=" + shlex.join(command) + "\n")

    print(f"{reviewer_name}: {status} ({elapsed}s), output: {out_path}")

try:
    stdin_data = None
    if stdin_file:
        if not os.path.isfile(stdin_file):
            returncode = 126
            status = "stdin_missing"
            output = f"stdin file does not exist: {stdin_file}\n"
            write_result()
            sys.exit(0)
        else:
            with open(stdin_file, "r", encoding="utf-8", errors="replace") as handle:
                stdin_data = handle.read()

    completed = subprocess.run(
        command,
        input=stdin_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_seconds,
        cwd=reviewer_cwd or None,
    )
    returncode = completed.returncode
    output = completed.stdout or ""
    if returncode != 0:
        status = f"exit_{returncode}"
    elif not output.strip():
        status = "empty"
except subprocess.TimeoutExpired as exc:
    returncode = 124
    status = "timeout"
    stdout = exc.stdout or ""
    stderr = exc.stderr or ""
    if isinstance(stdout, bytes):
        stdout = stdout.decode(errors="replace")
    if isinstance(stderr, bytes):
        stderr = stderr.decode(errors="replace")
    output = stdout + stderr
except FileNotFoundError as exc:
    returncode = 127
    status = "not_found"
    output = str(exc)

write_result()
sys.exit(0)
PY
