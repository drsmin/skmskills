# Claude Code — user skills

전역 Claude Code 스킬 모음. 이 디렉토리는 `~/.claude/skills/` 이며, 여기 있는 스킬은 이 머신의
**모든 프로젝트에서** 별도 설치 없이 사용된다.

원격: <https://github.com/drsmin/skmskills>

## 복구 (새 환경/pod)

이 저장소를 `~/.claude/skills` 로 clone 하면 바로 인식된다.

```bash
git clone https://github.com/drsmin/skmskills.git ~/.claude/skills
```

이미 디렉토리가 있으면 그 안에서 `git pull` 한다. (GitHub HTTPS push 는 토큰 인증이 필요하며,
자격증명·토큰 값은 이 저장소에 남기지 않는다.)

## 전역 규칙 (`global/CLAUDE.md`)

모든 프로젝트·모든 세션에 자동으로 읽히는 `~/.claude/CLAUDE.md` 의 원본. 저장소 밖 파일이라 여기 두고
심볼릭 링크로 잇는다(복구할 때도 같은 한 줄):

```bash
ln -sfn ~/.claude/skills/global/CLAUDE.md ~/.claude/CLAUDE.md
```

지금 담긴 것: 마일스톤 완료 보고의 마지막 줄에 늘 `/clear` 를 권한다.

## 수록 스킬

- **bootstrap-docs-workflow** — 새 프로젝트에 Markdown-first / AI-세션-재시작 방법론을 세팅한다.
  `docs/`(current-task·session-log·decisions(D-번호)·todo·recovery·context-budget) + `CLAUDE.md`
  규칙 허브 + **컨텍스트 예산 안전장치**를 스캐폴딩. 프로젝트당 1회. 기존 파일은 덮지 않음(멱등).
  안전장치는 기록 파일이 매 세션 시작 비용을 불리는 것을 막는다 — 핵심은 캡이 아니라 **읽는 양의
  고정**이고, `assets/check-docs-budget.sh` + pre-commit 훅이 2차 방어선이다.
  ⭐ **읽는 양은 산문이 아니라 `assets/session-brief.sh` 가 자른다.** 예전 판은 CLAUDE.md 에
  "session-log 최근 3개 / decisions 인덱스만" 이라고 *적기만* 했는데, 자를 줄 번호가 없으니
  결국 파일 전체가 읽혔다 — 어느 저장소 실측에서 규칙대로 11,754자 vs 실제 49,654자(**4.2배**),
  그것도 **모든 캡이 초록인 상태**로. 그래서 브리핑 스크립트가 범위를 잘라 출력하고, 가드는
  파일 크기 외에 **브리핑 출력 크기**와 **단위**(로그 항목당·결정당 본문)를 함께 잰다.
  ⭐ **결정은 하나 = 파일 하나**(`docs/decisions/D-NNN.md`, 인덱스는 `docs/decisions.md`). 한 파일이면
  세션 시작은 막아도 결정을 고칠 때마다 파일 전체가 읽힌다(결정 하나 1.3k자 vs 파일 47k자). 가드·브리핑은
  `docs/decisions/` 가 있으면 알아서 split 으로 돌고, 기존 저장소는 `assets/split-decisions.sh` 로 옮긴다.
  회전(session-log 월별 아카이브 · 끝난 todo Phase)은 `assets/rotate-docs.sh` 가 한다 — 전후 내용이 같을 때만 쓴다.
  세션 *안* 비용(정책 §7): `assets/check.sh` 는 게이트를 성공 한 줄·실패 전문으로 돌리고 소스 파일 크기(800 경고·1,500 실패)를 잰다,
  `assets/session-cost.py` 는 세션 기록에서 시작·최대 토큰과 대화를 키운 출력을 뽑는다. 커넥터·플러그인은 개인 설정으로 끈다(§3c).

- **context-budget-audit** — 위의 반대쪽. **이미 깔린** 문서 규율이 실제로 O(1) 인지 재고
  개보수한다. "가이드/규칙에서 토큰이 어디서 낭비되나" 류의 질문에 쓴다. 추정 대신 재는 명령,
  증상→고침 체크표(산문뿐인 읽기 범위 · 총합만 재는 가드 · 이중 읽기 · 회전 규칙 없는 디렉터리 ·
  영원히 안 걸리는 회전 조건 · 자기 상태를 서술하는 문서), 그리고 스크립트는 인라인 대신
  `bootstrap-docs-workflow/assets/` 에서 복사하게 한다. 한 파일로 쌓인 결정 기록을 쪼개는 이전도 맡는다.
