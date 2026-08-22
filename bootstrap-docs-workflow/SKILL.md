---
name: bootstrap-docs-workflow
description: Set up a Markdown-first, AI-session-restart working methodology in the current project — scaffold docs/ (current-task, session-log, decisions with D-numbers, todo, recovery, context-budget) plus a CLAUDE.md "rule hub" and a context-budget guard (bounded session-start reads + caps enforced by a pre-commit hook) so the record files can't inflate every future session. Use when starting a new project (or adopting the discipline in an existing one) and the user asks to "set up the docs workflow", "adopt this methodology", "bootstrap the working conventions", "이 방법론 적용해줘", "문서 기반 작업 규율 세팅", or asks to keep context/CLAUDE.md from growing unbounded. Run once per project; it detects the project name/remote and won't clobber files that already exist.
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
> `CLAUDE.md` must say "read the last 3 log entries / the decisions index only", not "read these
> files". Then `session-log.md` can reach 3,000 lines with session-start cost unchanged.

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

### `docs/current-task.md` — the single entry point

The one file a new session reads first. Keep a **"★current entry point★"** marker that each wrap-up
demotes to "★previous entry point★".

```markdown
# Current Task

새 세션은 이 문서를 먼저 읽고, docs/session-log.md → decisions.md → todo.md 순으로 컨텍스트를 복구한다.
(A new session reads this first, then session-log → decisions → todo to recover context.)

## 현재 목표 (Current goal)

<one paragraph: what we're building and the immediate next priority>

## 진입점 (Entry points, newest on top)

- **★현재 진입점★ — <YYYY-MM-DD> 프로젝트 부트스트랩. 방법론 문서 구조 생성.**

> 진입점은 최대 5개. 초과분은 삭제한다 (`session-log.md` 에 남아 있다).
```

### `docs/session-log.md` — what was done, newest first

The per-entry length note is load-bearing: this is the file that grows fastest.

```markdown
# Session Log

작업 이력. 최신 항목을 위에 추가한다. (Work history; newest entry on top.)
**항목당 15줄 이내.** 최근 12개만 여기 두고 나머지는 `docs/archive/` 로 회전한다.

---

## <YYYY-MM-DD> (01) — 프로젝트 부트스트랩

**요청.** 방법론(문서 기반 작업 규율) 적용.
**작업.** docs/ 구조(current-task·session-log·decisions·todo·recovery·context-budget) +
CLAUDE.md 규칙 허브 + 컨텍스트 예산 안전장치(`scripts/`, pre-commit 훅) 생성.
```

### `docs/decisions.md` — design/direction decisions, numbered `D-NNN`

**The index table at the top is required** — it's the only part a new session reads, so
`check-docs-budget.sh` treats a missing index as a hard failure. Add one row per decision.

```markdown
# Design Decisions

설계·방향 결정 기록. 각 결정은 무엇을·왜. 되돌리기 어려운 작업도 여기 남긴다.
(Each decision records the *what* and the *why*; irreversible actions belong here too.)

**세션 시작 시에는 아래 인덱스 표만 읽고, 필요한 D-번호만 펼쳐 읽는다.**
본문은 각 20줄 이내로 유지한다. 이 파일은 아카이브로 회전하지 않는다 — 근거를 잃으면 다음
세션이 같은 논쟁을 반복한다. 정책: `docs/context-budget.md` §5.

## 인덱스

| D | 결정 | 상태 |
| --- | --- | --- |
| D-002 | 컨텍스트 예산 안전장치 — 읽기 범위 고정 + 캡 + 회전 | 유효 |
| D-001 | 문서 기반 작업 규율 채택 | 유효 |

> 번호는 재사용하지 않는다. 뒤집힌 결정은 지우지 않고 상태를 `폐기(→D-0NN)` 로 바꾼다.

---

## D-002. 컨텍스트 예산 안전장치

**결정:** 기록 파일의 단조 증가가 세션 시작 비용을 늘리는 것을 막는다. 3중 방어:
① 읽기 범위 고정(CLAUDE.md 가 "이만큼만 읽어라"), ② 캡(`scripts/check-docs-budget.sh`,
pre-commit 훅), ③ 초과분 `docs/archive/` 회전. 정책 전문 `docs/context-budget.md`.

**이유:** 파일이 커지는 것 자체는 문제가 아니다. **매 세션 읽는 양이 커지는 것**이 문제다.
캡만 걸면 회전 노동만 늘고 원인이 남으므로 ①이 핵심이고 ②③은 보조다. `CLAUDE.md` 만은
매 세션 자동 로드되어 읽기 프로토콜로 방어할 수 없어 하드 캡 + 순증 금지 규칙을 적용한다.

---

## D-001. 문서 기반 작업 규율 채택

**결정:** 모든 작업을 docs/ 에 기록하고 CLAUDE.md 를 규칙 허브로 둔다. 마일스톤마다 커밋+push.

**이유:** AI 세션은 매번 초기화된다. git 에 커밋+push 된 것만 확실히 안전하므로, 맥락을
문서로 남겨 원격에 백업하면 어떤 세션도 처음부터 컨텍스트를 복구할 수 있다.
```

