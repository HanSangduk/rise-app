---
id: P66
title: 센터 선택 가입 요청 · 법정 문서/계약서의 센터 차원 · 최초 superadmin 시딩
status: 완료
domain: cross
created: 2026-09-06
completed: 2026-09-06
---

# P66 — 멀티센터 마무리: 센터 선택 · 센터별 법정 문서

## 목표 (람 요청)
1. `richramsang@gmail.com`을 최초 superadmin으로 시딩.
2. **미등록 번호의 가입 요청**이 센터 목록에서 고른 센터로 가게 한다(종전: 기본 센터 고정).
3. **개인정보처리방침·계약서가 각 센터의 내용**으로 나오게 한다.

## 진행 단계
- [x] superadmin 시딩(프로덕션)
- [x] 백엔드: `GET /v1/join/centers` · 가입 요청 center_id 검증 · 공개 문서 `?center=` (계약 v2.33)
- [x] 앱: 대기실 센터 선택 · 법정 문서 링크의 센터 파라미터
- [x] 법정 문서 HTML 6장: `?center=` 전달 + 같은 폴더 링크 승계
- [x] 검증(백엔드 뮤테이션 8/8 · 앱 뮤테이션 4/4 · 로컬 E2E · 앱 1377 pass · 아카이브)

## 결정 사항

### D1. superadmin은 **owner와 다른 계정**이어야 한다
`richramsang@gmail.com`은 Firebase에 계정이 없었고 기존 owner(`uu8q8…`)와도 겹치지 않아 그대로
만들었다. 겹쳤다면 만들지 않고 보고했을 것이다 — UserIndex는 uid당 역할 1개라 owner 계정을
superadmin으로 올리면 **그 사람이 자기 센터 어드민에서 잠긴다**(superadmin은 `/v1/admin/*` 외 403).
비밀번호는 32자 난수로 만들고 **그 자리에서 버렸다**. 첫 로그인은 어드민 로그인 화면의
비밀번호 재설정이다(신규 센터 owner와 같은 경로 — `EnsureUser`도 아무도 모르는 임시 비밀번호를 쓴다).

### D2. 센터 선택 — 봉인을 "여는" 것이 아니라 **조건이 갖춰진 것**
`JoinRequestCreate`가 바디 `center_id`를 무시해 온 이유는 코드 주석이 이미 적어 뒀다: 열 조건
셋(① 신원 등록 센터 2곳 이상 ② 회원이 읽을 목록 ③ 실재 검증) 중 ②·③이 없었기 때문이다.
이번에 ②(`GET /v1/join/centers`)와 ③(`resolveJoinCenter`)을 만들었고, ①은 런타임 조건이라
**앱이 목록 길이로 판단한다**(2곳 미만이면 선택 UI를 그리지 않는다).
신뢰 경계는 그대로다 — **고를 수는 있어도 만들 수는 없다**(목록에 없으면 400).

설계04 §4의 "앱에서 센터를 고르게 하지 말라"는 권고는 **전제가 바뀌어 갱신됐다**: 그 권고의
근거는 (a) 고를 데이터가 없다 (b) 오선택 경로가 생긴다 (c) 타 센터가 노출된다였는데, (a)는
Center 엔티티로 해소됐고 (b)는 대표 승인이 최종 관문이며 (c)는 초대 코드/QR의 대안이 **센터마다
인쇄물을 두는 물리적 준비**를 요구해 v1에 비현실적이다. 고르지 않으면 **모든 요청이 1호점 큐로
가서 2호점은 신규 회원을 영영 못 받는다** — 그 손해가 (c)보다 크다.

### D3. 상호가 빈 센터도 목록에 남긴다
`ListCenters`는 상호 미등록 문서를 유령으로 거르는데 **1호 고객이 그 상태다**. 걸러 버리면
그 센터를 고를 방법이 사라져 기존 신규 회원의 가입 경로가 통째로 막힌다. `name: ""`로 실어
보내고 앱이 폴백 라벨로 그린다. 목록에 이름 없는 항목이 보이는 것은 정상이 아니라
**미완 상태의 노출**이고, 그 센터가 상호를 등록하면 저절로 사라진다.

### D4. 모르는 센터는 **404**지 기본 센터가 아니다
공개 문서 endpoint에서 `?center=모름`을 기본 센터로 접으면 **남의 사업자 정보를 그 센터의
법정 고지로 인쇄한다.** 개인정보처리방침·계정 삭제 안내에서 그것은 오표기가 아니라 거짓 고지다.
404를 주면 문서가 자기 자리표시자를 유지한다(HTML의 `catch`가 이미 그렇게 동작한다).

