#!/usr/bin/env bash
# 자가 진단 — 이 저장소가 **규율을 지키고 있는지**를 한 번에 본다.
#               bootstrap-docs-workflow 스킬이 설치. 정책: docs/context-budget.md
#
# 왜: 설치한 것과 집행되는 것은 다르다. 가드 파일이 있어도 훅에 안 붙어 있으면 조용히
#     통과하고, 캡이 초록이어도 세션이 길면 느려진다 — 그 둘은 **재는 자가 다르다**.
#     이 스크립트는 흩어진 재는 자를 한 화면에 모은다.
#
# ⚠️ **새 가드가 아니다 — 읽기 전용이고 아무것도 막지 않는다.** 상한을 재는 것은
#    `check-docs-budget.sh` 하나이고, 비용을 재는 것은 `session-{cost,rereads}.py` 다.
#    이 스크립트는 **그것들을 부르고 판정만 모은다.** ⚠️ 여기에 새 상한을 넣지 말 것 —
#    넣으면 캡이 두 곳이 되고, 어긋나면 어느 쪽이 맞는지 아무도 모른다.
# ⚠️ **`scripts/pre-commit.d/` 에 넣지 말 것** — 커밋을 막는 순간 가드가 되고, 그러면
#    위 규약이 깨진다(진단은 사람이 **부를 때** 돈다).
#
# 부르는 명령은 교재 실습 과제와 **같아야 한다** — 과제 2(훅 증거) · 3(비용) · 5(상한).
# 과제가 바뀌면 이쪽도 바뀐다. 어긋나면 수강생이 자기 프로젝트에서 다른 것을 보게 된다.
#
# 사용: bash scripts/self-check.sh
# 종료코드: 0 = 집행이 살아 있다, 1 = **설치됐다고 믿는데 집행되지 않는 것**이 있다.
#           (상한 soft 초과·비용 경고는 1 로 만들지 않는다 — 그건 「고칠 것」이고 「고장」이 아니다)
#
# 이식성: bash 3.2 · BSD 도구. mapfile/declare -A 금지(check-docs-budget.sh 와 같은 이유).
#   ⚠️ `printf | grep -q` 로 쓰지 말 것 — pipefail + 64KB 초과 출력이면 printf 가 SIGPIPE 로
#   죽어 **판정이 조용히 뒤집힌다**. here-string(`<<<`)을 쓴다.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "✗ git 저장소가 아니다." >&2; exit 1; }
cd "$ROOT" || exit 1

COMMITS=50          # 기록 습관을 볼 최근 커밋 수 (전체를 세면 오래된 습관에 묻힌다)
SESSIONS=5          # 비용을 볼 최근 세션 수
RATIO_WARN=3        # 배율(최대/시작) 경고선 — session-cost.py 머리 주석의 경험값
REREAD_WARN=50      # 재독분 % 경고선 — session-rereads.py 머리 주석의 경험값
DOCSRATIO_WARN=80   # 기록을 함께 남긴 커밋 비율(%) 경고선
CONF="$ROOT/scripts/docs-budget.conf"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

