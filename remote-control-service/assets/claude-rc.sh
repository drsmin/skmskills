#!/usr/bin/env bash
# claude-rc.sh — `claude remote-control` 를 프로젝트별 systemd 사용자 서비스로 관리한다.
#
#   claude-rc.sh setup            유닛 템플릿 설치 + linger 점검
#   claude-rc.sh add <project>    ~/projects/<project> 를 서비스로 켜고 부팅 시 자동 시작
#   claude-rc.sh remove <project> 멈추고 자동 시작 해제
#   claude-rc.sh restart <project>
#   claude-rc.sh list             인스턴스·자동 시작·실행 중 프로세스
#   claude-rc.sh attach <project> 그 세션의 tmux 화면에 붙는다 (빠져나오기: Ctrl-b d)
#
# 인스턴스 이름 = ~/projects 아래 폴더 이름. 유닛이 %h/projects/%i 로 고정돼 있다.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SELF_DIR/claude-rc@.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_DST="$UNIT_DIR/claude-rc@.service"
WANTS_DIR="$UNIT_DIR/default.target.wants"
PROJECTS_DIR="$HOME/projects"

# 에이전트 셸·ssh 비대화 셸에서는 이게 비어 있어 `systemctl --user` 가
# "Failed to connect to bus: No medium found" 로 실패한다.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

die() { echo "오류: $*" >&2; exit 1; }

# 이름 검사. `claude-rc@@x` 처럼 @ 가 섞이면 systemd 는 '@x' 라는 다른 인스턴스를 만든다
# (실제로 있었던 사고). 그래서 이름에는 @ · / · 공백을 허용하지 않는다.
check_name() {
  local name="${1:-}"
  [ -n "$name" ] || die "프로젝트 이름이 필요하다"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "이름 '$name' 에 허용되지 않는 문자가 있다 (영숫자 . _ - 만, @ 는 붙이지 않는다)"
}

check_unit() {
  [ -f "$UNIT_DST" ] || die "유닛이 설치되지 않았다 — 먼저 '$0 setup'"
}

cmd_setup() {
  mkdir -p "$UNIT_DIR"
  if [ -f "$UNIT_DST" ] && ! cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    echo "기존 유닛이 스킬 판과 다르다 — 차이:"
    diff -u "$UNIT_DST" "$UNIT_SRC" || true
    echo "덮으려면: cp '$UNIT_SRC' '$UNIT_DST' && systemctl --user daemon-reload"
  elif [ ! -f "$UNIT_DST" ]; then
    cp "$UNIT_SRC" "$UNIT_DST"
    echo "설치: $UNIT_DST"
  else
    echo "유닛 최신: $UNIT_DST"
  fi
  systemctl --user daemon-reload

  command -v tmux >/dev/null || echo "경고: tmux 가 없다 — 설치 필요"
  [ -x "$HOME/.local/bin/claude" ] || echo "경고: $HOME/.local/bin/claude 가 없다 — 유닛의 ExecStart 경로를 맞춰야 한다"

  if loginctl show-user "$(id -un)" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "linger: 켜짐 (로그아웃·재부팅 후에도 서비스가 돈다)"
  else
    echo "linger: 꺼짐 — 사용자가 직접 실행해야 한다: sudo loginctl enable-linger $(id -un)"
  fi
}

cmd_add() {
  check_name "${1:-}"; check_unit
  local name="$1"
  [ -d "$PROJECTS_DIR/$name" ] || die "$PROJECTS_DIR/$name 폴더가 없다"
  systemctl --user enable --now "claude-rc@$name.service"
  sleep 2
  systemctl --user is-active "claude-rc@$name.service" >/dev/null \
    || die "켜지지 않았다 — systemctl --user status claude-rc@$name --no-pager"
  if tmux -L "rc-$name" has-session -t main 2>/dev/null; then
    echo "켜짐: claude-rc@$name (tmux -L rc-$name)"
    echo "처음 켠 폴더면 신뢰 확인 같은 질문에 멈춰 있을 수 있다 — '$0 attach $name' 로 확인"
  else
    echo "경고: 서비스는 active 인데 tmux 세션이 없다 — claude 가 바로 종료됐을 수 있다"
    echo "  수동 실행으로 원인 확인: cd $PROJECTS_DIR/$name && claude remote-control --name $name"
  fi
}

cmd_remove() {
  check_name "${1:-}"
  local name="$1"
  systemctl --user disable --now "claude-rc@$name.service" || true
  rm -f "$WANTS_DIR/claude-rc@$name.service"
  if tmux -L "rc-$name" has-session 2>/dev/null; then
    tmux -L "rc-$name" kill-server
  fi
  echo "자동 시작: $(systemctl --user is-enabled "claude-rc@$name.service" 2>/dev/null || echo disabled)"
  echo "상태: $(systemctl --user is-active "claude-rc@$name.service" 2>/dev/null || echo inactive)"
}

cmd_restart() {
  check_name "${1:-}"; check_unit
  systemctl --user restart "claude-rc@$1.service"
  systemctl --user is-active "claude-rc@$1.service"
}

cmd_list() {
  echo "== 인스턴스 =="
  systemctl --user list-units 'claude-rc@*' --all --no-pager --no-legend || true
  echo "== 부팅 시 자동 시작 =="
  ls "$WANTS_DIR" 2>/dev/null | grep '^claude-rc@' || echo "(없음)"
  # @@ 로 잘못 만든 인스턴스 찾기
  if ls "$WANTS_DIR" 2>/dev/null | grep -q '^claude-rc@@'; then
    echo "경고: 'claude-rc@@…' 잘못 만든 인스턴스가 있다 — '$0 remove' 로는 못 지운다:"
    echo "  systemctl --user disable --now 'claude-rc@@<이름>.service'; rm -f '$WANTS_DIR/claude-rc@@<이름>.service'"
  fi
  echo "== 실행 중 remote-control =="
  pgrep -af 'claude remote-control' | grep -v tmux || echo "(없음)"
}

cmd_attach() {
  check_name "${1:-}"
  exec tmux -L "rc-$1" attach -t main
}

case "${1:-}" in
  setup)   cmd_setup ;;
  add)     cmd_add "${2:-}" ;;
  remove)  cmd_remove "${2:-}" ;;
  restart) cmd_restart "${2:-}" ;;
  list)    cmd_list ;;
  attach)  cmd_attach "${2:-}" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