### D5. 법정 문서 링크는 센터를 **승계**한다
문서 5장 + 지원 페이지가 같은 폴더 링크에 `?center=`를 붙인다. 승계하지 않으면 회원이
이용약관에서 개인정보처리방침으로 한 번 넘어가는 순간 **다른 센터의 고지**를 읽는다.

### D6-b. 앱 스토어 방침은 **운영자 것**이어야 한다 (람 지적, 2026-09-06 추가)
람: "앱 심사에 올릴 개인정보처리방침은 내가 배포하는 거니까 라이즈 사업자 정보와는 상관없지 않나."
**절반 맞다.** 스토어 URL은 앱의 속성이고 그 앱은 여러 센터가 함께 쓴다 — 특정 센터 하나를
개인정보처리자로 선언한 문서를 거기 걸면 두 번째 센터 회원에게 거짓 고지가 된다. 그래서 스토어
URL은 **운영자 방침**으로 바꿨다.

**나머지 절반**: "사업자 정보와 무관"은 아니다. 주체가 라이즈에서 한상덕으로 바뀔 뿐,
**누가 처리하고 보호책임자 연락처가 무엇인지**는 여전히 필수 기재다(법 제30조). 사업자등록번호는
필수 기재가 아니라 **개인 명의로 게시할 수 있다** — 람의 판단대로 개인 실명(한상덕) +
richramsang@gmail.com으로 작성했다.

그리고 센터가 사라지는 게 아니라 **층이 둘로 나뉜다**: 회원권·수업·건강기록은 센터가 자기
목적으로 처리하므로 센터도 처리자다. 이번에 만든 센터별 문서(v2.33)는 버려지는 게 아니라
**둘째 층**이 되고, 비어 있던 **첫째 층**(운영자 방침)을 이번에 만들었다.

### D6. 계약서는 **이미 옳았다**
`gatherContractVars(ctx, centerID, …)`의 두 호출부가 모두 `p.CenterID`를 넘긴다. 계약서에 남의
사업자 정보가 인쇄될 경로는 없었다 — 확인만 하고 손대지 않았다.

## 변경 파일
| 파일 | 무엇을 |
|---|---|
| (프로덕션) Firebase Auth + Firestore `users/qepE1pJJ…` | superadmin 계정 생성 · 인덱스 `{role:"superadmin", center_id:""}` |
| `backend/internal/api/service_center_directory.go` **신설** | `JoinCenters`·`resolveJoinCenter`·`knownCenter`·`resolvePublicCenter` |
| `backend/internal/api/service.go` | `PublicBusiness`/`PublicCenter`에 centerID 인자 · `JoinRequestCreate`가 선택 센터 사용 |
| `backend/internal/api/handlers_me.go`·`handlers_admin.go`·`router.go` | `?center=` 전달 · `JoinCenters` 핸들러 · `GET /v1/join/centers` |
| `backend/internal/api/service_center_directory_test.go` **신설** | 8 케이스(목록·익명 차단·선택 큐 분리·정규화·센터별 사업자 정보·404·폴백) |
| `backend/internal/api/service_test.go` | 봉인 테스트를 새 불변식으로 개정(무시 → 거부) |
| `admin/public/legal/*.html` 6장 (+dist) | `?center=` API 전달 · 같은 폴더 링크 승계 |
| `app/lib/core/config/legal_links.dart` | `forCenter(url, centerId)` |
| `app/lib/features/my/presentation/widgets/legal_links_card.dart` | 세션 센터로 4행 주소 생성 · `legalRowsFor` 순수 함수 분리 |
| `app/lib/features/auth/**` (data·domain·presentation) | `fetchJoinCenters` · `CenterDirectory` · `joinCentersProvider` · `requestJoin(centerId)` · `_CenterPicker` |
| `app/lib/core/api/dto/join_dto.dart` | `CenterDirectoryDto`(코드젠 없는 평범한 DTO — 이유 주석) |
| `app/test/**` 6파일 | 페이크에 `fetchJoinCenters` · ProviderScope · 센터 선택 4건 · 센터별 고지 3건 |
| `app/pubspec.yaml` | `1.0.0+4` → `1.0.0+5` |
| `admin/public/legal/app-privacy.html` **신설** (+dist) | **앱 운영자(한상덕) 개인정보처리방침** — 스토어 등록 방침. 처리 주체 2층 구조 · 운영자가 직접 처리하는 3항목 · 권한 · 위탁(Google) · 권리행사 · 보호책임자(한상덕/richramsang@gmail.com) · 만14세 · 개정 이력. **자리표시자 0개**(센터 방침과 달리 초안 배너가 없다) |
| `admin/public/legal/index.html` | 운영자 방침 카드(00) 추가 · 센터 방침 카드를 "(센터)"로 명시 |
| `app/lib/core/config/legal_links.dart`·`legal_links_card.dart` | `appPrivacy` 링크 추가(센터 파라미터 없음 — 운영자는 하나뿐) · 마이 탭 5행 |
| `store/metadata/appstore.md` | 개인정보처리방침 URL → `legal/app-privacy.html`(교체 이유 주석) |
| `docs/API계약_v1.md` | **v2.33** 신설 |
| `backend/README.md` | v2.33 요약 |

