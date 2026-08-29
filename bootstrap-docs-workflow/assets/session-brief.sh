#!/usr/bin/env bash
# 세션 시작 브리핑 — 읽는 양을 **산문이 아니라 코드로** 고정한다.
#
# 왜: CLAUDE.md 가 "session-log 는 최근 3개만", "decisions 는 인덱스 표만" 이라고 적어도
#     읽는 쪽은 파일 단위로 읽는다. 범위가 문장으로만 있으면 결국 전체가 딸려 오고,
#     그러면 세션 시작 비용이 이력 길이에 비례해 커진다 — context-budget.md §1 이
#     "이게 핵심이다"라며 막았다고 선언한 바로 그 실패다.
#     어느 저장소 실측: 규칙대로 11,754자 vs 파일 전체 49,654자 = **4.2배**. 그리고 결정이
#     하나 늘 때 인덱스는 1줄인데 본문은 ~23줄이 붙으므로 격차는 계속 벌어진다.
#     그래서 범위를 스크립트가 잘라 출력한다. **이 출력이 세션 시작 읽기의 전부다.**
#
# 사용: bash scripts/session-brief.sh
# 종료코드: 0 = 정상, 1 = 저장소가 아님. 문서가 없으면 그 절만 건너뛴다(초기 단계일 수 있다).
#
# 이식성: bash 3.2 (macOS 기본). mapfile/declare -A 금지 — check-docs-budget.sh 와 같은 이유.
set -uo pipefail

SESS_ENTRIES=3     # session-log 에서 펼칠 최근 항목 수 (CLAUDE.md 와 같은 값)
GIT_LOG=10

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소가 아니다" >&2; exit 1; }
cd "$ROOT" || exit 1

if [ -t 1 ]; then BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'; else BLD=; DIM=; OFF=; fi

sec() { printf '\n%s━━ %s %s%s\n\n' "$BLD" "$1" "$OFF" "$DIM$2$OFF"; }
miss() { printf '%s(%s 없음 — 건너뜀)%s\n' "$DIM" "$1" "$OFF"; }

# ── 1. current-task.md — 전문. 캡이 걸려 있어 O(1) 이다 ──────────────────────
sec "docs/current-task.md" "전문"
[ -f docs/current-task.md ] && cat docs/current-task.md || miss docs/current-task.md

# ── 2. session-log.md — 최근 N개 항목만. 파일이 3,000줄이 되어도 이 절은 안 커진다 ──
sec "docs/session-log.md" "최근 ${SESS_ENTRIES}개 항목 (그 위로는 읽지 않는다)"
if [ -f docs/session-log.md ]; then
  awk -v n="$SESS_ENTRIES" '
    /^## / { c++ }
    c == 0 { next }          # 머리말은 건너뛴다 — 매 세션 같은 내용이다
    c >  n { exit }
    { print }
  ' docs/session-log.md
  total=$(grep -cE '^## ' docs/session-log.md 2>/dev/null) || total=0
  [ "$total" -gt "$SESS_ENTRIES" ] && printf '%s… 이전 %d개 항목은 파일에 있다 (필요할 때만 범위를 지정해 연다)%s\n' \
    "$DIM" "$((total - SESS_ENTRIES))" "$OFF"
else miss docs/session-log.md; fi

# ── 3. decisions.md — 첫 결정 본문 앞까지. 곧 머리말 + 인덱스 표다 ────────────
#     본문은 결정당 ~23줄씩 늘어난다. 여기서 자르지 않으면 이 절이 브리핑을 삼킨다.
sec "docs/decisions.md" "인덱스 표만 (본문은 필요한 D-번호만 펼친다)"
if [ -f docs/decisions.md ]; then
  awk '/^## D-[0-9]{3}/ { exit } { print }' docs/decisions.md
  nd=$(grep -cE '^## D-[0-9]{3}' docs/decisions.md 2>/dev/null) || nd=0
  printf '%s… 본문 %d개는 펼치지 않았다. 예: sed -n "/^## D-017/,/^## D-016/p" docs/decisions.md%s\n' \
    "$DIM" "$nd" "$OFF"
else miss docs/decisions.md; fi

# ── 4. todo.md — ★ 표시된 Phase 만 ──────────────────────────────────────────
#     "현재 Phase" 를 사람 판단에 맡기면 결국 전체를 읽게 된다. 마커로 기계가 읽게 만든다.
#     마커는 진행 중인 Phase 로 옮긴다. 없으면 읽기 프로토콜이 깨진 것이므로 가드가 잡는다.
sec "docs/todo.md" "★ 표시된 현재 Phase 만"
if [ -f docs/todo.md ]; then
  out=$(awk '/^## / { on = (index($0, "★") > 0) } on' docs/todo.md)
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    printf '%s… 나머지 Phase 는 접혀 있다 (grep "^## " docs/todo.md 로 목록만 본다)%s\n' "$DIM" "$OFF"
  else
    printf '%s⚠ ★ 표시된 Phase 가 없다 — 현재 Phase 헤딩에 ★ 를 붙인다 (context-budget.md §1)%s\n' "$DIM" "$OFF"
    grep -E '^## ' docs/todo.md
  fi
else miss docs/todo.md; fi

# ── 5. git ──────────────────────────────────────────────────────────────────
sec "git" "최근 ${GIT_LOG}개 커밋 · 작업 트리"
git log --oneline -"$GIT_LOG"
printf '\n'
git status --short 2>/dev/null | head -20 || true
git status --short 2>/dev/null | grep -q . || printf '%s(작업 트리 깨끗함)%s\n' "$DIM" "$OFF"

# ── 6. 닫는 말. 브리핑 크기는 check-docs-budget.sh 가 잰다 (여기 상수로 적지 않는다) ──
printf '\n%s━━ 이 브리핑을 읽는 것으로 세션 시작 읽기는 끝난다.%s\n' "$BLD" "$OFF"
printf '%s   위 파일들을 직접 열지 않는다 — 열면 전체가 딸려 오고 그게 이 규율이 막는 것이다.%s\n' "$DIM" "$OFF"
printf '%s   읽지 않는 것: docs/blueprint.md · docs/archive/ · docs/reports/ · (그 밖의 참조 문서)%s\n' "$DIM" "$OFF"
printf '%s   환경이 비어 있으면 docs/recovery.md 를 먼저 본다.%s\n' "$DIM" "$OFF"
