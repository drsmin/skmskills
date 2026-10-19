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

### `docs/current-task.md` — the single entry point

The one file a new session reads first. Keep a **"★current entry point★"** marker that each wrap-up
demotes to "★previous entry point★".

```markdown
# Current Task

새 세션은 이 문서를 먼저 읽고, docs/session-log.md → decisions.md → todo.md 순으로 컨텍스트를 복구한다.
(A new session reads this first, then session-log → decisions → todo to recover context.)

## 현재 목표 (Current goal)

<one paragraph: what we're building and the immediate next priority>

## 진입점 (Entry point)

- **★현재 진입점★ — <YYYY-MM-DD> 프로젝트 부트스트랩. 방법론 문서 구조 생성.**

> 진입점은 **1개**. 그 앞의 이력은 `session-brief.sh` 가 `session-log.md` 최근 3개로 이미
> 보여준다 — 여기에 목록을 또 두면 같은 것을 매 세션 두 번 읽는다.
```

Keep it at one. A list here duplicates exactly what the briefing already prints from `session-log`,
so every session reads the same headings twice.

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

`docs/decisions.md`:

```markdown
# Design Decisions

설계·방향 결정 기록. 각 결정은 무엇을·왜. 되돌리기 어려운 작업도 여기 남긴다.
(Each decision records the *what* and the *why*; irreversible actions belong here too.)

**세션 시작 시에는 아래 인덱스 표만 읽는다.** 본문은 `docs/decisions/<ID>.md` 에 하나씩 있다 —
필요한 ID 의 **그 파일만** 연다. 새 결정은 파일을 만들고(본문 20줄 이내) 표 **맨 위**에 한 줄.
이 기록은 아카이브로 회전하지 않는다 — 근거를 잃으면 다음 세션이 같은 논쟁을 반복한다.
정책: `docs/context-budget.md` §5.

## 인덱스 (최신이 위)

| D | 결정 | 상태 |
| --- | --- | --- |
| D-002 | 컨텍스트 예산 안전장치 — 브리핑 스크립트 + 캡 + 회전 | 유효 |
| D-001 | 문서 기반 작업 규율 채택 | 유효 |

> 번호는 재사용하지 않는다. 뒤집힌 결정은 지우지 않고 상태를 `폐기(→D-0NN)` 로 바꾼다.
```

`docs/decisions/D-002.md`:

```markdown
# D-002. 컨텍스트 예산 안전장치

**결정:** 기록 파일의 단조 증가가 세션 시작 비용을 늘리는 것을 막는다. 3중 방어:
① **읽기 범위를 스크립트가 고정**(`scripts/session-brief.sh` 출력이 세션 시작 읽기의 전부),
② 캡(`scripts/check-docs-budget.sh`, pre-commit 훅), ③ 초과분 `docs/archive/` 회전.
결정은 하나 = 파일 하나(`docs/decisions/`) — 결정을 읽거나 고칠 때도 그 하나만 열린다.
정책 전문 `docs/context-budget.md`.

**이유:** 파일이 커지는 것 자체는 문제가 아니다. **매 세션 읽는 양이 커지는 것**이 문제다.
캡만 걸면 회전 노동만 늘고 원인이 남으므로 ①이 핵심이고 ②③은 보조다. 그리고 ①을 산문으로
적으면 안 지켜진다 — 자를 줄 번호가 없어 결국 파일 전체가 읽힌다(실측 4.2배). 스크립트가
자른다. `CLAUDE.md` 만은 매 세션 자동 로드되어 읽기 프로토콜로 방어할 수 없어 하드 캡 +
순증 금지 규칙을 적용한다.
```

`docs/decisions/D-001.md`:

```markdown
# D-001. 문서 기반 작업 규율 채택

**결정:** 모든 작업을 docs/ 에 기록하고 CLAUDE.md 를 규칙 허브로 둔다. 마일스톤마다 커밋+push.

**이유:** AI 세션은 매번 초기화된다. git 에 커밋+push 된 것만 확실히 안전하므로, 맥락을
문서로 남겨 원격에 백업하면 어떤 세션도 처음부터 컨텍스트를 복구할 수 있다.
```

### `docs/todo.md`

