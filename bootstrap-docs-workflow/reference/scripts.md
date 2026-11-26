# bootstrap-docs-workflow — 스크립트별 상세

`SKILL.md` §3 에서 복사한 스크립트 각각이 무엇을 하고, 무엇을 지키며, 어떻게 확인하는지. 스크립트를 프로젝트에 맞게 고치거나 가드 출력이 이해되지 않을 때 읽는다.

- `session-brief.sh` — **the first line of defence, and the reason the protocol holds.** It cuts
  each file to its session-start range and prints them as one briefing; `CLAUDE.md` points at this
  command instead of listing files. Adjust the section list to the docs you actually created, and
  keep `SESS_ENTRIES` and `DEC_ROWS` in sync with the numbers `CLAUDE.md` quotes. It reads
  `todo.md`'s `★` marker to find the current phase — a judgement the script cannot make otherwise,
  and one that sends the reader back into the whole file if it is left implicit. It also folds the
  decisions index to its most recent `DEC_ROWS` rows: a full index was the one O(history) piece left
  in the briefing. Keep the `━━ <file>` section headers — the guard cuts the briefing on them.
  Its git section folds the working tree into a per-directory summary past `GIT_STATUS_LINES` —
  **a line cap alone does not bound it**: 62 long Korean paths made the injected briefing 14.4k
  chars (151% of the cap), and a guard that HARD-blocks in that state blocks the very rotation
  commit that would fix it. Any briefing piece that prints paths needs a size bound, not a line one.
- `check-docs-budget.sh` — two parts. **§A** caps file sizes/counts per `context-budget.md` §3.
  **§B** inspects `CLAUDE.md` structurally, because that file is auto-loaded and no read protocol
  can protect it. soft = warn (exit 0), hard = block (exit 1); every violation prints the specific
  action. Caps live in variables at the top; tune to project scale but keep the hub tight.
  Reference docs (any `docs/*.md` outside the core set) are auto-detected and reported **uncapped**.
  It measures units, not just totals — per-log-entry and per-decision body length — because a single
  long entry eats the briefing while every total stays green. And it measures the briefing's own
  output size, which is the only number that *is* the session-start cost — plus each briefing
  piece in characters, because line caps miss a line that doubles. Every character count goes
  through `_chars()` (strip UTF-8 continuation bytes, count bytes): `wc -m` and `awk length()`
  count **bytes** under an empty locale, which is what a pre-commit hook usually has, and that
  blocked commits with phantom HARDs. Each row prints its headroom to the next threshold, and a
  top-5 headroom summary closes the run.
- `docs-budget.conf.example` → `scripts/docs-budget.conf` (optional) — **project-specific values
  live here, never in the scripts**: caps, briefing windows, `BUDGET_MODE`, and the document format
  (`ENTRY_HEAD`, `DEC_ID`, `DEC_HEAD`). Both scripts source it, so replacing the scripts with a newer
  skill version keeps every customization. HUB caps raised here still have to match the
  `CLAUDE.md` contract line, so this is not a back door.
- `claude-md-sections.txt` — the allowed `##` sections of `CLAUDE.md`, one heading per line.
  **Section sprawl is the main route to hub bloat**, so adding a section must touch the doc *and*
  this file. Edit it to match whatever headings you actually installed. Entries start with `## `;
  comments start with `# ` (one hash) — the two must not overlap, or the list parses empty.
- `split-decisions.sh` — moves every `## D-NNN` body out of `docs/decisions.md` into
  `docs/decisions/<ID>.md` (first line `# <ID>. 제목`), leaving the preamble + index. Builds the index
  from the headings if there is none (newest on top). `--dry-run` shows the plan; it refuses on an
  already-split repo, duplicate IDs, or an unrecognized format, and writes nothing unless every body
  came out. A new repo doesn't need it — create `docs/decisions/` from the start.
- `rotate-docs.sh` — does the rotation the guard asks for (policy §4): keeps the newest `SESS_KEEP`
  (default 6) log entries and files the rest by heading date into `docs/archive/session-log-YYYY-MM.md`
  (newest on top, one pointer line left behind); moves todo phases that are all `[x]` and carry no
  `★` to `docs/archive/todo-done.md`. It never carries over unfinished items — that is a judgement —
  it lists the mixed phases instead. `--dry-run` first; it writes nothing unless the content lines
  before and after match exactly, and refuses an entry whose heading has no date.
- `check.sh` — **the gate, quiet on success** (policy §7). Runs `GATE_STEPS` from the conf (`이름|명령`
  per line — fill it with the project's real typecheck/lint/test commands plus the budget guard, and
  point the project's `check` script at it). Success prints one line per step, failure prints that
  step's full output and stops — never truncate it, a cause outside the tail costs a rerun. Then it
  sizes tracked source files: `SRC_SOFT` (800) warns, `SRC_HARD` (1,500) fails. **Don't put `pnpm -s` /
  `npm -s` in a step** — silent mode also drops child output, so the failure prints nothing. Verify
  both paths: plant a type error, confirm the cause line shows, revert.
- `session-cost.py` — read-only, `python3 -I scripts/session-cost.py`. Reads the session transcripts'
  `usage` and prints per session the first call's input tokens (baseline), the peak (in-session
  growth), and which tool results grew the conversation. The guard measures what the docs *would*
  cost; this measures what sessions *did* cost.
- `self-check.sh` — read-only, `bash scripts/self-check.sh`. Calls the other measures and collects
  only their verdicts, in five sections: ① installed ② **enforced** ③ caps ④ cost ⑤ record-keeping
  habit (does `docs/` land in the same commit). The exit code splits two things that look alike:
  `1` = **enforcement is dead** (the guard file exists but no hook runs it, or the hook log is
  empty — the "believed installed" state), `0` = enforcement is alive and what remains is for a
  human to fix (soft caps, session cost, habit). Mixing them gives a diagnostic that is always red,
  and then nobody reads it. **It is not a new guard** — it blocks nothing and owns no cap; the only
  cap source is `check-docs-budget.sh`. **Don't add a threshold to it** (two cap sources that
  disagree leave nobody knowing which is right) and **don't put it in `scripts/pre-commit.d/`**
  (blocking turns it into a guard). The commands it runs must match the project's own exercises /
  runbook, so they teach the same thing the tooling does. Verify both paths: delete
  `.git/hooks/pre-commit`, confirm exit 1, reinstall, confirm exit 0.
- `install-hooks.sh` — installs `.git/hooks/pre-commit`. It **refuses to clobber** a pre-existing
  hook it didn't create (exit 2) and prints the two lines to add manually instead. If it exits 2,
  relay that to the user rather than forcing it. **Project-specific pre-commit checks** (generated-
  artifact drift, lint) go in `scripts/pre-commit.d/*.sh`, which the hook runs after the budget
  check — never edit the hook or this installer to add one, because that is how the clobber marker
  gets lost. A check that skips itself (missing venv, missing tool) must **say** it skipped; a
  silently passing check reads as coverage.