### `docs/todo.md`

```markdown
# TODO

전체 작업 목록. `[x]` 완료, `[ ]` 미완, `[~]` 진행중.
완료된 Phase 는 `docs/archive/todo-done.md` 로 회전한다.

## Phase 0. 기반
- [x] 문서 구조 생성 (current-task / session-log / decisions / todo / recovery / context-budget)
- [x] 컨텍스트 예산 안전장치 — `scripts/check-docs-budget.sh` + pre-commit 훅 (D-002)
- [ ] <first real task>
```

### `docs/recovery.md` — what survives a fresh environment, and how to rebuild

Tailor the table to what you detected (node_modules? venv? build artifacts? credentials?).

```markdown
# 환경 유실 위험 & 복구 가이드 (Loss risk & recovery)

이 환경은 예고 없이 재기동/삭제될 수 있다. 무엇이 사라지고 무엇이 남는지, 재개 시 복구법을 정리한다.

## 1. 무엇이 사라지고 무엇이 남는가

| 대상 | 재기동 시 | 성격 | 복구 방법 |
| --- | --- | --- | --- |
| **커밋 + push 된 코드/문서** | ✅ 남음(원격) | 안전 | `git clone` 또는 그대로 |
| **커밋했지만 push 안 한 것** | ⚠️ 볼륨 유지 시만 | 위험 | **마일스톤마다 push** |
| **커밋 안 한 작업물** | ❌ 유실 | **최대 위험** | 없음 — 자주 커밋만이 방어 |
| 의존성(node_modules/venv 등) | ❌ 재현 가능 | 산출물 | 설치 명령 재실행 |
| 자격증명(토큰) | ❌ 유실 | 재설정 대상 | 재주입 (값은 문서에 절대 안 남김) |

**요지:** git 에 커밋+push 된 것만 확실히 안전. 나머지는 재현 가능. 진짜 위험은 커밋 안 한 작업물뿐.

## 2. 유실을 줄이는 작업 습관
- 마일스톤(논리적 한 단위)마다 커밋하고 곧바로 push.
- 방향 결정은 그때그때 decisions.md 에 D-번호로. 문서도 코드와 함께 원격 백업된다.
- 세션 종료 전 `git status` clean·`origin` 동기 확인.
- 민감정보(토큰·비밀번호)는 문서·로그·커밋에 절대 남기지 않는다.

## 3. 재개 절차
세션 시작 시 CLAUDE.md 순서(current-task → session-log → decisions → todo → git log)를 따르되,
환경이 비어 있으면 의존성 재설치부터 실행한다.

```bash
git clone <URL> && cd <project>
bash scripts/install-hooks.sh    # .git/hooks 는 커밋되지 않는다 — 클론마다 필요
<프로젝트별 의존성 설치·자격증명 재주입·정상성 확인 명령을 여기 채운다>
```
```

### `docs/context-budget.md` — the policy behind the guard

This is the **why** for §3's script. Write it so a future session can rotate correctly without
re-deriving the reasoning. Tune the numbers to project scale, but keep the `CLAUDE.md` cap tight.

