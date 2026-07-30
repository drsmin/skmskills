---
name: bootstrap-docs-workflow
description: Set up a Markdown-first, AI-session-restart working methodology in the current project — scaffold docs/ (current-task, session-log, decisions with D-numbers, todo, recovery) and a CLAUDE.md "rule hub". Use when starting a new project (or adopting the discipline in an existing one) and the user asks to "set up the docs workflow", "adopt this methodology", "bootstrap the working conventions", "이 방법론 적용해줘", "문서 기반 작업 규율 세팅". Run once per project; it detects the project name/remote and won't clobber files that already exist.
---

# Bootstrap the Markdown-first / session-restart methodology

This skill installs a documentation-driven working discipline into the **current** project. It is a
distillation of a proven methodology, not tied to any one codebase. The core idea:

> An AI agent's memory ends with the session. So **every piece of work is recorded in `docs/` as it
> happens**, `CLAUDE.md` points to where the rules live, and commits are pushed at every milestone —
> so any future session (or a fresh pod) can fully recover context from git alone.

Run this **once per project**. It is idempotent: it creates only the files that are missing and never
overwrites existing docs (it reports what it skipped).

## 0. Detect the project context (don't hardcode)

Before writing anything, gather real values so the scaffold is accurate:

```
basename "$(pwd)"                       # project name
git rev-parse --is-inside-work-tree     # is this a git repo?
git remote -v | head -1                 # remote kind (HTTPS/SSH), if any
git branch --show-current               # default branch
ls docs/ CLAUDE.md 2>/dev/null          # what already exists
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
```

### `docs/session-log.md` — what was done, newest first

```markdown
# Session Log

작업 이력. 최신 항목을 위에 추가한다. (Work history; newest entry on top.)

---

## <YYYY-MM-DD> (01) — 프로젝트 부트스트랩

**요청.** 방법론(문서 기반 작업 규율) 적용.
**작업.** docs/ 구조(current-task·session-log·decisions·todo·recovery) + CLAUDE.md 규칙 허브 생성.
```

### `docs/decisions.md` — design/direction decisions, numbered `D-NNN`

```markdown
# Design Decisions

설계·방향 결정 기록. 각 결정은 무엇을·왜. 되돌리기 어려운 작업도 여기 남긴다.
(Each decision records the *what* and the *why*; irreversible actions belong here too.)

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

## Phase 0. 기반
- [x] 문서 구조 생성 (current-task / session-log / decisions / todo / recovery)
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
환경이 비어 있으면 의존성 재설치부터 실행한다. <프로젝트별 설치·정상성 확인 명령을 여기 채운다>
```

## 2. Create or augment `CLAUDE.md` — the rule hub

`CLAUDE.md` is a **pointer/index**, not a changelog: it states the few invariant rules and points to
where each rule's source of truth lives. If it already exists, **merge** these sections in rather than
overwriting the user's content.

```markdown
# CLAUDE.md

<project> — 프로젝트 지침. 이 파일은 **규칙 허브**다: 규칙 원본은 각 문서에 있고 여기서는 위치를 가리킨다.

## 세션 시작 시
1. `docs/current-task.md` 를 먼저 읽는다 (현재 위치·진입점).
2. `docs/session-log.md` → `docs/decisions.md` → `docs/todo.md` 순으로 컨텍스트 복구.
3. git log 로 최신 상태 확인.
4. 환경이 비어 있으면 `docs/recovery.md` 복구 절차부터 실행.

## 작업 규칙 (항상 적용)
**모든 작업은 항상 기록한다.**
- 완료한 일 → `docs/session-log.md` (최신이 위)
- 설계·방향 결정 → `docs/decisions.md` 에 `D-번호`로 근거와 함께
- 진행 상태 → `docs/todo.md`, `docs/current-task.md` 갱신
- 되돌리기 어려운 작업(외부 연동·push 등) → 결정으로 남김
- 마일스톤마다 커밋하고 곧바로 push

## 위치 인덱스
| 종류 | 위치 |
| --- | --- |
| 설계·방향 결정 (D-001~) | `docs/decisions.md` |
| 작업 이력 / 현재 작업 / 할 일 | `docs/session-log.md` / `current-task.md` / `todo.md` |
| 환경 유실 & 복구 절차 | `docs/recovery.md` |

## 커밋 규칙
- 커밋·push 는 사용자가 요청할 때. 요청하면 커밋+push 한 흐름으로.
- 커밋 메시지 말미에 Co-Authored-By 트레일러 포함.
- 민감정보(토큰·비밀번호)는 커밋에 절대 남기지 않는다.
```

## 3. Report and offer the follow-up

Tell the user exactly which files were **created** vs **skipped (already existed)**. Then offer:

- to fill `docs/current-task.md` and `docs/todo.md` with the real first tasks once they describe the
  project's goal, and
- that the companion **`wrap-up-docs-commit`** skill closes out each work chunk (docs update →
  secret scan → commit → push) using this same discipline.

Do **not** commit here unless the user asks — creating the scaffold is itself the first thing a
wrap-up would record.
