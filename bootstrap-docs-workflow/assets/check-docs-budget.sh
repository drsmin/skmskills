#!/usr/bin/env bash
# docs 컨텍스트 예산 점검 — bootstrap-docs-workflow 스킬이 설치.
#
# 왜: session-log / decisions / todo 는 단조 증가한다. CLAUDE.md 가 "이 파일들을 읽어라"라고
#     지시하면 세션 시작 비용이 프로젝트 이력 길이에 비례해 커진다.
#     1차 방어선은 CLAUDE.md 의 읽기 범위 고정이고, 이 스크립트는 2차 방어선(캡)이다.
#     정책 전문: docs/context-budget.md
#
# CLAUDE.md 는 매 세션 자동 로드되어 읽기 프로토콜로 방어할 수 없으므로 §B 에서 별도로 깊게 본다.
# 검사하는 것은 **구조**뿐이다 — 문장 표현·규칙 순서·내용의 정확성은 일부러 보지 않는다(사람이 본다).
# 다듬을 때마다 빨개지는 가드는 결국 팀이 무르게 만든다.
#
# 사용: bash scripts/check-docs-budget.sh
# 종료코드: 0 = 통과(soft 경고 포함), 1 = hard 초과
#
# 이식성: **bash 3.2 에서도 돌아야 한다** (macOS 기본 /bin/bash). `mapfile`/`readarray` 와
#   `declare -A` 는 bash 4 전용이라 쓰지 않는다. 한 번 썼다가 §B-5·B-6·B-8 세 검사가
#   `set -u` 와 겹쳐 통째로 건너뛰어졌고, 그런데도 종료코드는 0 이었다 — 통과처럼 보이는 실패.
#   배열 대신 개행 구분 문자열 + `while IFS= read` 를 쓴다.
set -uo pipefail

# ── 캡 (프로젝트 규모에 맞게 조정 가능. 단 CLAUDE.md 는 낮게 유지할 것) ─────────
CLAUDE_SOFT=60;   CLAUDE_HARD=80     # 매 세션 자동 로드 — 가장 엄격
CURTASK_SOFT=40;  CURTASK_HARD=60    # 매 세션 전문을 읽음
ENTRY_SOFT=1;     ENTRY_HARD=3       # current-task 진입점 개수 — session-log 최근 N개와 중복이다
SESSLOG_SOFT=300; SESSLOG_HARD=500
SESSENT_SOFT=12;  SESSENT_HARD=20    # session-log 항목 개수 (회전 트리거 — 세션 비용 아님)
# 세션 시작 비용은 총 줄 수가 아니라 **최근 항목 하나의 길이**다. 총 줄 수·항목 개수는 회전
# 트리거일 뿐 브리핑 크기와 무관하다 — 긴 항목 하나가 브리핑을 삼킨다. "총합이 아니라 단위를 재라".
SESSBODY_SOFT=15; SESSBODY_HARD=22   # CLAUDE.md 의 "항목당 15줄 이내" 를 항목별로 강제
TODO_SOFT=120;    TODO_HARD=200
# decisions.md 는 총 줄 수로 재지 않는다. 결정은 계속 늘고, 세션 시작에 읽는 건
# 인덱스 표뿐이라(§1) 총합은 애초에 세션 비용이 아니다. 대신 **결정 하나의 본문 길이**를 잰다.
DECBODY_SOFT=20;  DECBODY_HARD=30    # §5 의 "본문 20줄 이내" 를 결정별로 강제
# 지난 결정은 고치지 않는다(그때의 근거다) ⇒ hard 를 과거 최댓값에 맞추면 **새 결정은 아무것도
# 막히지 않는다**(장식이 된 가드). 그래서 hard 는 **이 번호 이상**에만 적용한다 — 과거는 soft 로
# 남아 보이고, 새 결정만 차단된다. 0 = 전부에 적용(기존 동작).
# ⚠️ **이 값을 올려서 긴 새 결정을 통과시키지 말 것** — 그러면 다시 장식이 된다.
DECBODY_FROM=0
DEC_OVERHEAD=4                       # 헤딩 + 빈 줄 + 구분선 — 총합 상한을 결정 수에서 유도한다
REFDOC_NOTE=700                      # 참조 문서 분할 권고선 (캡 아님)
# 세션 브리핑(scripts/session-brief.sh) 출력 = 매 세션 실제로 읽는 양. 캡들이 전부 초록인 채로
# 이 값이 커질 수 있으므로 따로 잰다. 커지면 브리핑에 들어가는 *조각*을 줄인다.
BRIEF_SOFT=14000; BRIEF_HARD=20000
# 그 "조각" 들도 문자로 잰다. 위의 조각 캡들은 전부 **줄 수**인데 브리핑은 **문자**로
# 재므로, 줄은 그대로인 채 한 줄이 두 배가 되면 아무도 빨개지지 않는다 — §2.2 가 CLAUDE.md 에서
# 막은 실패가 브리핑 조각에서 반복됐다(어느 저장소: current-task 37줄 = 3,831자 · 줄당 103자).
# 세 값의 합 + 결정 인덱스 + git 이 BRIEF_SOFT 가 되게 잡는다 — 인덱스는 잔차이고 계속 커진다.
CURTASK_CHARS_SOFT=3200;  CURTASK_CHARS_HARD=4200   # 매 세션 전문을 읽는다
SESS3_CHARS_SOFT=3000;    SESS3_CHARS_HARD=4200     # 브리핑이 펼치는 최근 3개 항목의 합
TODOSTAR_CHARS_SOFT=2400; TODOSTAR_CHARS_HARD=3200  # ★ 절만 (나머지 Phase 는 안 읽는다)
DECIDX_LEN_SOFT=100;      DECIDX_LEN_HARD=140       # 인덱스 한 행 — 결정당 브리핑 비용이다

# CLAUDE.md 심화 상한. **아래 값은 CLAUDE.md 의 "상한 계약" 줄과 일치해야 한다** (§B-6).
# 상한을 늘려 우회하려면 문서와 이 파일을 둘 다 고쳐야 한다 — 그래서 조용히 미끄러지지 않는다.
HUB_CHARS=4000                       # 줄 수만 보면 한 줄이 예산을 다 먹는 걸 놓친다
HUB_LINELEN=240                      # 표 행 하나가 비대화의 실제 경로였다
HUB_SECTION=25                        # 섹션 하나가 문서를 삼키는 것을 막는다
SECTIONS_FILE=scripts/claude-md-sections.txt   # 허용 H2 목록 (없으면 해당 검사 생략)

