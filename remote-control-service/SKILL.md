---
name: remote-control-service
description: Run `claude remote-control` for a project as an always-on systemd user service (tmux-backed, survives logout and reboot) so the project can be driven from claude.ai/code or the Claude mobile app — add a project, remove/disable one that is finished, restart, list what is running, or attach to its screen. Use when the user asks "리모트 서비스로 띄워줘", "remote-control 서비스 추가/등록", "리모트 서비스 목록", "이 프로젝트 리모트 비활성화/내려줘", "claude-rc", or wants a project reachable from the Claude app without keeping a terminal open.
---

# Remote Control as a systemd user service

Each project runs as one instance of the template unit `claude-rc@.service`:

- **instance name = folder name under `~/projects`** (the unit hard-codes `%h/projects/%i`)
- `ExecStartPre` waits up to 60s for `api.anthropic.com` to resolve (boot-time network race)
- `ExecStart` runs `claude remote-control --name <name> --remote-control-session-name-prefix <name>`
  inside a detached tmux on its **own socket** `tmux -L rc-<name>`, session `main`
- `Type=oneshot` + `RemainAfterExit=yes`: the unit stays `active` even if claude inside tmux exits,
  so "active" alone does not prove it is running — the script also checks the tmux session
- `WantedBy=default.target` + **linger** → starts at boot without anyone logged in

All operations go through `assets/claude-rc.sh` (relative to this skill's base directory). Do not
retype the systemctl commands by hand — that is how `claude-rc@@agent-study-project` (a doubled `@`,
which systemd accepts as a different instance named `@agent-study-project`) got created and had to be
cleaned up manually. The script rejects names containing `@`, `/` or spaces.

## Shell note

From an agent shell (or non-interactive ssh) `XDG_RUNTIME_DIR` is unset and `systemctl --user` fails
with `Failed to connect to bus: No medium found`. The script exports
`XDG_RUNTIME_DIR=/run/user/$(id -u)` itself; if you run systemctl directly, prefix that.

## Commands

```bash
S=<skill base dir>/assets/claude-rc.sh
bash $S setup            # once per machine: install unit, daemon-reload, check tmux/claude/linger
bash $S list             # instances, boot-enabled list, running remote-control processes
bash $S add <project>    # enable --now, then verify the tmux session exists
bash $S remove <project> # disable --now, remove wants symlink, kill its tmux server
bash $S restart <project>
bash $S attach <project> # user-only: interactive tmux (detach: Ctrl-b d)
```

## Procedure

1. **First time on a machine** — run `setup`. If it reports `linger: 꺼짐`, ask the user to run
   `sudo loginctl enable-linger <user>` themselves (needs sudo; do not run it for them). If the
   installed unit differs from the skill's copy, `setup` shows the diff and does **not** overwrite —
   ask the user which one should win.
2. **Add** — confirm the folder name with the user if it is ambiguous, then `add <project>`. The
   session appears in claude.ai/code under that name. If the folder has never been opened in Claude
   Code, claude may be waiting at a first-run prompt (e.g. folder trust); tell the user to check with
   `attach` — you cannot answer an interactive tmux prompt from the agent shell.
3. **Remove** — when a project is finished, `remove <project>`. Report `is-enabled` / `is-active`
   from the output. Processes the project started outside this service (dev servers etc.) are not
   touched — list them and ask before killing.
4. **List** — `list`, then summarize as a table (service · folder · tmux socket · state). Flag any
   `claude-rc@@…` leftovers the script warns about.

Changing the unit itself (paths, flags such as `--permission-mode`, `--spawn`) is a template change
that affects every project: edit `assets/claude-rc@.service` in this skill repo, re-run `setup`, then
`restart` each instance — and commit the skill change.