```markdown
# TODO

전체 작업 목록. `[x]` 완료, `[ ]` 미완, `[~]` 진행중.
완료된 Phase 는 `docs/archive/todo-done.md` 로 회전한다.

## ★ Phase 0. 기반 — **현재 Phase**
- [x] 문서 구조 생성 (current-task / session-log / decisions / todo / recovery / context-budget)
- [x] 컨텍스트 예산 안전장치 — `session-brief.sh` + `check-docs-budget.sh` + pre-commit 훅 (D-002)
- [ ] <first real task>
```

**The `★` is load-bearing** — `session-brief.sh` prints only the marked section, and the guard fails
hard when no heading carries it. Move it to the phase in progress; never leave two or more.

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
그래서 1차 방어선은 캡이 아니라 읽기 프로토콜이다.

**단, 프로토콜을 산문으로만 적으면 지켜지지 않는다.** "최근 3개만" 이라고 써 두어도 읽는 쪽은
파일 단위로 읽는다 — 범위를 자를 줄 번호가 어디에도 없기 때문이다. 그래서 범위를 **스크립트가
자른다**: `bash scripts/session-brief.sh` 한 번이 세션 시작 읽기의 전부다.

| 파일 | 브리핑이 잘라 주는 범위 | 비용 |
| --- | --- | --- |
| `current-task.md` | 전문 | O(1) — 캡이 걸려 있음 |
| `session-log.md` | **최근 3개 항목** (머리말도 자른다) | O(1) — 파일이 커져도 불변 |
| `decisions.md` | 머리말 + 인덱스 표의 **최근 25행** (`DEC_ROWS`) | O(1) — 그 앞 행은 접고 `grep` 으로 펼친다 |
| `decisions/<ID>.md` | 출력하지 않음 — 필요한 ID 의 **그 파일만** 연다 | 0 (펼칠 때도 결정 하나) |
| `todo.md` | **`★` 표시된 Phase 만** | O(1) |
| 참조 문서(설계·스펙) · `archive/` | 출력하지 않음 | 0 |

`★` 마커가 중요하다 — "현재 Phase" 를 사람 판단에 맡기면 결국 파일을 연다. 마커를 진행 중인
Phase 로 옮기고, 없으면 가드가 hard 로 막는다(읽기 프로토콜이 깨진 상태이기 때문이다).

**인덱스 표도 접는다.** "O(결정 수)지만 한 줄씩"은 허용해도 되는 증가가 아니었다 — 어느
저장소에서 결정 54개에 4,538자, 브리핑의 32%였고, 결정이 하나 늘 때마다 ~80자씩 밀려 **열
세션마다 예산을 다시 넘겼다.** 브리핑은 최근 `DEC_ROWS` 행만 싣고 그 앞은
`… 그 앞 N행(D-0NN~D-001)은 접었다` 한 줄로 가리킨다. 가장 오래된 행을 접는 이유: 오래된
결정은 대개 `current-task.md` 가 번호와 함께 이미 되짚고 있고, 표는 파일에 **그대로 남아**
grep 한 번이면 펼쳐진다 — 아카이브가 아니다(§5 는 그대로 유효하다).

`session-log.md` 가 3,000줄이 되어도 세션 시작 비용은 그대로다. **이게 핵심이다.**
캡과 회전은 2차 방어선(파일 열람 부담, 검색 노이즈)일 뿐이다.

## 2. CLAUDE.md 는 특별 취급한다

`CLAUDE.md` 는 **매 세션 자동으로 컨텍스트에 들어간다.** 읽기 프로토콜로 방어할 수 없는
유일한 파일이므로 가장 엄격하고, 크기 외에 **구조**까지 검사한다.

- **허브이지 문서가 아니다.** 규칙의 *위치*만 가리킨다. 근거·이력·예시·코드는 넣지 않는다.
- **순증 금지.** 새 규칙은 기존 줄을 교체하거나 `docs/` 로 밀어내고 한 줄로 가리킨다.
  "일단 여기 적어두자"가 이 파일을 망친다.
- 프로젝트가 커져도 CLAUDE.md 는 커지지 않는다. 늘어나는 건 위치 인덱스의 행 수뿐이다.

### 상한 계약 — 문서가 자기 상한을 선언한다