## 검증
- **백엔드**: `go build` · `go test ./...` 전 패키지 · `-race` 그린. **뮤테이션 8/8 kill**
  (선택 무시 회귀 · 미지 센터 검증 제거 · 공개문서 미지센터 폴백 · PublicBusiness 기본센터 고정 ·
  PublicCenter 폴백 출처 · 목록에서 기본센터 제외 · 익명 차단 제거 · 센터 ID 정규화 제거).
- **앱**: `flutter analyze` 0 · `flutter test` **1377 pass**. **뮤테이션 4/4 kill**
  (선택 무시 전송 · 미선택 가드 제거 · 1곳일 때 선택 UI 노출 · 법정 문서에서 센터 제거).
- **로컬 E2E**(dev 백엔드 :8098, 실제 HTTP): 2호점 생성 → 신규 uid가 `GET /v1/join/centers`로
  두 센터 수신(기본 센터는 `name:""` 그대로) → 2호점을 골라 가입 요청 → **2호점 큐에만 뜬다**
  (1호점 큐 0건) → 없는 센터 400 → 2호점 사업자 정보 저장 → `?center=gangnam-2` = "강남2 스포츠",
  파라미터 없음 = "라이즈 컨디셔닝", 없는 센터 404.
- **아카이브 1.0.0 (5)**: 검사 스크립트 전 항목 ✓. 바이너리에 새 코드 실증 —
  `/v1/join/centers`·`?center=` 각 1건, "어느 센터에 요청할까요?"·"센터를 선택해주세요" UTF-16 각 1건.
  **IPA 자동 내보내기는 실패**(`No Account for Team` — 이 환경에 Xcode 계정 세션이 없다).
  P60에서 넣은 IPA 신선도 가드가 그것을 조용히 넘기지 않고 exit 1로 잡았다.
  아카이브는 `~/Library/Developer/Xcode/Archives/2026-09-06/Runner 1.0.0 (5) P66.xcarchive`에 배치.
- **어드민**: `tsc --noEmit` 0 · `npm run build` 성공. 화면 문구를 실제 설정 라벨("센터 신원")과 대조해 정정.
- **프로덕션 배포 후 실검증**(2026-09-06): 백엔드 `rize-api-00031-pxv` → `?center=rise` 200 ·
  `?center=nope` 404 · `/v1/join/centers`·`/v1/admin/centers` 무인증 401 · health 200.
  Hosting → 법정 문서 6장 `qsCenter`·링크 승계 각 1건, 어드민 번들에 센터 관리 화면.
  superadmin 실로그인 → `/v1/me` superadmin · `/v1/admin/centers` 200 · `/v1/members` 403.
- **운영자 방침 라이브 실측**: `legal/app-privacy.html` 200 · 14,964B · "한상덕" 5건 ·
  `richramsang@gmail.com` 2건 · **자리표시자 "(미정)" 0건**(센터 방침과 달리 초안 배너가 없어
  스토어 URL로 바로 쓸 수 있다) · 색인 카드 링크 1건.
- **아카이브 1.0.0 (6)**: 검사 전 항목 ✓ · 바이너리에 `app-privacy.html`(ascii 1) ·
  "앱 개인정보처리방침 (운영자)"·"개인정보처리방침 (센터)"(UTF-16 각 1) 실증. 앱 1377 pass.
