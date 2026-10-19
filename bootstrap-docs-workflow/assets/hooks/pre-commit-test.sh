#!/usr/bin/env bash
#
# 커밋 전 테스트 강제
#
# Claude Code 의 PreToolUse(Bash) 훅으로 붙는다(`.claude/settings.json`). 표준입력으로 훅 JSON 을
# 받아 **그 Bash 명령이 커밋인지** 보고, 커밋이면 테스트를 돌려 실패 시 도구 호출을 막는다.
#
# 왜 필요한가: "커밋 전에 테스트" 가 산문 규칙뿐이면 한 번 빠뜨렸을 때 깨진 채로 커밋된다.
# 산문은 지켜지지 않는다 — 커밋 경로에 기계를 놓는다.
#
# ⚠️ **git 훅(`core.hooksPath`)을 고르지 말 것** — 클론마다 사람이 설정해야 해서, 안 하면
#    「있는 것처럼 보이는데 아무것도 안 하는」 가드가 된다. `.claude/settings.json` 은 커밋되므로
#    이 프로젝트에서 여는 모든 세션에 자동으로 붙는다.
#
# ⚠️ 도구가 없으면 **조용히 넘기지 않는다** — 무엇을 못 봤는지 말하고 막는다
#    (조용히 덜 검사하는 가드는 초록불을 거짓으로 만든다 — 없는 것보다 나쁘다).
# ⚠️ 되돌리는 스위치를 두지 않았다 — 두면 그게 기본 경로가 된다. 정말 막힌 경우엔 사람이
#    `/hooks` 로 끄거나 `.claude/settings.json` 을 고친다(그 판단은 사람 몫이다).
set -uo pipefail

payload=$(cat)

# ① 값싼 선별 — 페이로드에 `commit` 이라는 글자조차 없으면 커밋일 수 없다(Bash 호출마다 도는 자리라
#    node 를 띄우지 않고 여기서 끝낸다).
case $payload in
*commit*) ;;
*) exit 0 ;;
esac

root=${CLAUDE_PROJECT_DIR:-}
if [[ -z $root ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
# ⚠️ 러너·PATH 는 **`scripts/docs-budget.conf` 에 둔다** — 여기 박으면 가드를 갱신할 때 사라진다.
#    TEST_CMD    커밋 전에 돌릴 명령 (기본 `yarn test`)
#    TEST_PATH   그 명령을 찾을 추가 PATH 접두 (예: 시스템 Node 가 없고 conda 로 깐 환경)
TEST_CMD='yarn test'
TEST_PATH=''
CONF="$root/scripts/docs-budget.conf"
# shellcheck disable=SC1090
[[ -f $CONF ]] && . "$CONF"
[[ -n $TEST_PATH ]] && export PATH="$root/$TEST_PATH:$PATH"

have_node=0
if command -v node >/dev/null 2>&1; then have_node=1; fi

# ② 정확히 어떤 명령인가. node 가 있으면 `tool_input.command` 만 본다(설명문에 든 "git commit" 에
#    끌려가지 않는다). 없으면 페이로드째로 보고 — 어차피 아래에서 막힌다.
if ((have_node)); then
  cmd=$(printf '%s' "$payload" | node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const j = JSON.parse(s);
        process.stdout.write(String(j?.tool_input?.command ?? ""));
      } catch {
        /* 파싱 실패 → 빈 문자열 → 커밋 아님으로 본다(훅 자체가 도구를 막지 않는다) */
      }
    });
  ')
else
  cmd=$payload
fi

# `git commit` · `git -C /path commit` · `git --no-pager commit` 을 잡고, `git log --grep commit`
# 처럼 하위 명령이 끼는 것은 잡지 않는다. 복합 명령(`git add -A && git commit …`)도 걸린다.
if ! grep -Eq '(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' <<<"$cmd"; then
  exit 0
fi

# ⚠️ **다른 저장소의 커밋은 막지 않는다.** 이 가드는 「이 프로젝트의 테스트가 통과하는가」를 보는
# 것이므로, `/tmp` 의 임시 저장소나 다른 프로젝트를 이 테스트로 판정하면 틀린 판정이다(실제로 반입
# 왕복 시늉의 임시 clone 커밋이 막혔다 — 실제로 겪었다). 명령이 프로젝트 밖을 가리키면 통과.
for target in $(grep -oE '(^|[;&|][[:space:]]*)cd[[:space:]]+[^;&|[:space:]]+|git[[:space:]]+-C[[:space:]]+[^;&|[:space:]]+' <<<"$cmd" |
  sed -E 's/.*(cd|-C)[[:space:]]+//'); do
  case $target in
  /*) abs=$target ;;
  *) abs=$root/$target ;;
  esac
  # 프로젝트 안(또는 그 하위)이 아니면 남의 저장소다.
  case $abs in
  "$root" | "$root"/*) ;;
  *) exit 0 ;;
  esac
done

# **흔적을 남긴다** — 훅이 「로드됐는지」는 하네스 안에서 관측할 수 없고(세션 시작 때 설정이 있어야
# 로드된다), 안 걸리면 아무 일도 안 일어나므로 **조용히 안 지켜지는** 상태와 구별이 안 된다.
# `.git/` 안이라 커밋에 섞이지 않는다. 확인: `tail -3 .git/pre-commit-test.log`
trace() { # $1 = allow|deny|skip · $2 = 한 줄 설명
  printf '%s\t%s\t%s\n' "$(date -Is)" "$1" "$2" >>"$root/.git/pre-commit-test.log" 2>/dev/null || true
}

deny() { # $1 = 사람과 모델에게 보일 이유
  trace deny "$(printf '%s' "$1" | head -1)"
  if ((have_node)); then
    HOOK_REASON=$1 node -e '
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: process.env.HOOK_REASON,
        },
        systemMessage: "커밋 전 테스트 가드가 커밋을 막았다 (scripts/hooks/pre-commit-test.sh)",
      }));
    '
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2 # node 가 없을 때의 차단 경로(stderr 가 모델에게 전달된다)
}

runner=${TEST_CMD%% *}
if ((!have_node)) || ! command -v "$runner" >/dev/null 2>&1; then
  deny "커밋 전 \`$TEST_CMD\` 를 돌려야 하는데 이 셸에서 \`$runner\` 를 찾지 못했다 — **테스트를 못 본 채로는 커밋하지 않는다**.
환경 복구 절차는 \`docs/recovery.md\` 에 있다(PATH 가 필요하면 conf 의 \`TEST_PATH\`)."
fi

if ! out=$(cd "$root" && eval "$TEST_CMD" 2>&1); then
  deny "커밋 전 \`$TEST_CMD\` 가 실패해서 커밋을 막았다. 고친 뒤 다시 커밋한다 (마지막 30줄):

$(printf '%s\n' "$out" | tail -30)"
fi

# ⚠️ 건너뛴 테스트가 있으면 vitest 가 `Tests  627 passed | 1 skipped (628)` 로 찍는다 —
#    `passed \(` 만 보던 정규식은 그때 **빈 값**을 남겼다(로그가 있는데 건수가 없어, 훅이 실제로
#    돌았는지 확인하는 유일한 단서가 반쪽이 됐다 — 실제로 겪었다).
#    `skipped`·`todo`·`failed` 가 섞여도 마지막 괄호까지 통째로 집는다.
trace allow "$(printf '%s\n' "$out" | grep -oE 'Tests +[0-9]+ passed[^(]*\([0-9]+\)' | tail -1)"
exit 0