# ── 문서 형식 — 기존 프로젝트는 형식이 다르다. 못 알아보면 0건으로 **통과처럼** 보인다 ──
ENTRY_HEAD='진입점|[Ee]ntry'        # current-task 에서 진입점 절을 찾는 헤딩 (ERE)
DEC_ID='D-[0-9]{3}'                 # 결정 ID (ERE). 예: ADR 이면 'ADR-[0-9]{3}'
DEC_HEAD='## '                      # 결정 본문 헤딩 머리. 예: '### '
BUDGET_MODE=block                   # block = hard 시 커밋 차단 · warn = 도입 모드(알리기만)
# 결정 배치 — single: docs/decisions.md 한 파일에 인덱스 + 본문
#             split : docs/decisions.md 는 머리말 + 인덱스만, 본문은 DEC_DIR/<ID>.md 하나씩
#             auto  : DEC_DIR 디렉터리가 있으면 split (기존 설치본은 설정 없이 그대로 single)
# 왜 split 인가: 한 파일이면 결정 하나를 고치려 해도 편집 도구가 파일 전체를 읽는다. 세션 시작
# 비용은 브리핑이 막지만 **작업 중 비용**은 결정 수에 비례해 커졌다. 이전: scripts/split-decisions.sh
DEC_LAYOUT=auto
DEC_DIR=docs/decisions

# 프로젝트별 값은 **이 파일이 아니라** scripts/docs-budget.conf 에 둔다(있으면 위 값을 덮는다).
# 그래야 스킬의 새 가드로 이 파일을 갈아 끼워도 캡·형식·모드가 살아남는다. 단 HUB_* 를 여기서
# 올려도 CLAUDE.md 의 계약 줄과 대조되므로(§B-8) 몰래 올리는 길은 여전히 없다.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.
# shellcheck disable=SC1091
[ -f "$ROOT/scripts/docs-budget.conf" ] && . "$ROOT/scripts/docs-budget.conf"
DEC_BODY_RE="^${DEC_HEAD}${DEC_ID}"
DEC_ROW_RE="^[|] *${DEC_ID}"

cd "$ROOT" || exit 0

if [ "$DEC_LAYOUT" = auto ]; then
  if [ -d "$DEC_DIR" ]; then DEC_LAYOUT=split; else DEC_LAYOUT=single; fi
fi
# 결정 본문 스트림 — split 이면 파일들을 single 과 **같은 모양**으로 이어 붙인다(첫 헤딩을
# DEC_HEAD 로 바꿔서). 그래야 아래 본문 검사가 한 벌로 두 배치를 다 잰다 — 두 벌을 두면 한쪽만 고친다.
# 인덱스(DEC_ROW_RE)는 배치와 무관하게 docs/decisions.md 에서 읽는다.
DEC_SRC=$(mktemp "${TMPDIR:-/tmp}/dec-src.XXXXXX") || DEC_SRC=/dev/null
trap 'rm -f "$DEC_SRC"' EXIT
_dec_files() {   # split 의 결정 파일 목록 (README 는 뺀다). 개행 구분.
  for f in "$DEC_DIR"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in [Rr][Ee][Aa][Dd][Mm][Ee].md|index.md) continue ;; esac
    printf '%s\n' "$f"
  done
}
if [ "$DEC_LAYOUT" = split ]; then
  _dec_files | while IFS= read -r f; do
    awk -v head="$DEC_HEAD" 'NR == 1 { sub(/^#+[ \t]*/, ""); print head $0; next } { print }' "$f"
    printf '\n'
  done > "$DEC_SRC"
elif [ -f docs/decisions.md ]; then
  cat docs/decisions.md > "$DEC_SRC"
fi
DEC_WHERE="decisions.md"; [ "$DEC_LAYOUT" = split ] && DEC_WHERE="$DEC_DIR/"

if [ -t 1 ]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=; YEL=; GRN=; DIM=; BLD=; OFF=
fi

fail=0
warn=0
declare -a ACTIONS=()
HEADROOM=""   # "정렬키|상태|표시명|값 / 문턱|여유" 줄들. bash 3.2 라 배열 대신 문자열.
HR_PARENT=""  # 하위 항목("  └ …")에 붙일 직전 최상위 항목 이름
HR_NOTE=""; HR_ROOM=0; HR_STAGE=0   # _hr_record 의 출력 (bash 는 값을 하나만 돌려준다)

# 여유는 **다음 문턱**까지 잰다 — 통과면 권고선까지, 권고를 넘겼으면 한계까지, 한계를 넘겼으면
# 초과분. hard 하나로만 재면 두 가지를 잃는다: ① 통과 행에서 "몇 줄 뒤에 노랑인지"가 안 보이고
# ② soft/hard 비율이 행마다 33~75% 로 달라 순위가 섞인다(실제로 soft 를 넘긴 행이 통과 행
# 아래로 깔렸다). 그래서 정렬은 **상태 먼저**(HARD > soft > ok), 같은 상태 안에서 문턱에 가까운 순.
# 표시는 권고·한계를 **둘 다** 찍는다 — 하나만 찍으면 그 행의 다른 문턱이 화면에서 사라진다.
_hr_record() {   # <표시명> <값> <soft> <hard> <단위>
  local label=$1 n=$2 soft=$3 hard=$4 unit=$5 pct target tag key name
  [ "$soft" -gt 0 ] || soft=$hard
  if [ "$n" -gt "$hard" ]; then
    HR_STAGE=2; HR_ROOM=$(( n - hard )); target=$hard; tag=HARD
    pct=$(( n * 100 / hard ));  HR_NOTE="초과 ${HR_ROOM}${unit} · ${pct}%"
  elif [ "$n" -gt "$soft" ]; then
    HR_STAGE=1; HR_ROOM=$(( hard - n )); target=$hard; tag=soft
    pct=$(( n * 100 / hard ));  HR_NOTE="여유 ${HR_ROOM}${unit} → 한계 · ${pct}%"
  else
    HR_STAGE=0; HR_ROOM=$(( soft - n )); target=$soft; tag=ok
    pct=$(( n * 100 / soft ))
    if [ "$soft" -eq "$hard" ]; then HR_NOTE="여유 ${HR_ROOM}${unit} → 한계 · ${pct}%"
    else                             HR_NOTE="여유 ${HR_ROOM}${unit} → 권고 · ${pct}%"; fi
  fi
  [ "$pct" -gt 9999 ] && pct=9999
  key=$(( HR_STAGE * 10000 + pct ))
  name="$label"
  case "$label" in
    " "*) name="${HR_PARENT} ${label#"${label%%[! ]*}"}" ;;
    *)    HR_PARENT="$label" ;;
  esac
  HEADROOM="${HEADROOM}${key}|${tag}|${name}|${n}${unit} / ${target}|${HR_NOTE}
"
}


# 문자 수는 로케일에서 뗀다. `wc -m` 은 로케일이 비어 있으면(pre-commit 훅에서 흔하다)
# 문자가 아니라 **바이트**를 센다 — 한글이 1.6배로 부풀어 CLAUDE.md 2,127자가 3,576 으로,
# 브리핑 11,819자가 20,562 로 읽혔고 **없는 HARD 로 커밋을 막고 있었다**.
#
# UTF-8 은 이어지는 바이트가 전부 0x80~0xBF 이므로 그것만 지우면 문자당 정확히 1바이트가 남는다.
# 로케일도 python 도 필요 없다 — 처음엔 python 으로 셌지만, 그러면 python 이 없는 환경에서
# 바이트 근사로 조용히 떨어져 **거기서 다시 거짓 HARD 가 났다**(훅에서 실제로 재현했다).
# 근사로 떨어지는 폴백을 두느니 폴백이 없는 쪽이 낫다. CR 은 지워 CRLF 를 한 자로 센다.
_chars() {
  LC_ALL=C tr -d '\r\200-\277' | LC_ALL=C wc -c | tr -d ' '
}

