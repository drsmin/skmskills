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
