#!/usr/bin/env bash
# docs 컨텍스트 예산 점검 — bootstrap-docs-workflow 스킬이 설치.
#
# 왜: session-log / decisions / todo 는 단조 증가한다. CLAUDE.md 가 "이 파일들을 읽어라"라고
#     지시하면 세션 시작 비용이 프로젝트 이력 길이에 비례해 커진다.
#     1차 방어선은 CLAUDE.md 의 읽기 범위 고정이고, 이 스크립트는 2차 방어선(캡)이다.
#     정책 전문: docs/context-budget.md
#
# 사용: bash scripts/check-docs-budget.sh
# 종료코드: 0 = 통과(soft 경고 포함), 1 = hard 초과
set -uo pipefail

# ── 캡 (프로젝트 규모에 맞게 조정 가능. 단 CLAUDE.md 는 낮게 유지할 것) ─────────
CLAUDE_SOFT=60;   CLAUDE_HARD=80     # 매 세션 자동 로드 — 가장 엄격
CURTASK_SOFT=40;  CURTASK_HARD=60    # 매 세션 전문을 읽음
ENTRY_SOFT=5;     ENTRY_HARD=7       # current-task 진입점 개수
SESSLOG_SOFT=300; SESSLOG_HARD=500
SESSENT_SOFT=12;  SESSENT_HARD=20    # session-log 항목 개수
TODO_SOFT=120;    TODO_HARD=200
DEC_SOFT=400;     DEC_HARD=700       # 회전하지 않고 압축한다
REFDOC_NOTE=700                      # 참조 문서 분할 권고선 (캡 아님)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.
cd "$ROOT" || exit 0

if [ -t 1 ]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=; YEL=; GRN=; DIM=; BLD=; OFF=
fi

fail=0
warn=0
declare -a ACTIONS=()

# 파일이 없으면 -1 을 돌려 "건너뜀" 으로 표시한다 (아직 만들지 않은 단계일 수 있다).
#
# 주의: `$(grep -c ... || echo 0)` 로 쓰면 안 된다. 매치가 0건일 때 grep 은 "0" 을 출력하고
# 종료코드 1 을 반환하므로 `|| echo 0` 이 함께 발동해 "0\n0" 이 되고, 이후 [ -eq ] 비교가
# 에러로 죽으면서 점검이 조용히 건너뛰어진다 — 있으나 마나 한 안전장치가 된다.
# 반드시 대입 후 실패만 보정한다.
_lines() {
  [ -f "$1" ] || { echo -1; return; }
  awk 'END{print NR}' "$1"
}
_count() {
  [ -f "$1" ] || { echo -1; return; }
  local n
  n=$(grep -cE "$2" "$1" 2>/dev/null) || n=0
  echo "$n"
}

# 특정 섹션 안에서만 센다. 파일 전체를 세면 오탐이 난다 — current-task.md 의 "현재 목표" 절에
# 불릿을 쓰면 그게 진입점으로 잡힌다(실제로 발생했다). 헤딩 제목으로 구간을 잡고 다음 헤딩에서 끊는다.
# 인자: <파일> <헤딩에 포함된 문자열> <셀 줄의 정규식>
_count_in_section() {
  [ -f "$1" ] || { echo -1; return; }
  awk -v want="$2" -v pat="$3" '
    /^#+ /   { inside = (index($0, want) > 0); next }
    inside && $0 ~ pat { c++ }
    END      { print c+0 }
  ' "$1"
}

# check <표시명> <실제값> <soft> <hard> <단위> <초과 시 안내>
check() {
  local label=$1 n=$2 soft=$3 hard=$4 unit=$5 action=$6
  if [ "$n" -lt 0 ]; then
    printf '%s  --  %s %-34s %s(파일 없음 — 건너뜀)%s\n' "$DIM" "$OFF" "$label" "$DIM" "$OFF"
    return
  fi
  if [ "$n" -gt "$hard" ]; then
    printf '%s HARD %s %-34s %4d%s  한계 %d\n' "$RED" "$OFF" "$label" "$n" "$unit" "$hard"
    ACTIONS+=("${RED}[HARD]${OFF} $label → $action")
    fail=1
  elif [ "$n" -gt "$soft" ]; then
    printf '%s soft %s %-34s %4d%s  권고 %d\n' "$YEL" "$OFF" "$label" "$n" "$unit" "$soft"
    ACTIONS+=("${YEL}[soft]${OFF} $label → $action")
    warn=1
  else
    printf '%s  ok  %s %-34s %4d%s %s(≤%d)%s\n' "$GRN" "$OFF" "$label" "$n" "$unit" "$DIM" "$soft" "$OFF"
  fi
}

printf '%s컨텍스트 예산 점검%s  %s(정책: docs/context-budget.md)%s\n\n' "$BLD" "$OFF" "$DIM" "$OFF"

# ── CLAUDE.md — 매 세션 자동 로드. 읽기 프로토콜로 방어할 수 없는 유일한 파일 ──
check "CLAUDE.md" "$(_lines CLAUDE.md)" "$CLAUDE_SOFT" "$CLAUDE_HARD" "줄" \
  "내용을 docs/ 로 밀어내고 한 줄 포인터로 교체. 허브는 커지지 않는다"