# 브리핑의 한 절만 떼어 문자로 센다. **브리핑 출력 자체를 자른다** — 여기서 파일을 다시
# 슬라이스하면 브리핑과 가드가 서로 다른 범위를 재게 되고, 한쪽만 고치면 조용히 어긋난다.
# 인자: <브리핑 출력> <절 머리글에 들어 있는 문자열>
_brief_piece() {
  printf '%s\n' "$1" | awk -v want="$2" '/^━━/ { on = (index($0, want) > 0) } on' | _chars
}


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
    /^#+ /   { inside = ($0 ~ want); next }
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
  # hard=0 은 "이 프로젝트엔 해당 없는 개념" — conf 에서 끈다. **건너뛴다고 출력한다**:
  # 말없이 통과하는 검사는 커버리지처럼 보여서 없는 것보다 나쁘다(이식성 절).
  if [ "$hard" -le 0 ]; then
    printf '%s  --  %s %-34s %s(conf 에서 끔 — 값 %d%s)%s\n' \
      "$DIM" "$OFF" "$label" "$DIM" "$n" "$unit" "$OFF"
    return
  fi
  _hr_record "$label" "$n" "$soft" "$hard" "$unit"
  if [ "$HR_STAGE" = 2 ]; then
    printf '%s HARD %s %-34s %5d%s  권고 %d 한계 %d  %s%s%s\n' \
      "$RED" "$OFF" "$label" "$n" "$unit" "$soft" "$hard" "$DIM" "$HR_NOTE" "$OFF"
    ACTIONS+=("${RED}[HARD]${OFF} $label → $action ${DIM}(${HR_ROOM}${unit} 줄이면 통과)${OFF}")
    fail=1
  elif [ "$HR_STAGE" = 1 ]; then
    printf '%s soft %s %-34s %5d%s  권고 %d 한계 %d  %s%s%s\n' \
      "$YEL" "$OFF" "$label" "$n" "$unit" "$soft" "$hard" "$DIM" "$HR_NOTE" "$OFF"
    ACTIONS+=("${YEL}[soft]${OFF} $label → $action ${DIM}(한계까지 ${HR_ROOM}${unit})${OFF}")
    warn=1
  else
    printf '%s  ok  %s %-34s %5d%s  권고 %d 한계 %d  %s%s%s\n' \
      "$GRN" "$OFF" "$label" "$n" "$unit" "$soft" "$hard" "$DIM" "$HR_NOTE" "$OFF"
  fi
}

# ok/bad — 참·거짓 검사용 (수치 캡이 아닌 구조 검사)
bad()  { printf '%s HARD %s %s\n' "$RED" "$OFF" "$1"; ACTIONS+=("${RED}[HARD]${OFF} $2"); fail=1; }
meh()  { printf '%s soft %s %s\n' "$YEL" "$OFF" "$1"; ACTIONS+=("${YEL}[soft]${OFF} $2"); warn=1; }
good() { printf '%s  ok  %s %s\n' "$GRN" "$OFF" "$1"; }

printf '%s컨텍스트 예산 점검%s  %s(정책: docs/context-budget.md)%s\n\n' "$BLD" "$OFF" "$DIM" "$OFF"
printf '%s§A 파일 크기·개수%s  %s(여유는 다음 문턱까지 — 통과면 권고선, 넘겼으면 한계)%s\n' \
  "$BLD" "$OFF" "$DIM" "$OFF"

# ── §A-1 CLAUDE.md 줄 수 ────────────────────────────────────────────────────
check "CLAUDE.md" "$(_lines CLAUDE.md)" "$CLAUDE_SOFT" "$CLAUDE_HARD" "줄" \
  "내용을 docs/ 로 밀어내고 한 줄 포인터로 교체. 허브는 커지지 않는다"

# ── §A-2 current-task.md — 매 세션 전문을 읽는다 ────────────────────────────
check "docs/current-task.md" "$(_lines docs/current-task.md)" "$CURTASK_SOFT" "$CURTASK_HARD" "줄" \
  "진입점 목록을 잘라낸다 (session-log 에 중복 존재하므로 삭제 가능)"
check "  └ 진입점 개수" \
  "$(_count_in_section docs/current-task.md "$ENTRY_HEAD" '^- ')" "$ENTRY_SOFT" "$ENTRY_HARD" "개" \
  "오래된 진입점 삭제 (아카이브 불필요 — session-log 에 있음)"
# 스캔 sanity — 진입점 절을 못 찾으면 위 검사는 0개로 **통과처럼** 보인다. 영어 헤딩
# (`## Entry points`)이던 기존 프로젝트에서 진입점 5개가 "0개 ok" 로 찍혔다.
if [ -f docs/current-task.md ] && ! grep -qE "^#+ .*(${ENTRY_HEAD})" docs/current-task.md; then
  meh "  └ 진입점 절을 못 찾았다 (ENTRY_HEAD='${ENTRY_HEAD}')" \
      "current-task.md 의 진입점 헤딩에 맞게 scripts/docs-budget.conf 의 ENTRY_HEAD 를 정한다"
fi

# ── §A-3 session-log.md — 최근 N개만 읽지만 회전 트리거 ─────────────────────
check "docs/session-log.md" "$(_lines docs/session-log.md)" "$SESSLOG_SOFT" "$SESSLOG_HARD" "줄" \
  "오래된 항목을 docs/archive/session-log-YYYY-MM.md 로 회전 — bash scripts/rotate-docs.sh"
check "  └ 항목 개수" "$(_count docs/session-log.md '^## ')" "$SESSENT_SOFT" "$SESSENT_HARD" "개" \
  "회전한다 — bash scripts/rotate-docs.sh (context-budget.md §4)"

