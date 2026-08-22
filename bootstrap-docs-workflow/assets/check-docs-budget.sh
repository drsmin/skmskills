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

# CLAUDE.md 심화 상한. **아래 값은 CLAUDE.md 의 "상한 계약" 줄과 일치해야 한다** (§B-6).
# 상한을 늘려 우회하려면 문서와 이 파일을 둘 다 고쳐야 한다 — 그래서 조용히 미끄러지지 않는다.
HUB_CHARS=4000                       # 줄 수만 보면 한 줄이 예산을 다 먹는 걸 놓친다
HUB_LINELEN=240                      # 표 행 하나가 비대화의 실제 경로였다
HUB_SECTION=25                        # 섹션 하나가 문서를 삼키는 것을 막는다
SECTIONS_FILE=scripts/claude-md-sections.txt   # 허용 H2 목록 (없으면 해당 검사 생략)

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

# ok/bad — 참·거짓 검사용 (수치 캡이 아닌 구조 검사)
bad()  { printf '%s HARD %s %s\n' "$RED" "$OFF" "$1"; ACTIONS+=("${RED}[HARD]${OFF} $2"); fail=1; }
meh()  { printf '%s soft %s %s\n' "$YEL" "$OFF" "$1"; ACTIONS+=("${YEL}[soft]${OFF} $2"); warn=1; }
good() { printf '%s  ok  %s %s\n' "$GRN" "$OFF" "$1"; }

printf '%s컨텍스트 예산 점검%s  %s(정책: docs/context-budget.md)%s\n\n' "$BLD" "$OFF" "$DIM" "$OFF"
printf '%s§A 파일 크기·개수%s\n' "$BLD" "$OFF"

# ── §A-1 CLAUDE.md 줄 수 ────────────────────────────────────────────────────
check "CLAUDE.md" "$(_lines CLAUDE.md)" "$CLAUDE_SOFT" "$CLAUDE_HARD" "줄" \
  "내용을 docs/ 로 밀어내고 한 줄 포인터로 교체. 허브는 커지지 않는다"

# ── §A-2 current-task.md — 매 세션 전문을 읽는다 ────────────────────────────
check "docs/current-task.md" "$(_lines docs/current-task.md)" "$CURTASK_SOFT" "$CURTASK_HARD" "줄" \
  "진입점 목록을 잘라낸다 (session-log 에 중복 존재하므로 삭제 가능)"
check "  └ 진입점 개수" \
  "$(_count_in_section docs/current-task.md '진입점' '^- ')" "$ENTRY_SOFT" "$ENTRY_HARD" "개" \
  "오래된 진입점 삭제 (아카이브 불필요 — session-log 에 있음)"

# ── §A-3 session-log.md — 최근 N개만 읽지만 회전 트리거 ─────────────────────
check "docs/session-log.md" "$(_lines docs/session-log.md)" "$SESSLOG_SOFT" "$SESSLOG_HARD" "줄" \
  "오래된 항목을 docs/archive/session-log-YYYY-MM.md 로 회전"
check "  └ 항목 개수" "$(_count docs/session-log.md '^## ')" "$SESSENT_SOFT" "$SESSENT_HARD" "개" \
  "최근 ${SESSENT_SOFT}개만 남기고 회전 (context-budget.md §4)"

# ── §A-4 todo.md ───────────────────────────────────────────────────────────
check "docs/todo.md" "$(_lines docs/todo.md)" "$TODO_SOFT" "$TODO_HARD" "줄" \
  "완료된 Phase 를 docs/archive/todo-done.md 로 회전"

# ── §A-5 decisions.md — 회전하지 않고 압축한다 ──────────────────────────────
check "docs/decisions.md" "$(_lines docs/decisions.md)" "$DEC_SOFT" "$DEC_HARD" "줄" \
  "각 결정 본문을 20줄 이내로 압축. 상세는 참조 문서로 (§5 — 회전 금지)"