PY=$(command -v python3 || true)
broken=0            # 「집행되지 않는 것」 — 이것만 종료코드 1 로 만든다
todo=""             # 사람이 고칠 것 (종료코드에는 영향 없음)
note() { todo="${todo}  · $1
"; }

echo "자가 진단 — $(basename "$ROOT")"
echo

# ── ① 설치 ─────────────────────────────────────────────────────────────────
# 파일이 있는지만 본다. **있다는 것이 돈다는 뜻은 아니다** — 그건 ② 가 본다.
echo "① 설치 — 규율의 자리가 있는가"
for f in docs/current-task.md docs/session-log.md docs/decisions.md docs/todo.md \
         CLAUDE.md scripts/session-brief.sh scripts/check-docs-budget.sh; do
  if [ -f "$f" ]; then printf '  ok   %s\n' "$f"
  else printf '  ✗    %s 없다\n' "$f"; broken=$((broken + 1)); fi
done
if [ -d docs/decisions ] && ls docs/decisions/*.md >/dev/null 2>&1; then
  printf '  ok   docs/decisions/ 결정 %d건\n' "$(ls docs/decisions/*.md | wc -l | tr -d ' ')"
else
  printf '  note docs/decisions/ 가 비었다 — 갈림길을 아직 안 남겼다(교재 과제 4)\n'
fi
echo

# ── ② 집행 ─────────────────────────────────────────────────────────────────
# 교재 3-5 의 함정 넷 중 **「출력 없음을 통과로 받아들인다」** 를 막는 절이다.
# 가드 파일이 있는 것과 커밋이 실제로 막히는 것은 다르다 — 그 차이를 여기서 본다.
echo "② 집행 — 실제로 막히는가 (파일이 있는 것과 다르다)"
if [ -f .git/hooks/pre-commit ] && grep -q 'check-docs-budget' .git/hooks/pre-commit 2>/dev/null; then
  printf '  ok   .git/hooks/pre-commit 에 예산 가드가 붙어 있다\n'
else
  printf '  ✗    .git/hooks/pre-commit 에 예산 가드가 없다 — bash scripts/install-hooks.sh\n'
  broken=$((broken + 1))
fi
mode=${BUDGET_MODE:-warn}
if [ "$mode" = block ]; then
  printf '  ok   BUDGET_MODE=block — hard 초과면 커밋이 막힌다\n'
else
  printf '  note BUDGET_MODE=%s — 판정만 찍고 **막지 않는다**(도입 모드)\n' "$mode"
  note "BUDGET_MODE 를 block 으로 올린다 — hard 위반을 0 으로 만든 뒤에"
fi
# 커밋 전 테스트 훅은 `.claude/settings.json` 에 붙는다(.git/hooks 가 아니다).
if [ -f .claude/settings.json ] && grep -q 'pre-commit-test' .claude/settings.json 2>/dev/null; then
  log=.git/pre-commit-test.log
  if [ -s "$log" ]; then
    printf '  ok   커밋 전 테스트 훅 — 마지막 기록: %s\n' "$(tail -1 "$log" | cut -c1-72)"
  else
    # ⚠️ 이것이 교재가 경고하는 **조용한 통과**다 — 설정은 있는데 실행 경로가 없었다.
    printf '  ✗    훅 설정은 있는데 %s 가 비었다 — 한 번도 돈 증거가 없다\n' "$log"
    printf '       (/hooks 를 한 번 열거나 세션을 다시 시작한다. 그때까지는 yarn test 를 손으로)\n'
    broken=$((broken + 1))
  fi
else
  printf '  note 커밋 전 테스트 훅이 .claude/settings.json 에 없다\n'
  note "커밋 전 테스트 훅을 붙인다 — 적어 둔 규칙은 지켜지지 않는다(교재 2-3)"
fi
echo

# ── ③ 상한 ─────────────────────────────────────────────────────────────────
# 캡을 재는 것은 저쪽 하나다. 여기서는 **부르고 판정만** 가져온다(교재 과제 5 와 같은 명령).
echo "③ 상한 — bash scripts/check-docs-budget.sh"
if [ -f scripts/check-docs-budget.sh ]; then
  out=$(bash scripts/check-docs-budget.sh 2>&1); rc=$?
  soft=$(grep -cE '^ *soft ' <<<"$out" | tr -d ' ')
  if [ "$rc" -ne 0 ]; then
    # ⚠️ 여기에 `✗` 를 쓰지 말 것 — 그 기호는 **집행 고장**(종료코드 1) 전용이다. hard 초과는
    # 커밋을 막지만 그건 가드가 **일하고 있다는 뜻**이고, 고침은 사람의 회전이다(아래 할 일).
    printf '  hard 초과 — 커밋이 막힌다. 전문을 보려면 위 명령을 직접 돌린다\n'
    # 인용한 가드 줄의 `✗` 도 지운다 — 이 출력에서 그 기호는 **집행 고장** 하나만 뜻한다.
    grep -E '^ *(hard|✗)' <<<"$out" | head -5 | sed 's/^/       /; s/✗/·/'
    note "hard 초과를 고친다 — 회전(bash scripts/rotate-docs.sh)이거나 내용을 docs/ 로 옮긴다"
  elif [ "${soft:-0}" -gt 0 ]; then
    printf '  note soft %s건 — 커밋은 통과. 곧 회전할 것\n' "$soft"
    grep -E '^ *soft ' <<<"$out" | head -3 | sed 's/^/       /'
    note "soft 를 회전으로 내린다 — ⚠️ 캡을 올리는 것은 고침이 아니다"
  else
    printf '  ok   전부 초록\n'
  fi
else
  printf '  ✗    가드가 없다\n'; broken=$((broken + 1))
fi
echo

# ── ④ 비용 ─────────────────────────────────────────────────────────────────
# ③ 이 전부 초록인 채로 느려질 수 있다 — 그 비용은 **세션 기록**에만 있다(교재 과제 3).
# 지배 요인은 문서 크기가 아니라 **세션 수명**이다(D-094~D-096 계열).
echo "④ 비용 — 세션 기록 실측 (추정하지 않는다)"
if [ -z "$PY" ]; then
  printf '  note python3 가 없어 건너뛴다 — 말없이 통과시키지 않으려고 적는다\n'
elif [ ! -f scripts/session-cost.py ]; then
  printf '  note scripts/session-cost.py 가 없어 건너뛴다\n'
else
  cost=$("$PY" -I scripts/session-cost.py -n "$SESSIONS" 2>&1)
  if grep -q '세션 기록이 없다' <<<"$cost"; then
    printf '  note 세션 기록이 아직 없다 — 작업을 한 회차 한 뒤에 다시 돈다\n'
  else
    # 표의 **배율 열(7번째)** 만 본다 — 머리줄·빈 줄·도구별 줄은 9열이 아니라 걸리지 않는다.
    # ⚠️ 열 번호를 눈으로 세지 말 것 — 토큰 수 열은 **쉼표가 박혀** awk 가 `300,336`→`300` 으로
    # 읽는다(그래서 6번째를 읽었을 때 배율이 300.0 으로 보였다). 배율 열만 쉼표가 없다.
    worstr=$(awk 'NF>=9 && $7+0>0 {if ($7+0>m) m=$7+0} END {printf "%.1f", m+0}' <<<"$cost")
    printf '  %s   배율(최대/시작) 최대 %s — %s 를 넘으면 세션이 길다\n' \
      "$(awk -v w="$worstr" -v l="$RATIO_WARN" 'BEGIN{print (w>l)?"note":"ok  "}')" "$worstr" "$RATIO_WARN"
    awk -v w="$worstr" -v l="$RATIO_WARN" 'BEGIN{exit !(w>l)}' && \
      note "마일스톤마다 /clear — 배율이 ${worstr} 다(세션 안 누적이 시작 부하의 ${worstr}배)"
    grep '시작 부하 중앙값' <<<"$cost" | sed 's/^/       /'
  fi
fi
if [ -n "$PY" ] && [ -f scripts/session-rereads.py ]; then
  rr=$("$PY" -I scripts/session-rereads.py -n "$SESSIONS" 2>&1)
  if ! grep -q '세션 기록이 없다' <<<"$rr"; then
    # 「재독분 … (NN%)」 와 「컴팩트 N회」 — 둘 다 세션 수명의 지표다.
    worstd=$(grep -oE '\( *[0-9]+%\)' <<<"$rr" | tr -dc '0-9\n' | sort -rn | head -1)
    comp=$(grep -oE '컴팩트 [0-9]+회' <<<"$rr" | tr -dc '0-9\n' | sort -rn | head -1)
    printf '  %s   재독분 최대 %s%% — %s%% 를 넘으면 세션이 너무 길다 · 컴팩트 최대 %s회\n' \
      "$([ "${worstd:-0}" -gt "$REREAD_WARN" ] && echo note || echo 'ok  ')" \
      "${worstd:-0}" "$REREAD_WARN" "${comp:-0}"
    [ "${worstd:-0}" -gt "$REREAD_WARN" ] && \
      note "재독분이 ${worstd}% 다 — 고침은 문서 축소가 아니라 /clear 다(컴팩트가 다시 읽게 만든다)"
  fi
fi
echo

# ── ⑤ 기록 습관 ────────────────────────────────────────────────────────────
# 기계가 막을 수 없는 유일한 절이다 — 「작업과 기록을 같은 커밋에」는 사람의 습관이다.
echo "⑤ 기록 습관 — 최근 $COMMITS 커밋에 docs/ 가 함께 들어갔는가"
tot=0; with=0
for c in $(git log --format=%h -n "$COMMITS" 2>/dev/null); do
  tot=$((tot + 1))
  git show --stat --format= --name-only "$c" 2>/dev/null | grep -q '^docs/' && with=$((with + 1))
done
if [ "$tot" -gt 0 ]; then
  pct=$((with * 100 / tot))
  printf '  %s   %d/%d = %d%% (경고선 %d%%)\n' \
    "$([ "$pct" -lt "$DOCSRATIO_WARN" ] && echo note || echo 'ok  ')" "$with" "$tot" "$pct" "$DOCSRATIO_WARN"
  [ "$pct" -lt "$DOCSRATIO_WARN" ] && \
    note "기록을 함께 남긴다 — /wrap-up-docs-commit 은 기록 넷을 갱신한 뒤 커밋한다"
else
  printf '  note 커밋이 없다\n'
fi
echo

# ── 판정 ───────────────────────────────────────────────────────────────────
# 둘을 가른다: **고장**(집행이 죽었다 → 1) 과 **고칠 것**(상한·비용·습관 → 0).
# 섞으면 「빨간불이 늘 떠 있는 진단」이 되고, 그러면 아무도 안 본다.
if [ -n "$todo" ]; then printf '할 일\n%s' "$todo"; fi
if [ "$broken" -gt 0 ]; then
  echo "✗ 집행되지 않는 것이 $broken 건 있다 — **설치됐다고 믿는 상태**다(교재 3-5 의 함정 넷)."
  exit 1
fi
echo "✓ 집행은 살아 있다. 위 「할 일」은 막지 않는 것들이다(상한·비용·습관)."
exit 0