```markdown
# 컨텍스트 예산 정책

이 방법론의 구조적 약점은 **기록 파일이 단조 증가**한다는 것이다. `session-log.md` 는 세션마다
쌓이고 `decisions.md` 는 D-번호가 늘고 `todo.md` 는 완료 항목이 남는다. 그런데 `CLAUDE.md` 가
"이 파일들을 읽어라"라고 지시하므로, 방치하면 **세션 시작 비용이 이력 길이에 비례해 증가**한다.

## 1. 원칙 — 크기 제한보다 "읽는 양의 고정"이 먼저다

파일이 커지는 것 자체는 문제가 아니다. **매 세션 읽는 양이 커지는 것**이 문제다.
그래서 1차 방어선은 캡이 아니라 `CLAUDE.md` 의 읽기 프로토콜이다.

| 파일 | 세션 시작에 읽는 범위 | 비용 |
| --- | --- | --- |
| `current-task.md` | 전문 | O(1) — 캡이 걸려 있음 |
| `session-log.md` | **최근 3개 항목** | O(1) — 파일이 커져도 불변 |
| `decisions.md` | **상단 인덱스 표만** | O(결정 수), 한 줄씩 |
| `todo.md` | **현재 Phase만** | O(1) |
| 참조 문서(설계·스펙) | 읽지 않음 (해당 작업 진입 시에만) | 0 |
| `archive/` | 읽지 않음 (명시적으로 찾을 때만) | 0 |

`session-log.md` 가 3,000줄이 되어도 세션 시작 비용은 그대로다. **이게 핵심이다.**
캡과 회전은 2차 방어선(파일 열람 부담, 검색 노이즈)일 뿐이다.

## 2. CLAUDE.md 는 특별 취급한다

`CLAUDE.md` 는 **매 세션 자동으로 컨텍스트에 들어간다.** 읽기 프로토콜로 방어할 수 없는
유일한 파일이므로 가장 엄격하다.

- **하드 캡 80줄.** 초과 시 커밋이 막힌다.
- **허브이지 문서가 아니다.** 규칙의 *위치*만 가리킨다. 근거·이력·예시·코드는 넣지 않는다.
- **순증 금지.** 새 규칙은 기존 줄을 교체하거나 `docs/` 로 밀어내고 한 줄로 가리킨다.
  "일단 여기 적어두자"가 이 파일을 망친다.
- 프로젝트가 커져도 CLAUDE.md 는 커지지 않는다. 늘어나는 건 위치 인덱스의 행 수뿐이다.

## 3. 캡 (2차 방어선)

`scripts/check-docs-budget.sh` 가 점검한다. soft = 경고, hard = 커밋 차단.

| 대상 | soft | hard | 초과 시 |
| --- | --- | --- | --- |
| `CLAUDE.md` | 60줄 | **80줄** | 내용을 `docs/` 로 밀어내고 한 줄 포인터로 교체 |
| `docs/current-task.md` | 40줄 | 60줄 | 진입점 목록을 자름 (§4) |
| `docs/current-task.md` 진입점 수 | 5개 | 7개 | 초과분 삭제 (session-log 에 중복) |
| `docs/session-log.md` | 300줄 | 500줄 | 오래된 항목 회전 (§4) |
| `docs/session-log.md` 항목 수 | 12개 | 20개 | 오래된 항목 회전 |
| `docs/todo.md` | 120줄 | 200줄 | 완료 Phase 회전 |
| `docs/decisions.md` | 400줄 | 700줄 | §5 — 회전하지 않고 압축한다 |

참조 문서(설계·스펙)는 캡이 없다 — 세션 시작에 읽지 않는다. 700줄을 넘기면 주제별 분할을 고려한다.

## 4. 회전 절차 (rotate, 삭제가 아니다)

`docs/archive/` 로 옮긴다. 아카이브는 **기본적으로 읽지 않는** 영역이지만 git 에 남아
검색·복구가 가능하다.

### session-log 회전
1. 최근 **12개 항목**만 `docs/session-log.md` 에 남긴다.
2. 나머지를 `docs/archive/session-log-YYYY-MM.md` 로 이동 (월별, 최신이 위 순서 유지).
3. `docs/session-log.md` 하단에 한 줄만 남긴다: `> 이전 이력: docs/archive/session-log-YYYY-MM.md`

### todo 회전
완료된 Phase(전 항목 `[x]`)를 `docs/archive/todo-done.md` 로 이동하고,
`docs/todo.md` 에는 `## Phase N. <제목> — 완료 (archive/todo-done.md)` 한 줄만 남긴다.