문서 안에 계약 줄을 두고 가드가 그 줄을 파싱해 자기 상수와 대조한다.

```
> **상한 계약(가드가 이 줄을 파싱한다):** 전체 `4000자` · 전체 `80줄` · 한 줄 `240자` · 섹션 `25줄`
```

**상한을 늘리려면 문서와 스크립트를 둘 다 고쳐야 한다.** 한 곳만 고치면 가드가 불일치로 막는다.
"일단 늘리고 보자"가 안 되고, 상한 변경이 의식적인 행위가 된다.

### 줄 수만으로는 부족하다

가장 흔한 비대화 경로는 줄이 늘어나는 게 아니라 **한 줄이 비대해지는 것**이다. 표 행 하나에
요약을 밀어넣으면 줄 수는 그대로인데 컨텍스트는 통째로 먹힌다. 그래서 4종을 함께 본다:
전체 문자 수 · 전체 줄 수 · **한 줄 길이** · **섹션 본문 줄 수**.

### 섹션 스프롤을 막는다

허용 `##` 섹션 목록을 `scripts/claude-md-sections.txt` 에 둔다. 섹션을 새로 만들려면 문서와 이
파일을 둘 다 고쳐야 하므로, 섹션을 늘리기 전에 "그 내용이 `docs/` 로 가야 하는 게 아닌가"를 먼저
따지게 된다. 섹션 추가는 비대화의 1차 경로다.

### 허브가 거짓말하지 않게 한다

- **백틱 경로 존재 검사** — 파일을 옮기거나 지우고 문서를 안 고치면 허브가 조용히 거짓말한다.
  위치 인덱스가 틀린 허브는 없는 것보다 나쁘다(다음 세션이 그걸 믿고 헤맨다).
- **`D-번호` 해결 검사** — 참조한 결정이 실제로 정의돼 있는지(`docs/decisions/<ID>.md`, 한 파일 배치면 `docs/decisions.md`).

### 검사하지 않는 것

문장 표현·규칙 순서·규칙 내용의 *정확성* 은 일부러 검사하지 않는다 — 그건 사람이 본다.
문구를 다듬을 때마다 빨개지는 가드는 결국 팀이 무르게 만든다. **구조만 본다.**

## 3. 캡 (2차 방어선)

`scripts/check-docs-budget.sh` 가 점검한다. soft = 경고, hard = 커밋 차단.

| 대상 | soft | hard | 초과 시 |
| --- | --- | --- | --- |
| `CLAUDE.md` | 60줄 | **80줄** | 내용을 `docs/` 로 밀어내고 한 줄 포인터로 교체 |
| `docs/current-task.md` | 40줄 | 60줄 | 진입점 목록을 자름 (§4) |
| `docs/current-task.md` 진입점 수 | **1개** | 3개 | 초과분 삭제 — 브리핑이 session-log 최근 3개를 이미 보여준다 |
| `docs/session-log.md` | 300줄 | 500줄 | 오래된 항목 회전 (§4) |
| `docs/session-log.md` 항목 수 | 12개 | 20개 | 오래된 항목 회전 |
| `docs/session-log.md` **항목당 본문** | **15줄** | **22줄** | 상세를 `decisions.md` 로 옮기고 항목엔 `D-번호`만 |
| `docs/todo.md` | 120줄 | 200줄 | 완료 Phase 회전 |
| `docs/todo.md` `★` 마커 | — | **필수 1~2개** | 진행 중인 Phase 헤딩에 `★` (브리핑이 이걸로 찾는다) |
| 결정당 본문 (`docs/decisions/<ID>.md`) | **20줄** | **30줄** | §5 — 그 결정을 압축한다 |
| `docs/decisions.md` 총합 (한 파일 배치만) | (파생) | (파생) | `서문 + 결정수 × (20\|30 + 4)` — split 이면 재지 않는다 |
| `docs/decisions.md` **인덱스 행 길이** | **100자** | **140자** | 그 행을 줄인다 — 상세는 본문에 있다 |
| **세션 브리핑 출력** | **14,000자** | **20,000자** | 아래 조각 중 빨간/노란 것을 줄인다 |
| └ current-task 전문 | 3,200자 | 4,200자 | 긴 줄을 쪼개지 말고 **덜어낸다** |
| └ 로그 최근 3개 | 3,000자 | 4,200자 | 새 항목을 짧게 (지난 항목은 고치지 않는다) |
| └ todo `★` 절 | 2,400자 | 3,200자 | 끝난 항목을 회전 |