# ── current-task.md — 매 세션 전문을 읽는다 ─────────────────────────────────
check "docs/current-task.md" "$(_lines docs/current-task.md)" "$CURTASK_SOFT" "$CURTASK_HARD" "줄" \
  "진입점 목록을 잘라낸다 (session-log 에 중복 존재하므로 삭제 가능)"
check "  └ 진입점 개수" \
  "$(_count_in_section docs/current-task.md '진입점' '^- ')" "$ENTRY_SOFT" "$ENTRY_HARD" "개" \
  "오래된 진입점 삭제 (아카이브 불필요 — session-log 에 있음)"

# ── session-log.md — 최근 N개만 읽지만 회전 트리거 ──────────────────────────
check "docs/session-log.md" "$(_lines docs/session-log.md)" "$SESSLOG_SOFT" "$SESSLOG_HARD" "줄" \
  "오래된 항목을 docs/archive/session-log-YYYY-MM.md 로 회전"
check "  └ 항목 개수" "$(_count docs/session-log.md '^## ')" "$SESSENT_SOFT" "$SESSENT_HARD" "개" \
  "최근 ${SESSENT_SOFT}개만 남기고 회전 (context-budget.md §4)"

# ── todo.md ────────────────────────────────────────────────────────────────
check "docs/todo.md" "$(_lines docs/todo.md)" "$TODO_SOFT" "$TODO_HARD" "줄" \
  "완료된 Phase 를 docs/archive/todo-done.md 로 회전"

# ── decisions.md — 회전하지 않고 압축한다 ───────────────────────────────────
check "docs/decisions.md" "$(_lines docs/decisions.md)" "$DEC_SOFT" "$DEC_HARD" "줄" \
  "각 결정 본문을 20줄 이내로 압축. 상세는 참조 문서로 (§5 — 회전 금지)"

# ── decisions.md 인덱스 표 — 세션 시작에 읽는 것이 이 표뿐이므로 없으면 프로토콜이 깨진다 ──
if [ -f docs/decisions.md ]; then
  idx=$(_count docs/decisions.md '^\| *D-[0-9]{3}')
  bodies=$(_count docs/decisions.md '^## D-[0-9]{3}')
  if [ "$idx" -eq 0 ] && [ "$bodies" -gt 0 ]; then
    printf '%s HARD %s %-34s %s\n' "$RED" "$OFF" "  └ 결정 인덱스 표" "없음 — 세션 시작 읽기 프로토콜이 깨진다"
    ACTIONS+=("${RED}[HARD]${OFF} decisions.md → 상단에 D-번호 인덱스 표를 만든다")
    fail=1
  elif [ "$idx" -ne "$bodies" ]; then
    printf '%s soft %s %-34s %s\n' "$YEL" "$OFF" "  └ 결정 인덱스 표" "인덱스 ${idx}행 vs 본문 ${bodies}개 — 불일치"
    ACTIONS+=("${YEL}[soft]${OFF} decisions.md → 인덱스 표와 본문 개수를 맞춘다")
    warn=1
  else
    printf '%s  ok  %s %-34s %4d개 %s(본문과 일치)%s\n' "$GRN" "$OFF" "  └ 결정 인덱스 표" "$idx" "$DIM" "$OFF"
  fi
fi

# ── 참조 문서 (설계·스펙 등) — 캡 없음. 세션 시작에 읽지 않기 때문이다 ──────────
# docs/ 의 코어 파일 외 .md 를 자동 인식한다. 분할 권고선만 알린다.
CORE=" current-task.md session-log.md decisions.md todo.md recovery.md context-budget.md "
for f in docs/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case "$CORE" in *" $b "*) continue ;; esac
  n=$(_lines "$f")
  if [ "$n" -gt "$REFDOC_NOTE" ]; then
    printf '%s note %s %-34s %4d줄  %s캡은 없다(온디맨드). 주제별 분할 고려%s\n' \
      "$DIM" "$OFF" "$f" "$n" "$DIM" "$OFF"
  else
    printf '%s  ok  %s %-34s %4d줄 %s(캡 없음 — 온디맨드 참조 문서)%s\n' \
      "$GRN" "$OFF" "$f" "$n" "$DIM" "$OFF"
  fi
done

# ── 결과 ───────────────────────────────────────────────────────────────────
if [ ${#ACTIONS[@]} -gt 0 ]; then
  printf '\n%s할 일%s\n' "$BLD" "$OFF"
  for a in "${ACTIONS[@]}"; do printf '  · %s\n' "$a"; done
  printf '  %s회전 절차: docs/context-budget.md §4%s\n' "$DIM" "$OFF"
fi

echo
if [ "$fail" = 1 ]; then
  printf '%s✗ hard 한계 초과 — 회전/압축 후 다시 커밋한다.%s\n' "$RED" "$OFF"
  printf '  %s급하면 git commit --no-verify 로 우회할 수 있지만, 그 세션 안에 처리한다.%s\n' "$DIM" "$OFF"
  exit 1
elif [ "$warn" = 1 ]; then
  printf '%s⚠ soft 권고 초과 — 커밋은 통과. 곧 회전할 것.%s\n' "$YEL" "$OFF"
  exit 0
else
  printf '%s✓ 컨텍스트 예산 이내.%s\n' "$GRN" "$OFF"
  exit 0
fi
