#!/usr/bin/env bash
#
# 큰 파일 Read 차단
#
# Claude Code 의 PreToolUse(Read) 훅으로 붙는다(`.claude/settings.json`). Read 대상 파일의 크기를
# 보고, 이미지가 캡을 넘으면 **막고 자르는 방법을 알려준다**.
#
# 왜 필요한가: 「화면 사진을 통째로 Read 하지 말 것」을 CLAUDE.md 에 적어 둔 **뒤에도** PNG 5장이
# 1,777,896자(= 그 세션 도구 결과의 21%)로 들어왔다(실측). **산문 금지는 지켜지지 않는다** —
# 규칙이 옳아도 집행 형태가 틀리면 그만이다. 기계가 잘라야 한다.
#
# ⚠️ 이미지는 **막는다**(hard). 한 장이 수십만 자라 「경고 후 통과」는 이미 비용을 다 낸 뒤다.
# ⚠️ 텍스트는 **알리기만** 한다 — 큰 소스를 한 번 통째로 읽는 것이 정답인 경우가 있고,
#    hard 로 막으면 결국 훅을 끄게 된다(`SRC_HARD=0` 과 같은 판단이다).
# ⚠️ 캡은 `scripts/docs-budget.conf` 에 있다 — 여기 박으면 가드를 갱신할 때 사라진다.
set -uo pipefail

payload=$(cat)

root=${CLAUDE_PROJECT_DIR:-}
if [[ -z $root ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
READ_IMAGE_HARD=0
READ_TEXT_SOFT=0
READ_IGNORE=''
TEST_PATH=''
CONF="$root/scripts/docs-budget.conf"
# shellcheck disable=SC1090
[[ -f $CONF ]] && . "$CONF"
# ⚠️ PATH 접두는 **conf 의 `TEST_PATH`** 에서 온다 — 여기 박지 말 것(갱신 때 사라진다).
#    node 가 시스템에 없는 환경(conda 등)에서 아래 폴백 경로가 쓴다.
[[ -n $TEST_PATH ]] && export PATH="$root/$TEST_PATH:$PATH"

# 둘 다 꺼져 있으면 할 일이 없다.
if ((READ_IMAGE_HARD == 0 && READ_TEXT_SOFT == 0)); then exit 0; fi

# ① 값싼 추출 — 이 훅은 **Read 호출마다** 돈다. node 를 띄우면 호출당 ~150ms 라
#    먼저 셸로 긁고, 못 긁었을 때만 node 로 정확히 본다(따옴표가 escape 된 경로 등).
path=$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p' <<<"$payload" | head -1)
if [[ -z $path ]]; then
  command -v node >/dev/null 2>&1 || exit 0 # node 없이는 더 못 본다 — Read 를 막지 않는다
  path=$(printf '%s' "$payload" | node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      try {
        const j = JSON.parse(s);
        process.stdout.write(String(j?.tool_input?.file_path ?? ""));
      } catch {
        /* 파싱 실패 → 빈 경로 → 통과 (훅 자체가 도구를 막지 않는다) */
      }
    });
  ')
fi

[[ -n $path && -f $path ]] || exit 0
# 여기서부터는 알릴 일이 생겼을 때만 node 가 필요하다(위 ①은 셸로 끝낸다).
if [[ -n $READ_IGNORE ]] && grep -Eq "$READ_IGNORE" <<<"$path"; then exit 0; fi

# 범위를 지정한 Read(offset/limit · pages)는 이미 잘라 읽는 것이다 — 막지 않는다.
if printf '%s' "$payload" | grep -Eq '"(offset|limit|pages)"[[:space:]]*:'; then exit 0; fi

bytes=$(wc -c <"$path" | tr -d ' ')

trace() { # $1 = allow|deny|note · $2 = 한 줄 설명
  printf '%s\t%s\t%s\n' "$(date -Is)" "$1" "$2" >>"$root/.git/pre-read-size.log" 2>/dev/null || true
}

deny() { # $1 = 사람과 모델에게 보일 이유
  trace deny "$(printf '%s' "$1" | head -1)"
  HOOK_REASON=$1 node -e '
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: process.env.HOOK_REASON,
      },
      systemMessage: "큰 파일 Read 가드가 막았다 (scripts/hooks/pre-read-size.sh)",
    }));
  '
  exit 0
}

case ${path,,} in
*.png | *.jpg | *.jpeg | *.gif | *.webp | *.bmp | *.pdf)
  if ((READ_IMAGE_HARD > 0 && bytes > READ_IMAGE_HARD)); then
    deny "이 파일은 ${bytes}바이트로 Read 캡(${READ_IMAGE_HARD})을 넘는다 — 통째로 읽으면 **대략 $((bytes * 133 / 100))자**가 대화에 들어온다(base64 로 1.33배 — 아주 큰 그림은 하네스가 줄여 더 적을 수 있다)(실측: PNG 5장 = 1,777,896자 = 한 세션 도구 결과의 21%).

**필요한 영역만 잘라서** 작게 본다:
\`\`\`
python3 -c \"from PIL import Image; im=Image.open('$path'); im.crop((0,0,im.width,400)).resize((im.width//2,200)).save('/tmp/crop.png')\"
\`\`\`
그리고 \`/tmp/crop.png\` 를 Read 한다. 크기만 알고 싶으면 \`python3 -c \"from PIL import Image; print(Image.open('$path').size)\"\`.
캡은 \`scripts/docs-budget.conf\` 의 \`READ_IMAGE_HARD\` 다 — ⚠️ **올려서 풀지 말 것**."
  fi
  ;;
*)
  if ((READ_TEXT_SOFT > 0 && bytes > READ_TEXT_SOFT)); then
    trace note "soft ${bytes}B $path"
    HOOK_CTX="⚠ ${path} 는 ${bytes}바이트다 — 통째로 읽기 전에 범위를 좁힐 수 있는지 본다(\`sed -n\`, Read 의 offset/limit, \`grep -n\`). 캡은 scripts/docs-budget.conf 의 READ_TEXT_SOFT." \
      node -e '
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: process.env.HOOK_CTX,
        },
      }));
    '
    exit 0
  fi
  ;;
esac

exit 0