**브리핑 출력 행이 제일 중요하다.** 위의 다른 캡은 전부 파일 크기를 잰다 — 정작 *매 세션 읽는
양*은 아무도 안 잰다. 실제로 **모든 캡이 초록인 채로** 읽기 비용이 4.2배가 돼 있던 저장소가 있었다.
그 숫자는 문서에 적지 않고 가드가 잰다 — 적어 두면 문서가 자기 상태를 두고 거짓말한다.

**조각도 문자로 잰다.** 조각 캡이 줄 수뿐이면, 줄은 그대로인 채 한 줄이 두 배가 될 때 아무도
빨개지지 않는다 — §2 가 CLAUDE.md 에서 막은 실패가 브리핑 조각에서 반복됐다(current-task 37줄 =
3,831자). 가드는 **브리핑 출력 자체를** 절 머리글로 잘라 잰다(파일을 다시 자르면 브리핑과 가드가
다른 범위를 재게 된다). 인덱스와 git 은 창(`DEC_ROWS`·`GIT_LOG`)으로 고정돼 캡이 없다.

**문자 수는 로케일에서 뗀다.** `wc -m`·`awk length()` 는 로케일이 비면(pre-commit 훅에서 흔하다)
**바이트**를 센다 — 한글이 1.6배로 부풀어 없는 HARD 로 커밋을 막았다. UTF-8 의 이어지는 바이트
(0x80~0xBF)를 지우고 바이트를 센다. 근사 폴백(python 등)은 두지 않는다 — 없는 환경에서 조용히
바이트로 떨어져 거짓 HARD 가 다시 났다.

**여유를 찍는다.** 가드는 행마다 **다음 문턱까지의 여유**(통과면 권고선까지, 넘겼으면 한계까지)를
찍고, 끝에 급한 순서 5개(상태 먼저, 같은 상태면 문턱에 가까운 순)를 요약한다. 통과/실패만 찍으면
"몇 줄 뒤에 노랑인지"가 안 보여 매번 손으로 다시 잰다.

**총합이 아니라 단위를 재는 이유.** 세션 시작에 읽히는 건 로그 *최근 3개*와 결정 *인덱스 표*
뿐이다. 총 줄 수는 회전 트리거일 뿐이고, 긴 항목 하나가 브리핑을 삼킨다. 반대로 총합에 고정
캡을 두면(결정은 계속 는다) 못 지킬 값이 되어 가드가 결국 무르게 만들어진다 — 그래서
`decisions.md` 총합 상한은 **결정 수에서 유도**한다.

참조 문서(설계·스펙)는 캡이 없다 — 세션 시작에 읽지 않는다. 700줄을 넘기면 주제별 분할을
고려한다. (여기에 "현재 N줄" 을 적지 않는다 — 적어 두면 문서가 자기 상태를 두고 거짓말한다.)

## 4. 회전 절차 (rotate, 삭제가 아니다)

`docs/archive/` 로 옮긴다. 아카이브는 **기본적으로 읽지 않는** 영역이지만 git 에 남아
검색·복구가 가능하다.

`bash scripts/rotate-docs.sh` 가 아래 두 회전을 한다(`--dry-run` 으로 먼저 본다). 회전 전후 내용
줄이 한 줄이라도 다르면 아무것도 바꾸지 않고 멈춘다. 손으로 하면 포인터 누락·순서 뒤집힘이 잦았다.

### session-log 회전
1. 최근 **`SESS_KEEP`(기본 6)개 항목**만 `docs/session-log.md` 에 남긴다. 권고선(12개)보다 낮게
   남겨야 다음 회전까지 여유가 생긴다 — 12개로 자르면 다음 세션에 또 경고가 뜬다.
2. 나머지는 항목 헤딩의 날짜(`## YYYY-MM-DD …`)로 `docs/archive/session-log-YYYY-MM.md` **맨 위**에
   끼운다(최신이 위 순서 유지). 날짜를 못 읽는 항목이 있으면 스크립트는 거부한다.