- **wrap-up-docs-commit** — 작업 한 단위를 마무리한다. 문서 갱신(session-log·decisions·todo·
  current-task) → 민감정보 스캔 → 커밋(Co-Authored-By) → 즉시 push. bootstrap 의 동반 스킬.
  기록 길이 캡·인덱스 표 갱신·훅 차단 시 회전(우회 금지)·리포 외부 변경 보고까지 안내하므로
  예산 안전장치와 물린다.
- **bootstrap-screen-manual** — **화면 기준 사용 설명서**(`docs/manual/` 위키 — 화면 하나에 문서
  하나)를 심고, **화면·메뉴·권한을 바꾸고 문서를 안 고치면 테스트가 깨지게** 만든다. 문서-화면 대응은
  각 문서 머리의 선언 한 줄이 계약이고, 검사는 **구조만**(문구는 사람이 본다). 라우터·테스트 러너·
  권한 체계 유무에 맞춰 검사를 켜고 끈다.
- **new-webapp-project** — 웹 콘텐츠가 메인인 하이브리드 앱 골격(base)을 복사해 **새 앱
  프로젝트를 세운다.** clone → origin 교체 → SSOT(`project.config.ts`) → 스코프 → `apps/web` →
  게이트 → prebuild → 물려받은 문서 정리. 절반만 된 fork 에서 **이어서 하기**도 된다.
  ⭐ 단계를 스킬에 복사하지 않고 **base 의 `docs/start-new-project.md` 를 읽어서 따른다** —
  base 가 개선될 때 스킬이 조용히 낡는 것을 막는다.
  기본 base: `github.com/drsmin/drs-webapp-base` (다른 base 를 줘도 된다)

- **remote-control-service** — 프로젝트의 `claude remote-control` 을 **systemd 사용자 서비스**로
  상시 띄운다(tmux 안에서, 로그아웃·재부팅 후에도). 템플릿 유닛 `claude-rc@<프로젝트>` 하나에
  `~/projects/<프로젝트>` 하나. 추가·제거(비활성화)·재시작·목록·화면 붙기를 `assets/claude-rc.sh`
  로만 한다 — 손으로 치다 `claude-rc@@x`(@ 두 개 → 다른 인스턴스) 같은 사고가 실제로 났다.
  에이전트 셸에서 `systemctl --user` 가 `No medium found` 로 죽는 문제(`XDG_RUNTIME_DIR`)도 스크립트가 처리.
  linger(`sudo loginctl enable-linger`)는 사용자가 직접 켠다.

**`new-webapp-project` 를 뺀 나머지**는 특정 코드베이스에 묶이지 않은 방법론 스킬이라 어떤
프로젝트에서도 쓸 수 있다. `bootstrap-docs-workflow`(기록 규율) → `bootstrap-screen-manual`
(사용 설명서) → `wrap-up-docs-commit`(마무리) 순으로 물리고, `context-budget-audit` 은
기존 설치를 점검할 때 아무 때나 끼어든다.

**`new-webapp-project` 는 성격이 다르다** — 특정 골격(base)을 전제하는 **부트스트랩 스킬**이다.
base 주소는 인자로 바꿀 수 있고, 위 세 방법론 스킬과 함께 쓴다(그 base 자체가 이미
`bootstrap-docs-workflow` 의 문서 구조를 갖고 있다).

## 새 스킬 추가

각 스킬은 `<name>/SKILL.md` 를 진입점으로 하며, YAML frontmatter(`name`, `description`)로 시작한다.
`description` 에 "언제 쓰는지"(트리거 문구 포함)를 적어야 자동 선택이 잘 된다. 추가·수정 후 커밋·push.

**스크립트는 `<name>/assets/` 에 파일로 둔다** — SKILL.md 에 인라인으로 적으면 에이전트가 매번
재타이핑하면서 조용히 드리프트한다. 실제로 `check-docs-budget.sh` 의 `$(grep -c … || echo 0)` 한 줄이
그런 식으로 점검을 무력화했다(매치 0건일 때 `"0\n0"` 이 되어 비교가 죽고 검사가 건너뛰어짐).
SKILL.md 에는 호출 시 주어지는 base 디렉터리 기준으로 `cp` 하라는 지시와 프롬프트 텍스트만 남긴다.
스크립트를 심는 스킬은 **일부러 깨뜨려 실패를 확인하는 단계**를 반드시 포함한다 — 통과만 하는
검사는 커버리지처럼 보이기 때문에 없는 것보다 나쁘다.
