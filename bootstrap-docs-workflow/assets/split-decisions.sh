#!/usr/bin/env bash
# decisions.md 를 결정 하나 = 파일 하나로 쪼갠다 — bootstrap-docs-workflow 스킬이 설치.
#
# 왜: 결정을 한 파일에 두면 세션 시작 비용은 브리핑이 막아도(인덱스만 싣는다) **작업 중 비용**이
#     결정 수에 비례해 커진다. 결정 하나를 고치려 해도 편집 도구가 파일 전체를 읽고, 범위를 안 주고
#     열면 전체가 딸려 온다(어느 저장소: 결정 하나 1.3k자 vs 파일 47k자 = 35배). 쪼개 두면 읽기·쓰기
#     모두 결정 하나로 고정된다.
#
# 결과: docs/decisions.md  = 머리말 + 인덱스 표 (세션 브리핑이 읽는 자리 — 그대로)
#       docs/decisions/<ID>.md = 본문. 첫 줄은 '# <ID>. 제목'
#       가드·브리핑은 docs/decisions/ 가 있으면 split 으로 판정한다(DEC_LAYOUT=auto).
#
# 사용: bash scripts/split-decisions.sh [--dry-run]
# 종료코드: 0 = 완료(또는 미리보기), 1 = 거부(이미 쪼갬·ID 중복·형식 인식 실패·저장소 아님)
#
# 이식성: bash 3.2 · POSIX awk (macOS 기본). mapfile/declare -A 금지 — check-docs-budget.sh 와 같은 이유.
set -uo pipefail

DEC_ID='D-[0-9]{3}'; DEC_HEAD='## '; DEC_DIR=docs/decisions
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소가 아니다" >&2; exit 1; }
# shellcheck disable=SC1091
[ -f "$ROOT/scripts/docs-budget.conf" ] && . "$ROOT/scripts/docs-budget.conf"
cd "$ROOT" || exit 1
DEC_BODY_RE="^${DEC_HEAD}${DEC_ID}"; DEC_ROW_RE="^[|] *${DEC_ID}"
SRC=docs/decisions.md
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

die() { echo "✗ $1" >&2; [ -n "${2:-}" ] && echo "  $2" >&2; exit 1; }

[ -f "$SRC" ] || die "$SRC 가 없다" "결정 기록이 아직 없으면 처음부터 $DEC_DIR/<ID>.md 로 쓰면 된다"
if [ -d "$DEC_DIR" ] && ls "$DEC_DIR" 2>/dev/null | grep -qE "^${DEC_ID}[.]md$"; then
  die "$DEC_DIR/ 에 결정 파일이 이미 있다 — 이미 쪼갠 저장소다" "남은 본문이 있으면 손으로 옮긴다 (가드가 '본문 N개가 남아 있다' 로 알린다)"
fi
n=$(grep -cE "$DEC_BODY_RE" "$SRC") || n=0
[ "$n" -gt 0 ] || die "본문 헤딩 '${DEC_HEAD}${DEC_ID}' 를 0건 찾았다 — 형식을 인식하지 못했다" \
  "scripts/docs-budget.conf 에 DEC_ID·DEC_HEAD 를 이 저장소 형식으로 정한다"
# 헤딩 머리의 ID 만 센다 — 「D-023. … — D-006 개정」처럼 제목이 다른 결정을 언급하면
# 줄 전체에서 ID 를 뽑을 때 D-006 이 중복으로 잡힌다(실제로 5건 오탐해 분할을 거부했다).
dups=$(grep -oE "$DEC_BODY_RE" "$SRC" | grep -oE "$DEC_ID" | sort | uniq -d | tr '\n' ' ')
[ -z "$dups" ] || die "같은 ID 의 본문이 둘 이상이다: $dups" "번호를 정리한 뒤 다시 실행한다 (덮어쓰지 않는다)"

idx=$(grep -cE "$DEC_ROW_RE" "$SRC") || idx=0
first=$(grep -oE "$DEC_BODY_RE" "$SRC" | head -1 | grep -oE "$DEC_ID")
last=$(grep -oE "$DEC_BODY_RE" "$SRC" | tail -1 | grep -oE "$DEC_ID")
echo "결정 본문 ${n}개 (${first} … ${last}) → $DEC_DIR/<ID>.md"
if [ "$idx" -eq 0 ]; then
  echo "인덱스 표가 없다 → 본문 헤딩에서 만든다 (최신이 위, 상태 '유효' — 뒤집힌 결정은 손으로 고친다)"
