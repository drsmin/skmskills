#!/usr/bin/env bash
# session-log · todo 회전 — bootstrap-docs-workflow 스킬이 설치.
#
# 왜: 회전 기준은 가드가 재지만(항목 수·줄 수 캡), 회전 자체는 손으로 하고 있었다. 어디서 자를지,
#     항목 날짜로 월별 아카이브 나누기, 기존 아카이브에 최신이 위로 끼우기, `> 이전 이력` 포인터,
#     ★ Phase 건드리지 않기 — 손으로 하면 하나씩 빠지고(포인터 누락이 가장 잦았다), 가드가 막는
#     순간 `--no-verify` 로 넘기고 싶어진다. 그래서 기계적인 부분은 스크립트가 한다.
#     판단이 필요한 것(미완 항목을 어느 Phase 로 이월할지)은 하지 않고 목록만 찍는다.
#
# 하는 일:
#   session-log — 최근 SESS_KEEP 개만 남기고 나머지를 항목 날짜(## YYYY-MM-DD …)로
#                 docs/archive/session-log-YYYY-MM.md 맨 위에 끼운다. 꼬리 포인터 줄은 하나로 다시 쓴다.
#   todo        — 항목이 전부 [x] 이고 ★ 가 없는 `## ` 절을 docs/archive/todo-done.md 끝에 붙이고,
#                 그 자리에 `## <제목> — 완료 (docs/archive/todo-done.md)` 한 줄을 남긴다.
#                 미완이 섞인 절은 옮기지 않는다 — 이월하라고 알리기만 한다.
#   둘 다, 회전 전후의 **내용 줄 전체가 같을 때만** 파일을 바꾼다(아니면 아무것도 안 바꾸고 멈춘다).
#
# 사용: bash scripts/rotate-docs.sh [--dry-run]
# 종료코드: 0 = 완료(또는 바꿀 것 없음·미리보기), 1 = 거부(날짜 없는 항목·검산 불일치·저장소 아님)
#
# 이식성: bash 3.2 · POSIX awk (macOS 기본). mapfile/declare -A 금지 — check-docs-budget.sh 와 같은 이유.
set -uo pipefail

SESS_ENTRIES=3   # 브리핑이 펼치는 수 — SESS_KEEP 은 이보다 작을 수 없다
SESS_KEEP=6      # 회전 뒤 남길 항목 수. 가드의 권고선(SESSENT_SOFT=12)보다 낮게 둬야 다음 회전까지 여유가 생긴다
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소가 아니다" >&2; exit 1; }
# shellcheck disable=SC1091
[ -f "$ROOT/scripts/docs-budget.conf" ] && . "$ROOT/scripts/docs-budget.conf"
cd "$ROOT" || exit 1
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
LOG=docs/session-log.md; TODO=docs/todo.md; AR=docs/archive; DONE=$AR/todo-done.md

die() { echo "✗ $1" >&2; [ -n "${2:-}" ] && echo "  $2" >&2; exit 1; }
[ "$SESS_KEEP" -ge "$SESS_ENTRIES" ] || die "SESS_KEEP($SESS_KEEP) 가 브리핑 창 SESS_ENTRIES($SESS_ENTRIES) 보다 작다"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rotate-docs.XXXXXX") || die "임시 디렉터리를 못 만들었다"
trap 'rm -rf "$TMP"' EXIT

# 끝의 빈 줄·'---' 구분선을 뗀다
trim() { awk '{ l[NR] = $0 } END { e = NR; while (e > 0 && (l[e] ~ /^[[:space:]]*$/ || l[e] == "---")) e--; for (i = 1; i <= e; i++) print l[i] }' "$@"; }
# 검산용 내용 줄 — 첫 `## ` 앞의 머리말, 헤딩, 빈 줄, 구분선, 포인터 줄을 뺀 나머지(정렬)
#   (awk 에 파일을 직접 넘긴다 — cat 으로 이으면 FNR 이 안 돌아가 둘째 파일의 머리말이 섞인다)
content() {
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk '/^## / { on = 1 } on && !/^#/ && !/^[[:space:]]*$/ && $0 != "---" && !/^> 이전 이력/' "$f"
  done | LC_ALL=C sort
}
changed=0

