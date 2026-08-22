---
name: wrap-up-docs-commit
description: Close out a chunk of work under the Markdown-first methodology — update the project docs (session-log, decisions, todo, current-task), scan for secrets, then commit and push in one flow. Use when the user asks to "wrap up and commit", "record and push", "문서 정리하고 커밋/푸시", "마무리하고 커밋", or otherwise finalize a milestone. Companion to bootstrap-docs-workflow; assumes docs/ + CLAUDE.md exist (falls back gracefully if some are absent).
---

# Wrap up: update docs, commit, push

This project follows a Markdown-first / AI-session-restart discipline: **every piece of work is
recorded in `docs/` before it's committed**, and commits are pushed immediately (milestone push
reduces environment-loss risk — see `docs/recovery.md` if present). This skill closes out a work chunk.

These records accumulate, and a new session's start-up cost depends on them staying small. So writing
the entry and **keeping it short** are the same job — see `docs/context-budget.md` if the project has
one (installed by `bootstrap-docs-workflow`). Caps below are that skill's defaults; if the project set
different ones, follow the project.

**Only commit when the user has asked.** Never commit unprompted. Once they ask, commit **and** push
in one flow — under this methodology the standing rule is "push right after committing," so don't ask
for a separate push confirmation.

Skip any doc a step genuinely doesn't touch, and any file that doesn't exist in this project — but
check each. Use today's real date; convert relative dates to absolute.

## 1. Update the docs to reflect the work just done

- **`docs/session-log.md`** — add an entry at the **top** (newest first): what was requested, what
  changed (key files), and the verification result. Match the existing heading style (e.g.
  `## YYYY-MM-DD (NN) — <title>`; use the next sequence number). **Keep it to ~15 lines** — the diff
  holds the detail, this entry holds the orientation.
- **`docs/decisions.md`** — if a design/direction decision was made, append a new `## D-NNN <title>`
  section (next number after the current highest) with the **reasoning, not just the what**.
  Irreversible actions (external integration, publishing, push) belong here too. **Body ≤20 lines**,
  and if the file has an index table at the top, **add a row there too** — that table is the only part
  a new session reads, so a missing row makes the decision invisible. Never reuse a number; supersede
  by marking the old one `폐기(→D-NNN)`.
- **`docs/todo.md`** — mark finished items `[x]` with a one-line summary; add follow-ups as `[ ]`.
- **`docs/current-task.md`** — demote the old "★current entry point★" to "★previous entry point★"
  and write a new current entry point so the next session resumes cleanly. **Keep at most ~5 entry
  points**; delete the overflow rather than archiving it (`session-log.md` already has it).
- **`CLAUDE.md`** — only if a new invariant rule, doc, or resource location was introduced (it's the
  rule hub / index, not a changelog). It's auto-loaded into every session, so prefer **replacing** a
  line or adding one index row over appending prose. If a rule needs explanation, put the explanation
  in `docs/` and point at it from here.

Keep entries scannable. Do **not** record secrets.

### If a record file is at its cap, rotate before committing

A project with `docs/context-budget.md` also has `scripts/check-docs-budget.sh` wired to a pre-commit
hook, so an over-cap file will **block the commit** in §3. Don't reach for `--no-verify` — that just
defers the same work to a session with less context on it. Run the check first and rotate what it
names (procedure in `docs/context-budget.md` §4; typically: move the oldest `session-log.md` entries
to `docs/archive/session-log-YYYY-MM.md`, completed phases to `docs/archive/todo-done.md`, and leave a
one-line pointer behind). Rotation is a move, not a delete — the history stays in git and searchable,
it just stops costing every future session.

`decisions.md` is the exception: **compress, never rotate.** Losing the reasoning makes the next
session re-litigate a settled question.

## 2. Review before staging

```
git status
git diff --stat
```

- Confirm the changes match what was actually done; read anything surprising.
- **Secret scan** — never commit tokens/passwords/keys/emails:
  ```
  git diff | grep -iE "password|token|secret|bearer |api[_-]?key|@.*\.(com|net|org)" \
    | grep -v "Co-Authored-By\|noreply\|packageManager" | head
  ```
  Investigate any hit before proceeding.
- Include legitimately untracked artifacts (e.g. auto-generated plan backups under `docs/`), but not
  build output or dependencies.

## 3. Commit

Stage and commit with a heredoc for the multi-line message. Use the project's default branch (detect
with `git branch --show-current`). If a pre-commit hook rejects the commit, **read what it says and
fix that** (for the budget guard, rotate per §1) rather than bypassing it.

End the message with the Co-Authored-By trailer for **whichever
model is currently running** — take the exact name from the harness's commit-trailer instruction, and
never copy a model name hardcoded here or in a previous commit:

```
git add -A
git commit -F - <<'EOF'
<one-line summary (include D-NNN if a decision was recorded)>

<body: what changed and why, key files, verification result>

Co-Authored-By: <현재 실행 중인 모델명 / current model name> <noreply@anthropic.com>
EOF
```

Keep the subject concise; the body should let a future session understand the change without the
diff. If the work spans a decision, reference the `D-NNN`.

### A mixed trailer history is correct — never "fix" it

When the model changes mid-project, older commits keep the older trailer. **Never rewrite the trailer
in past commits**: a commit records who wrote it at that time, and that mix is exactly how you date
the switch later:

```
git log --format="%h %ad %b" --date=short | grep -B2 "Co-Authored-By" | head
```

If a project wants that boundary written down (so nobody mistakes it for a defect and "fixes" it),
record it in **that project's** `CLAUDE.md` commit rules — with the actual commit hashes. It does not
belong here: this file stays model-neutral, which is why the trailer above is a placeholder.

## 4. Push (immediately, same flow)

Use the existing remote. If the remote is HTTPS, no interactive flags are needed. Push to the branch
you committed on:

```
git push origin "$(git branch --show-current)"
git status -sb | head -1   # confirm in sync: ## <branch>...origin/<branch> (no ahead/behind)
```

If push fails (no remote, auth), report it plainly and leave the commit in place — the local commit
already protects the work; the user can set up the remote and push.

## 5. Report

State the commit hash, the push result (`<old>..<new> <branch> -> <branch>`), and that the branch is
in sync with origin. If any doc was intentionally left unchanged, say so. If anything was rotated to
`docs/archive/`, say what moved — it's the one change that isn't visible in the working docs.

Finally: if work in this session touched files **outside** the repo (user-level skills, `~/.claude`
settings, global git config), say so explicitly and note that those are **not** covered by this
commit. Otherwise "committed and pushed" reads as if everything was saved when part of it wasn't.