3. `docs/session-log.md` 하단에 한 줄만 남긴다: `> 이전 이력: docs/archive/session-log-YYYY-MM.md`

### todo 회전
1. **먼저 남은 미완 항목을 갈 Phase 로 이월시킨다** (`(3주차에서 이월)` 처럼 출처를 적는다).
   "전 항목 `[x]`" 가 되기를 기다리면 미완 하나 때문에 **영원히 회전하지 않는다.** 이월은 판단이라
   스크립트가 하지 않는다 — 미완이 섞인 Phase 를 찍어 줄 뿐이다.
2. 그 다음 스크립트가 항목이 전부 `[x]` 이고 `★` 가 없는 Phase 를 `docs/archive/todo-done.md` 로
   옮기고, `docs/todo.md` 에는 `## Phase N. <제목> — 완료 (docs/archive/todo-done.md)` 한 줄을 남긴다.
3. `★` 마커를 새 현재 Phase 로 옮긴다.

### 리포트·발표본 회전
개정할 때마다 **새 날짜 파일**이 되는 산출물이 있으면(리포트·발표본) 현행판 하나만 남기고
이전 판은 생성물(`.pptx`/`.docx` 등)까지 함께 `docs/archive/reports/` 로 옮긴다. 세션 시작에
읽지 않아도 `grep -r docs/` 가 매번 n중으로 걸린다 — 어느 저장소에서는 거의 같은 발표본 3판이
`docs/` 전체의 39% 였다. 아카이브된 판은 *그때의 기록*이므로 오늘의 값과 대조하는 테스트
목록에서도 뺀다.

### current-task 정리
진입점은 **1개**. 초과분은 그냥 삭제한다 — 브리핑이 `session-log.md` 최근 3개를 이미
보여주므로 목록을 또 두면 매 세션 두 번 읽는다. ★현재 진입점★ 마커는 새 항목으로 갈아 끼운다.

## 5. 결정은 회전하지 않는다 — 압축하고, 하나씩 쪼개 둔다

결정은 **왜 지금 코드가 이렇게 생겼는지**의 유일한 근거다. 아카이브로 밀어내면 다음 세션이
같은 논쟁을 반복한다. 회전 대신:

- **결정 하나 = 파일 하나** (`docs/decisions/D-NNN.md`). 한 파일에 두면 세션 시작은 브리핑이
  막아도 결정을 고칠 때마다 편집 도구가 파일 전체를 읽고, 그 비용은 결정 수에 비례해 커진다.
  쪼개 두면 읽기·쓰기가 결정 하나로 고정된다. 한 파일로 쌓인 저장소는
  `bash scripts/split-decisions.sh` 로 옮긴다(가드·브리핑은 `docs/decisions/` 가 있으면 알아서 split).

- **상단 인덱스 표**를 유지한다 (D-번호 + 한 줄 + 상태). 세션 시작에 읽는 건 이 표뿐이다.
- 각 결정 본문은 **20줄 이내.** 길어지면 상세를 참조 문서로 옮기고 결정에는 링크만 둔다.
  **가드가 결정별로 이걸 잰다** (soft 20 · hard 30 — 위반한 D-번호를 찍는다). 총 줄 수에는
  고정 캡을 두지 않는다 — 세션 시작에 읽는 건 인덱스 표뿐이라 총합은 세션 비용이 아니고,
  못 지킬 고정값을 두면 가드가 결국 무르게 만들어진다.
- 뒤집힌 결정은 지우지 않고 상태를 `폐기(→D-0NN)` 로 바꾼다. **번호는 재사용하지 않는다.**
- 인덱스 표는 `decisions.md` 에 **전부** 남긴다(최신이 위). split 이면 가드가 표의 ID 와 파일
  목록을 맞대 보고, 파일 이름과 첫 헤딩의 ID 가 다르거나 `decisions.md` 에 본문이 남으면 막는다.

## 6. 점검

```bash
bash scripts/session-brief.sh         # 세션 시작 — 읽는 양이 여기서 고정된다
bash scripts/check-docs-budget.sh     # 캡 점검 (수동)
bash scripts/install-hooks.sh         # pre-commit 훅 설치 (클론마다 1회)
```