# ── session-log ─────────────────────────────────────────────────────────────
if [ -f "$LOG" ]; then
  mkdir -p "$TMP/log"
  # 머리말 → pre, 항목 → eNNNN. 꼬리의 '> 이전 이력' 줄은 버린다(아래에서 하나로 다시 쓴다)
  awk -v out="$TMP/log" '
    /^> 이전 이력/ { next }
    /^## / { n++; f = sprintf("%s/e%04d", out, n) }
    n == 0 { print > (out "/pre"); next }
    { print > f }
  ' "$LOG"
  total=$(ls "$TMP/log" | grep -c '^e') || total=0
  if [ "$total" -le "$SESS_KEEP" ]; then
    echo "session-log: 항목 ${total}개 ≤ 남길 수 ${SESS_KEEP} — 회전할 것 없음"
  else
    nodate=""; i=0
    for f in "$TMP"/log/e*; do
      i=$((i + 1)); [ "$i" -le "$SESS_KEEP" ] && continue
      head -1 "$f" | grep -qE '^## [0-9]{4}-[0-9]{2}' || nodate="$nodate
    $(head -1 "$f")"
    done
    [ -z "$nodate" ] || die "날짜(## YYYY-MM-…)를 못 읽은 항목이 있다 — 어느 달로 보낼지 모른다:$nodate" \
      "헤딩에 날짜를 넣은 뒤 다시 실행한다 (아무것도 바꾸지 않았다)"
    moved=$((total - SESS_KEEP))
    # 새 session-log: 머리말 + 남길 항목 + 포인터
    {
      if [ -f "$TMP/log/pre" ]; then trim "$TMP/log/pre"; printf '\n---\n\n'; fi
      i=0
      for f in "$TMP"/log/e*; do
        i=$((i + 1)); [ "$i" -gt "$SESS_KEEP" ] && break
        trim "$f"; printf '\n---\n\n'
      done
    } > "$TMP/log.new"
    # 옮길 항목을 달별로 모은다 (최신이 위 순서 그대로)
    months=""
    i=0
    for f in "$TMP"/log/e*; do
      i=$((i + 1)); [ "$i" -le "$SESS_KEEP" ] && continue
      m=$(head -1 "$f" | grep -oE '^## [0-9]{4}-[0-9]{2}' | cut -c4-)
      case " $months " in *" $m "*) ;; *) months="$months $m" ;; esac
      { trim "$f"; printf '\n---\n\n'; } >> "$TMP/blk-$m"
    done
    mkdir -p "$TMP/ar"
    for m in $months; do
      dst="$AR/session-log-$m.md"
      if [ -f "$dst" ]; then
        # 첫 항목 앞에 끼운다 — 옮기는 항목이 그 달에서 가장 최근이다
        awk -v blk="$TMP/blk-$m" '
          !done && /^## / { while ((getline l < blk) > 0) print l; done = 1 }
          { print }
          END { if (!done) while ((getline l < blk) > 0) print l }
        ' "$dst" > "$TMP/ar/session-log-$m.md"
      else
        { printf '# Session Log — %s (회전됨)\n\n`docs/session-log.md` 에서 회전된 항목. 최신이 위. 세션 시작에 읽지 않는다.\n\n---\n\n' "$m"
          trim "$TMP/blk-$m"; } > "$TMP/ar/session-log-$m.md"
      fi
      trim "$TMP/ar/session-log-$m.md" > "$TMP/ar/t" && mv "$TMP/ar/t" "$TMP/ar/session-log-$m.md"
    done
    latest=$( { ls "$AR" 2>/dev/null; ls "$TMP/ar"; } | grep -oE '^session-log-[0-9]{4}-[0-9]{2}\.md$' | LC_ALL=C sort -u | tail -1)
    printf '> 이전 이력: `%s/%s` (월별 — 그 앞 달은 같은 폴더)\n' "$AR" "$latest" >> "$TMP/log.new"
    # 검산: 옮기기 전(로그 + 그 달 아카이브)과 뒤의 내용 줄이 같아야 한다
    before=$(content "$LOG"; for m in $months; do content "$AR/session-log-$m.md"; done)
    after=$(content "$TMP/log.new"; for m in $months; do content "$TMP/ar/session-log-$m.md"; done)
    [ "$(printf '%s\n' "$before" | LC_ALL=C sort)" = "$(printf '%s\n' "$after" | LC_ALL=C sort)" ] ||
      die "session-log 검산 불일치 — 회전 전후 내용 줄이 다르다 (아무것도 바꾸지 않았다)"
    echo "session-log: ${total}개 → ${SESS_KEEP}개 남김, ${moved}개 →$(for m in $months; do printf ' %s/session-log-%s.md' "$AR" "$m"; done)"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$AR"
      for m in $months; do mv "$TMP/ar/session-log-$m.md" "$AR/"; done
      mv "$TMP/log.new" "$LOG"; changed=1
    fi
  fi