# 항목당 본문 길이 — **이것이 실제 세션 시작 비용이다.** 위 두 검사(총 줄 수·항목 개수)는
# 회전 트리거일 뿐 브리핑 크기와 무관하다. 긴 항목 하나가 브리핑을 삼키는 것을 막는다.
if [ -f docs/session-log.md ]; then
  _sess_bodies() {
    awk '
      /^## / { if (t != "") emit(); t = $0; n = 0; last = 0; seen = 0; next }
      t != "" {
        # 빈 줄·구분선·인용(회전 절차가 요구하는 "> 이전 이력" 꼬리말)은 본문이 아니다.
        # 이걸 안 빼면 파일 꼬리말이 **마지막 항목의 본문으로 계산돼** 4줄이 덤으로 붙는다.
        if ($0 ~ /^[[:space:]]*$/ || $0 == "---" || $0 ~ /^> /) { n++; next }
        if (!seen) { n = 0; seen = 1 }
        n++; last = n
      }
      END { if (t != "") emit() }
      function emit() {
        if (last > LIM) { split(t, w, " "); printf "%s%s(%d) ", w[2], w[3], last }
      }
    ' LIM="$1" docs/session-log.md
  }
  # 최댓값도 잰다 — "전부 15줄 이내" 는 여유가 0 인 것과 15 인 것을 똑같이 보이게 한다.
  _sess_max() {
    awk '
      /^## / { if (t != "") { if (last > m) m = last } t = $0; n = 0; last = 0; seen = 0; next }
      t != "" {
        if ($0 ~ /^[[:space:]]*$/ || $0 == "---" || $0 ~ /^> /) { n++; next }
        if (!seen) { n = 0; seen = 1 }
        n++; last = n
      }
      END { if (last > m) m = last; print m+0 }
    ' docs/session-log.md
  }
  sess_max=$(_sess_max)
  _hr_record "  └ 항목당 본문" "$sess_max" "$SESSBODY_SOFT" "$SESSBODY_HARD" "줄"
  sess_hard=$(_sess_bodies "$SESSBODY_HARD")
  sess_soft=$(_sess_bodies "$SESSBODY_SOFT")
  if [ -n "$sess_hard" ]; then
    printf '%s HARD %s %-34s %s\n' "$RED" "$OFF" "  └ 항목당 본문" "최대 ${sess_max}줄 · ${SESSBODY_HARD}줄 초과: $sess_hard  ${DIM}${HR_NOTE}${OFF}"
    ACTIONS+=("${RED}[HARD]${OFF} session-log.md → $sess_hard 를 ${SESSBODY_SOFT}줄 이내로 압축 (상세는 decisions.md 로)")
    fail=1
  elif [ -n "$sess_soft" ]; then
    printf '%s soft %s %-34s %s\n' "$YEL" "$OFF" "  └ 항목당 본문" "최대 ${sess_max}줄 · ${SESSBODY_SOFT}줄 초과: $sess_soft  ${DIM}${HR_NOTE}${OFF}"
    ACTIONS+=("${YEL}[soft]${OFF} session-log.md → $sess_soft 를 ${SESSBODY_SOFT}줄 이내로 압축")
    warn=1
  else
    printf '%s  ok  %s %-34s %s\n' "$GRN" "$OFF" "  └ 항목당 본문" \
      "$(_count docs/session-log.md '^## ')개 · 최대 ${sess_max}줄  권고 ${SESSBODY_SOFT} 한계 ${SESSBODY_HARD}  ${DIM}${HR_NOTE}${OFF}"
  fi
fi

# ── §A-4 todo.md ───────────────────────────────────────────────────────────
check "docs/todo.md" "$(_lines docs/todo.md)" "$TODO_SOFT" "$TODO_HARD" "줄" \
  "완료된 Phase 를 docs/archive/todo-done.md 로 회전 — bash scripts/rotate-docs.sh (미완은 먼저 이월)"

# ★ 마커 — scripts/session-brief.sh 가 이걸로 "현재 Phase" 를 찾는다. 없으면 브리핑이
# Phase 목록만 뱉거나(정보 손실) 읽는 쪽이 파일 전체를 열게 된다. 읽기 프로토콜의 일부다.
if [ -f docs/todo.md ]; then
  star=$(_count docs/todo.md '^## .*★')
  if [ "$star" -eq 0 ]; then
    bad "  └ ★ 현재 Phase 마커 없음" \
        "docs/todo.md 의 진행 중인 Phase 헤딩에 ★ 를 붙인다 (session-brief.sh 가 읽는다)"
  elif [ "$star" -gt 2 ]; then
    meh "  └ ★ 마커 ${star}개 — 브리핑이 커진다" \
        "docs/todo.md 의 ★ 는 1~2개만 (끝난 Phase 에서 뗀다)"
  else
    good "  └ ★ 현재 Phase 마커 ${star}개 ${DIM}(session-brief.sh 가 이 절만 출력)${OFF}"
  fi
fi

