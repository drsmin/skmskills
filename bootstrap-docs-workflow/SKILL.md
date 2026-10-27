---
name: bootstrap-docs-workflow
description: Set up a Markdown-first, AI-session-restart working methodology in the current project — scaffold docs/ (current-task, session-log, decisions with D-numbers, todo, recovery, context-budget) plus a CLAUDE.md "rule hub" and a context-budget guard (bounded session-start reads + caps enforced by a pre-commit hook) so the record files can't inflate every future session — plus in-session cost controls (quiet gate runner, source-file size cap, session-cost measurement, lean personal settings). Use when starting a new project (or adopting the discipline in an existing one) and the user asks to "set up the docs workflow", "adopt this methodology", "bootstrap the working conventions", "이 방법론 적용해줘", "문서 기반 작업 규율 세팅", or asks to keep context/CLAUDE.md from growing unbounded. Run once per project; it detects the project name/remote and won't clobber files that already exist.
---

# Bootstrap the Markdown-first / session-restart methodology

This skill installs a documentation-driven working discipline into the **current** project. It is a
distillation of a proven methodology, not tied to any one codebase. The core idea:

> An AI agent's memory ends with the session. So **every piece of work is recorded in `docs/` as it
> happens**, `CLAUDE.md` points to where the rules live, and commits are pushed at every milestone —
> so any future session (or a fresh pod) can fully recover context from git alone.

Run this **once per project**. It is idempotent: it creates only the files that are missing and never
overwrites existing docs (it reports what it skipped).

### The methodology's built-in failure mode — install the guard, not just the docs

The record files (`session-log`, `decisions`, `todo`) **grow monotonically**, and `CLAUDE.md` tells
every new session to read them. Left alone, session-start cost grows in proportion to project history,
and `CLAUDE.md` itself — which is auto-loaded into *every* session — accretes rules until it's a
changelog. A scaffold without the guard is a slow context leak.

So this skill installs both. The key insight, which shapes §2 and §3:

> **Capping file size is the second line of defence. The first is bounding how much gets read.**
> Then `session-log.md` can reach 3,000 lines with session-start cost unchanged.

**And bounding it in prose does not work.** An earlier version of this skill wrote the protocol as
a list — "read the last 3 log entries / the decisions index only" — and it read correctly but was
never followed, because *there is no line number anywhere to cut on*, so the reader opens whole
files. Measured on a real repo 30 sessions in: **11,754 chars by the rule, 49,654 by the files —
4.2x**, and widening, because each new decision adds 1 index line but ~23 body lines. The very
O(history) growth the policy declares it has solved reproduces inside the file that is deliberately
never rotated.

> **So a script cuts the ranges, and its output is the whole of session-start reading.**
> `CLAUDE.md` points at one command, not at a list of files. Judgement calls the script cannot make
> — "which is the current phase?" — become a `★` marker the script greps for, not a human decision.

That failure is invisible to every file-size cap: it happened with **all caps green**. So the guard
also measures the briefing itself.

`CLAUDE.md` is the one exception — auto-loading means no read protocol can protect it, so it gets a
hard line cap and a no-net-growth rule written into the file itself.

## 0. Detect the project context (don't hardcode)

Before writing anything, gather real values so the scaffold is accurate:

```
basename "$(pwd)"                       # project name
git rev-parse --is-inside-work-tree     # is this a git repo?
git remote -v | head -1                 # remote kind (HTTPS/SSH), if any
git branch --show-current               # default branch
ls docs/ CLAUDE.md 2>/dev/null          # what already exists
```

Also check what the budget guard (§3) would touch:

```
ls scripts/ 2>/dev/null                 # will you be adding to an existing scripts/ dir?
ls .git/hooks/pre-commit 2>/dev/null    # an existing hook must NOT be clobbered
```

- If not a git repo, mention it — the recovery/commit discipline assumes git. Offer to `git init`.
- If `docs/` or `CLAUDE.md` already exist, treat them as authoritative: **augment, don't replace.**
- Ask the user only what you genuinely can't detect (e.g. "does this project have a rebuildable
  runtime env like node_modules / a venv?" for the recovery table). Prefer sensible defaults.

## 1. Scaffold `docs/` (create only what's missing)

Create each file below if it does not already exist. Fill placeholders (`<project>`, dates) with the
detected values. Use today's real date.