fi

# ── todo ────────────────────────────────────────────────────────────────────
if [ -f "$TODO" ]; then
  mkdir -p "$TMP/todo"
  awk -v out="$TMP/todo" '
    /^## / { n++; f = sprintf("%s/s%04d", out, n) }
    n == 0 { print > (out "/pre"); next }
    { print > f }
  ' "$TODO"
  done_list=""; partial=""
  : > "$TMP/todo.new"; : > "$TMP/done.add"
  [ -f "$TMP/todo/pre" ] && cat "$TMP/todo/pre" >> "$TMP/todo.new"
  for f in "$TMP"/todo/s*; do
    [ -f "$f" ] || continue
    h=$(head -1 "$f")
    nx=$(grep -cE '^[[:space:]]*- \[[xX]\]' "$f") || nx=0
    no=$(grep -cE '^[[:space:]]*- \[( |~)\]' "$f") || no=0
    star=0; case "$h" in *★*) star=1 ;; esac
    rotated=0; case "$h" in *"— 완료 ("*) rotated=1 ;; esac
    if [ "$star" -eq 0 ] && [ "$rotated" -eq 0 ] && [ "$nx" -gt 0 ] && [ "$no" -eq 0 ]; then
      done_list="$done_list
    $h"
      { trim "$f"; printf '\n'; } >> "$TMP/done.add"
      printf '%s — 완료 (`%s`)\n\n' "$h" "$DONE" >> "$TMP/todo.new"
    else
      [ "$star" -eq 0 ] && [ "$rotated" -eq 0 ] && [ "$nx" -gt 0 ] && [ "$no" -gt 0 ] &&
        partial="$partial
    $h — 미완 ${no}개 (갈 Phase 로 이월하면 다음 실행에 회전된다)"
      cat "$f" >> "$TMP/todo.new"
    fi
  done
  if [ -z "$done_list" ]; then
    echo "todo: 전부 끝난 Phase 없음 — 회전할 것 없음"
  else
    {
      if [ -f "$DONE" ]; then trim "$DONE"; printf '\n'
      else printf '# TODO — 완료된 Phase (회전됨)\n\n`%s` 에서 회전된 완료 Phase. 세션 시작에 읽지 않는다.\n\n' "$TODO"; fi
      trim "$TMP/done.add"
    } > "$TMP/done.new"
    trim "$TMP/todo.new" > "$TMP/t" && mv "$TMP/t" "$TMP/todo.new"
    before=$(content "$TODO"; content "$DONE")
    after=$(content "$TMP/todo.new"; content "$TMP/done.new")
    [ "$(printf '%s\n' "$before" | LC_ALL=C sort)" = "$(printf '%s\n' "$after" | LC_ALL=C sort)" ] ||
      die "todo 검산 불일치 — 회전 전후 내용 줄이 다르다 (아무것도 바꾸지 않았다)"
    echo "todo: 완료 Phase → $DONE:$done_list"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$AR"; mv "$TMP/done.new" "$DONE"; mv "$TMP/todo.new" "$TODO"; changed=1
    fi
  fi
  [ -n "$partial" ] && echo "todo: 미완이 섞여 옮기지 않은 Phase:$partial"
fi

if [ "$DRY" -eq 1 ]; then echo "(미리보기 — 아무것도 바꾸지 않았다)"
elif [ "$changed" -eq 1 ]; then echo "✓ 회전했다 — 포매터를 돌리고 bash scripts/check-docs-budget.sh 로 확인한다"; fi
exit 0