# ── §A-5 decisions.md — 회전하지 않고 압축한다. 재는 것은 **결정당 본문** 이다 ────────
#     총합 상한은 결정 수에서 유도한다 — 결정이 늘었다는 이유로 빨개지면 가드는 무르게 된다.
if [ -s "$DEC_SRC" ]; then
  n_dec=$(_count "$DEC_SRC" "$DEC_BODY_RE")
  pre=$(awk -v re="$DEC_BODY_RE" '$0 ~ re {print NR-1; exit}' "$DEC_SRC")
  [ -n "$pre" ] || pre=0
  if [ "$n_dec" -gt 0 ]; then
    if [ "$DEC_LAYOUT" = split ]; then
      # 총합은 한 파일이 아니라 재지 않는다 — 한 번에 열리는 단위가 결정 하나다
      HR_PARENT="$DEC_DIR/"   # 아래 "  └ 결정당 본문" 이 앞 항목(todo 등)에 붙지 않게
      printf '%s  ok  %s %-34s %4d개 %s(split — 본문은 %s<ID>.md, 총합 캡 없음)%s\n' \
        "$GRN" "$OFF" "$DEC_DIR/" "$n_dec" "$DIM" "$DEC_DIR/" "$OFF"
    else
      check "docs/decisions.md" "$(_lines docs/decisions.md)" \
        "$(( pre + n_dec * (DECBODY_SOFT + DEC_OVERHEAD) ))" \
        "$(( pre + n_dec * (DECBODY_HARD + DEC_OVERHEAD) ))" "줄" \
        "결정당 본문을 ${DECBODY_SOFT}줄 이내로 압축한다 (§5 — 회전 금지)"
    fi
    dec_max=$(awk -v re="$DEC_BODY_RE" '
      $0 ~ re { if (id != "") { if (last > m) m = last } id = 1; n = 0; last = 0; seen = 0; next }
      id != "" {
        if ($0 ~ /^[[:space:]]*$/ || $0 == "---") { n++; next }
        if (!seen) { n = 0; seen = 1 }
        n++; last = n
      }
      END { if (last > m) m = last; print m+0 }
    ' "$DEC_SRC")
    # 결정별 본문 길이 — 앞뒤 빈 줄과 구분선을 뺀 실제 내용.
    # LIM 초과를 나열하고, FROM 이상(= hard 적용 대상)의 **최댓값**을 둘째 줄에 낸다.
    _dec_long() {   # <LIM> → "목록\n대상최댓값"
      awk -v re="$DEC_BODY_RE" -v idre="$DEC_ID" -v LIM="$1" -v FROM="${DECBODY_FROM:-0}" '
        $0 ~ re { if (id != "") emit(); match($0, idre); id = substr($0, RSTART, RLENGTH); n = 0; last = 0; seen = 0; next }
        id != "" {
          if ($0 ~ /^[[:space:]]*$/ || $0 == "---") { n++; next }
          if (!seen) { n = 0; seen = 1 }
          n++; last = n
        }
        END { if (id != "") emit(); printf "\n%d\n", gmax + 0 }
        function emit() {
          if (last > LIM) printf "%s(%d) ", id, last
          # hard 적용 대상의 최댓값 — ID 의 숫자만 떼어 FROM 과 견준다
          num = id; gsub(/[^0-9]/, "", num)
          if (FROM > 0 && num + 0 < FROM) return
          if (last > gmax) gmax = last
        }
      ' "$DEC_SRC"
    }
    _dl=$(_dec_long "$DECBODY_SOFT")
    long=$(printf '%s\n' "$_dl" | sed -n 1p)
    dec_gated=$(printf '%s\n' "$_dl" | sed -n 2p)
    [ -n "$dec_gated" ] || dec_gated=0
    # 헤드룸은 **집행 대상**을 잰다 — 과거 최댓값으로 재면 「98%」가 영원히 떠 있고
    # 그 숫자를 내리려고 캡을 올리게 된다 — 캡 올리기 금지의 반대 방향이다.
    if [ "${DECBODY_FROM:-0}" -gt 0 ]; then
      _hr_record "  └ 결정당 본문" "$dec_gated" "$DECBODY_SOFT" "$DECBODY_HARD" "줄"
      # 집행 대상이 아직 없으면(새 결정 0개) 비율은 0% 이고 그게 맞다 — 과거 숫자를 쓰면
      # 「98%」가 영원히 떠 있고 그 숫자를 내리려고 캡을 올리게 된다.
      HR_NOTE="$HR_NOTE · D-$(printf '%03d' "$DECBODY_FROM") 이상만 집행(과거 최대 ${dec_max}줄)"
    else
      _hr_record "  └ 결정당 본문" "$dec_max" "$DECBODY_SOFT" "$DECBODY_HARD" "줄"
    fi
    if [ -n "$long" ]; then
      # 판정은 최댓값 하나로 한다 — 같은 계산을 두 벌 두면 한쪽만 고치게 된다.
      # 단 hard 는 **DECBODY_FROM 이상**의 최댓값으로 본다(지난 결정은 고치지 않으므로 soft 로 남는다).
      if [ "$dec_gated" -gt "$DECBODY_HARD" ]; then
        printf '%s HARD %s %-34s %s\n' "$RED" "$OFF" "  └ 결정당 본문" "집행 대상 최대 ${dec_gated}줄 · ${DECBODY_HARD}줄 초과: $long  ${DIM}${HR_NOTE}${OFF}"
        ACTIONS+=("${RED}[HARD]${OFF} $DEC_WHERE → $long 를 ${DECBODY_SOFT}줄 이내로 압축 (§5)")
        fail=1
      else
        printf '%s soft %s %-34s %s\n' "$YEL" "$OFF" "  └ 결정당 본문" "최대 ${dec_max}줄 · ${DECBODY_SOFT}줄 초과: $long  ${DIM}${HR_NOTE}${OFF}"
        ACTIONS+=("${YEL}[soft]${OFF} $DEC_WHERE → $long 를 ${DECBODY_SOFT}줄 이내로 압축 (§5)")
        warn=1
      fi
    else
      printf '%s  ok  %s %-34s %s\n' "$GRN" "$OFF" "  └ 결정당 본문" \
        "${n_dec}개 · 최대 ${dec_max}줄  권고 ${DECBODY_SOFT} 한계 ${DECBODY_HARD}  ${DIM}${HR_NOTE}${OFF}"
    fi
  fi
fi

# ── §A-6 decisions.md 인덱스 표 — 세션 시작에 읽는 것이 이 표뿐이다 ──────────
if [ -f docs/decisions.md ]; then
  HR_PARENT="docs/decisions.md"   # 인덱스는 배치와 무관하게 이 파일에 있다
  # 스캔 sanity — 결정 형식을 못 알아보면 본문 0 · 인덱스 0 이 "일치" 로 **통과처럼** 보인다.
  # `### ADR-001` 형식이던 기존 프로젝트에서 실제로 아무것도 재지 않고 초록을 찍었다.
  # 인덱스·목차 같은 머리 헤딩을 빼고도 헤딩이 있는데 결정이 0건이면 형식이 다른 것이다.
  other_heads=$(grep -E '^#{2,3} ' docs/decisions.md | grep -vcE '^#{2,3} *(인덱스|[Ii]ndex|목차)') || other_heads=0
  if [ "$DEC_LAYOUT" = single ] && [ "$(_count docs/decisions.md "$DEC_BODY_RE")" -eq 0 ] && [ "$other_heads" -gt 0 ]; then
    bad "  └ 결정 형식을 인식하지 못했다 (헤딩 ${other_heads}개 · '${DEC_HEAD}${DEC_ID}' 0건)" \
        "scripts/docs-budget.conf 에 DEC_ID·DEC_HEAD 를 이 저장소 형식으로 정한다 (예: DEC_ID='ADR-[0-9]{3}' DEC_HEAD='### ')"
  fi
  idx=$(_count docs/decisions.md "$DEC_ROW_RE")
  bodies=$(_count "$DEC_SRC" "$DEC_BODY_RE")
  if [ "$DEC_LAYOUT" = split ]; then
    # split 고유의 구조 검사 — 개수만 맞으면 "D-041 이 두 개, D-042 가 없음" 을 놓친다
    nf=0; bad_head=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      nf=$((nf + 1))
      fid=$(basename "$f" .md)
      hid=$(head -1 "$f" | grep -oE "$DEC_ID" | head -1) || hid=""
      printf '%s\n' "$fid" | grep -qxE "$DEC_ID" || { bad_head="$bad_head $fid(파일명)"; continue; }
      [ "$fid" = "$hid" ] || bad_head="$bad_head $fid(헤딩:${hid:-없음})"
    done < <(_dec_files)
    if [ "$nf" -eq 0 ]; then
      bad "  └ $DEC_DIR/ 에 결정 파일이 0개 — 본문 검사가 무의미해졌다" \
          "본문을 $DEC_DIR/<ID>.md 로 두거나, single 이면 디렉터리를 지우고 DEC_LAYOUT=single"
    fi
    [ -n "$bad_head" ] && bad "  └ 결정 파일 이름·첫 헤딩 불일치:$bad_head" \
      "파일 이름은 <ID>.md, 첫 줄은 '# <ID>. 제목' 으로 맞춘다"
    left=$(_count docs/decisions.md "$DEC_BODY_RE")
    [ "$left" -gt 0 ] && bad "  └ decisions.md 에 본문 ${left}개가 남아 있다 (split 인데)" \
      "본문을 $DEC_DIR/<ID>.md 로 옮긴다 — 인덱스 파일이 다시 커진다 (scripts/split-decisions.sh)"
    ids_idx=$(grep -E "$DEC_ROW_RE" docs/decisions.md | grep -oE "$DEC_ID" | sort -u)
    ids_body=$(_dec_files | while IFS= read -r f; do basename "$f" .md; done | sort -u)
    no_body=$(comm -23 <(printf '%s\n' "$ids_idx") <(printf '%s\n' "$ids_body") | tr '\n' ' ')
    no_row=$(comm -13 <(printf '%s\n' "$ids_idx") <(printf '%s\n' "$ids_body") | tr '\n' ' ')
    [ -n "${no_body// /}" ] && meh "  └ 인덱스에만 있고 파일이 없는 결정: $no_body" \
      "$DEC_DIR/<ID>.md 를 만들거나 인덱스 행을 고친다"
    [ -n "${no_row// /}" ] && [ "$idx" -gt 0 ] && meh "  └ 파일만 있고 인덱스 행이 없는 결정: $no_row" \
      "decisions.md 인덱스 표 맨 위에 한 줄을 넣는다"
  fi
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

  # 인덱스 **행 길이** — 결정 하나가 브리핑에 더하는 비용이 이 값이다. 표는 O(결정 수)로
  # 커지는 유일한 절이므로(§1 의 표가 "O(결정 수) but 한 줄씩" 이라 허용한 자리), 행이 길어지면
  # 그 허용이 깨진다. 본문 길이는 재고 있었지만 **행 길이는 아무도 안 재고 있었다**.
  if [ "$idx" -gt 0 ]; then
    # `awk length()` 는 로케일을 탄다 — 빈 로케일에서 바이트를 센다(같은 표가 101자 vs 186자로
    # 갈렸고 **없는 HARD 로 커밋을 막았다**. §B-2 가 CLAUDE.md 에서 겪은 것과 같은 함정이다).
    # _chars 와 같은 방법으로 뗀다: 이어지는 바이트를 지우면 문자당 1바이트가 남는다.
    _idx_rows() { LC_ALL=C tr -d '\r\200-\277' < docs/decisions.md; }
    idx_max=$(_idx_rows | LC_ALL=C awk -v re="$DEC_ROW_RE" '$0 ~ re { c = length($0); if (c > m) m = c } END { print m+0 }')
    _hr_record "  └ 인덱스 행 길이" "$idx_max" "$DECIDX_LEN_SOFT" "$DECIDX_LEN_HARD" "자"
    _idx_long() {
      _idx_rows | LC_ALL=C awk -v lim="$1" -v re="$DEC_ROW_RE" '
        $0 ~ re { if (length($0) > lim) { split($0, f, "|"); gsub(/ /, "", f[2]); printf "%s(%d) ", f[2], length($0) } }'
    }
    idx_hard=$(_idx_long "$DECIDX_LEN_HARD")
    idx_soft=$(_idx_long "$DECIDX_LEN_SOFT")
    if [ -n "$idx_hard" ]; then
      printf '%s HARD %s %-34s %s\n' "$RED" "$OFF" "  └ 인덱스 행 길이" "최대 ${idx_max}자 · ${DECIDX_LEN_HARD}자 초과: $idx_hard  ${DIM}${HR_NOTE}${OFF}"
      ACTIONS+=("${RED}[HARD]${OFF} decisions.md → 인덱스 행 $idx_hard 을 ${DECIDX_LEN_SOFT}자 이내로 (상세는 본문에 있다)")
      fail=1
    elif [ -n "$idx_soft" ]; then
      printf '%s soft %s %-34s %s\n' "$YEL" "$OFF" "  └ 인덱스 행 길이" "최대 ${idx_max}자 · ${DECIDX_LEN_SOFT}자 초과: $idx_soft  ${DIM}${HR_NOTE}${OFF}"
      ACTIONS+=("${YEL}[soft]${OFF} decisions.md → 인덱스 행 $idx_soft 을 ${DECIDX_LEN_SOFT}자 이내로 (상세는 본문에 있다)")
      warn=1
    else
      printf '%s  ok  %s %-34s %s\n' "$GRN" "$OFF" "  └ 인덱스 행 길이" \
        "최대 ${idx_max}자  권고 ${DECIDX_LEN_SOFT} 한계 ${DECIDX_LEN_HARD}  ${DIM}${HR_NOTE}${OFF}"
    fi
  fi
fi

# ── §A-6b 세션 브리핑 출력 크기 — **이것이 실제 세션 시작 비용이다** ─────────
#     위 캡들은 전부 파일 크기를 잰다. 정작 매 세션 읽는 양은 아무도 안 재고 있었고,
#     그래서 모든 캡이 초록인 채로 읽기 비용이 4.2배가 돼 있던 저장소가 있었다.
#     숫자를 문서에 적지 않고 여기서 잰다 — 적어 두면 문서가 자기 상태를 두고 거짓말한다.
#     조각도 같은 눈금(문자)으로 올린다 — "조각을 줄여라"만 적어 두면 **어느 조각인지**를
#     매번 손으로 다시 재게 된다. 실제로 그랬다.
# 실행 비트가 아니라 **파일 존재**로 문을 연다. `-x` 로 두면 실행 권한만 빠진 설치에서
# 이 절이 통째로 조용히 건너뛰어진다 — 브리핑 캡이 없는데 가드는 초록을 찍는, 이 파일이
# 가장 경계하는 "통과처럼 보이는 실패"다. 어차피 `bash <파일>` 로 부르므로 비트는 필요 없다.
if [ -f scripts/session-brief.sh ]; then
  brief_out=$(bash scripts/session-brief.sh 2>/dev/null)
  brief_chars=$(printf '%s\n' "$brief_out" | _chars)
  check "세션 브리핑 출력" "${brief_chars:-0}" "$BRIEF_SOFT" "$BRIEF_HARD" "자" \
    "아래 조각 중 빨간/노란 것을 줄인다 (인덱스가 잔차다 — 결정이 늘면 나머지를 줄인다)"

  p_cur=$(_brief_piece "$brief_out" 'current-task')
  p_ses=$(_brief_piece "$brief_out" 'session-log')
  p_dec=$(_brief_piece "$brief_out" 'decisions.md')
  p_tod=$(_brief_piece "$brief_out" 'todo.md')
  p_git=$(_brief_piece "$brief_out" 'git 최근')
  check "  └ current-task 전문" "${p_cur:-0}" "$CURTASK_CHARS_SOFT" "$CURTASK_CHARS_HARD" "자" \
    "긴 줄을 쪼개지 말고 **덜어낸다** — D-번호로 대체 가능한 근거·수치는 decisions/todo 에 있다"
  check "  └ 로그 최근 3개" "${p_ses:-0}" "$SESS3_CHARS_SOFT" "$SESS3_CHARS_HARD" "자" \
    "새 항목을 짧게 쓴다 (지난 항목은 고치지 않는다 — 그때 한 말이 바뀐다). 상세는 decisions.md"
  check "  └ todo ★ 절" "${p_tod:-0}" "$TODOSTAR_CHARS_SOFT" "$TODOSTAR_CHARS_HARD" "자" \
    "끝난 항목을 archive/todo-done.md 로 회전 · 측정 상세는 decisions.md 로"
  # 인덱스와 git 은 여기서 캡을 걸지 않는다 — 인덱스는 행 길이로(§A-6), git 은 상수(10커밋)로 이미 잡힌다.
  printf '%s  --  %s %-34s %s인덱스 %s자 · git %s자 — 둘은 창(DEC_ROWS·GIT_LOG)으로 고정 · 행 길이는 §A-6%s\n' \
    "$DIM" "$OFF" "  └ 나머지 조각" "$DIM" "${p_dec:-0}" "${p_git:-0}" "$OFF"
else
  printf '%s HARD %s %s\n' "$RED" "$OFF" " 세션 브리핑 출력          scripts/session-brief.sh 가 없다"
  ACTIONS+=("${RED}[HARD]${OFF} scripts/session-brief.sh 를 설치한다 — 세션 시작 비용을 재는 유일한 검사다")
  fail=1
fi

# ── §A-7 참조 문서 — 캡 없음. 세션 시작에 읽지 않기 때문이다 ─────────────────
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

# ══ §B CLAUDE.md 심화 — 자동 로드되므로 읽기 프로토콜로 방어할 수 없다 ══════
if [ -f CLAUDE.md ]; then
  printf '\n%s§B CLAUDE.md 구조 (자동 로드 — 별도 방어)%s\n' "$BLD" "$OFF"
  HR_PARENT="CLAUDE.md"   # 아래 하위 항목들의 부모 (헤드룸 요약 표시용)

  # B-1 문자 수. 줄 수만 보면 긴 표 행 하나가 예산을 삼키는 걸 놓친다.
  hub_chars=$(_chars < CLAUDE.md)
  check "  문자 수" "$hub_chars" "$((HUB_CHARS * 8 / 10))" "$HUB_CHARS" "자" \
    "내용을 docs/ 로 옮긴다 (상한을 늘리지 말 것)"

  # B-2 한 줄 길이
  # `awk length()` 도 로케일을 탄다 — 빈 로케일에서는 바이트다(같은 파일이 133자 vs 79자로
  # 갈렸다. 훅과 사람 셸의 로케일이 달라 **같은 커밋이 환경에 따라 다른 판정**을 받는다).
  # _chars 와 같은 방법으로 뗀다: 이어지는 바이트를 지우면 문자당 1바이트가 남는다.
  read -r longest_len longest_no <<<"$(LC_ALL=C tr -d '\r\200-\277' < CLAUDE.md |
    LC_ALL=C awk '{ if (length($0)>m) {m=length($0); n=NR} } END{print m+0, n+0}')"
  # 문턱이 하나뿐인 검사(soft 없음)도 같은 눈금에 올린다 — 안 올리면 순위에서 통째로 빠진다.
  _hr_record "  최장 행" "$longest_len" "$HUB_LINELEN" "$HUB_LINELEN" "자"
  if [ "$longest_len" -gt "$HUB_LINELEN" ]; then
    bad "  최장 행 ${longest_no}행이 ${longest_len}자 > 상한 ${HUB_LINELEN}자" \
        "CLAUDE.md ${longest_no}행을 쪼개거나 내용을 docs/ 로 옮긴다"
  else
    good "  최장 행 ${longest_len}자 ${DIM}(≤${HUB_LINELEN}, ${longest_no}행) ${HR_NOTE}${OFF}"
  fi

  # B-3 섹션(H2) 본문 줄 수 — 섹션 하나가 문서를 삼키는 것을 막는다
  read -r sec_max sec_name <<<"$(awk '
    /^## / { if (t!="") { if (c>m) {m=c; nm=t} } t=$0; c=0; next }
    t!=""  { c++ }
    END    { if (t!="") { if (c>m) {m=c; nm=t} } print m+0, nm }' CLAUDE.md)"
  _hr_record "  최대 섹션 본문" "$sec_max" "$HUB_SECTION" "$HUB_SECTION" "줄"
  if [ "$sec_max" -gt "$HUB_SECTION" ]; then
    bad "  최대 섹션 본문 ${sec_max}줄 > 상한 ${HUB_SECTION}줄 (${sec_name})" \
        "해당 섹션을 docs/ 로 옮기고 한 줄 포인터만 남긴다"
  else
    good "  최대 섹션 본문 ${sec_max}줄 ${DIM}(≤${HUB_SECTION}) ${HR_NOTE}${OFF}"
  fi

  # B-4 허용 H2 목록 — 섹션 스프롤이 비대화의 1차 경로다.
  #     목록을 별도 파일에 두므로 섹션 추가는 문서 + 이 파일 **둘 다** 고쳐야 한다.
  if [ -f "$SECTIONS_FILE" ]; then
    # 항목은 '## ' 로 시작하는 줄. 주석은 '# ' 한 칸 — 항목이 '##' 이므로 겹치지 않는다.
    # (겹치는 필터를 쓰면 목록이 빈 채로 "전부 허용되지 않음"이 되어 오탐한다. 실제로 겪었다.)
    allow_n=$(grep -cE '^## ' "$SECTIONS_FILE" 2>/dev/null) || allow_n=0
    if [ "$allow_n" -eq 0 ]; then
      # 스캔 sanity — 목록이 0건이면 이 검사는 통과처럼 보이는 실패가 된다
      bad "  허용 섹션 목록 파싱 0건 ($SECTIONS_FILE)" \
          "항목은 '## ' 로 시작해야 한다. 주석은 '# ' 로 쓴다"
    else
      unknown=$(comm -23 <(grep -E '^## ' CLAUDE.md | sort -u) <(grep -E '^## ' "$SECTIONS_FILE" | sort -u))
      missing=$(comm -13 <(grep -E '^## ' CLAUDE.md | sort -u) <(grep -E '^## ' "$SECTIONS_FILE" | sort -u))
      if [ -n "$unknown" ]; then
        bad "  허용되지 않은 섹션: $(echo "$unknown" | tr '\n' '|')" \
            "docs/ 에 쓰거나 $SECTIONS_FILE 에 등록한다 (무단 추가 = 실패)"
      elif [ -n "$missing" ]; then
        meh "  사라진 섹션: $(echo "$missing" | tr '\n' '|')" \
            "개명했다면 $SECTIONS_FILE 도 같이 고친다"
      else
        good "  허용 섹션 목록 일치 ${DIM}(${allow_n}개)${OFF}"
      fi
    fi
  else
    printf '%s  --  %s 허용 섹션 검사 생략 %s(%s 없음)%s\n' "$DIM" "$OFF" "$DIM" "$SECTIONS_FILE" "$OFF"
  fi

  # B-5 백틱 경로가 실제로 존재하는가 — 파일을 옮기고 문서를 안 고치면 허브가 조용히 거짓말한다
  #     `bash scripts/x.sh` 처럼 명령이 섞인 경우가 있어 공백으로 쪼갠 뒤 '/' 포함 토큰만 본다.
  #     `/clear` 같은 슬래시 명령(맨 앞 '/' 하나 + 이름)은 경로가 아니다 — 템플릿이 쓰자 막혔다.
  #     프로젝트가 쓰는 표기는 conf 로 맞춘다(스크립트를 고치면 다음 갱신에 되돌아간다):
  #       PATH_IGNORE — 경로가 아닌 것(URL 주소·모듈 지정자·외부 저장소 폴더)을 거르는 ERE
  #       PATH_ROOTS  — 축약 표기를 해석할 접두 목록(예: `foo/bar.ts` → src/lib/foo/bar.ts)
  path_refs=$(
    grep -oE '`[^`]+`' CLAUDE.md | tr -d '`' | tr ' ' '\n' |
      sed 's/[),.:;]*$//' | grep '/' |
      grep -vE '^~|://|\*|<|>|YYYY|NNN|\{|^/[A-Za-z][A-Za-z0-9:_-]*$' | sort -u
  )
  [ -n "${PATH_IGNORE:-}" ] && path_refs=$(printf '%s\n' "$path_refs" | grep -vE "$PATH_IGNORE")
  path_n=0; missing_paths=
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    path_n=$((path_n + 1))
    [ -e "$ref" ] && continue
    #     접두를 붙여서도 찾아본다 — 허브가 `src/lib/` 를 생략해 적는 저장소가 있다.
    hit=0
    for root in ${PATH_ROOTS:-}; do
      [ -e "$root$ref" ] && { hit=1; break; }
    done
    ((hit)) || missing_paths="$missing_paths $ref"
  done < <(printf '%s\n' "$path_refs")
  if [ -n "$missing_paths" ]; then
    bad "  존재하지 않는 경로:$missing_paths" \
        "옮겼거나 지웠다면 CLAUDE.md 도 고친다 (또는 해당 디렉터리를 만든다)"
  else
    good "  백틱 경로 ${path_n}건 전부 존재"
  fi

  # B-6 D-번호가 decisions.md 에 정의돼 있는가
  if [ -s "$DEC_SRC" ]; then
    d_refs=$(grep -oE "$DEC_ID" CLAUDE.md | sort -u)
    d_def=$(sed -nE "s/^#{2,3} *(${DEC_ID}).*/\\1/p" "$DEC_SRC" | sort -u)
    ref_n=0; undefined=
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      ref_n=$((ref_n + 1))
      printf '%s\n' "$d_def" | grep -qx "$d" || undefined="$undefined $d"
    done < <(printf '%s\n' "$d_refs")
    def_n=0
    while IFS= read -r d; do
      [ -n "$d" ] && def_n=$((def_n + 1))
    done < <(printf '%s\n' "$d_def")
    if [ -n "$undefined" ]; then
      bad "  $DEC_WHERE 에 없는 결정 참조:$undefined" \
          "해당 D-번호를 $DEC_WHERE 에 정의하거나 CLAUDE.md 의 참조를 고친다"
    else
      good "  D-번호 참조 ${ref_n}건 전부 해결"
    fi
    # B-7 스캔 sanity — 조용히 0건이면 위 검사가 전부 무의미해진다 (통과처럼 보이는 실패)
    if [ "$ref_n" -gt 0 ] && [ "$def_n" -eq 0 ]; then
      bad "  $DEC_WHERE 정의 스캔이 0건 — D-번호 검사가 무의미해졌다" \
          "$DEC_WHERE 의 결정 제목 형식(DEC_HEAD·DEC_ID)을 확인한다"
    fi
  fi
  if [ "$path_n" -eq 0 ]; then
    meh "  경로 스캔 결과 0건 — 백틱 표기가 바뀌었는지 확인" \
        "CLAUDE.md 가 위치 인덱스로 기능하는지 확인 (규칙 허브는 어딘가를 가리켜야 한다)"
  fi

  # B-8 상한 계약 줄 ↔ 이 스크립트 상수 일치 (상한의 단일 진실 원천)
  #     문서가 자기 상한을 선언하고 가드가 그걸 대조한다. 상한을 늘리려면 둘 다 고쳐야 하므로
  #     "일단 늘리고 보자"가 안 된다.
  d_chars=$(sed -nE 's/.*전체 `([0-9]+)자`.*/\1/p' CLAUDE.md | head -1)
  d_lines=$(sed -nE 's/.*전체 `([0-9]+)줄`.*/\1/p' CLAUDE.md | head -1)
  d_llen=$(sed -nE 's/.*한 줄 `([0-9]+)자`.*/\1/p' CLAUDE.md | head -1)
  d_sect=$(sed -nE 's/.*섹션 `([0-9]+)줄`.*/\1/p' CLAUDE.md | head -1)
  contract_bad=""
  for pair in "chars:$d_chars:$HUB_CHARS" "lines:$d_lines:$CLAUDE_HARD" \
              "lineLen:$d_llen:$HUB_LINELEN" "section:$d_sect:$HUB_SECTION"; do
    k=${pair%%:*}; rest=${pair#*:}; got=${rest%%:*}; exp=${rest##*:}
    if [ -z "$got" ]; then contract_bad="$contract_bad $k(선언없음)"
    elif [ "$got" != "$exp" ]; then contract_bad="$contract_bad $k(문서$got≠가드$exp)"
    fi
  done
  if [ -n "$contract_bad" ]; then
    bad "  상한 계약 불일치:$contract_bad" \
        "CLAUDE.md 의 계약 줄과 이 스크립트의 HUB_* 상수를 같이 고친다 (둘 다여야 한다)"
  else
    good "  상한 계약 줄 ↔ 가드 상수 일치"
  fi
fi

# ── 헤드룸 요약 — 급한 순서 ────────────────────────────────────────────────
#     상태 먼저(HARD > soft > ok), 같은 상태 안에서는 다음 문턱에 가까운 순.
#     문턱이 하나뿐인 구조 검사도 여기 들어온다 — 빠지면 여유 0 인 항목이 화면에서 사라진다.
if [ -n "$HEADROOM" ]; then
  printf '\n%s헤드룸%s %s(급한 순서 — 상태 먼저, 같은 상태면 다음 문턱에 가까운 순)%s\n' \
    "$BLD" "$OFF" "$DIM" "$OFF"
  printf '%s' "$HEADROOM" | grep -v '^[[:space:]]*$' | sort -t'|' -k1,1rn | head -5 |
    while IFS='|' read -r key tag label vals note; do
      case "$tag" in
        HARD) c=$RED ;;
        soft) c=$YEL ;;
        *)    c=$GRN ;;
      esac
      # 폭 맞춤은 쓰지 않는다 — printf 는 바이트로 세고 한글은 3바이트라 어차피 어긋난다.
      printf '  %s%4s%s  %s %s—%s %s · %s%s\n' \
        "$c" "$tag" "$OFF" "$label" "$DIM" "$OFF" "$vals" "$note" "$OFF"
    done