else
  echo "인덱스 표 ${idx}행은 그대로 둔다"
fi
anchors=$(grep -rlE 'decisions\.md#' --include='*.md' . 2>/dev/null | grep -v '/node_modules/' | tr '\n' ' ')
[ -n "$anchors" ] && echo "⚠ decisions.md#앵커 링크가 있다 — 옮긴 뒤 $DEC_DIR/<ID>.md 로 고친다: $anchors"
[ -n "$(git status --porcelain -- "$SRC" 2>/dev/null)" ] && echo "⚠ $SRC 에 커밋하지 않은 변경이 있다 — 먼저 커밋해 두면 되돌리기 쉽다"
if [ "$DRY" -eq 1 ]; then echo "(미리보기 — 아무것도 바꾸지 않았다)"; exit 0; fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/split-dec.XXXXXX") || die "임시 디렉터리를 못 만들었다"
trap 'rm -rf "$TMP"' EXIT

# 한 번 훑으며 머리말(첫 본문 앞)과 본문 파일을 쓴다. 본문 끝의 빈 줄·'---' 구분선은 뗀다.
awk -v bre="$DEC_BODY_RE" -v idre="$DEC_ID" -v head="$DEC_HEAD" -v out="$TMP" '
  function flush(   i, e) {
    if (id == "") return
    e = cnt; while (e > 0 && (buf[e] ~ /^[[:space:]]*$/ || buf[e] == "---")) e--
    for (i = 1; i <= e; i++) print buf[i] > (out "/" id ".md")
    close(out "/" id ".md"); cnt = 0
  }
  $0 ~ bre {
    flush()
    match($0, idre); id = substr($0, RSTART, RLENGTH)
    cnt = 1; buf[1] = "# " substr($0, length(head) + 1)
    next
  }
  id == "" { print > (out "/_preamble"); next }
  { buf[++cnt] = $0 }
  END { flush() }
' "$SRC"

made=$(ls "$TMP" | grep -cE "^${DEC_ID}[.]md$") || made=0
[ "$made" -eq "$n" ] || die "본문 ${n}개 중 ${made}개만 나왔다 — 아무것도 바꾸지 않았다"

# 머리말 끝의 빈 줄·구분선을 떼고, 인덱스가 없으면 만들고, 본문 위치를 한 줄로 가리킨다.
{
  awk '{ l[NR] = $0 } END { e = NR; while (e > 0 && (l[e] ~ /^[[:space:]]*$/ || l[e] == "---")) e--; for (i = 1; i <= e; i++) print l[i] }' "$TMP/_preamble" 2>/dev/null
  if [ "$idx" -eq 0 ]; then
    printf '\n## 인덱스 (최신이 위)\n\n| ID | 결정 | 상태 |\n| --- | --- | --- |\n'
    grep -E "$DEC_BODY_RE" "$SRC" | sed -E "s/^${DEC_HEAD}(${DEC_ID})[.:]? *(.*)$/| \\1 | \\2 | 유효 |/; s/\\*\\*//g" |
      awk '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) print l[i] }'
  fi
  printf '\n결정 본문은 `%s/<ID>.md` 에 하나씩 있다 — 인덱스에서 ID 를 찾아 **그 파일만** 연다.\n' "$DEC_DIR"
  printf '새 결정은 `%s/<ID>.md` 를 만들고(첫 줄 `# <ID>. 제목`, 본문 20줄 이내) 인덱스 표에 한 줄 넣는다.\n' "$DEC_DIR"
} > "$TMP/_index"

mkdir -p "$DEC_DIR"
for f in "$TMP"/*.md; do mv "$f" "$DEC_DIR/"; done
mv "$TMP/_index" "$SRC"

echo "✓ $DEC_DIR/ 에 ${n}개, $SRC 는 머리말 + 인덱스만 남았다"
echo "  다음: CLAUDE.md 의 '결정 →' 규칙 줄을 '$DEC_DIR/<ID>.md + 인덱스 한 줄' 로 고친다"
echo "        포매터(prettier 등)를 돌리고 bash scripts/check-docs-budget.sh 로 확인한다 (split 으로 판정돼야 한다)"
[ "$idx" -eq 0 ] && echo "        만든 인덱스가 최신이 위인지, 뒤집힌 결정의 상태를 '폐기(→ID)' 로 고쳤는지 본다"
exit 0
