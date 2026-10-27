#!/usr/bin/env python3
"""안 쓰는 스킬·MCP 도구·플러그인을 시작 컨텍스트에서 빼고, 필요할 때 다시 켠다.

정책: docs/context-budget.md §7. 개인 설정 `.claude/settings.local.json`(git 에 안 올림)만 고친다.
바꾼 뒤엔 /clear 나 새 세션이라야 반영된다. 효과는 `python3 -I scripts/session-cost.py` 의 시작 값으로 잰다.

손잡이 셋 — 듣는 것만 넣었다 (실측 2026-10-27):
  skills    skillOverrides "user-invocable-only" — 모델 목록에선 숨고 /이름 으로는 그대로 부른다.
            스킬 30여 개에 약 1.2천 토큰.
  mcp       permissions.deny "mcp__<서버>" — 그 서버의 도구 목록이 빠진다(커넥터 7개 + 원격 MCP 로 약 1.6만).
            서버 안내문(instructions)은 남는다. 원격 제어 세션은 커넥터를 env·disabledMcpServers 와
            상관없이 실어 오므로 이 deny 가 유일하게 듣는 자리다.
  plugins   enabledPlugins false — 마켓에서 설치한 플러그인. claude.ai 에서 동기화된 플러그인
            (~/.claude/plugins/synced/)은 키가 맞아도 꺼지지 않았다.
듣지 않아서 뺀 것: 내장 도구(Artifact·Workflow·ScheduleWakeup 등)의 permissions.deny — 호출만 막고
설명은 목록에 그대로 실린다. 토큰은 못 줄이고 쓸 일이 생기면 막히기만 한다.

GROUPS 는 예시다 — 프로젝트에서 실제로 보이는 이름으로 고친다. 스킬 이름은 세션 시작의 스킬 목록,
MCP 서버 접두사는 도구 이름(mcp__<서버>__<도구>)에서 가져온다.

사용:
  python3 -I scripts/tools-toggle.py                 # 그룹별 상태
  python3 -I scripts/tools-toggle.py off all         # 전부 끈다
  python3 -I scripts/tools-toggle.py on connectors   # 그룹 하나를 다시 켠다
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".claude/settings.local.json"

A = "anthropic-skills:"
GROUPS = {
    "artifact": {"skills": ["artifact-design", "artifact-diagramming", "artifact-capabilities", "dataviz"]},
    "workflow": {"skills": ["workflow-authoring", "loop", "schedule"]},
    "office": {
        "skills": [A + s for s in (
            "docx", "pdf", "pptx", "xlsx", "docs", "google-workspace", "doc-coauthoring",
            "canvas-design", "algorithmic-art", "slack-gif-creator", "theme-factory",
            "brand-guidelines", "web-artifacts-builder", "internal-comms", "mcp-builder",
            "skill-creator", "deep-research")],
    },
    "misc": {"skills": ["plugin-authoring", "claude-api", "keybindings-help", "fewer-permission-prompts",
                        "init", "security-review"]},
    "connectors": {
        "mcp": ["mcp__claude_ai_Gmail", "mcp__claude_ai_Notion", "mcp__claude_ai_Slack",
                "mcp__claude_ai_Google_Calendar", "mcp__claude_ai_Google_Drive",
                "mcp__claude_ai_Claude_Docs", "mcp__claude-code-remote"],
    },
    # "plugins": {"plugins": ["<이름>@<마켓>"]},   # claude plugin list 로 이름을 본다
}


def load(p):
    return json.loads(p.read_text()) if p.exists() else {}


def save(p, d):
    p.parent.mkdir(exist_ok=True)
    p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")


def state(g, local):
    spec = GROUPS[g]
    deny = set(local.get("permissions", {}).get("deny", []))
    sk = local.get("skillOverrides", {})
    pl = local.get("enabledPlugins", {})
    checks = ([t in deny for t in spec.get("mcp", [])]
              + [sk.get(s) == "user-invocable-only" for s in spec.get("skills", [])]
              + [pl.get(p) is False for p in spec.get("plugins", [])])
    return "off" if all(checks) else "on" if not any(checks) else "일부"


def apply(g, off, local):
    spec = GROUPS[g]
    deny = local.setdefault("permissions", {}).setdefault("deny", [])
    for t in spec.get("mcp", []):
        if off and t not in deny:
            deny.append(t)
        if not off and t in deny:
            deny.remove(t)
    sk = local.setdefault("skillOverrides", {})
    for s in spec.get("skills", []):
        if off:
            sk[s] = "user-invocable-only"
        else:
            sk.pop(s, None)
    pl = local.setdefault("enabledPlugins", {})
    for p in spec.get("plugins", []):
        if off:
            pl[p] = False
        else:
            pl.pop(p, None)
    for k in ("skillOverrides", "enabledPlugins"):
        if not local[k]:
            del local[k]
    if not local["permissions"]["deny"]:
        del local["permissions"]["deny"]
    if not local["permissions"]:
        del local["permissions"]


def main(argv):
    local = load(LOCAL)
    if len(argv) == 2 and argv[0] in ("on", "off"):
        names = list(GROUPS) if argv[1] == "all" else [argv[1]]
        if any(n not in GROUPS for n in names):
            sys.exit(f"그룹 없음: {argv[1]} — {', '.join(GROUPS)}")
        for n in names:
            apply(n, argv[0] == "off", local)
        save(LOCAL, local)
        print(f"{argv[0]}: {', '.join(names)} — /clear 나 새 세션부터 반영된다")
    elif argv:
        sys.exit(__doc__)
    for g in GROUPS:
        print(f"  {state(g, local):4} {g}")


if __name__ == "__main__":
    main(sys.argv[1:])
