#!/usr/bin/env bash
# git 훅 설치 — bootstrap-docs-workflow 스킬이 설치.
# .git/hooks 는 커밋되지 않으므로 클론할 때마다 실행해야 한다 (docs/recovery.md 재개 절차 참고).
# 기존 훅이 있으면 덮어쓰지 않는다.
set -euo pipefail

MARKER="# managed-by: bootstrap-docs-workflow"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "git 저장소가 아니다 — 훅을 설치할 수 없다." >&2
  exit 1
}
HOOKS="$ROOT/.git/hooks"
HOOK="$HOOKS/pre-commit"
mkdir -p "$HOOKS"

write_hook() {
  cat > "$HOOK" <<EOF
#!/usr/bin/env bash
$MARKER
# 컨텍스트 예산 점검. hard 초과 시 커밋 차단. 우회: git commit --no-verify
ROOT=\$(git rev-parse --show-toplevel)
[ -f "\$ROOT/scripts/check-docs-budget.sh" ] || exit 0
bash "\$ROOT/scripts/check-docs-budget.sh"
EOF
  chmod +x "$HOOK"
}

if [ ! -e "$HOOK" ]; then
  write_hook
  echo "✓ 설치: .git/hooks/pre-commit"
elif grep -qF "$MARKER" "$HOOK" 2>/dev/null; then
  write_hook
  echo "✓ 갱신: .git/hooks/pre-commit (이 스킬이 관리하던 훅)"
else
  # 사용자/다른 도구가 만든 훅이다. 덮어쓰면 그 로직이 사라진다.
  echo "⚠ .git/hooks/pre-commit 이 이미 있고 이 스킬이 만든 것이 아니다 — 덮어쓰지 않았다." >&2
  echo "  기존 훅에 아래 두 줄을 직접 추가하면 된다:" >&2
  echo >&2
  echo '    ROOT=$(git rev-parse --show-toplevel)' >&2
  echo '    bash "$ROOT/scripts/check-docs-budget.sh" || exit 1' >&2
  echo >&2
  echo "  또는 수동 점검: bash scripts/check-docs-budget.sh" >&2
  exit 2
fi

echo "  hard 초과 시 커밋이 막힌다. 우회는 git commit --no-verify"
