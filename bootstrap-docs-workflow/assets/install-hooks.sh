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

# 훅 본문은 고정이고, 프로젝트별 검사(생성물 드리프트·린트 등)는 scripts/pre-commit.d/*.sh 에
# 둔다. 검사를 붙이려고 이 스크립트나 훅을 고치면 위의 마커 보호가 같이 사라진다 — 어느
# 저장소에서 그림 드리프트 검사를 붙이며 실제로 그렇게 됐다. 확장 지점이 있으면 고칠 일이 없다.
write_hook() {
  cat > "$HOOK" <<EOF
#!/usr/bin/env bash
$MARKER
# 컨텍스트 예산 점검 + scripts/pre-commit.d/*.sh. 하나라도 실패하면 커밋 차단.
# 우회: git commit --no-verify
ROOT=\$(git rev-parse --show-toplevel)
# 가드 출력은 통과면 마지막 줄만 — 커밋마다 수천 자가 에이전트 대화에 쌓인다(정책 §7).
# 막히거나 경고가 있으면 전문을 보인다.
if [ -f "\$ROOT/scripts/check-docs-budget.sh" ]; then
  out=\$(bash "\$ROOT/scripts/check-docs-budget.sh" 2>&1); rc=\$?
  # ⚠️ \`printf | grep -q\` 로 되돌리지 말 것 — 지금 이 훅엔 pipefail 이 없어 안 터지지만,
  # 한 줄 들어오면 가드 발화가 조용히 사라진다(check.sh · pre-read-size.sh 와 같은 함정).
  if [ "\$rc" -ne 0 ] || grep -q 'soft 권고 초과\|도입 모드' <<<"\$out"; then
    printf '%s\n' "\$out"
  else
    printf '%s\n' "\$out" | tail -1
  fi
  [ "\$rc" -eq 0 ] || exit 1
fi
# 확장 검사는 실행 비트가 아니라 파일 존재로 고른다 — 비트만 빠진 검사가 말없이 건너뛰어지지
# 않게. 검사가 스스로 건너뛸 때는 **건너뛴다고 출력해야 한다**(말없이 통과하는 검사는 없는 것보다 나쁘다).
for f in "\$ROOT"/scripts/pre-commit.d/*.sh; do
  [ -f "\$f" ] || continue
  bash "\$f" || { echo "✗ pre-commit.d/\$(basename "\$f") 실패" >&2; exit 1; }
done
# 명시적으로 끝낸다. 마지막 줄이 \`[ -f x ] && cmd\` 이면 파일이 없을 때 그 종료코드 1 이 훅의
# 종료코드가 되어 **이유 없이 커밋이 막힌다.**
exit 0
EOF
  chmod +x "$HOOK"
}

# 예전 버전이 만든 훅은 마커 없이 이 머리말만 있다. 이걸 못 알아보면 스킬이 **자기가 만든 훅을
# 남의 훅으로 보고** 거부한다(기존 설치본을 갱신하다 실제로 막혔다).
LEGACY_MARK="# 자동 생성: scripts/install-hooks.sh"

# 예전 훅에서 표준 줄(셔뱅·주석·ROOT·가드 호출·exit)을 뺀 나머지 = 프로젝트가 덧붙인 검사.
# 그냥 덮어쓰면 그 검사가 **말없이 사라진다**(그림 드리프트 검사가 실제로 그렇게 빠졌다).
legacy_extras() {
  grep -vE '^[[:space:]]*(#|$)|^ROOT=|check-docs-budget\.sh|^exit [01]$' "$HOOK" || true
}

if [ ! -e "$HOOK" ]; then
  write_hook
  echo "✓ 설치: .git/hooks/pre-commit"
elif grep -qF "$MARKER" "$HOOK" 2>/dev/null; then
  write_hook
  echo "✓ 갱신: .git/hooks/pre-commit (이 스킬이 관리하던 훅)"
elif grep -qF "$LEGACY_MARK" "$HOOK" 2>/dev/null; then
  extras=$(legacy_extras)
  if [ -n "$extras" ] && [ "${1:-}" != "--migrated" ]; then
    echo "⚠ 예전 버전이 만든 훅이다. 그런데 표준 밖의 검사가 덧붙어 있다 — 덮어쓰지 않았다." >&2
    echo "  덮어쓰면 아래 줄이 사라진다:" >&2
    printf '%s\n' "$extras" | sed 's/^/    | /' >&2
    echo >&2
    echo "  이 검사를 scripts/pre-commit.d/<이름>.sh 로 옮긴 뒤 다시 실행한다:" >&2
    echo "    bash scripts/install-hooks.sh --migrated" >&2
    exit 2
  fi
  cp "$HOOK" "$HOOK.legacy.bak"
  write_hook
  echo "✓ 갱신: .git/hooks/pre-commit (예전 버전 훅 — 원본은 pre-commit.legacy.bak)"
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
