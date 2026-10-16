#!/usr/bin/env bash
# Hands a task to Codex through `codex exec`, or continues an earlier Codex session.
#
# Usage: task.sh [--write] [--resume <session-id>] [-m <model>] [--effort <level>] [prompt...]
#
# The prompt comes from the arguments, or from stdin when there are none. Codex runs in its
# read-only sandbox unless --write is given. A resume with no prompt tells Codex to continue.
# Codex's final message goes to stdout, followed by a "Codex session: <id>" line to pass to
# --resume; the path of Codex's event log goes to stderr.
set -euo pipefail

TMPDIR="${TMPDIR:-/tmp}"

CONTINUE_PROMPT="Continue from the current thread state. Pick the next highest-value step and \
follow through until the task is resolved."

die() {
  printf 'task.sh: %s\n' "$*" >&2
  exit 1
}

sandbox=read-only session="" model=() effort=()
while [ $# -gt 0 ]; do
  case "$1" in
  --write)
    sandbox=workspace-write
    shift
    ;;
  --resume)
    [ $# -ge 2 ] || die "--resume needs a session id"
    session="$2"
    shift 2
    ;;
  -m | --model)
    [ $# -ge 2 ] || die "$1 needs a model name"
    model=(-m "$2")
    shift 2
    ;;
  --effort)
    [ $# -ge 2 ] || die "--effort needs a level"
    case "$2" in
    none | minimal | low | medium | high | xhigh) ;;
    *) die "unknown effort '$2'; use none, minimal, low, medium, high, or xhigh" ;;
    esac
    effort=(-c "model_reasoning_effort=\"$2\"")
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *) break ;;
  esac
done

if [ $# -gt 0 ]; then
  prompt="$*"
elif [ ! -t 0 ]; then
  prompt="$(cat)"
else
  prompt=""
fi
if [ -z "$prompt" ]; then
  [ -n "$session" ] || die "no prompt given; pass it as arguments or on stdin"
  prompt="$CONTINUE_PROMPT"
fi

command -v codex >/dev/null || die "codex not found on PATH; install it with 'brew install codex'"

out_dir="$(mktemp -d "${TMPDIR%/}/codex-task.XXXXXX")"
log="$out_dir/events.jsonl"
result="$out_dir/result"
printf 'task.sh: %s task; Codex log: %s\n' "$sandbox" "$log" >&2

flags=(-c "sandbox_mode=\"$sandbox\"" ${model[@]+"${model[@]}"} ${effort[@]+"${effort[@]}"})
flags+=(--json -o "$result")
status=0
if [ -n "$session" ]; then
  command codex exec resume "${flags[@]}" "$session" - <<<"$prompt" >"$log" 2>&1 || status=$?
else
  command codex exec "${flags[@]}" - <<<"$prompt" >"$log" 2>&1 || status=$?
fi

thread_pattern='s/.*"type":"thread.started","thread_id":"\([^"]*\)".*/\1/p'
thread_id="$(sed -n "$thread_pattern" "$log" | head -n 1)"
if [ "$status" -ne 0 ] || [ ! -s "$result" ]; then
  tail -n 20 "$log" >&2
  die "codex exited with status $status and wrote no result; full log: $log"
fi
cat "$result"
printf '\nCodex session: %s\n' "${thread_id:-${session:-unknown}}"