- **법정 문서 HTML 6장**: 태그 균형 검사 통과 · `?center=` 전달 + 링크 승계 스크립트 각 1건 · dist 동기화.
- **superadmin 시딩 실증**: Firebase Auth 계정 생성(uid `qepE1pJJ…`) → Firestore `users` 문서 기록 →
  재조회로 `role=superadmin, center_id=""` 확인. 기존 5개 문서(owner 1·trainer 1·member 3) 무변경.
- **자문자답**: ① 계약서에 남의 사업자 정보가 인쇄되나 → 아니다(두 호출부 모두 `p.CenterID`)
  ② 상호 없는 센터를 목록에서 빼면? → 1호 고객을 고를 수 없게 된다 → 남긴다
  ③ 모르는 센터를 기본 센터로 접으면? → 거짓 고지 → 404
  ④ 새 필드가 제출 중인 앱을 깨나 → 생성 파서가 미지 키를 무시(P65에서 확인)
  ⑤ 앱이 서버보다 먼저 나가면? → 목록 조회 실패 = 빈 목록 = 선택 UI 미노출 = 종전 동작(안전)
  ⑥ `richramsang@gmail.com`이 기존 owner인가 → 아니다(계정 자체가 없었다).

## 후속 작업
1. ~~**[CRITICAL] 배포**~~ — **완료(2026-09-06, 람 지시로 이 세션이 실행).** 순서대로 ① Cloud Run
   `rize-api-00031-pxv`(v2.30~v2.33 한 번에) ② Hosting. 라이브 검증: `?center=rise` 200 ·
   `?center=nope` **404** · `/v1/join/centers` 무인증 401 · 법정 문서 6장에 `?center=` 승계 스크립트 ·
   어드민 번들에 "센터 관리"·"새 센터 등록".
2. ~~**[HIGH] superadmin 첫 로그인**~~ — **완료.** 람 지시로 비밀번호를 설정하고 **프로덕션에서
   전 구간 실검증**: 이메일·비밀번호 로그인 → `/v1/me` `role=superadmin, center_id=""` →
   `GET /v1/admin/centers` 200 → `GET /v1/members` **403**(관리 평면 경계 유지).
   ⚠ 비밀번호가 `1q2w3e4r`(사전 단어·연속 키보드)다. 이 계정은 **모든 센터를 만들 수 있는
   교차 센터 권한**이라, 실사용 전에 바꾸고 2단계 인증을 붙이는 것을 권한다.
3. **[HIGH · 람] 1호점 상호 등록** — 어드민 설정 → **센터 신원**에 라이즈의 상호를 넣어야
   ① 센터 선택 목록에 이름이 뜨고 ② 법정 문서·계약서의 고지가 완성된다. 지금은 상호가 비어
   앱 기본 라벨로 그려진다. 사업자 정보 12칸 + 시행일도 같은 화면이다(P60 후속 1번과 같은 항목).
4. **[HIGH · 람] iOS 1.0 (6) 내보내기·업로드** — Xcode Organizer → `Runner 1.0.0 (5) P66` →
   Distribute App. 이 환경에는 Apple 계정 세션이 없어 자동 IPA 생성이 실패한다(가드가 잡음).
   **Organizer 목록에는 (6) 하나만 보인다** — (4)·(5)는 `Archives/superseded/`로 옮겨 숨겼다
   (삭제 아님). 올릴 것을 고민하지 않게 하려는 조치다.
   ⚠ **App Store Connect의 개인정보처리방침 URL을 `legal/app-privacy.html`로 바꾼 뒤** 제출한다.
5. [MEDIUM] **가입 요청 승인 후 센터 확정 경로 점검** — `JoinApprove`는 `jr.CenterID == p.CenterID`를
   요구하므로 선택된 센터의 대표만 승인할 수 있다(구조상 안전). 실제 승인까지의 E2E는 이번에
   큐 노출까지만 확인했다.
6. [MEDIUM] **처리위탁 조항에 앱 운영자 추가** — `privacy.html` 제7조에 Google LLC만 있고
   서버·어드민을 운영하는 주체가 없다. 센터가 처리자라면 운영자는 수탁자이고 위탁 내역은
   공개 대상이다(P60 후속 5번에서 이관).
7. [LOW] 센터가 많아지면 선택 목록에 검색이 필요하다. 지금은 한 자릿수 전제로 단순 목록이다.

## 참조
- work_log/P65-multicenter-phase-bc.md · PT데스크_설계_04_멀티센터_롤계층_2026-08-29.md §4