### current-task 정리
진입점 목록은 **최대 5개**. 초과분은 그냥 삭제한다 — `session-log.md` 에 같은 내용이 있으므로
아카이브할 필요가 없다. ★현재 진입점★ 마커는 새 항목을 올릴 때 ★이전 진입점★ 으로 강등한다.

## 5. decisions.md 는 회전하지 않는다 — 압축한다

결정은 **왜 지금 코드가 이렇게 생겼는지**의 유일한 근거다. 아카이브로 밀어내면 다음 세션이
같은 논쟁을 반복한다. 회전 대신:

- **상단 인덱스 표**를 유지한다 (D-번호 + 한 줄 + 상태). 세션 시작에 읽는 건 이 표뿐이다.
- 각 결정 본문은 **20줄 이내.** 길어지면 상세를 참조 문서로 옮기고 결정에는 링크만 둔다.
- 뒤집힌 결정은 지우지 않고 상태를 `폐기(→D-0NN)` 로 바꾼다. **번호는 재사용하지 않는다.**
- hard 캡에 닿으면 `docs/archive/decisions-001-050.md` 로 **본문만** 분할하고
  인덱스 표는 `decisions.md` 에 전부 남긴다.

## 6. 점검

```bash
bash scripts/check-docs-budget.sh     # 수동
bash scripts/install-hooks.sh         # pre-commit 훅 설치 (클론마다 1회)
```

훅은 hard 초과 시 커밋을 막고 soft 초과 시 경고만 한다. 급할 때 우회는 `git commit --no-verify`
이지만, 우회했다면 그 세션 안에 회전을 처리한다. 미룰수록 회전 비용이 커진다.
```

### `docs/archive/README.md` — the rotation target

```markdown
# archive

회전된 이력을 보관한다. **세션 시작 시 읽지 않는 영역이다** — 명시적으로 찾을 때만 열어본다.

`session-log.md` 등이 예산을 넘으면 오래된 항목을 여기로 옮긴다. 삭제가 아니라 이동이므로
git 에 남아 검색·복구가 가능하고, 대신 매 세션의 컨텍스트 비용에서는 빠진다.

| 파일 | 내용 |
| --- | --- |
| `session-log-YYYY-MM.md` | 월별로 회전된 작업 이력 |
| `todo-done.md` | 완료된 Phase |

회전 절차와 기준은 `docs/context-budget.md` §4.
`decisions.md` 는 **회전하지 않는다** — 근거를 잃으면 다음 세션이 같은 논쟁을 반복한다 (§5).
```

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

```markdown
# CLAUDE.md

<project> — 규칙 허브. **규칙 원본은 각 문서에 있고 여기서는 위치만 가리킨다.**

> ⚠️ 이 파일은 매 세션 자동으로 컨텍스트에 들어간다. **80줄을 넘기지 않는다.**
> 새 규칙은 줄을 *추가*하지 말고 기존 줄을 교체하거나 `docs/` 로 밀어낸다.
> 변경 이력·근거·예시는 여기 두지 않는다. 예산 정책 전문: `docs/context-budget.md`

## 세션 시작 시 — 읽는 양을 고정한다 (이력이 길어져도 늘지 않는다)
1. `docs/current-task.md` — 전문
2. `docs/session-log.md` — **최근 3개 항목만.** 그 위로는 읽지 않는다
3. `docs/decisions.md` — **상단 인덱스 표만.** 필요한 `D-번호`만 펼쳐 읽는다
4. `docs/todo.md` — **현재 Phase만**
5. `git log --oneline -10`

**세션 시작에 읽지 않는 것:** 참조 문서(설계·스펙 — 해당 작업에 들어갈 때만) ·
`docs/archive/`(회전된 이력 — 명시적으로 찾을 때만)
환경이 비어 있으면 이 순서 전에 `docs/recovery.md`.

## 작업 규칙 (항상 적용)
**모든 작업은 기록한다. 단 짧게 — 누적되는 파일이다.**
- 완료한 일 → `docs/session-log.md` 최상단. **항목당 15줄 이내**
- 설계·방향 결정 → `docs/decisions.md` 에 `D-번호` + 근거. **상단 인덱스 표에 한 줄 추가**
- 진행 상태 → `docs/todo.md` · `docs/current-task.md`(진입점 **최대 5개**, 초과분 삭제)
- 되돌리기 어려운 작업(외부 연동·push 등) → 결정으로 남김
- 마일스톤마다 커밋하고 곧바로 push
- 완료된 Phase·오래된 이력은 `docs/archive/` 로 회전시킨다 (삭제 아님)