fi


# ── 결과 ───────────────────────────────────────────────────────────────────
if [ ${#ACTIONS[@]} -gt 0 ]; then
  printf '\n%s할 일%s\n' "$BLD" "$OFF"
  for a in "${ACTIONS[@]}"; do printf '  · %s\n' "$a"; done
  printf '  %s회전 절차: docs/context-budget.md §4%s\n' "$DIM" "$OFF"
fi

printf '\n%s구조만 검사했다 — 문장 표현·규칙 순서·내용의 정확성은 사람이 본다.%s\n' "$DIM" "$OFF"
# 도입 모드 — 기존 프로젝트는 설치 순간 HARD 가 나는 게 정상이다(CLAUDE.md 가 허브가 아니다).
# 그때부터 모든 커밋을 막으면 가드를 떼어 버리게 된다. warn 이면 같은 판정을 찍되 막지 않는다.
# **판정은 그대로다** — 무르게 하는 게 아니라 차단만 미룬다. 이전이 끝나면 block 으로 올린다.
if [ "$fail" = 1 ] && [ "$BUDGET_MODE" = warn ]; then
  printf '%s✗ hard 한계 초과 — 도입 모드(BUDGET_MODE=warn)라 커밋은 막지 않는다.%s\n' "$YEL" "$OFF"
  printf '  %s이전을 마치면 scripts/docs-budget.conf 에서 BUDGET_MODE=block 으로 올린다.%s\n' "$DIM" "$OFF"
  exit 0
fi
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