**The file bodies are in this skill's `assets/templates/`** — `cp` them, don't retype them. Paths
below are relative to the skill base directory you are given at invocation time, same as §3's
scripts: `cp "<skill base dir>/assets/templates/<name>" docs/<name>`. **Read a template before
copying it** when you need to fill placeholders — each one is 0.2-9.5KB, so you pull in only what
that file needs instead of carrying all ten.

⚠️ **Don't reconstruct a template from memory.** They carry load-bearing details the guard parses
(the cap-contract line's exact backtick format, the `★` marker, the `| D-NNN |` index row shape) —
a paraphrase passes review and fails the guard.

### `docs/current-task.md` — the single entry point

The one file a new session reads first. Keep a **"★current entry point★"** marker that each wrap-up
demotes to "★previous entry point★" — **exactly one**. A list here duplicates what the briefing
already prints from `session-log`, so every session reads the same headings twice.

Template: **`assets/templates/current-task.md`** — fill `<project>`/goal from §0.

### `docs/session-log.md` — what was done, newest first

The per-entry length note is load-bearing: this is the file that grows fastest.

Template: **`assets/templates/session-log.md`**.

### `docs/decisions.md` + `docs/decisions/` — design/direction decisions, numbered `D-NNN`

**One decision = one file** (`docs/decisions/D-NNN.md`, first line `# D-NNN. 제목`), and
`docs/decisions.md` holds only the preamble and the **index table** — newest row on top, because the
briefing prints the first `DEC_ROWS` rows and folds the rest. A missing index is a hard failure: it
is the only part a new session reads.

Why split from day one: in a single file the briefing still bounds the *session-start* read, but
**work-time** cost grows with every decision — editing one decision means the edit tool reads the
whole file, and opening it without a range pulls in everything (one repo: one decision 1.3k chars
vs the file 47k = 35x). Split, both reading and writing one decision stay one decision's size.
The guard and the briefing detect the layout (`DEC_LAYOUT=auto`: `docs/decisions/` exists → split),
so old single-file installs keep working; `scripts/split-decisions.sh` migrates them (§3b).

Templates: **`assets/templates/decisions.md`** → `docs/decisions.md` (the index), and the two seed
bodies **`decisions-D-001.md`** / **`decisions-D-002.md`** → `docs/decisions/D-001.md` / `D-002.md`.

### `docs/todo.md`

Template: **`assets/templates/todo.md`** — keep exactly one `★` marker on the current phase.

**The `★` is load-bearing** — `session-brief.sh` prints only the marked section, and the guard fails
hard when no heading carries it. Move it to the phase in progress; never leave two or more.

### `docs/recovery.md` — what survives a fresh environment, and how to rebuild

Template: **`assets/templates/recovery.md`** — tailor the table to what §0 detected (node_modules?
venv? build artifacts? credentials?) and fill the dependency-install / credential / health-check
commands at the end.

### `docs/context-budget.md` — the policy behind the guard

This is the **why** for §3's script — written so a future session can rotate correctly without
re-deriving the reasoning.

Template: **`assets/templates/context-budget.md`** (≈9.5KB, the longest). It carries the whole
policy: why bounding *reads* precedes capping *size*, the cap contract the guard parses,
section-sprawl and hub-honesty checks, the caps table, the rotation procedure, why decisions are
split instead of rotated, and §7 on in-session cost. **Scale the numbers to the project**, but keep
the `CLAUDE.md` cap tight — that file is auto-loaded, so no read protocol can protect it.

### `docs/archive/README.md` — the rotation target

Template: **`assets/templates/archive-README.md`**.

## 2. Create or augment `CLAUDE.md` — the rule hub

`CLAUDE.md` is a **pointer/index**, not a changelog: it states the few invariant rules and points to
where each rule's source of truth lives. If it already exists, **merge** these sections in rather than
overwriting the user's content.

Two things in this template are load-bearing and easy to water down — don't:

1. **The session-start section states ranges, not filenames.** "read `session-log.md`" is the leak;
   "read the last 3 entries of `session-log.md`" is the fix. Keep the bounds, and keep large
   reference docs (design/spec) and `docs/archive/` *out* of the startup routine.
2. **The self-cap warning at the top.** This file is auto-loaded every session, so it's the one file
   a read protocol can't protect. The cap only holds if the rule lives in the file itself.

The **contract line** is load-bearing too: the doc declares its own limits and the guard parses that
line and compares it against its own constants. Raising a limit then requires editing *both* the doc
and the script — which turns "just bump it" into a deliberate act. Keep the backtick format exactly
(`전체 \`4000자\`` etc.) or the guard reports the declaration as missing.

Template: **`assets/templates/CLAUDE.md`** — each location-index row carries three things and no
more: one phrase for *what*, the source location, and the 1-2 "never do this" lines that prevent an
accident without opening the source.

As the project grows, add rows to the location index — **not** paragraphs. If a new rule needs
explanation, the explanation goes in `docs/` and this file gets one line pointing at it.

## 3. Install the budget guard (`scripts/`)

Copy both scripts from this skill's `assets/` directory — **don't retype them.** The base directory
is given to you at invocation time:

```bash
mkdir -p scripts
cp "<skill base dir>/assets/session-brief.sh"       scripts/
cp "<skill base dir>/assets/check-docs-budget.sh"   scripts/
cp "<skill base dir>/assets/install-hooks.sh"       scripts/
cp "<skill base dir>/assets/claude-md-sections.txt" scripts/
cp "<skill base dir>/assets/docs-budget.conf.example" scripts/   # 프로젝트별 값은 여기로
cp "<skill base dir>/assets/split-decisions.sh"     scripts/   # 한 파일 결정 기록 → 하나씩 (기존 저장소용)
cp "<skill base dir>/assets/rotate-docs.sh"         scripts/   # session-log · todo 회전
cp "<skill base dir>/assets/check.sh"               scripts/   # 조용한 게이트 + 소스 크기 (§7)
cp "<skill base dir>/assets/session-cost.py"        scripts/   # 세션 비용 실측 (읽기 전용)
cp "<skill base dir>/assets/session-rereads.py"     scripts/   # 재독분 실측 — 세션 수명의 재는 자 (§7)
cp "<skill base dir>/assets/self-check.sh"          scripts/   # 자가 진단 — 위의 재는 자들을 한 화면에 (§7)
cp "<skill base dir>/assets/tools-toggle.py"       scripts/   # 안 쓰는 스킬·MCP·플러그인 끄고 켜기 (§3c)
mkdir -p scripts/hooks docs/decisions                             # 새 저장소는 처음부터 split
cp "<skill base dir>/assets/hooks/pre-commit-test.sh" scripts/hooks/   # 커밋 전 테스트 강제 (§7)
cp "<skill base dir>/assets/hooks/pre-read-size.sh"   scripts/hooks/   # 큰 파일 Read 차단 (§7)
cp "<skill base dir>/assets/hooks/session-start-brief.sh" scripts/hooks/  # 브리핑 자동 주입 (§1)
chmod +x scripts/*.sh scripts/hooks/*.sh
bash scripts/install-hooks.sh
```

**`scripts/hooks/` 셋은 `.git/hooks` 가 아니라 `.claude/settings.json` 에 붙는다** — 그래서
클론마다 사람이 설정할 필요가 없다(`install-hooks.sh` 가 다루는 pre-commit 예산 가드와 다른 경로다).
러너·PATH 는 **conf** 에서 읽는다(`TEST_CMD`·`TEST_PATH` — 스크립트에 박으면 다음 갱신에 사라진다):

```jsonc
// .claude/settings.json
{"hooks":{
 "SessionStart":[
  {"matcher":"startup|clear|compact|resume|fork","hooks":[{"type":"command","command":"bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/session-start-brief.sh\"","timeout":30}]}],
 "PreToolUse":[
  {"matcher":"Bash","hooks":[{"type":"command","command":"bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/pre-commit-test.sh\"","timeout":300}]},
  {"matcher":"Read","hooks":[{"type":"command","command":"bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/pre-read-size.sh\"","timeout":10}]}]
}}
```

**왜 `SessionStart` 가 필요한가**: 「브리핑 한 번이 세션 시작 읽기의 전부다」라고 적어 둔 **뒤에도**
읽는 쪽이 `head -120` 으로 잘랐다 — 어느 저장소 실측에서 **10세션 중 2세션이 네 조각 중 셋을 아예
못 봤다**. 부르는 명령이면 자를 수 있고, 주입이면 자를 자리가 없다. 훅은 `--compact` 판을 넣는다.

⚠️ **주입분 캡 10,000자는 하네스 것이다** — 넘으면 본문을 파일로 빼고 **「읽으라」고 하지 않는다**
(= 브리핑 없는 세션). `BRIEF_COMPACT_HARD` 를 **올려도 하네스가 이긴다**(훅이 코드로 고정한다).
좁힐 곳은 conf 의 `*_COMPACT` 창이다. ⚠️ **조각을 빼서 줄이지 말 것** — 가드가 조각 4종의 **존재**를
따로 본다(조각 하나를 지운 판은 **더 작아져 초록**이었다).

⚠️ **설치한 뒤 되돌려 확인한다**(전부 조용히 안 도는 실패 모양이 있다): 큰 이미지가 막히는지 ·
범위 지정(`offset`/`limit`)이 통과하는지 · 테스트 실패가 커밋을 막는지 · 러너가 없을 때 **통과하지
않고 막는지** · 훅이 **유효한 JSON 하나만** 내는지(`| python3 -m json.tool`) · 브리핑이 **없거나
비거나 캡을 넘을 때** 그 사실을 적어 보내는지. 훅이 실제로 돌았는지는 `tail -3
.git/pre-commit-test.log` 로 본다 — ⚠️ **커밋에 걸린 시간으로 판단하지 말 것**(훅은 도구 호출
**전에** 돈다). ⚠️ **「훅이 JSON 을 냈다」를 「주입됐다」로 읽지 말 것** — 주입은 다음 세션에서 본다.

- `session-brief.sh` — **the first line of defence, and the reason the protocol holds.** It cuts
  each file to its session-start range and prints them as one briefing; `CLAUDE.md` points at this
  command instead of listing files. Adjust the section list to the docs you actually created, and
  keep `SESS_ENTRIES` and `DEC_ROWS` in sync with the numbers `CLAUDE.md` quotes. It reads
  `todo.md`'s `★` marker to find the current phase — a judgement the script cannot make otherwise,
  and one that sends the reader back into the whole file if it is left implicit. It also folds the
  decisions index to its most recent `DEC_ROWS` rows: a full index was the one O(history) piece left
  in the briefing. Keep the `━━ <file>` section headers — the guard cuts the briefing on them.
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

### §B checks, and why each exists

| 검사 | 막는 실패 |
| --- | --- |
| 문자 수 | 줄 수만 보면 **긴 표 행 하나가 예산을 삼키는 것**을 놓친다 |
| 한 줄 길이 | 위와 같은 원인. 한 행에 요약을 밀어넣는 게 실제 비대화 경로였다 |
| 섹션 본문 줄 수 | 섹션 하나가 문서를 삼키는 것 |
| 허용 섹션 목록 | **섹션 스프롤** — 비대화의 1차 경로 |
| 백틱 경로 존재 | 파일을 옮기고 문서를 안 고치면 **허브가 조용히 거짓말한다** |
| `D-번호` 해결 | 없는 결정을 가리키는 참조 |
| 계약 줄 ↔ 상수 | 상한을 **문서만 고쳐** 몰래 올리는 것 |
| 스캔 sanity | 목록·정규식이 0건을 반환해 **검사가 통과처럼 보이며 무의미해지는 것** |

The last one matters most: a guard that silently scans nothing passes forever and reads as coverage.
Structure only — sentence wording, rule order, and whether a rule is *correct* are deliberately not
checked. A guard that reddens on every copy edit gets weakened by the team.

### Then verify the guard actually fires

Non-negotiable. Inject a violation per check and confirm each blocks:

```bash
cp CLAUDE.md /tmp/hub.bak
printf '\n## 몰래 추가한 섹션\n- x\n' >> CLAUDE.md        # 허용 목록 밖 섹션
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
cp /tmp/hub.bak CLAUDE.md

sed -i 's/전체 `4000자`/전체 `99999자`/' CLAUDE.md        # 문서만 상한 올리기
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
cp /tmp/hub.bak CLAUDE.md
bash scripts/check-docs-budget.sh                          # back to green
```

Also worth injecting: a 300-char line, a `docs/` path that doesn't exist, a `D-999` reference, and a
`claude-md-sections.txt` whose entries are all commented out (that last one must fail as
"파싱 0건", not pass silently).

**And the reading-protocol checks specifically** — these are the ones that protect the first line
of defence, so a silent pass here is the most expensive kind:

```bash
sed -i 's/^## ★ Phase 0/## Phase 0/' docs/todo.md          # ★ 마커 제거
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"  # 브리핑이 현재 Phase 를 못 찾는다
git checkout docs/todo.md

printf '\nx\n%.0s' {1..40} >> docs/session-log.md          # 항목 하나를 비대하게
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"  # 총 줄 수는 여전히 초록이다
git checkout docs/session-log.md
```

The second one is the point of the whole unit-vs-total distinction: the file-level cap does **not**
fire, and without the per-entry check the guard reports all-green while the briefing has doubled.

**And the split-layout checks** (skip on a single-file log) — a split that drifts reads as green
unless these fire:

```bash
sed -i '1s/D-001/D-009/' docs/decisions/D-001.md            # 파일 이름 ≠ 첫 헤딩
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
git checkout docs/decisions/D-001.md
printf '\n## D-099. 남은 본문\n\nx\n' >> docs/decisions.md   # split 인데 인덱스 파일에 본문
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
git checkout docs/decisions.md
```

**And the environment checks** — these catch a guard that judges the same commit differently in a
hook than in your shell, or skips a section without saying so:

```bash
LC_ALL= LANG= bash scripts/check-docs-budget.sh | grep -E '문자 수|브리핑 출력'
bash scripts/check-docs-budget.sh             | grep -E '문자 수|브리핑 출력'   # 두 값이 같아야 한다

chmod -x scripts/session-brief.sh                          # 실행 비트만 빠진 설치
bash scripts/check-docs-budget.sh | grep '브리핑 출력'      # 여전히 재야 한다 (건너뛰면 안 된다)
chmod +x scripts/session-brief.sh
```

If `docs/decisions.md` has no index table, the script hard-fails by design (both layouts) — that table is what the
session-start protocol reads, so its absence breaks the whole scheme.

Finally, run `bash scripts/session-brief.sh` and read the output. It should be a few thousand
characters, end at the index table (no decision bodies, at most `DEC_ROWS` index rows), and print
exactly one todo phase.

## 3b. Existing projects — adopt without breaking them

Skip this on a new repo. On an existing one the scaffold is the easy part. Three things break:

1. **The guard goes red on install, and that is correct.** A pre-existing `CLAUDE.md` is almost
   never a hub (one test repo: 133 lines, 7,017 chars, 12 sections → 4 HARDs). Blocking every
   commit from that moment gets the guard removed. So **start in adoption mode**: put
   `BUDGET_MODE=warn` in `scripts/docs-budget.conf`. The verdicts stay identical; only blocking
   waits.
2. **Formats differ, and an unrecognized format reads as green.** English headings
   (`## Entry points`) and ADR-style decisions (`### ADR-001`) used to scan as "0 found, ok". The
   guard now flags both ("진입점 절을 못 찾았다", "결정 형식을 인식하지 못했다"). Answer them in the conf
   (`ENTRY_HEAD`, `DEC_ID`, `DEC_HEAD`) rather than renaming the repo's documents. An ADR repo
   still needs an index table (`| ADR-001 | … |`); that one is a real gap, not a format question.
3. **Migrate `CLAUDE.md` into a hub.** Per section: if it is a rule *source*, move it to
   `docs/<topic>.md` and leave one pointer row in the location index; if it is history or a
   rationale, it becomes a decision. Register the surviving `##` headings in
   `claude-md-sections.txt` and add the contract line. Existing content is the user's, so **show
   the move plan before moving anything.**
4. **Split a single-file decision log.** If `docs/decisions.md` holds the bodies, run
   `bash scripts/split-decisions.sh --dry-run`, show the plan, then run it without the flag. Verify
   nothing was lost (concatenate `docs/decisions/*.md` and diff against the old bodies, ignoring blank
   and `---` lines), run the formatter, and change the `CLAUDE.md` decision rule line to point at
   `docs/decisions/<ID>.md`. The guard then reports `docs/decisions/ … (split …)`.

Then rotate what is over cap (§4 of the policy), and once the guard is all green **flip
`BUDGET_MODE=block` and record it as a decision.** Without the flip, adoption mode becomes permanent
and the guard becomes decoration.

**Flipping is not enough on its own — check what the hard caps still enforce.** Where a repo's
own rule says *past records are never rewritten* (decisions, shipped session entries), the past
cannot be compressed, so the hard cap ends up pinned to the largest thing in history. One repo
flipped to `block` with the decision cap at 260 lines while its longest past decision was 256:
green, blocking, and a brand-new 250-line decision would have sailed through. The fix is not a
tighter cap but **a split between what is enforced and what is merely shown**: set
`DECBODY_FROM=<next number>` so the hard cap applies only from there on; the past stays visible as
soft. Make the headroom table measure the enforced set too — if it reports the historical maximum,
"98%" sits there forever and the only way to make that number fall is to raise the cap.
Axes that rotate (session entries, todo) need none of this: rotation removes the past, so pinning
hard to the post-rotation reality *is* enforcement for new entries.
⚠️ Never bump `DECBODY_FROM` to excuse "just this one" — that one becomes the next baseline.
⚠️ Verify both directions at the boundary: one line over must block, exactly at the cap must pass,
and the historical maximum must stay soft. Then confirm `git commit` itself is refused — a guard's
own exit code is only half the path.

**Upgrading an older install of this skill** is `context-budget-audit`'s job, but the installer
handles its half. A hook from an older version (header `# 자동 생성: scripts/install-hooks.sh`, no
marker) is recognized as its own. If that hook carries extra project checks, the installer refuses
and prints exactly the lines that would be lost; move them to `scripts/pre-commit.d/*.sh`, then
run `bash scripts/install-hooks.sh --migrated`. The old hook is kept as `pre-commit.legacy.bak`.

## 3c. Lean sessions — offer, don't impose

The baseline before any work is mostly harness, not docs: claude.ai connectors (tool names + server
instructions), plugins, skill listings. One machine went from 27k to 47k tokens per call at session
start as connectors were added, against a few thousand for the project docs. These are **personal**
choices (who uses Gmail from this repo is not a repo decision), so ask, then write
`.claude/settings.local.json` — policy §7 has the JSON; plugin names come from `claude plugin list`.
Make sure `.claude/settings.local.json` is ignored (add it to `.gitignore` if `git check-ignore` says
no). If a settings file exists, merge keys — never overwrite. Say how to undo: delete the line and
start a new session (connectors have no per-session toggle); plugins come back via `/plugin`.
Rather than hand-editing JSON, edit the `GROUPS` in `scripts/tools-toggle.py` to the names this machine
actually shows and run `python3 -I scripts/tools-toggle.py off <group|all>` (`on` to restore, then `/clear`).
Only three knobs shrink the listing (measured): `skillOverrides: "user-invocable-only"` for skills,
`permissions.deny: ["mcp__<server>"]` for MCP tools (server instructions stay; in remote-control sessions
this is the only thing that works), `enabledPlugins: false` for marketplace plugins. Denying a built-in tool
(Artifact, Workflow…) only blocks calls — its description stays — and claude.ai-synced plugins ignore
`enabledPlugins`. Don't promise savings from those.

## 4. Report and offer the follow-up

Tell the user exactly which files were **created** vs **skipped (already existed)**, and whether the
pre-commit hook was installed or declined (existing hook). Then offer:

- to fill `docs/current-task.md` and `docs/todo.md` with the real first tasks once they describe the
  project's goal, and
- that the companion **`wrap-up-docs-commit`** skill closes out each work chunk (docs update →
  secret scan → commit → push) using this same discipline.

Tell them the one command that matters day to day: **`bash scripts/session-brief.sh` at the start of
every session** — that is the whole read, and opening the docs directly is what the discipline
exists to prevent. And the other half: **commit and `/clear` at each milestone** — the briefing makes
a fresh session cheap, while a long one grows with every tool output (policy §7).

Mention two things the user needs to know about the guard:

- `.git/hooks` is **not** committed, so `bash scripts/install-hooks.sh` must be re-run after every
  fresh clone (it's in `docs/recovery.md` step 2 for that reason).
- `git commit --no-verify` bypasses a hard block when they're mid-flight; the rotation should then be
  done within that session.

If the project **already had** these docs (you skipped most files), the interesting question is not
what was created but whether the reading protocol actually holds — an older install will have the
prose-only version. Point at **`context-budget-audit`**, which measures the real session-start cost
and retrofits the briefing, the unit checks, and the missed rotations.

Do **not** commit here unless the user asks — creating the scaffold is itself the first thing a
wrap-up would record.