## 컨텍스트 예산
`bash scripts/check-docs-budget.sh` — pre-commit 훅에서 자동 실행된다.
초과 시 회전 절차는 `docs/context-budget.md`. 훅 설치: `bash scripts/install-hooks.sh`

## 위치 인덱스
| 종류 | 위치 |
| --- | --- |
| 설계·방향 결정 (D-001~) | `docs/decisions.md` |
| 작업 이력 / 현재 작업 / 할 일 | `docs/session-log.md` / `current-task.md` / `todo.md` |
| 환경 유실 & 복구 절차 | `docs/recovery.md` |
| 컨텍스트 예산 정책 | `docs/context-budget.md` |

## 커밋 규칙
- 커밋·push 는 사용자가 요청할 때. 요청하면 커밋+push 한 흐름으로.
- 커밋 메시지 말미에 Co-Authored-By 트레일러 포함(값은 **그 세션의 모델** — 하네스가 지정한 값을
  쓰고, 과거 커밋의 트레일러는 고치지 않는다. 이력이 섞이는 건 정상이다).
- 민감정보(토큰·비밀번호)는 커밋에 절대 남기지 않는다.
```

As the project grows, add rows to the location index — **not** paragraphs. If a new rule needs
explanation, the explanation goes in `docs/` and this file gets one line pointing at it.

## 3. Install the budget guard (`scripts/`)

Copy both scripts from this skill's `assets/` directory — **don't retype them.** The base directory
is given to you at invocation time:

```bash
mkdir -p scripts
cp "<skill base dir>/assets/check-docs-budget.sh" scripts/
cp "<skill base dir>/assets/install-hooks.sh"     scripts/
chmod +x scripts/*.sh
bash scripts/install-hooks.sh
```

- `check-docs-budget.sh` — checks the §3-of-`context-budget.md` caps. soft = warn (exit 0),
  hard = block (exit 1). Every violation prints the specific rotation action to take. Caps live in
  variables at the top of the file; tune them to project scale, but keep the `CLAUDE.md` cap tight.
  It auto-detects reference docs (any `docs/*.md` outside the core set) and reports them **uncapped**,
  since the read protocol already excludes them.
- `install-hooks.sh` — installs `.git/hooks/pre-commit`. It **refuses to clobber** a pre-existing
  hook it didn't create (exit 2) and prints the two lines to add manually instead. If it exits 2,
  relay that to the user rather than forcing it.

Then **verify the guard actually fires** — a check that only ever passes is worse than none, because
it looks like coverage. Confirm at minimum that a hard violation blocks:

```bash
cp CLAUDE.md /tmp/c.bak
for i in $(seq 1 60); do echo "- filler $i" >> CLAUDE.md; done
bash scripts/check-docs-budget.sh; echo "expect exit 1, got $?"
cp /tmp/c.bak CLAUDE.md
bash scripts/check-docs-budget.sh   # back to green
```

If `docs/decisions.md` has no index table, the script hard-fails by design — that table is what the
session-start protocol reads, so its absence breaks the whole scheme.

## 4. Report and offer the follow-up

Tell the user exactly which files were **created** vs **skipped (already existed)**, and whether the
pre-commit hook was installed or declined (existing hook). Then offer:

- to fill `docs/current-task.md` and `docs/todo.md` with the real first tasks once they describe the
  project's goal, and
- that the companion **`wrap-up-docs-commit`** skill closes out each work chunk (docs update →
  secret scan → commit → push) using this same discipline.

Mention two things the user needs to know about the guard:

- `.git/hooks` is **not** committed, so `bash scripts/install-hooks.sh` must be re-run after every
  fresh clone (it's in `docs/recovery.md` step 2 for that reason).
- `git commit --no-verify` bypasses a hard block when they're mid-flight; the rotation should then be
  done within that session.

Do **not** commit here unless the user asks — creating the scaffold is itself the first thing a
wrap-up would record.
