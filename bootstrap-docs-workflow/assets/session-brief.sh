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
# 사용: bash scripts/session-brief.sh            전체판 — 사람이 **명령으로** 읽는 길
#       bash scripts/session-brief.sh --compact  압축판 — SessionStart 훅이 **자동 주입**한다
#
# 판이 둘인 이유: 전체판을 그대로 주입할 수 없다. 하네스가 주입 문맥을 **10,000자**에서
# 자르고, 넘으면 본문을 파일로 빼고 경로+프리뷰만 주면서 **읽으라고 하지 않는다** — 즉 브리핑이
# 통째로 없는 세션이 된다. 그래서 압축판은 창이 더 좁고(`*_COMPACT`) current-task 의 **지난 회차를
# 접는다**. 접지 않는 것은 「직전 완료」·「⏭ 다음」·todo ★ 절이다 — 그게 세션이 이어 쓸 맥락이고,
# 그걸 접으면 압축이 아니라 맥락 소실이다.
# ⚠️ 두 판을 하나로 합치지 말 것 — 전체판을 압축판에 맞추면 명령으로 읽는 쪽이 얇아지고,
#    압축판을 전체판에 맞추면 **주입이 조용히 사라진다**. 창 값은 docs-budget.conf 에 있다.
#
# 종료코드: 0 = 정상, 1 = 저장소가 아님. 문서가 없으면 그 절만 건너뛴다(초기 단계일 수 있다).
#
# 이식성: bash 3.2 (macOS 기본). mapfile/declare -A 금지 — check-docs-budget.sh 와 같은 이유.
set -uo pipefail

COMPACT=0
case ${1:-} in
  --compact) COMPACT=1 ;;
  '') ;;
  *) echo "모르는 인자: $1 (쓸 수 있는 것: --compact)" >&2; exit 1 ;;
esac

SESS_ENTRIES=3     # session-log 에서 펼칠 최근 항목 수 (CLAUDE.md 와 같은 값)
DEC_ROWS=25        # decisions 인덱스에서 펼칠 최근 행 수 — 이 절만 O(결정 수) 였다
GIT_LOG=10
# 브리핑 꼬리에 적는 「읽지 않는 것」 — 저장소마다 다르다. conf 로 덮어쓴다.
NOREAD_NOTE='docs/archive/ · docs/reports/ · (그 밖의 참조 문서)'
# 압축판의 창 — conf 가 덮어쓴다. 기본값은 「conf 가 없어도 압축판이 캡 안에 든다」쪽으로 잡는다.
SESS_ENTRIES_COMPACT=1
DEC_ROWS_COMPACT=8
GIT_LOG_COMPACT=5
CURTASK_FOLD_RE='^\*\*(그 앞|그 회차의 ⏭)'
DEC_ID='D-[0-9]{3}'; DEC_HEAD='## '   # 결정 형식 — check-docs-budget.sh 와 같은 값
DEC_LAYOUT=auto; DEC_DIR=docs/decisions   # 결정 배치 — check-docs-budget.sh 와 같은 값

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소가 아니다" >&2; exit 1; }
# 프로젝트별 값(SESS_ENTRIES·DEC_ROWS·형식)은 가드와 같은 설정 파일에서 읽는다
# shellcheck disable=SC1091
[ -f "$ROOT/scripts/docs-budget.conf" ] && . "$ROOT/scripts/docs-budget.conf"
# 압축판은 **같은 조각을 더 좁은 창으로** 낸다 — 조각 자체를 빼지 않는다(조각이 빠지면
# 세션 시작 읽기의 네 축 중 하나가 통째로 없어지고, 그게 이 규율이 막는 실패다).
if [ "$COMPACT" = 1 ]; then
  SESS_ENTRIES=$SESS_ENTRIES_COMPACT
  DEC_ROWS=$DEC_ROWS_COMPACT
  GIT_LOG=$GIT_LOG_COMPACT
fi
DEC_BODY_RE="^${DEC_HEAD}${DEC_ID}"; DEC_ROW_RE="^[|] *${DEC_ID}"
cd "$ROOT" || exit 1
if [ "$DEC_LAYOUT" = auto ]; then
  if [ -d "$DEC_DIR" ]; then DEC_LAYOUT=split; else DEC_LAYOUT=single; fi
fi

if [ -t 1 ]; then BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'; else BLD=; DIM=; OFF=; fi

sec() { printf '\n%s━━ %s %s%s\n\n' "$BLD" "$1" "$OFF" "$DIM$2$OFF"; }
miss() { printf '%s(%s 없음 — 건너뜀)%s\n' "$DIM" "$1" "$OFF"; }