훅은 hard 초과 시 커밋을 막고 soft 초과 시 경고만 한다. 급할 때 우회는 `git commit --no-verify`
이지만, 우회했다면 그 세션 안에 회전을 처리한다. 미룰수록 회전 비용이 커진다.

## 7. 세션 안 비용 — 시작이 고정돼도 세션은 자란다

느려짐은 **호출마다 들어가는 입력 토큰**이다. 위의 장치는 시작 읽기를 고정할 뿐이고, 실측에서 더 큰
쪽은 세션 안 누적이었다(시작 4.7만 → 같은 세션 안에서 27.5만, 대부분 명령 출력). 재는 법:
`python3 -I scripts/session-cost.py` — 세션마다 시작·최대 토큰과 대화를 키운 도구 결과를 보인다.

| 원인 | 장치 |
| --- | --- |
| **세션 수명** — 긴 세션의 컴팩트가 재독을 만든다 | **재는 자 `python3 -I scripts/session-rereads.py`.** 고침은 **`/clear`** 다(아래) |
| 게이트 출력이 커밋마다 쌓인다 | `scripts/check.sh` — 성공은 단계당 한 줄, 실패만 전문. 훅도 통과면 한 줄 |
| 큰 파일을 통째로 읽는다 | **훅 `scripts/hooks/pre-read-size.sh`** 가 이미지는 막고 텍스트는 알린다 + `check.sh` 끝의 크기 검사 |
| 커밋 전 테스트를 빠뜨린다 | **훅 `scripts/hooks/pre-commit-test.sh`** — 실패면 도구 호출을 거부한다 |
| 기본 부하(커넥터·플러그인·스킬 목록) | 개인 설정 `.claude/settings.local.json` 으로 안 쓰는 것을 끈다(아래) |
| 긴 출력·넓은 탐색·스크린샷 | 습관(아래) |

**실측이 가르친 순서 — 지배 요인은 세션 수명이다.** 한 저장소에서 세션 9개를 뜯어 보니 **한 세션이
호출의 83% · 컴팩트의 91% · 도구 결과의 90%** 를 혼자 썼고 그 세션의 **재독분이 78%** 였다(나머지
8세션은 0~2%). 컴팩트가 요약에서 빠진 파일을 다시 읽게 만들고, 그 재독이 캐시를 깨는 것이 체감
느려짐이다. ⚠️ **느려진다고 문서를 더 깎지 말 것** — 시작 읽기는 위 장치로 이미 O(1)이고, 분자는
크기가 아니라 **횟수**라 파일 크기 가드엔 보이지 않는다. ⚠️ **재독을 훅으로 막지도 말 것**(컴팩트
뒤의 정당한 복구 읽기까지 막는다). ⚠️ **컴팩트 문턱(`CLAUDE_CODE_MAX_CONTEXT_TOKENS`)을 올려
푸는 것도 답이 아니다** — 호출당 지연이 60~80k 구간 3.0초 → 220~240k 구간 **14.0초**라, 문턱을
올리면 컴팩트는 줄고 호출이 느려진다(실측 8,042 호출).

**산문 금지는 지켜지지 않는다 — 집행 형태를 고른다.** 「화면 사진을 통째로 Read 하지 말 것」을
`CLAUDE.md` 에 적은 **뒤에도** PNG 5장이 1,777,896자(그 세션 도구 결과의 21%)로 들어왔다. 규칙이
옳아도 사람·모델이 자를 지점을 모르면 그만이다 ⇒ **훅이 막고 자르는 명령을 준다.** 같은 이유로
세션 시작 읽기도 산문(「목차만 보라」)에서 **스크립트**(`session-brief.sh`)로 옮겼다.

**습관.** 명령·로그 출력은 `tail`·`grep`·요약으로 받는다. 큰 파일은 범위를 지정해 연다. 여러 파일을
훑는 탐색은 하위 에이전트에 맡기고 결론만 받는다. 스크린샷은 필요한 영역만 작게 찍는다(한 장이
수만 자다). **마일스톤마다 커밋하고 `/clear`** — 새 세션은 브리핑 한 번이면 이어진다.

