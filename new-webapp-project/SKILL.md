---
name: new-webapp-project
description: Start a new hybrid app project from a web-first native shell base (drs-webapp-base) — clone the base, set the new remote, fill the SSOT (project.config.ts), rename the scope, scaffold apps/web, run the gates, prebuild, and clean up inherited docs. Use when the user asks to "start a new project", "새 프로젝트 시작", "앱 프로젝트 만들어줘", "base 로 fork 해서 시작", "hybrid 앱 새로 시작", or names the base repo. Also resumes a half-finished fork (it reads fork:check to find what is left). Drives the base's own docs/start-new-project.md rather than restating it, so it never drifts from the base.
---

# Start a new project from the webapp base

이 스킬은 **웹 콘텐츠(Next.js)가 메인인 하이브리드 앱**의 재사용 셸 골격(base)을 복사해
**새 앱 프로젝트 하나를 돌아가는 상태까지** 세운다.

- 기본 base: `https://github.com/drsmin/drs-webapp-base.git` (사용자가 다른 base 를 주면 그것을 쓴다)
- ⭐ **절차의 내용은 base 안의 `docs/start-new-project.md` 가 갖는다.** 이 스킬은 그것을
  **읽고 실행하는 껍데기**다 — 여기에 단계를 다시 적으면 base 가 바뀔 때 조용히 갈라진다.
  clone 직후 그 문서를 읽고, **거기 적힌 순서를 따른다.**

## 0. 시작 전 안전 확인 (건너뛰지 마라)

1. **base 저장소 안에서 실행하면 안 된다.** `git remote get-url origin` 이 base 를 가리키면
   **즉시 멈추고** 사용자에게 알린다 — 그 상태로 진행하면 **base 의 SSOT 를 덮어써서**
   골격 자체를 망친다. (base 를 고치는 작업이라면 이 스킬이 아니다.)
2. **이미 fork 안에 있는가**(origin 이 base 가 아니고 `project.config.ts` 가 있다) →
   **이어서 하기 모드**로 간다: `npm run fork:check` 를 돌려 남은 항목만 처리한다.
3. 새로 시작이라면 **작업 디렉토리가 비어 있거나 새 디렉토리**여야 한다.

## 1. 사용자에게 먼저 물어볼 것

**값을 절대 추측해서 채우지 마라.** 이 골격의 플레이스홀더는 *일부러 틀린 값*이고, 그럴듯한
기본값을 넣는 순간 그게 스토어까지 나간다 — 검사기가 못 잡는 유일한 실패 방식이다.
모르면 플레이스홀더로 **남겨 두고** 무엇이 남았는지 보고한다.

**되돌릴 수 없는 것부터** 묻는다 (스토어 출시 후 변경 불가):

| 물어볼 것                | 예                                      | 비고                                  |
| ------------------------ | --------------------------------------- | ------------------------------------- |
| 앱 표시명                | `우리앱`                                | 스토어·홈화면                         |
| GitHub 저장소            | `myorg/myapp`                           | **먼저 빈 저장소를 만들어 두어야 한다** |
| **iOS 번들 ID / Android 패키지** | `com.myorg.myapp`               | ⚠️ **출시 후 되돌릴 수 없다**          |
| **웹 URL (production)**  | `https://app.example.com`               | ⚠️ **이게 곧 앱의 내용이다**           |
| 딥링크 스킴              | `myapp`                                 | 앱 간 충돌 방지                       |
| 쓸 기능                  | 공유 / 자동 재로그인 / 푸시 / 위치 …    | **켠 것만** 권한이 붙는다             |
| 브랜드 색 (primary·배경·전경) | `#2563EB` …                        | 폴백 화면이 이 조합으로만 그려진다    |

한 번에 다 받으려 하지 말고 **위 표를 보여주고 아는 것부터** 받는다. 기능 토글과 색은 나중에
바꿔도 되지만 번들 ID·웹 URL 은 먼저 확정하는 것이 낫다고 알려준다.

## 2. 실행

clone 하고 **base 의 매뉴얼을 읽은 뒤 그 순서대로** 진행한다.

```sh
git clone <base-url> <dir> && cd <dir>
git remote set-url origin https://github.com/<owner>/<repo>.git
```

그다음 **`docs/start-new-project.md` 를 읽고 따른다.** 대략 이런 흐름이지만
(세부는 그 문서가 authoritative):

