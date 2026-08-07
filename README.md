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
  `docs/`(current-task·session-log·decisions(D-번호)·todo·recovery) + `CLAUDE.md` 규칙 허브를
  스캐폴딩. 프로젝트당 1회. 기존 파일은 덮지 않음(멱등).
- **wrap-up-docs-commit** — 작업 한 단위를 마무리한다. 문서 갱신(session-log·decisions·todo·
  current-task) → 민감정보 스캔 → 커밋(Co-Authored-By) → 즉시 push. bootstrap 의 동반 스킬.
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

각 스킬은 `<name>/SKILL.md` 하나로 구성되며, YAML frontmatter(`name`, `description`)로 시작한다.
`description` 에 "언제 쓰는지"(트리거 문구 포함)를 적어야 자동 선택이 잘 된다. 추가·수정 후 커밋·push.