# ── 1. current-task.md — 전문. 캡이 걸려 있어 O(1) 이다 ──────────────────────
#     압축판만 **지난 회차 블록을 제목 줄로 접는다**(`CURTASK_FOLD_RE`). 제목 줄에 D-번호와
#     회차 번호가 있으니 필요하면 그 결정 파일만 펼친다 — 접힌 것이 어디 있는지가 남는다.
#     ⚠️ 「직전 완료」·「⏭ 다음」을 접는 쪽으로 정규식을 넓히지 말 것 — 그 둘이 이어 쓸 맥락이다.
if [ "$COMPACT" = 1 ]; then
  sec "docs/current-task.md" "직전 완료 + ⏭ 다음 (지난 회차는 제목만)"
else
  sec "docs/current-task.md" "전문"
fi
if [ -f docs/current-task.md ]; then
  if [ "$COMPACT" = 1 ]; then
    awk -v fre="$CURTASK_FOLD_RE" -v dim="$DIM" -v off="$OFF" '
      $0 ~ fre { folded++; print dim "· (접힘) " substr($0, 1, 160) off; infold = 1; next }
      infold   { next }
      { print }
      END { if (folded > 0)
              printf "%s… 지난 회차 %d개는 제목만 냈다. 전문: sed -n \"/그 앞/,$p\" docs/current-task.md%s\n",
                     dim, folded, off }
    ' docs/current-task.md
  else
    cat docs/current-task.md
  fi
else miss docs/current-task.md; fi

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

# ── 3. decisions.md — 머리말 + 인덱스 표의 **최근 DEC_ROWS 행**까지 ──────────
#     본문은 결정당 ~23줄씩 늘어난다. 여기서 자르지 않으면 이 절이 브리핑을 삼킨다.
#     인덱스도 자른다: 표 전체를 싣던 동안 이 절만 O(결정 수)로 커졌고(어느 저장소: 54개 = 4,538자
#     = 브리핑의 32%), 결정이 하나 늘 때마다 브리핑이 ~80자씩 밀려 10세션마다 예산을 넘겼다.
#     접는 쪽은 **가장 오래된** 행이다 — 오래된 결정은 대개 current-task 가 번호와 함께 이미
#     되짚고 있고, 표는 파일에 그대로 남아 grep 한 번이면 펼쳐진다 (아카이브가 아니다).
sec "docs/decisions.md" "인덱스 표 최근 ${DEC_ROWS}행 (본문·그 앞 행은 필요할 때 펼친다)"
if [ -f docs/decisions.md ]; then
  awk -v n="$DEC_ROWS" -v dim="$DIM" -v off="$OFF" -v bre="$DEC_BODY_RE" -v rre="$DEC_ROW_RE" -v idre="$DEC_ID" '
    function foldline() {
      if (folded > 0 && !said) {
        printf "%s… 그 앞 %d행(%s~%s)은 접었다. 표는 파일에 있다: grep \"^| D-\" docs/decisions.md%s\n",
               dim, folded, hi, lo, off
        said = 1
      }
    }
    $0 ~ bre { foldline(); exit }
    $0 ~ rre {
      rows++
      if (rows <= n) { print; next }
      match($0, idre); id = substr($0, RSTART, RLENGTH)
      if (folded == 0) hi = id
      lo = id; folded++
      next
    }
    { foldline(); print }
    END { foldline() }
  ' docs/decisions.md
  if [ "$DEC_LAYOUT" = split ]; then
    # 본문은 결정 하나 = 파일 하나. 펼치는 비용이 결정 하나로 고정된다
    nd=$(ls "$DEC_DIR" 2>/dev/null | grep -cE "^${DEC_ID}[.]md$") || nd=0
    first=$(grep -oE "$DEC_ROW_RE" docs/decisions.md 2>/dev/null | head -1 | grep -oE "$DEC_ID") || first=""
    printf '%s… 본문 %d개는 펼치지 않았다. 결정 하나 = 파일 하나: %s/%s.md%s\n' \
      "$DIM" "$nd" "$DEC_DIR" "${first:-<ID>}" "$OFF"
  else
    nd=$(grep -cE "$DEC_BODY_RE" docs/decisions.md 2>/dev/null) || nd=0
    first=$(grep -oE "$DEC_BODY_RE" docs/decisions.md 2>/dev/null | head -1 | grep -oE "$DEC_ID") || first=""
    printf '%s… 본문 %d개는 펼치지 않았다. 예: sed -n "/^%s%s/,/^%s/p" docs/decisions.md%s\n' \
      "$DIM" "$nd" "$DEC_HEAD" "${first:-<ID>}" "$DEC_HEAD" "$OFF"
  fi
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
printf '%s   읽지 않는 것: %s%s\n' "$DIM" "$NOREAD_NOTE" "$OFF"
printf '%s   환경이 비어 있으면 docs/recovery.md 를 먼저 본다.%s\n' "$DIM" "$OFF"
# 압축판은 「전부」가 아니라 **시작점**이다 — 더 필요하면 전체판을 부른다(파일을 열지 않는다).
[ "$COMPACT" = 1 ] && printf '%s   더 필요하면 전체판: bash scripts/session-brief.sh%s\n' "$DIM" "$OFF"
