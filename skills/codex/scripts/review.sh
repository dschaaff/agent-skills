#!/usr/bin/env bash
# Runs a Codex review of the current git repository through `codex exec`.
#
# Usage: review.sh <native|adversarial> [--base <ref> | --uncommitted] [-m <model>] [focus...]
#
# native       Codex's built-in reviewer. Takes no focus text.
# adversarial  The skill's adversarial prompt, answered as JSON matching
#              schemas/review-output.schema.json. Remaining words become the focus text.
#
# With no scope flag, a dirty tree is reviewed as uncommitted changes and a clean tree as the
# branch against the default branch. The review goes to stdout; the path of Codex's event log
# goes to stderr.
set -euo pipefail

TMPDIR="${TMPDIR:-/tmp}"

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UNTRACKED_MAX_BYTES=24576

die() {
  printf 'review.sh: %s\n' "$*" >&2
  exit 1
}

default_branch() {
  local ref candidate
  if ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "$ref"
    return
  fi
  for candidate in main master trunk; do
    for ref in "$candidate" "origin/$candidate"; do
      if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
        printf '%s\n' "$ref"
        return
      fi
    done
  done
  die "cannot detect the default branch; pass --base <ref>"
}

untracked_files_context() {
  local file
  printf '## Untracked Files\n\n'
  while IFS= read -r -d '' file; do
    if [ "$(wc -c <"$file")" -gt "$UNTRACKED_MAX_BYTES" ] || ! grep -Iq . "$file"; then
      printf -- '- %s (not inlined: empty, binary, or over %s bytes)\n\n' \
        "$file" "$UNTRACKED_MAX_BYTES"
      continue
    fi
    printf '### %s\n\n%s\n\n' "$file" "$(cat -- "$file")"
  done < <(git ls-files --others --exclude-standard -z)
}

working_tree_context() {
  printf '## Git Status\n\n%s\n\n' "$(git status --short)"
  printf '## Staged Diff\n\n%s\n\n' "$(git diff --cached --no-ext-diff --submodule=diff)"
  printf '## Unstaged Diff\n\n%s\n\n' "$(git diff --no-ext-diff --submodule=diff)"
  untracked_files_context
}

branch_context() {
  local merge_base="$1"
  printf '## Commit Log\n\n%s\n\n' "$(git log --oneline --decorate "$merge_base..HEAD")"
  printf '## Diff Stat\n\n%s\n\n' "$(git diff --stat "$merge_base..HEAD")"
  printf '## Branch Diff\n\n%s\n' "$(git diff --no-ext-diff --submodule=diff "$merge_base..HEAD")"
}

write_adversarial_prompt() {
  local label="$1" focus_text="$2" merge_base="$3"
  cat "$SKILL_DIR/prompts/adversarial-review.md"
  printf '\n<review_target>\nTarget: %s\nUser focus: %s\n</review_target>\n\n' \
    "$label" "$focus_text"
  printf '<repository_context>\n'
  if [ -z "$merge_base" ]; then
    working_tree_context
  else
    branch_context "$merge_base"
  fi
  printf '</repository_context>\n'
}

mode="${1:-}"
case "$mode" in
native | adversarial) shift ;;
*) die "usage: review.sh <native|adversarial> [--base <ref>|--uncommitted] [-m <model>] [focus]" ;;
esac

scope="" base="" model=() focus=()
while [ $# -gt 0 ]; do
  case "$1" in
  --base)
    [ $# -ge 2 ] || die "--base needs a ref"
    [ "$scope" != uncommitted ] || die "--base and --uncommitted are mutually exclusive"
    scope=branch base="$2"
    shift 2
    ;;
  --uncommitted)
    [ "$scope" != branch ] || die "--base and --uncommitted are mutually exclusive"
    scope=uncommitted
    shift
    ;;
  -m | --model)
    [ $# -ge 2 ] || die "$1 needs a model name"
    model=(-m "$2")
    shift 2
    ;;
  *)
    focus+=("$1")
    shift
    ;;
  esac
done

if [ "$mode" = native ] && [ ${#focus[@]} -gt 0 ]; then
  die "native review takes no focus text; use adversarial instead"
fi
command -v codex >/dev/null || die "codex not found on PATH; install it with 'brew install codex'"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$root"

if [ -z "$scope" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    scope=uncommitted
  else
    scope=branch base="$(default_branch)"
  fi
fi

merge_base=""
if [ "$scope" = uncommitted ]; then
  [ -n "$(git status --porcelain)" ] || die "no uncommitted changes to review"
  label="working tree diff"
  target=(--uncommitted)
else
  git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "unknown ref: $base"
  merge_base="$(git merge-base HEAD "$base")" || die "HEAD and $base share no merge base"
  ! git diff --quiet "$merge_base..HEAD" || die "no changes between $base and HEAD"
  label="branch diff against $base"
  target=(--base "$base")
fi

out_dir="$(mktemp -d "${TMPDIR%/}/codex-review.XXXXXX")"
log="$out_dir/events.jsonl"
result="$out_dir/result"
printf 'review.sh: %s review of the %s; Codex log: %s\n' "$mode" "$label" "$log" >&2

status=0
if [ "$mode" = native ]; then
  command codex exec review "${target[@]}" ${model[@]+"${model[@]}"} --json --ephemeral \
    -o "$result" </dev/null >"$log" 2>&1 || status=$?
else
  focus_text="No extra focus provided."
  [ ${#focus[@]} -eq 0 ] || focus_text="${focus[*]}"
  prompt="$out_dir/prompt.md"
  write_adversarial_prompt "$label" "$focus_text" "$merge_base" >"$prompt"
  command codex exec -s read-only ${model[@]+"${model[@]}"} --json --ephemeral \
    --output-schema "$SKILL_DIR/schemas/review-output.schema.json" \
    -o "$result" - <"$prompt" >"$log" 2>&1 || status=$?
fi

if [ "$status" -ne 0 ] || [ ! -s "$result" ]; then
  tail -n 20 "$log" >&2
  die "codex exited with status $status and wrote no review; full log: $log"
fi
cat "$result"
