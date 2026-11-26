# bootstrap-docs-workflow — 가드 검증 (건너뛰지 않는다)

`SKILL.md` §3 설치 직후 이 파일의 주입을 **전부** 돌린다. 통과만 하는 검사는 커버리지처럼 보여 없는 것보다 나쁘다.

### §B checks, and why each exists

| 검사 | 막는 실패 |
| --- | --- |
| 문자 수 | 줄 수만 보면 **긴 표 행 하나가 예산을 삼키는 것**을 놓친다 |
| 한 줄 길이 | 위와 같은 원인. 한 행에 요약을 밀어넣는 게 실제 비대화 경로였다 |
| 섹션 본문 줄 수 | 섹션 하나가 문서를 삼키는 것 |
| 허용 섹션 목록 | **섹션 스프롤** — 비대화의 1차 경로 |
| 백틱 경로 존재 | 파일을 옮기고 문서를 안 고치면 **허브가 조용히 거짓말한다** |
| `D-번호` 해결 | 없는 결정을 가리키는 참조 |
| 계약 줄 ↔ 상수 | 상한을 **문서만 고쳐** 몰래 올리는 것 |
| 스캔 sanity | 목록·정규식이 0건을 반환해 **검사가 통과처럼 보이며 무의미해지는 것** |

The last one matters most: a guard that silently scans nothing passes forever and reads as coverage.
Structure only — sentence wording, rule order, and whether a rule is *correct* are deliberately not
checked. A guard that reddens on every copy edit gets weakened by the team.

### Then verify the guard actually fires

Non-negotiable. Inject a violation per check and confirm each blocks:

```bash
cp CLAUDE.md /tmp/hub.bak
printf '\n## 몰래 추가한 섹션\n- x\n' >> CLAUDE.md        # 허용 목록 밖 섹션
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
cp /tmp/hub.bak CLAUDE.md

sed -i 's/전체 `4000자`/전체 `99999자`/' CLAUDE.md        # 문서만 상한 올리기
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
cp /tmp/hub.bak CLAUDE.md
bash scripts/check-docs-budget.sh                          # back to green
```

Also worth injecting: a 300-char line, a `docs/` path that doesn't exist, a `D-999` reference, and a
`claude-md-sections.txt` whose entries are all commented out (that last one must fail as
"파싱 0건", not pass silently).

**And the reading-protocol checks specifically** — these are the ones that protect the first line
of defence, so a silent pass here is the most expensive kind:

```bash
sed -i 's/^## ★ Phase 0/## Phase 0/' docs/todo.md          # ★ 마커 제거
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"  # 브리핑이 현재 Phase 를 못 찾는다
git checkout docs/todo.md

printf '\nx\n%.0s' {1..40} >> docs/session-log.md          # 항목 하나를 비대하게
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"  # 총 줄 수는 여전히 초록이다
git checkout docs/session-log.md
```

The second one is the point of the whole unit-vs-total distinction: the file-level cap does **not**
fire, and without the per-entry check the guard reports all-green while the briefing has doubled.

**And the split-layout checks** (skip on a single-file log) — a split that drifts reads as green
unless these fire:

```bash
sed -i '1s/D-001/D-009/' docs/decisions/D-001.md            # 파일 이름 ≠ 첫 헤딩
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
git checkout docs/decisions/D-001.md
printf '\n## D-099. 남은 본문\n\nx\n' >> docs/decisions.md   # split 인데 인덱스 파일에 본문
bash scripts/check-docs-budget.sh; echo "expect 1, got $?"
git checkout docs/decisions.md
```

**And the environment checks** — these catch a guard that judges the same commit differently in a
hook than in your shell, or skips a section without saying so:

```bash
LC_ALL= LANG= bash scripts/check-docs-budget.sh | grep -E '문자 수|브리핑 출력'
bash scripts/check-docs-budget.sh             | grep -E '문자 수|브리핑 출력'   # 두 값이 같아야 한다

chmod -x scripts/session-brief.sh                          # 실행 비트만 빠진 설치
bash scripts/check-docs-budget.sh | grep '브리핑 출력'      # 여전히 재야 한다 (건너뛰면 안 된다)
chmod +x scripts/session-brief.sh
```

If `docs/decisions.md` has no index table, the script hard-fails by design (both layouts) — that table is what the
session-start protocol reads, so its absence breaks the whole scheme.

Finally, run `bash scripts/session-brief.sh` and read the output. It should be a few thousand
characters, end at the index table (no decision bodies, at most `DEC_ROWS` index rows), and print
exactly one todo phase.