# ── §A-6 decisions.md 인덱스 표 — 세션 시작에 읽는 것이 이 표뿐이다 ──────────
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

  # B-1 문자 수. 줄 수만 보면 긴 표 행 하나가 예산을 삼키는 걸 놓친다.
  hub_chars=$(wc -m < CLAUDE.md | tr -d ' ')
  check "  문자 수" "$hub_chars" "$((HUB_CHARS * 8 / 10))" "$HUB_CHARS" "자" \
    "내용을 docs/ 로 옮긴다 (상한을 늘리지 말 것)"

  # B-2 한 줄 길이
  read -r longest_len longest_no <<<"$(awk '{ if (length($0)>m) {m=length($0); n=NR} } END{print m+0, n+0}' CLAUDE.md)"
  if [ "$longest_len" -gt "$HUB_LINELEN" ]; then
    bad "  최장 행 ${longest_no}행이 ${longest_len}자 > 상한 ${HUB_LINELEN}자" \
        "CLAUDE.md ${longest_no}행을 쪼개거나 내용을 docs/ 로 옮긴다"
  else
    good "  최장 행 ${longest_len}자 ${DIM}(≤${HUB_LINELEN}, ${longest_no}행)${OFF}"
  fi

  # B-3 섹션(H2) 본문 줄 수 — 섹션 하나가 문서를 삼키는 것을 막는다
  read -r sec_max sec_name <<<"$(awk '
    /^## / { if (t!="") { if (c>m) {m=c; nm=t} } t=$0; c=0; next }
    t!=""  { c++ }
    END    { if (t!="") { if (c>m) {m=c; nm=t} } print m+0, nm }' CLAUDE.md)"
  if [ "$sec_max" -gt "$HUB_SECTION" ]; then
    bad "  최대 섹션 본문 ${sec_max}줄 > 상한 ${HUB_SECTION}줄 (${sec_name})" \
        "해당 섹션을 docs/ 로 옮기고 한 줄 포인터만 남긴다"
  else
    good "  최대 섹션 본문 ${sec_max}줄 ${DIM}(≤${HUB_SECTION})${OFF}"
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
  mapfile -t path_refs < <(
    grep -oE '`[^`]+`' CLAUDE.md | tr -d '`' | tr ' ' '\n' |
      sed 's/[),.:;]*$//' | grep '/' |
      grep -vE '^~|://|\*|<|>|YYYY|NNN|\{' | sort -u
  )
  missing_paths=()
  for p in "${path_refs[@]:-}"; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || missing_paths+=("$p")
  done
  if [ "${#missing_paths[@]}" -gt 0 ]; then
    bad "  존재하지 않는 경로: ${missing_paths[*]}" \
        "옮겼거나 지웠다면 CLAUDE.md 도 고친다 (또는 해당 디렉터리를 만든다)"
  else
    good "  백틱 경로 ${#path_refs[@]}건 전부 존재"
  fi

  # B-6 D-번호가 decisions.md 에 정의돼 있는가
  if [ -f docs/decisions.md ]; then
    mapfile -t d_refs < <(grep -oE 'D-[0-9]{3}' CLAUDE.md | sort -u)
    mapfile -t d_def  < <(sed -nE 's/^#{2,3} *(D-[0-9]{3}).*/\1/p' docs/decisions.md | sort -u)
    undefined=()
    for d in "${d_refs[@]:-}"; do
      [ -n "$d" ] || continue
      printf '%s\n' "${d_def[@]:-}" | grep -qx "$d" || undefined+=("$d")
    done
    if [ "${#undefined[@]}" -gt 0 ]; then
      bad "  decisions.md 에 없는 결정 참조: ${undefined[*]}" \
          "해당 D-번호를 decisions.md 에 정의하거나 CLAUDE.md 의 참조를 고친다"
    else
      good "  D-번호 참조 ${#d_refs[@]}건 전부 해결"
    fi
    # B-7 스캔 sanity — 조용히 0건이면 위 검사가 전부 무의미해진다 (통과처럼 보이는 실패)
    if [ "${#d_refs[@]}" -gt 0 ] && [ "${#d_def[@]}" -eq 0 ]; then
      bad "  decisions.md 정의 스캔이 0건 — D-번호 검사가 무의미해졌다" \
          "decisions.md 의 '## D-NNN' 제목 형식을 확인한다"
    fi
  fi
  if [ "${#path_refs[@]}" -eq 0 ]; then
    meh "  경로 스캔 결과 0건 — 백틱 표기가 바뀌었는지 확인" \
        "CLAUDE.md 가 위치 인덱스로 기능하는지 확인 (규칙 허브는 어딘가를 가리켜야 한다)"
  fi

  # B-8 상한 계약 줄 ↔ 이 스크립트 상수 일치 (상한의 단일 진실 원천)
  #     문서가 자기 상한을 선언하고 가드가 그걸 대조한다. 상한을 늘리려면 둘 다 고쳐야 하므로
  #     "일단 늘리고 보자"가 안 된다.
  declare -A want=( [전체]="$HUB_CHARS" [줄]="$CLAUDE_HARD" [한줄]="$HUB_LINELEN" [섹션]="$HUB_SECTION" )
  d_chars=$(sed -nE 's/.*전체 `([0-9]+)자`.*/\1/p' CLAUDE.md | head -1)
  d_lines=$(sed -nE 's/.*전체 `([0-9]+)줄`.*/\1/p' CLAUDE.md | head -1)
  d_llen=$(sed -nE 's/.*한 줄 `([0-9]+)자`.*/\1/p' CLAUDE.md | head -1)
  d_sect=$(sed -nE 's/.*섹션 `([0-9]+)줄`.*/\1/p' CLAUDE.md | head -1)
  contract_bad=""
  for pair in "chars:$d_chars:${want[전체]}" "lines:$d_lines:${want[줄]}" \
              "lineLen:$d_llen:${want[한줄]}" "section:$d_sect:${want[섹션]}"; do
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

# ── 결과 ───────────────────────────────────────────────────────────────────
if [ ${#ACTIONS[@]} -gt 0 ]; then
  printf '\n%s할 일%s\n' "$BLD" "$OFF"
  for a in "${ACTIONS[@]}"; do printf '  · %s\n' "$a"; done
  printf '  %s회전 절차: docs/context-budget.md §4%s\n' "$DIM" "$OFF"
fi

printf '\n%s구조만 검사했다 — 문장 표현·규칙 순서·내용의 정확성은 사람이 본다.%s\n' "$DIM" "$OFF"
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