1. `nvm use && npm install` → `npm run fork:check` (**실패가 정상** — 그 출력이 할 일 목록이다)
2. `project.config.ts` 채우기 — **고치는 파일은 이것 하나다.** `project.config.schema.ts` 는 건드리지 않는다
3. ⚠️ 값을 다 채웠으면 맨 위 import 를 `import type { ProjectConfig }` 로 바꾼다
   (안 하면 `typecheck` 이 미사용 import 로 실패한다)
4. 스코프·루트 `package.json` 이름 교체 → **`npm install` 재실행**
5. 제품 웹앱을 `apps/web/` 에 (매뉴얼 5절) — 사용자가 지금은 원하지 않으면 건너뛰고 남은 일로 보고
6. 에셋·권한 문구·EAS
7. 검증: `fork:check` 0건 → CI 게이트 전부 → `npx expo prebuild --clean`
8. 문서 정리 (아래 4절)

## 3. 사람이 해야 하는 것 — 대신 하지 말고 멈춰서 알려준다

이것들은 **에이전트가 대신할 수 없다.** 도달하면 무엇을 해야 하는지 알려주고 기다린다.

- **GitHub 빈 저장소 생성** (또는 `gh repo create` 를 쓸지 사용자에게 확인)
- **브랜딩 이미지 파일** — 경로는 고정(`assets/branding/…`)이고 내용은 사람이 넣는다.
  ⚠️ **그럴듯한 아이콘을 생성해 넣지 마라.** 교체를 잊은 채 출시되는 것이 이 골격이 막으려는 것이다
- **`eas login` / `eas init`** — 계정 인증. `projectId` 를 받아 SSOT 에 적는 것까지는 도와도 된다
- **푸시 설정 파일·서명 키** — 🔒 비밀값이다. **커밋하지 않는다** (EAS secrets/credentials)
- **실기기 확인** — 특히 **생체 인증 경로는 시뮬레이터로 검증되지 않는다**

## 4. 물려받은 문서 정리 (base 매뉴얼 11절 = 파일별 처분 표)

**파일마다 처분이 다르다.** 표는 매뉴얼에 있고, 그중 틀리기 쉬운 둘만 여기 못 박는다.

- ⭐ **`docs/decisions.md` 는 남긴다. 번호도 바꾸지 않는다.** 코드 주석이 D-번호를 **수백 곳에서**
  참조하므로(base 실측 561곳) 지우거나 renumber 하면 그 포인터가 전부 허공을 가리킨다.
  새 결정은 **이어서** 번호를 붙인다.
- ⚠️ **`CLAUDE.md` 는 최상단만 고친다.** 맨 위가 "이것은 BASE 프로젝트다 / 어떤 특정 앱도
  아니다"로 시작하는데 **새 앱에서는 사실이 아니다** — 그 절만 이 앱의 성격으로 바꾸고
  **"이 골격의 불변 규칙" 목록은 그대로 남긴다**(그게 골격의 계약이다). 안 고치면 다음 세션이
  **제품 코드를 넣는 것 자체를 규칙 위반으로 오해**한다.

`session-log` 는 비우고(base 저장소 링크만), `current-task` 는 새로 쓰고, `todo` 는 이 제품의
할 일로 바꾼다. 나머지 문서(`fork-guide`·`web-contract`·`code-standards`·`dev-workflow`·
`recovery`·`blueprint`·`start-new-project`)는 **남긴다.**

## 5. 마무리 보고

끝내기 전에 **정확히** 보고한다. 추측으로 "완료"라고 하지 않는다.

- `npm run fork:check` 결과 (0건인가)
- 통과한 게이트 목록, 실패한 것이 있으면 그대로
- `prebuild` 를 돌렸는가 / 실제로 앱을 띄워 봤는가
- **남은 일** — 특히 사람이 해야 하는 것(에셋·EAS·비밀값·실기기)과 아직 안 채운 SSOT 값
- 첫 커밋을 할지 사용자에게 확인한다 (이 골격의 규칙: **커밋·push 는 사용자가 요청할 때**)

## 왜 이 스킬이 단계를 다시 적지 않는가

base 는 **fork 되기 위해** 존재하고 그 절차는 계속 다듬어진다(실제로 리허설로 결함 12건을
잡아 절차를 고쳤다). 스킬이 단계를 복사해 두면 **base 가 개선될 때마다 조용히 낡는다** —
그리고 낡은 절차는 "왜 안 되는지 모르겠다"로 나타난다. 그래서 이 스킬은 **어디서 시작하는지와
무엇을 사람에게 물어야 하는지**만 갖고, 나머지는 clone 한 base 의 문서를 읽어서 따른다.
