#!/usr/bin/env bash
#
# 세션 시작 브리핑 자동 주입 
#
# Claude Code 의 SessionStart 훅으로 붙는다(`.claude/settings.json`). `session-brief.sh --compact`
# 출력을 `additionalContext` 로 감싸 **세션 컨텍스트에 직접 넣는다**.
#
# 왜 필요한가: CLAUDE.md 는 「브리핑 한 번이 세션 시작 읽기의 전부다」라고 적는데,
# 브리핑 전체판은 277줄이라 읽는 쪽이 `head -120` 으로 잘라 왔다 — 최근 10세션 중 **2세션이
# session-log·decisions·todo★ 세 조각을 아예 못 봤다**(실측). D-093·D-094 와 **같은 실패**다:
# 규칙은 옳고 집행 형태가 틀렸다. 부르는 명령이면 자를 수 있고, 주입이면 자를 자리가 없다.
#
# ⚠️ **하네스 캡은 10,000자다.** 넘으면 하네스가 본문을 파일로 빼고 경로+프리뷰만 주면서
#    **「읽으라」고 하지 않는다** ⇒ 브리핑이 통째로 없는 세션이 된다. 그래서 **우리가 먼저 재서
#    자르고, 자른 사실을 본문에 적는다**. 하네스에 맡기면 조용한 실패다.
# ⚠️ **stdout 에는 JSON 만** 찍는다(하네스 요구 — 섞이면 파싱이 깨져 주입이 사라진다). 진단은 stderr.
# ⚠️ **캡을 올려서 풀지 말 것** — 좁힐 곳은 `docs-budget.conf` 의 `*_COMPACT` 창이다.
# ⚠️ SessionStart 는 **블로킹이 없다**(exit 2 도 세션을 막지 못한다). 그래서 이 훅이 할 수 있는
#    최선은 **실패를 조용히 넘기지 않는 것**이다 — 비면 「비었다」를 적어 보낸다.
set -uo pipefail

root=${CLAUDE_PROJECT_DIR:-}
if [[ -z $root ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

BRIEF_COMPACT_HARD=9500
CONF="$root/scripts/docs-budget.conf"
# shellcheck disable=SC1090
[[ -f $CONF ]] && . "$CONF"

# 하네스가 주입 문맥을 자르는 선. conf 값이 이보다 크면 **하네스 쪽이 이긴다** —
# 우리 캡을 올려도 소용없다는 사실을 코드로 고정한다(위 ⚠️).
HARNESS_CAP=10000
cap=$BRIEF_COMPACT_HARD
((cap > HARNESS_CAP)) && cap=$HARNESS_CAP

# JSON 문자열로 감싸 내보낸다. 파이썬이 없으면 주입을 **포기한다**(exit 0) —
# 손으로 escape 하면 깨진 JSON 이 되고, 그건 조용한 실패다.
emit() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
body = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": body,
}}, ensure_ascii=False))
'
  else
    echo "python3 이 없어 브리핑 주입을 건너뛴다 — bash scripts/session-brief.sh 를 직접 부를 것" >&2
    cat >/dev/null
    return 1
  fi
}

brief="$root/scripts/session-brief.sh"
if [[ ! -f $brief ]]; then
  # 조용히 넘기지 않는다 — 브리핑이 없다는 사실 자체가 세션이 알아야 할 것이다.
  printf '%s\n' "⚠ scripts/session-brief.sh 가 없다 — 세션 시작 읽기를 자르는 유일한 장치다. docs/recovery.md 를 본다." | emit
  exit 0
fi

# ANSI 를 벗긴다. 파이프라면 session-brief.sh 가 색을 끄지만(`[ -t 1 ]`), 명시적으로 지운다 —
# 색 코드가 섞이면 주입 본문에 쓰레기가 들어간다.
out=$(bash "$brief" --compact 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

if [[ -z ${out//[[:space:]]/} ]]; then
  printf '%s\n' "⚠ 브리핑이 빈 출력을 냈다 — bash scripts/session-brief.sh 를 직접 부르고 원인을 본다." | emit
  exit 0
fi

# **우리가 먼저 잰다.** 자를 때는 자른 사실을 본문 끝에 적는다 — 적지 않으면 「브리핑을 다 봤다」고
# 믿은 채 조각이 빠진 세션이 된다(그게 이 훅이 고치려는 바로 그 실패다).
chars=$(printf '%s' "$out" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
if ((chars > cap)); then
  note="
⚠ 브리핑이 캡(${cap}자)을 넘어 여기서 잘렸다 — 원문 ${chars}자. **잘린 뒤는 못 본 것이다.**
   이어서 보려면: bash scripts/session-brief.sh
   고침은 캡 상향이 아니라 docs-budget.conf 의 *_COMPACT 창 좁히기다."
  keep=$((cap - ${#note} - 16))
  ((keep < 1000)) && keep=1000
  out=$(printf '%s' "$out" | cut -c1-"$keep" 2>/dev/null || printf '%s' "$out")
  # cut -c 는 바이트가 아니라 문자로 센다(LC_ALL 의존) — 넘치면 파이썬으로 정확히 자른다.
  out=$(printf '%s' "$out" | python3 -c '
import sys
s = sys.stdin.read()
n = int(sys.argv[1])
sys.stdout.write(s[:n])
' "$keep" 2>/dev/null || printf '%s' "$out")
  out="${out}${note}"
  echo "브리핑 ${chars}자 > 캡 ${cap}자 — 잘라 주입했다" >&2
fi

printf '%s' "$out" | emit
exit 0
