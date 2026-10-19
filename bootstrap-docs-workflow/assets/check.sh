#!/usr/bin/env bash
# 게이트 실행기 — bootstrap-docs-workflow 스킬이 설치. 정책: docs/context-budget.md §7.
#
# 왜: 게이트는 커밋마다 돈다. 단계 출력을 그대로 흘리면 성공해도 수천 자이고(한 저장소에서
#     6,600자 → 이 실행기로 560자), 그게 매번 에이전트 대화에 쌓여 **긴 세션을 느리게** 만든다.
#     세션 시작 비용은 브리핑이 고정하지만 세션 *안* 비용은 이런 반복 출력이 키운다.
#     그래서 **성공은 한 줄, 실패만 전문**이다. 실패 출력은 자르지 않는다 — 원인이 꼬리 밖에
#     있으면 다시 돌려야 해서 오히려 더 쌓인다.
#
#     끝에 소스 파일 크기를 잰다. 파일 하나를 통째로 읽는 비용에 상한을 두는 것이다 —
#     soft 는 알리기만(손댈 때 나눈다), hard 는 막는다.
#
# 사용: bash scripts/check.sh            (전부 보려면 CHECK_VERBOSE=1)
# 설정: scripts/docs-budget.conf 의 GATE_STEPS · SRC_* (스크립트를 갈아 끼워도 남는다)
# 종료코드: 0 = 전부 통과, 1 = 실패 (실패한 단계에서 멈춘다), 2 = GATE_STEPS 없음
#
# 이식성: bash 3.2 · BSD 도구에서도 돌아야 한다. `date +%N` 은 BSD 에 없어 `$SECONDS` 를 쓴다.
#   **`pnpm -s`/`npm -s` 를 단계 명령에 쓰지 않는다** — 하위 패키지 출력까지 지워 실패 원인이 사라진다.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
cd "$ROOT" || exit 1

# 단계: 한 줄에 `이름|명령`. 위에서부터 돌고 처음 실패에서 멈춘다.
GATE_STEPS=""
# 성공 줄에 붙일 요약 — 출력에서 이 정규식에 맞는 조각을 모은다(테스트 개수 등).
GATE_SUMMARY_RE='Tests +[0-9]+ passed( \([0-9]+\))?|[0-9]+ passed in [0-9.]+s'  # vitest·jest | pytest
# 소스 파일 크기 (줄). 0 이면 끈다.
SRC_SOFT=800
SRC_HARD=1500
SRC_GLOBS='*.ts *.tsx *.js *.jsx *.mjs *.py *.go *.rs *.java *.kt *.swift *.rb *.php *.cs *.dart *.vue *.svelte'
SRC_EXCLUDE='(^|/)(vendor|dist|build|generated)/|\.min\.|\.d\.ts$' # 확장 정규식, 경로에 맞으면 뺀다

CONF="$ROOT/scripts/docs-budget.conf"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

if [ -z "$GATE_STEPS" ]; then
  echo "✗ GATE_STEPS 가 비었다 — scripts/docs-budget.conf 에 '이름|명령' 줄로 채운다." >&2
  exit 2
fi

total=0
while IFS='|' read -r name cmd; do
  case "$name" in '' | \#*) continue ;; esac
  st=$SECONDS
  out=$(bash -c "$cmd" 2>&1)
  rc=$?
  dt=$((SECONDS - st))
  total=$((total + dt))
  if [ "$rc" -ne 0 ]; then
    printf '✗ %s 실패 (%ds) — 출력 전문:\n%s\n' "$name" "$dt" "$out"
    exit 1
  fi
  note=$(printf '%s\n' "$out" | grep -oE "$GATE_SUMMARY_RE" | sed -E 's/^Tests +//' | paste -s -d '+' - 2>/dev/null)
  printf '%s\n' "$out" | grep -qE '⚠|soft 권고' && note="${note:+$note · }경고 있음 — 따로 돌려 본다"
  printf '✓ %-14s %3ds%s\n' "$name" "$dt" "${note:+  $note}"
  [ "${CHECK_VERBOSE:-}" = 1 ] && printf '%s\n' "$out"
done <<EOF
$GATE_STEPS
EOF

if [ "$SRC_SOFT" -gt 0 ]; then
  # shellcheck disable=SC2086
  big=$(git ls-files -z -- $SRC_GLOBS 2>/dev/null | xargs -0 wc -l 2>/dev/null |
    grep -vE ' total$' | grep -vE "$SRC_EXCLUDE" | awk -v s="$SRC_SOFT" '$1 > s' | sort -rn)
  if [ -n "$big" ]; then
    over=$(printf '%s\n' "$big" | awk -v h="$SRC_HARD" '$1 > h')
    if [ -n "$over" ]; then
      printf '✗ 소스 파일 %d줄 초과 — 나눈 뒤 커밋한다:\n%s\n' "$SRC_HARD" "$over"
      exit 1
    fi
    printf '⚠ 소스 파일 %d줄 초과 (손댈 때 나눈다):\n%s\n' "$SRC_SOFT" "$big"
  fi
fi

printf '✓ 게이트 통과 (%ds)\n' "$total"
