# bootstrap-docs-workflow — 기존 프로젝트에 처음 도입할 때

이 방법론이 **아직 깔린 적 없는** 기존 저장소용이다. 이미 깔린 설치를 재고 고치는 일(옛 버전 갱신 · 산문뿐인 읽기 범위 · 놓친 회전)은 `context-budget-audit` 이 맡는다.

## 3b. Existing projects — adopt without breaking them

Skip this on a new repo. On an existing one the scaffold is the easy part. Three things break:

1. **The guard goes red on install, and that is correct.** A pre-existing `CLAUDE.md` is almost
   never a hub (one test repo: 133 lines, 7,017 chars, 12 sections → 4 HARDs). Blocking every
   commit from that moment gets the guard removed. So **start in adoption mode**: put
   `BUDGET_MODE=warn` in `scripts/docs-budget.conf`. The verdicts stay identical; only blocking
   waits.
2. **Formats differ, and an unrecognized format reads as green.** English headings
   (`## Entry points`) and ADR-style decisions (`### ADR-001`) used to scan as "0 found, ok". The
   guard now flags both ("진입점 절을 못 찾았다", "결정 형식을 인식하지 못했다"). Answer them in the conf
   (`ENTRY_HEAD`, `DEC_ID`, `DEC_HEAD`) rather than renaming the repo's documents. An ADR repo
   still needs an index table (`| ADR-001 | … |`); that one is a real gap, not a format question.
3. **Migrate `CLAUDE.md` into a hub.** Per section: if it is a rule *source*, move it to
   `docs/<topic>.md` and leave one pointer row in the location index; if it is history or a
   rationale, it becomes a decision. Register the surviving `##` headings in
   `claude-md-sections.txt` and add the contract line. Existing content is the user's, so **show
   the move plan before moving anything.**
4. **Split a single-file decision log.** If `docs/decisions.md` holds the bodies, run
   `bash scripts/split-decisions.sh --dry-run`, show the plan, then run it without the flag. Verify
   nothing was lost (concatenate `docs/decisions/*.md` and diff against the old bodies, ignoring blank
   and `---` lines), run the formatter, and change the `CLAUDE.md` decision rule line to point at
   `docs/decisions/<ID>.md`. The guard then reports `docs/decisions/ … (split …)`.

Then rotate what is over cap (§4 of the policy), and once the guard is all green **flip
`BUDGET_MODE=block` and record it as a decision.** Without the flip, adoption mode becomes permanent
and the guard becomes decoration.

**Flipping is not enough on its own — check what the hard caps still enforce.** Where a repo's
own rule says *past records are never rewritten* (decisions, shipped session entries), the past
cannot be compressed, so the hard cap ends up pinned to the largest thing in history. One repo
flipped to `block` with the decision cap at 260 lines while its longest past decision was 256:
green, blocking, and a brand-new 250-line decision would have sailed through. The fix is not a
tighter cap but **a split between what is enforced and what is merely shown**: set
`DECBODY_FROM=<next number>` so the hard cap applies only from there on; the past stays visible as
soft. Make the headroom table measure the enforced set too — if it reports the historical maximum,
"98%" sits there forever and the only way to make that number fall is to raise the cap.
Axes that rotate (session entries, todo) need none of this: rotation removes the past, so pinning
hard to the post-rotation reality *is* enforcement for new entries.
⚠️ Never bump `DECBODY_FROM` to excuse "just this one" — that one becomes the next baseline.
⚠️ Verify both directions at the boundary: one line over must block, exactly at the cap must pass,
and the historical maximum must stay soft. Then confirm `git commit` itself is refused — a guard's
own exit code is only half the path.

**Upgrading an older install of this skill** is `context-budget-audit`'s job, but the installer
handles its half. A hook from an older version (header `# 자동 생성: scripts/install-hooks.sh`, no
marker) is recognized as its own. If that hook carries extra project checks, the installer refuses
and prints exactly the lines that would be lost; move them to `scripts/pre-commit.d/*.sh`, then
run `bash scripts/install-hooks.sh --migrated`. The old hook is kept as `pre-commit.legacy.bak`.
