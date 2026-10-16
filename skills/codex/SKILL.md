---
name: codex
description: Codex second opinion through the `codex exec` CLI - use when the user wants Codex to review or adversarially review a diff, take over or rescue a task, or continue an earlier Codex session.
argument-hint: "[review | adversarial-review | task | resume] [args]"
---

# Codex

Run the Codex CLI non-interactively to get a second model's review or a delegated task.
Two scripts in this skill's `scripts/` directory wrap `codex exec`; call them by their full
path under this skill's base directory, from inside the target repository.

## Running a script

Every script call is a Bash call with both of these set:

- `dangerouslyDisableSandbox: true`. Claude Code's Seatbelt sandbox blocks the writes Codex
  makes under `~/.codex` and its traffic to `chatgpt.com`. macOS also refuses to apply a
  second Seatbelt profile inside the first, so Codex's own `read-only` and `workspace-write`
  sandboxes only work when Claude's sandbox is off. Outside it, Codex enforces its own.
- `run_in_background: true`. A review or task takes minutes. You are notified when it ends;
  read the output then. To cancel, stop the background task with TaskStop.

## 1. Pick the mode

| Request | Command |
| --- | --- |
| Review, code review | `scripts/review.sh native [scope]` |
| Adversarial review, "try to break it", ship/no-ship | `scripts/review.sh adversarial [scope] [focus...]` |
| Investigate, diagnose, research (no edits) | `scripts/task.sh "<prompt>"` |
| Fix, implement, rescue, hand off work | `scripts/task.sh --write "<prompt>"` |
| Continue, keep going, apply the fix, dig deeper | `scripts/task.sh --resume <session-id> [--write] ["<prompt>"]` |

Scope for either review: `--uncommitted` for staged, unstaged, and untracked changes, or
`--base <ref>` for the branch against that ref. With no scope flag the script reviews a
dirty tree as uncommitted changes and a clean tree as the branch against the default branch.
Focus text is free words after the scope, for adversarial reviews only.

Both scripts accept `-m <model>`; `task.sh` also accepts `--effort
none|minimal|low|medium|high|xhigh`. Pass them only when the user names a model or effort.

A resume needs the session id from the `Codex session:` line of the earlier `task.sh` run in
this conversation. A resume runs read-only unless you pass `--write` again. With no
earlier session in view, start a new task instead.

## 2. Write the task prompt

For `task.sh`, write a self-contained prompt: Codex sees none of this conversation. State
the goal, the relevant files and symptoms, what is already known or ruled out, and what
"done" looks like. A long prompt goes on stdin through a quoted heredoc rather than as an
argument.

## 3. Present the result

The step is done when every finding or result line from Codex is in front of the user.

- **Native review**: show Codex's review text as written.
- **Adversarial review**: the output is JSON. Lead with `verdict` and `summary`, then list
  every finding, most severe first, as `severity` - `title` at `file:line_start`, followed
  by `body`, `recommendation`, and `confidence`. End with `next_steps`.
- **Task**: show Codex's final message, then list the files it changed (`git status
  --short` after a `--write` run), then the session id for a later resume.

Attribute all of it to Codex. Where you disagree with a finding after reading the code, say
so beside that finding. Changes to the code are a separate step that the user chooses: end
after presenting.

## Failures

The scripts fail fast with a message, and on a Codex error they print the tail of the
event log and its path.

- `failed to initialize in-process app-server client: Operation not permitted`: the call ran
  inside Claude's sandbox. Run it again with `dangerouslyDisableSandbox: true`.
- Not logged in, or an auth error: the user runs `! codex login`.
- `no uncommitted changes` or `no changes between`: the scope is empty. Ask the user which
  ref or commit range to review.
