---
name: bootstrap-docs-workflow
description: Install the Markdown-first / session-restart discipline in a project that does not have it yet — docs/ (current-task, session-log, D-numbered decisions, todo, recovery, context-budget), a CLAUDE.md rule hub, and a context-budget guard (briefing script, pre-commit, Claude hooks). Use for "set up the docs workflow", "이 방법론 적용해줘", "문서 기반 작업 규율 세팅", or to stop CLAUDE.md/context growing unbounded. Once per project; never overwrites. Already installed → use context-budget-audit.
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

스크립트마다 한 줄 — **고치거나 출력이 낯설면 `reference/scripts.md` 를 먼저 읽는다** (각 스크립트가
지키는 것, 함정, 확인법이 거기 있다):

| 스크립트 | 하는 일 |
| --- | --- |
| `session-brief.sh` | **1차 방어선.** 각 문서를 세션 시작 범위로 잘라 한 브리핑으로 출력. `CLAUDE.md` 는 파일 목록 대신 이 명령을 가리킨다 |
| `check-docs-budget.sh` | §A 파일 크기·개수 캡, §B `CLAUDE.md` 구조 검사, 단위(항목당·결정당)와 브리핑 출력 크기까지. soft=경고, hard=차단 |
| `docs-budget.conf.example` | 프로젝트별 값(캡·창·`BUDGET_MODE`·문서 형식)은 **여기에만** — 스크립트를 갈아도 남는다 |
| `claude-md-sections.txt` | `CLAUDE.md` 허용 `##` 섹션 목록 — 섹션 스프롤 방지 |
| `split-decisions.sh` | 한 파일 결정 기록 → `docs/decisions/<ID>.md` (기존 저장소용, `--dry-run` 먼저) |
| `rotate-docs.sh` | session-log·끝난 todo Phase 를 `docs/archive/` 로 회전 (내용이 같을 때만 쓴다) |
| `check.sh` | 게이트: 성공 한 줄·실패 전문. 소스 파일 크기 `SRC_SOFT`/`SRC_HARD` |
| `session-cost.py` · `session-rereads.py` | 읽기 전용. 세션 기록에서 실제 토큰 비용·재독분을 잰다 |
| `self-check.sh` | 읽기 전용 자가 진단. exit 1 = 강제가 죽었다, 0 = 사람 몫만 남았다. 가드가 아니다 |
| `tools-toggle.py` | 안 쓰는 스킬·MCP·플러그인을 개인 설정에서 끄고 켠다 (`reference/lean-sessions.md`) |
| `install-hooks.sh` | `.git/hooks/pre-commit` 설치. 남의 훅은 덮지 않는다(exit 2 → 사용자에게 전달). 추가 검사는 `scripts/pre-commit.d/*.sh` |

### Then verify the guard actually fires

**Non-negotiable.** Run every injection in **`reference/verify.md`** (§B 검사표 · 허브 · 읽기 프로토콜 ·
split · 환경) and confirm each blocks, then revert. Finally run `bash scripts/session-brief.sh` and read
the output: a few thousand characters, ending at the index table, exactly one todo phase.

## 3b. Existing projects

On a repo that has never had this methodology, the guard goes red on install and that is correct —
**read `reference/existing-projects.md` before installing** (adoption mode `BUDGET_MODE=warn`, format
mapping in the conf, migrating `CLAUDE.md` into a hub with a move plan shown first, splitting decisions,
then flipping to `block`). If the repo **already has** an install of this skill, use
`context-budget-audit` instead.

## 3c. Lean sessions — offer, don't impose

Harness overhead (connectors, plugins, skill listings) usually dwarfs the docs. It is a **personal**
choice, so ask first; the knobs and `tools-toggle.py` usage are in `reference/lean-sessions.md`.

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
