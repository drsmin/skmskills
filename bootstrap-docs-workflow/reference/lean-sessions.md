# bootstrap-docs-workflow — 세션을 가볍게 (개인 설정)

## Lean sessions — offer, don't impose

The baseline before any work is mostly harness, not docs: claude.ai connectors (tool names + server
instructions), plugins, skill listings. One machine went from 27k to 47k tokens per call at session
start as connectors were added, against a few thousand for the project docs. These are **personal**
choices (who uses Gmail from this repo is not a repo decision), so ask, then write
`.claude/settings.local.json` — policy §7 has the JSON; plugin names come from `claude plugin list`.
Make sure `.claude/settings.local.json` is ignored (add it to `.gitignore` if `git check-ignore` says
no). If a settings file exists, merge keys — never overwrite. Say how to undo: delete the line and
start a new session (connectors have no per-session toggle); plugins come back via `/plugin`.
Rather than hand-editing JSON, edit the `GROUPS` in `scripts/tools-toggle.py` to the names this machine
actually shows and run `python3 -I scripts/tools-toggle.py off <group|all>` (`on` to restore, then `/clear`).
Only three knobs shrink the listing (measured): `skillOverrides: "user-invocable-only"` for skills,
`permissions.deny: ["mcp__<server>"]` for MCP tools (server instructions stay; in remote-control sessions
this is the only thing that works), `enabledPlugins: false` for marketplace plugins. Denying a built-in tool
(Artifact, Workflow…) only blocks calls — its description stays — and claude.ai-synced plugins ignore
`enabledPlugins`. Don't promise savings from those.