**개인 설정** (git 에 올리지 않는다 — 사람마다 쓰는 연결이 다르다):

    { "disableClaudeAiConnectors": true,
      "enabledPlugins": { "<이름>@<마켓>": false } }

커넥터는 이 프로젝트에서 전부 꺼진다(다시 켜려면 줄을 지우고 새 세션). 플러그인 이름은
`claude plugin list`, 다시 켜기는 `/plugin`. 효과는 다음 세션의 `session-cost.py` 시작 값으로 확인한다.
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

The **contract line** is load-bearing too: the doc declares its own limits and the guard parses that
line and compares it against its own constants. Raising a limit then requires editing *both* the doc
and the script — which turns "just bump it" into a deliberate act. Keep the backtick format exactly
(`전체 \`4000자\`` etc.) or the guard reports the declaration as missing.

```markdown
# CLAUDE.md

<project> — 규칙 허브. **규칙 원본은 각 문서에 있고 여기서는 위치만 가리킨다.**

> ⚠️ 이 파일은 매 세션 자동으로 컨텍스트에 들어간다. 새 규칙은 줄을 *추가*하지 말고 기존 줄을
> 교체하거나 `docs/` 로 밀어낸다. 변경 이력·근거·예시는 여기 두지 않는다.
>
> **상한 계약(가드가 이 줄을 파싱한다):** 전체 `4000자` · 전체 `80줄` · 한 줄 `240자` · 섹션 `25줄`
>
> 상한·허용 섹션·백틱 경로 존재·`D-번호` 해결은 `scripts/check-docs-budget.sh` 가 검사한다
> (pre-commit). 위반 시 **상한을 늘리지 말고** 내용을 `docs/` 로 옮긴다 — 상한을 고치려면 이 줄과
> 스크립트를 **둘 다** 고쳐야 한다. 예산 정책 전문: `docs/context-budget.md`

## 세션 시작 시 — 읽는 양을 스크립트가 고정한다 (이력이 길어져도 늘지 않는다)
**`bash scripts/session-brief.sh` 한 번이 세션 시작 읽기의 전부다.** 이 안에 들어 있는 것:
`current-task.md` 전문 · `session-log.md` 최근 3개 · `decisions.md` 인덱스 최근 25행 ·
`todo.md` 의 `★` 표시 Phase · `git log -10` + 작업 트리.

**위 파일들을 직접 열지 않는다** — 열면 전체가 딸려 오고 그게 이 규율이 막는 것이다.
필요한 `D-번호`·과거 세션은 그때 **범위를 지정해** 펼친다. 근거는 D-002.

**세션 시작에 읽지 않는 것:** 참조 문서(설계·스펙 — 해당 작업에 들어갈 때만) ·
`docs/archive/`(회전된 이력 — 명시적으로 찾을 때만)
환경이 비어 있으면 이것보다 먼저 `docs/recovery.md`.

## 작업 규칙 (항상 적용)
**모든 작업은 기록한다. 단 짧게 — 누적되는 파일이다.**
- 완료한 일 → `docs/session-log.md` 최상단. **항목당 15줄 이내**
- 설계·방향 결정 → `docs/decisions/D-NNN.md` 새 파일(본문 20줄 이내) + `docs/decisions.md` **인덱스 표 맨 위에 한 줄**(100자 이내)
- 진행 상태 → `docs/todo.md` · `docs/current-task.md`(진입점 **1개**, 나머지는 삭제)
- 되돌리기 어려운 작업(외부 연동·push 등) → 결정으로 남김
- 마일스톤마다 커밋하고 곧바로 push
- 완료된 Phase·오래된 이력은 `docs/archive/` 로 회전시킨다 (삭제 아님)

## 컨텍스트 예산
`bash scripts/check-docs-budget.sh` — pre-commit 훅에서 자동 실행된다.
초과 시 회전 절차는 `docs/context-budget.md`. 훅 설치: `bash scripts/install-hooks.sh`
**세션 안:** 게이트는 `bash scripts/check.sh` · 긴 출력은 꼬리만 · 큰 파일은 범위로 · 마일스톤마다 `/clear` — 완료 보고 끝에 늘 권한다 (§7)

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
