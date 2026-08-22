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

## 수록 스킬

- **bootstrap-docs-workflow** — 새 프로젝트에 Markdown-first / AI-세션-재시작 방법론을 세팅한다.
  `docs/`(current-task·session-log·decisions(D-번호)·todo·recovery·context-budget) + `CLAUDE.md`
  규칙 허브 + **컨텍스트 예산 안전장치**를 스캐폴딩. 프로젝트당 1회. 기존 파일은 덮지 않음(멱등).
  안전장치는 기록 파일이 매 세션 시작 비용을 불리는 것을 막는다 — 핵심은 캡이 아니라 **읽는 양의
  고정**(CLAUDE.md 가 "session-log 최근 3개 / decisions 인덱스만" 처럼 범위를 지정)이고,
  `assets/check-docs-budget.sh` + pre-commit 훅이 2차 방어선이다.
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

**앞의 세 스킬**은 특정 코드베이스에 묶이지 않은 방법론 스킬이라 어떤 프로젝트에서도 쓸 수 있다.
`bootstrap-docs-workflow`(기록 규율) → `bootstrap-screen-manual`(사용 설명서) →
`wrap-up-docs-commit`(마무리) 순으로 물린다.

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
