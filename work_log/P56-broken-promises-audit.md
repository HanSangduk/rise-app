---
id: P56
title: 결함 클래스 전수 감사 — 앱이 못 하는 것을 약속하는 자리 / 막다른 길 / 조용한 실패
status: 진행 중
domain: app
created: 2026-09-02
completed:
---

# P56 — 결함 클래스 전수 감사

## 목표
람: *"이런 부분들이 또 있는지 한번 확인해보고 있으면 개선 방향 리서치 및 분석해서 찾아서
수정하는 작업을 진행해줘."*

P55에서 나온 것은 개별 버그가 아니라 **결함 클래스**였다. 같은 모양이 또 있는지 전수로 본다.

## 감사 대상 결함 클래스 (P55 실측에서 귀납)
1. **거짓 약속** — 화면이 앱·서버가 못 하는 것을 말한다
   (예: "아래에서 센터를 **찾아**"인데 목록이 없음 / "여러 센터 이용 가능"인데 `UserIndex`가 uid당 1건)
2. **자기모순** — 한 화면이 판별자를 여럿 써서 두 상태를 동시에 말한다
   (예: "찾지 못했어요" 경고 + "승인 대기 중" 카드 동시 표시)
3. **막다른 길** — 다음 행동이 없거나, 있는데 그 수단을 안 준다
   (예: "센터에 문의하세요"인데 전화번호를 안 줌)
4. **조용한 실패** — 실패했는데 아무 말이 없다
   (예: 미연결 상태 촬영 탭이 throw가 아니라 `return` — 사진 4장 찍고 저장이 무반응)
5. **와이어 불일치** — 서버 응답 키와 클라이언트 파싱 키가 다르다
   (예: `created_at` vs `requested_at` → 2건째에 어드민 전체 다운)
6. **정당한 경로를 막는 가드** — 방어가 과해서 합법 사용자를 가둔다
   (예: 미연결 계정 탈퇴 404 → 자기 개인정보를 지울 수 없음)
7. **선언만 있고 구현이 없는 것** — 상수·필드·문서는 있는데 그 값을 세우는 코드가 없다
   (예: `store.JoinRejected`가 프로덕션 코드에서 한 번도 대입되지 않았다)

## 진행 단계
- [x] P 클레임 + 클래스 정의
- [x] 3팀 병렬 감사(앱 · 와이어 · 계약)
- [x] 교차검증 + 자문자답 (오탐 20+건 기각)
- [~] 수리 — CRITICAL·즉시성 높은 것 우선 완료, 나머지는 후속 작업
- [ ] 검증

## 결정 사항

### 메타 발견 — 이번 것의 대부분은 새 결함이 아니다
계약팀 결론: **"발견의 대부분은 P55·P53 수리의 절반"**이다. 백엔드는 고쳤는데 앱·계약문서·
법정문서가 안 따라온 자리들이다. 근본 원인은 **수리의 완결 기준이 작업마다 달랐던 것**.
→ 앞으로 수리는 **서버 · 클라이언트 · 계약문서(`docs/API계약_v1.md`) · 법정문서** 네 칸을
모두 확인한 뒤에 끝난 것으로 본다. 이 한 줄이 이 클래스를 통째로 없앤다.

### 오탐 비율이 이 감사의 값어치다
백엔드 가드는 **거의 전부 근거가 적혀 있고 정당했다**(20건 기각). 결함으로 센 것은
**"저장소가 다른 곳에서 이미 내린 판단과 어긋나는 자리"**뿐이다 — 형제 동사가 반대로 판정 /
서버는 허용하는데 클라이언트가 차단 / 인프라 에러를 조건 불성립으로 삼킴.
앱팀도 자기 하위 팀 주장 3건을 뒤집었고, **"빨간 선"(카메라 크로스헤어)은 참이고
"빨간 버튼"(FAB)만 거짓**임을 갈랐다 — 일괄 치환했으면 정확한 안내를 틀리게 만드는 회귀였다.

## 수리 완료

| # | 자리 | 무엇이 거짓·위험이었나 |
|---|---|---|
| L1 | 법정 문서 3종 + 라이브 | **폐기 패키지 ID `com.han.rize` 고지.** P46에서 Play가 실제로 거부한 값이고, 그 URL이 Play 데이터 안전의 계정삭제 주소다 — 심사자가 열면 **존재하지 않는 앱의 삭제 안내**를 본다. 내가 P46에서 두 번 갈아타며 문서를 안 따라가게 둔 자리 |
| L1가드 | `test/tool/legal_identifier_guard_test.dart` **신설** | `build.gradle.kts`의 `applicationId`를 진실의 원천으로 법정 문서·iOS 번들 ID를 대조. **두 번 틀린 자리를 사람이 계속 지키게 두지 않는다** |
| L2 | `account_deletion.dart` + 테스트 | 탈퇴 화면이 *"보존되는 기록에서도 이름과 전화번호는 **함께 지워져요**"* — P53 결정 3과 정반대(서명 계약서는 봉인 해시 때문에 못 지운다). **그 파일 헤더가 스스로 "서버는 지우지 않는데 화면이 지웁니다라고 말하면 거짓 고지"라고 경고**하고 있었다 |
| L6 | `contract_pt_v1_{reported,exempt}.md` | **회원이 서명하는 계약서**가 *"앱의 '환불 예상액' 화면에서 미리 확인"*을 약속. 그 화면은 P39에서 의도적으로 제거됐다. 실서명 0건 창이라 아직 고칠 수 있었다. 슬롯 수 무변화(26/25) |
| privacy 제목 | `privacy.html:223` | *"서버로 전송되지 않고 기기 안에만"* 선언 직후 첫 항목이 *"다만 서버에도 저장됩니다"*로 자기를 뒤집음 — **부분 수정이 만든 모순** |
| H2 | `booking_screen.dart` 취소 다이얼로그 | 정책 조회 실패 시 폴백 24h로 `free=true`가 나와 **경고가 아예 안 뜬 채 세션이 차감**. `isFallback`의 dartdoc이 적은 그 사고 자리 |
| H5 | `session_restore.dart` | 복원 경로가 `MemberNotLinkedFailure`의 서버 상태를 **한 번도 안 읽었다**. 거절당한 회원이 앱을 껐다 켜면 "승인 대기 중"(거짓) |
| H6 | `auth_view_model.dart` `requestJoin` | 거절 화면에서 재요청이 성공해도 **화면이 안 바뀜**. 서버는 rejected면 409를 안 내 **요청은 실제로 접수** → 회원이 반복 → **P55가 없앤 중복 큐가 되살아난다** |
| B7~B9 | `service.go` 5곳 | `if x, err := ...; err == nil && 조건` — 스토어 순단에 **가드가 조용히 통째로 꺼진다**. 납부(되돌릴 수단 없음)·환불 패스 차감·P55 C-2 방어선. 저장소에 옳은 형(`else if !errors.Is(ErrNotFound)`)이 이미 있었다 |
| B7~B9가드 | `service_guard_not_silent_test.go` **신설** + `hookStore.GetUserIndex` | 실패 주입으로 "조회가 실패하면 진행하지 않는다"를 고정 |

## 변경 파일
`admin/public/legal/{privacy,terms,account-deletion}.html` · `app/assets/legal/contract_pt_v1_*.md` ·
`app/lib/features/my/domain/account_deletion.dart` · `app/lib/features/booking/presentation/booking_screen.dart` ·
`app/lib/features/auth/presentation/{session_restore,auth_view_model}.dart` ·
`backend/internal/api/service.go` · 테스트 4개(신설 2 · 갱신 2)

## 검증
- 앱 `flutter analyze` 0 · `flutter test` **1221 pass**
- 백엔드 `go build` · `go test ./...` 전건 그린
- **뮤테이션 4건 전부 KILLED**: 법정 문서를 옛 ID로 되돌림 / `serverJoinStatus` 제거 /
  `JoinApprove` 가드를 옛 `err == nil` 형으로 복원 / (앞선 P55분 포함)
- 법정 문서 라이브 실측: 3종 모두 `com.han.rise`
- ⚠ 테스트가 **내 테스트의 오류를 먼저 잡았다** — `hookStore`가 `GetUserIndex`를 안 감싸
  주입이 안 먹었고, 코드가 아니라 하네스가 틀렸던 것


### L9 — 접속기록 2년 보관: 문서가 아니라 구현이 없다 (→ **P61에서 수리**, 2026-09-06 · 인프라 적용은 람 실행)
`privacy.html:275,499,534`가 *"개인정보처리시스템 접속기록 2년 이상"*(안전성 확보조치 기준 §8)을
약속하는데 실측: **Cloud Logging `_Default` 보존 30일**, uid·대상 정보주체를 남기는 접속기록
미들웨어 **0건**(`auth.go:202`의 실패 로그뿐). 기준 §8의 접속기록은 "취급자 계정·일시·접속지·
처리한 정보주체·수행 업무"라 **Cloud Run 요청 로그 보존을 늘리는 것만으로는 부족**하다.
- 법정 의무를 문서에서 지우는 건 답이 아니다(의무는 남는다). 구현으로 닫는다:
  ① 인증 미들웨어 뒤에 구조화 로그 `{uid, role, method, path, target_member_id, ts}` —
     Cloud Logging에 `jsonPayload`로 ② `_Default` 버킷 보존을 730일로(`gcloud logging buckets
     update _Default --location=global --retention-days=730`, 비용은 이 규모에서 무시 가능)
     ③ `privacy.html:534`의 "위·변조 방지"는 로그 버킷 잠금(`--locked`)까지 해야 참이 된다
- 람 결정 필요: ②③은 인프라·과금 변경이라 자율 범위 밖으로 뒀다.


## 2차 수리 (2026-09-02 — 3갈래 병렬 + 내 직접분)
갈래 로그: 백엔드 **P57** · 어드민 **P58** · 앱은 이 문서에 합산.

### 내 직접분
- 법정 문서: L4(`:271` 철회=파기 → 잠금+요청 시 삭제, 같은 문서 `:133/:298/:323`과 정합) ·
  L5(`:215` 스태프 사진 "보관 안 함" → v2.25 이후 저장소 보관) · L8(계정삭제 안내에 **앱 내
  셀프 삭제 경로** 추가) · 계약서 제13조 `④④⑤⑥` → `④⑤⑥⑦`(두 템플릿, 골든 통과)
- **자문자답이 내 문장 둘을 잡았다**: L5 초안 "교체·삭제 시 파일 삭제"는 절반 거짓(퇴사 시 파기
  0건 — B13에 병합) → "교체 시"로 축소 / L4의 "제7조 참조"는 오기 → 제4조
- L9(접속기록 2년): **구현 부재**(Cloud Logging 30일·uid 접속기록 미들웨어 0). 문서에서
  의무를 지우지 않고 구현 항목으로 — 인프라·과금은 람 결정
- 프로덕션 `join_requests` 실측: **1건(pending)·승인분 0** → A5 과거분 마이그레이션 불필요

### 교차검증
- 어드민(P58) 주장 전건 번들 grep 재확인(위험 지시 "승인만 처리" 0건 · 새 문구·라우트 실재)
- 백엔드(P57) 뮤테이션 **내가 2건 독립 재현**: A5 비우기 무력화 → `TestJoinApproveClearsNameAndPhone`
  FAIL / A3 정규화 무력화 → `TestPaymentInstallmentsNeverNullOnWire` FAIL. 첫 시도는 제거 방식이
  컴파일을 깨 "build failed"로 판정 불가 → 대입만 무력화하는 방식으로 정정
- 어드민이 요청한 4건(철회 회원 메타 목록·`include_deleted`·`media_not_configured`·`route_not_found`
  고정)을 백엔드가 구현 → **어드민 갈래를 재개해 배선** 지시(안 하면 "서버만 열린 절반")
- 백엔드 갈래에 L11(v2.11 절 스테일) 개정 지시 → 2곳 반영 확인

### 배포
- Cloud Run **00029**(v2.28) — `/no-such-route` → 404 `code:"route_not_found"` 라이브 실측
- Hosting은 어드민 갈래 완료 + **피어 세션 ptdesk-b4(P60 App Store 재제출)와 조율 후**.
  같은 워킹트리라 앱 갈래의 미완성 `app/lib` 편집이 그쪽 아카이브에 섞일 수 있음을 통보함

## 3차 수리 (2026-09-05 — 대기실 E2E 실측 + L10)

### 대기실 E2E — 프로덕션 백엔드 · 에뮬레이터 · 미연결 테스트 번호(010-5555-6666)
릴리스 APK는 에뮬레이터에서 Play Integrity가 없어 reCAPTCHA 폴백(Chrome 커스텀 탭)으로 빠져
타임아웃 → **디버그 빌드 + `DEV_SESSION=false` + 프로덕션 API_BASE_URL**로 진행(디버그는 테스트
번호에 앱 검증을 끈다 — 릴리스는 심사 번호 하나만). 확인한 것:

| 단계 | 결과 |
|---|---|
| 빈 상태 | "아직 연결된 센터가 없어요" · 경고 카드 · 연락 카드(번호 없음 → 통화 버튼 없음) · CTA "가입 요청 보내기" · "다른 번호로 다시 시도" · 하단 `이용약관 · 개인정보처리방침 · 계정 삭제` |
| 가입 요청 시트 | 키보드 위로 정확히 올라옴(showRiseSheet) · 이름 입력 → 전송 → 스낵바 |
| 대기 상태 | "가입 요청을 보냈어요" · `승인 대기 중` 배지 · "연결됐는지 확인" / "다시 요청 (27초 후)" 쿨다운 · 안내문 |
| 서버 실측 | `join_requests` 1 → 2 (uid·이름·번호·created_at 정상) |
| 강제 종료 → 재실행 | **대기 화면으로 복원(H5)** — 서버 `me.join_request`에서 상태를 읽음. 쿨다운은 서버 시각 기준 |
| 계정 삭제 | 미연결 전용 고지("보낸 가입 요청 / 앱 로그인 계정" 삭제 · 데스크 회원 정보는 별개) → 동의 체크 → 확인 다이얼로그 → 로그인 화면 복귀 |
| 서버 실측 | `join_requests` 2 → **1**(원상) · Identity Toolkit lookup: 테스트 번호 계정 **0건** |
| 크래시 | logcat FATAL 0건 |

### L10 — 어드민 "센터 신원"이 회원 앱에 뜬다는 약속, 앱은 그 값을 어디서도 안 읽었다 (수리 완료)
E2E 중 연락 카드가 **"라이즈 컨디셔닝 센터 (강남)"**을 찍는 걸 보고 출처를 좇았다.
- **거짓 약속**: 어드민 `CENTER_IDENTITY_EFFECT_NOTE` "회원 앱의 센터 찾기 목록에 이 이름으로 뜹니다" —
  그런 목록은 없다(P55가 센터 선택 대신 대기실을 택했다). 같은 문안이 경고·주석 포함 5곳
- **와이어 불일치**: 어드민은 `PUT /v1/center {center{name,phone,address}}`에 저장, 앱 대기실은
  `GET /v1/public/business`(사업자 정보)에서 전화·주소를 읽음 → 대표가 센터 전화를 저장해도 앱엔 안 나옴
- **선언만 있고 구현 없음**: `CenterResponse.Name` 주석 "클라이언트는 빈 값이면 하드코딩 상호로 폴백" —
  읽는 클라이언트가 0개. 앱 5곳(홈 헤더 폴백·다음 예약 카드·마이 탭·대기실 매칭/연락 카드)이
  로컬 상수. 지점명 "(강남)"은 P48 목업 값이고 확인된 사실이 아니다

수리(4칸):
- **서버** `GET /v1/public/center`(+`/api/` 미러, 무인증, `Cache-Control: public, max-age=300`) →
  `{name, phone, address}` 3칸 고정. 전화·주소만 사업자 정보로 폴백(서버 한 곳에서 — 화면마다 다른
  번호를 말하는 자기모순 방지), 상호는 폴백 없음(법인명≠센터 상호). 테스트 3본 + QR 누출 테스트 확장
  + `TestPublicBusinessNeedsNoAuth`의 "하나뿐" 주석 정정
- **앱** `centerContactProvider` → 새 경로, `CenterContact.name`/`displayName`, 동기
  `centerDisplayNameProvider`(로딩 중 임시 상수 → 서버 값 교체) → 5곳 배선.
  `AppConfig.centerFullName` = `'라이즈 컨디셔닝 센터'`(지점명 제거, 어드민 `CENTER_NAME_FALLBACK`과
  동일 문자열). 테스트 7본(`center_contact_provider_test.dart`)
- **어드민** 문안 5곳 — 앱이 실제로 읽는 자리(센터 연결 화면·홈·마이 탭, 연락 카드 전화·주소, 사업자
  폴백)만 적음. 상호 미등록 경고에 임시 상호 문자열 노출
- **계약** v2.29 절 + v2.13 "유일한 무인증 경로" 헤딩·v2.19 불변 표 교차참조

자문자답:
- Q 폴백을 앱에서 하면? → A 어드민(`centerDisplayName`)·앱·대기실이 각자 합치면 화면마다 번호가
  갈린다. 서버 한 곳. 상호는 왜 안 폴백? → 사업자명은 법인명일 수 있어 간판과 다르다
- Q 새 무인증 경로가 노출 면을 넓히나? → A 세 값 모두 이미 `/v1/public/business`로 공개된 종류
  (전화·주소)거나 간판(상호). `id·status·created_at·policy·business·facility`는 키 잠금 테스트로 차단
- Q `NextBookingCard`를 ConsumerWidget으로? → A 테스트 3본이 ProviderScope 없이 띄운다 → 상호를
  파라미터로 받고 홈이 provider 값을 넘김(기본값 임시 상수)
- Q 홈 헤더 테스트가 `AppConfig.centerFullName`을 기대하는데? → A 위젯 테스트에서 dio 호출은
  flutter_test가 400으로 막음 → DioException → 빈 값 → 같은 폴백. 1272건 전건 통과로 확인
- Q "(강남)" 제거가 스토어 스크린샷과 어긋나나? → A 다음 예약 카드 둘째 줄 문구만 바뀜.
  Guideline 2.3(기능 정확성) 사유 아님 — 다음 재캡처 때 반영

### L10 후속 — 공개 경로의 401은 로그아웃 사유가 아니다 (피어 세션 ptdesk-b4/P60 지적, 수리 완료)
`dio_client.dart`의 401 인터셉터는 경로 구분 없이 세션을 비웠다. 새 `/v1/public/center`는 신원을 보지
않는 경로인데, **구서버**(v2.29 배포 전 — 라우트가 없어 auth 미들웨어가 먼저 401 `missing_token`)나
Bearer 첨부 실패(getIdToken 예외)에서 온 401이 홈 헤더의 상호 읽기 한 번으로 회원을 로그아웃시킬 수
있었다. `isPublicApiPath()`(`/v1/public/*`·`/api/v1/public/*`)를 두고 그 경로의 401은 세션을 건드리지
않는다. 인증 경로의 401은 종전대로 — 두 방향을 `public_path_401_test.dart`(4본)가 고정.
자문자답: 테스트에서 `dioProvider`(autoDispose)를 read만 하면 인터셉터의 `ref.read`가 "disposed
Ref"로 터진다 → 구독을 걸어 앱과 같은 수명으로. 첫 실패는 이 테스트 결함이었고 코드 결함이 아니었다.

### 검증
- 백엔드 `go test ./...` 전 패키지 ok · `go build` ok
- 앱 `flutter analyze` 0건 · `flutter test` **전건 통과**(1272 + 신규 4)
- 어드민 `npm run build` ok
- **에뮬레이터 재확인(수정 빌드, 프로덕션 백엔드)**: 대기실 연락 카드가 **"라이즈 컨디셔닝 센터"**(지점명
  없음)를 찍는다 — 라이브 서버(00029)에 새 경로가 없어 provider가 빈 값으로 접힌 폴백 경로다. 같은 번호로
  가입 요청 없이 곧장 `계정 삭제` → 로그인 복귀 → Identity Toolkit 0건 · `join_requests` 1건(원상).
  즉 **가입 요청이 없는 미연결 계정의 삭제 경로도 동작**한다
- 피어 세션(ptdesk-b4): iOS 1.0(4)를 L10 포함 트리로 재아카이브(바이너리에 `/v1/public/center` 문자열
  실물 확인) → 401 방어선 추가 뒤 한 번 더 통보

### 산출물 — Android 1.0.0+4 재빌드(L10 + 401 방어선 포함 트리)
- `app/build/app/outputs/bundle/release/app-release.aab`(86.8MB) · `app/build/app/outputs/flutter-apk/app-release.apk`(111.8MB)
- `aapt` 실측: `com.han.rise` versionCode 4 / 1.0.0 · `libapp.so` 문자열: `/v1/public/center` 1건 · `센터 (강남)` 0건
- 첫 `bundleRelease`는 피어 세션의 동시 flutter 작업과 겹쳐 실패 → 재실행 성공(코드 문제 아님)
- iOS는 피어(ptdesk-b4)가 같은 트리로 재아카이브 예정(401 방어선 반영 통보 완료)

### 배포 — **자동 모드 분류기가 차단(2건)** → 람 실행 → **2026-09-06 실측 완료**
- Cloud Run `rize-api-00030-x6w` 라이브: `GET /v1/public/center` → 200 `{"name":"","phone":"","address":""}`
- Hosting 번들 `index-C22ujGXc.js`: 새 문안 "센터 연결 화면·홈·마이 탭" 2건, 옛 "센터 찾기 목록" 0건
- A3 프로덕션 실측: `centers/rise/payments` 문서 **0건** → `installments:null` 잔존 없음(종결)
```bash
# 백엔드 v2.29 (Cloud Run rev 00030)
gcloud run deploy rize-api --source backend --region asia-northeast3 --project rize-218c1 \
  --set-build-env-vars GOOGLE_BUILDABLE=./cmd/server
# 어드민 문안 (Hosting) — 빌드+배포+스모크
./deploy-hosting.sh
```
배포 전까지 앱(다음 빌드)이 `/v1/public/center`를 부르면 라이브 서버는 404 `route_not_found` →
provider가 빈 값으로 접어 임시 상호를 보여준다(막다른 길 아님). 순서는 서버 먼저.

## 4차 수리 착수 (2026-09-06 — 후속 항목 설계 → 적대 검토 → 구현 워크플로)

설계 4건(L9·B13·대기실/삭제 고지·지뢰)을 각각 에이전트가 코드 실측으로 세우고, 렌즈 2개(정직성·법적 정확성·4칸 / 회귀·테스트·운영)로 적대 검토했다.
검토 8건 중 4건(L9·지뢰)은 에이전트 한도 초과로 실패 → 내가 직접 검토. 설계를 뒤집은 결정:
- **B13 실패 정책 = 전파**(best-effort 아님): ①계정 잠금 ②인덱스 강등 뒤라 ③파기 실패를 500으로 올려도 보안상 손해가 없고,
  status가 active로 남아 재시도가 멱동으로 수렴한다 → 별도 reconcile 없이 "지체 없이 삭제"가 참이 된다(검토 #2).
  검토가 잡은 두 번째 구멍: 어드민 [사진 지우기](빈 photo_url PUT)가 고아를 만든다 → UpdateStaffProfile에도 같은 파기 판정.
  어드민 퇴사 행의 [사진 선택]은 서버 400과 짝을 맞춰 숨긴다(눌러야 실패하는 버튼 금지).
- **삭제 고지의 "요청 없음"은 앱이 알 수 없다**(코드 인증 직후엔 /v1/me를 부른 적이 없고 서버도 없음/조회실패를 구분 안 함)
  → JoinRequestTrace는 unknown/pending/settled 3값, unknown은 '있다면'으로 헤지, 완료 문구는 서버 purged 건수·member_id로.
- 대기실 힌트 "다음 확인부터 연결돼요"는 없는 동작(재매칭은 로그인 직후만) → "같은 번호를 다시 인증하면"으로, 링크 라벨을
  '번호 다시 인증하기'로. '다른 센터' 표현은 v1 단일 센터라 승격 금지. pending 쿨다운 문장은 버튼 라벨과 중복이라 넣지 않음.
- **지뢰의 전제 정정**: memberId 없는 세션은 타입상 불가. 실제 트리거는 '셸이 그려진 채 세션이 null'(재검증 notLinked·401·
  로그아웃·탈퇴)이고, 재검증 notLinked는 **지금도 도달 가능**(다른 기기 탈퇴 후 토큰 만료 전 기동)하며 착지가 전화번호
  화면이라 SMS 재인증을 강제한다 → 세션 종료 이유(enum)별 착지 + SessionGoneFailure + 플랫폼 초기 라우트 무시 + 가드 테스트.
- L9는 §8 원문(law.go.kr)을 내가 독립 확인: ①1년/2년(민감정보 → 2년) ②점검 주기는 내부 관리계획으로 ③안전 보관.
  '월 1회'는 우리가 정하는 값. 인프라(버킷·sink·잠금)는 람 실행. `--enable-analytics`는 불가역이라 제외.
구현은 P61(L9)·P62(B13)·P63(문구·고지)·P64(지뢰)로 분리 — 각 P 파일 참조.

### 4차 수리 결과 (2026-09-06)
구현 4건(P61·P62·P63·P64) → 실제 diff를 항목당 2렌즈(정확성·회귀·운영 / 정직성·법적 정확성·4칸)로 적대 검증(8 에이전트)
→ **33건 이슈** 전부 반영(백엔드 체인 P61→P62, 앱 체인 P63→P64) → 내가 전체 테스트 재실행.

검증이 잡은 것 중 큰 것(설계·구현 에이전트 둘 다 놓친 자리):
- **P61**: 점검 스크립트가 `jsonPayload.time`을 읽었다 — Cloud Logging은 `time`·`severity`를 LogEntry 필드로 승격하며
  jsonPayload에서 제거하므로 운영 첫 실행에 KeyError로 죽을 코드였다(서버 주석 스스로 "time → LogEntry.timestamp"라
  적어 놓고). LogEntry `timestamp` 우선 + `--dry-run` 픽스처 실행으로 고정. `remote_ip`는 True-Client-IP·X-Real-IP·XFF
  첫 값 순이라 셋 다 위조 가능 → `xff_last`(GFE가 덧붙인 값) 필드 추가. Timeout 30s 뒤 응답은 504로, 헤더 뒤 패닉은
  `aborted:true`로 사실대로. 헤더 512자 클립. P61은 인프라·법정문서 칸이 람 실행 대기라 `status: 진행 중`으로 되돌림.
- **P62**: 파기 판정이 접두 `staff/photos/`만 봐서 **A의 photo_url이 B의 파일을 가리키면 A 퇴사가 B의 파일을 지웠고**,
  stale PUT(옛 URL 되보내기)이 새 파일을 지우는 회귀가 있었다 → uid·버킷 명의 결속(`staff/photos/<uid>-…`만) + stale PUT 409.
  교체(⑤)도 best-effort를 버리고 전파(새 파일 롤백)로 — privacy "교체하거나 지우면 삭제"가 참이 되게. 미구성 purger면
  파기했다고 치지 않고 photo_url 유지(`Configured()`). 어드민 퇴사 행은 [사진 지우기]만 열어 잔류 사진 정리 경로 제공.
- **P63**: matched 단계에서 '계정 삭제'를 unlinked로 열었는데 재인증한 **기존 회원**은 principal에 member_id가 있어 서버가
  회원 경로(전체 파기)를 돈다 → unknown scope + 사유별 배너. 로컬 기록만으로 pending을 단정하던 trace → 서버 확답만 pending.
  '제가 아니거나 다른 센터예요'(단일 센터) → '제가 아니에요'. copyWith가 serverJoinStatus를 못 지우던 것 → clear 플래그.
- **P64**: 콜드스타트 notLinked 착지(전화번호 화면)와 재검증 착지(대기실)가 달랐다 → 한 규칙(`sessionEndRoute`)으로, 재검증
  경로의 phone ''로 가입 요청이 나가던 구멍 → Firebase 번호로 seed. SessionGoneFailure 메시지가 danger 스낵바로 새던 5곳 →
  공통 헬퍼가 건너뜀. app.dart 리스너를 순수 함수로 뽑아 테스트. 촬영 '바이트 보존' 과잉 약속 정정.
- 검증 중 발견한 **기존 플레이키** `TestBodyPhotoListLockedIsMetaOnlyOnWire`(P57, 목록 순서 비결정)를 내가 고정(대상 id 명시).

최종 검증(내가 직접): 백엔드 `go build`·`go vet`·`go test ./...` 전 패키지 ok · 앱 `flutter analyze` 0건 · `flutter test` **1370 전건 통과**
(4차 착수 전 1338) · 어드민 `npm run build` ok. 에뮬레이터 실측: P63 대기실·삭제 고지 전 흐름(n1~n7.png, P63 절 참조).

## 후속 작업 (미수리 — 우선순위 순, 2026-09-06 4차 착수 반영)
1. ~~[배포 대기] v2.29 백엔드 + 어드민 문안 Hosting~~ — **완료·실측**(2026-09-06, 위 배포 절)
1-b. **[배포 대기·람] v2.30(접속기록)·v2.31(사진 파기) 서버 + Hosting(어드민·privacy.html)** — 피어 세션 P65(v2.32 멀티센터 가입 연결)와
   같은 트리라 한 번에 배포. 순서: 서버 → `setup-access-log.sh` → 스태프 사진 잔류 측정·정리 → Hosting. P65는 프로덕션
   superadmin 0건이라 시딩이 선행돼야 센터 관리 화면이 열린다(P65 참조): **새 이메일**로 Firebase Auth 계정 생성 → Firestore `users/{그 uid}` = `{role:"superadmin", center_id:""}`. 기존 owner 계정 재사용 금지(역할이 uid당 1개라 라이즈 어드민에서 잠긴다).
   공유 트리 재검증(2026-09-06 17:20): go test 전 패키지 ok · admin build ok · flutter analyze 0
   → 피어 P66(v2.33 센터 선택 가입 요청·법정 문서 센터 차원, pubspec **1.0.0+5**) 뒤 재검증(17:50): go test ok · admin build ok ·
   flutter analyze 0 · flutter test 1377 전건. superadmin 시딩은 피어가 완료(richramsang@gmail.com). iOS는 1.0.0 (5) 재아카이브,
   Android AAB/APK는 내가 재빌드 — 피어 P67(스토어용 운영자 명의 개인정보처리방침 `app-privacy.html` 분리, 마이 탭 약관 5행)로
   pubspec이 **1.0.0+6**이 되어 최종 산출물은 versionCode 6(app/build/app/outputs/…, 2026-09-06 밤 실측). iOS도 (6) 하나만 Organizer에 남김(피어).
   피어가 그 AAB를 독립 검증(업로드 키 서명·프로덕션 주소·integration_test 0건)해 `~/Downloads/rise-1.0.0+6.aab`로 복사 — 람은 그 파일을 올리면 된다.
   **배포 완료(2026-09-06 21:05, 람이 피어 세션에 직접 지시해 실행)** — Cloud Run `rize-api-00031-pxv`(v2.30~v2.33) + Hosting(`index-CKOeAPoh.js`).
   내 독립 실측: `/v1/public/center` 200 · `?center=nope` 404 · `/v1/join/centers` 무인증 401 · **접속기록 라인이 프로덕션 _Default에
   실제로 쌓임**(superadmin의 /v1/me 200 · /v1/admin/centers 200 · 경계 403 — uid·route·status 확인) · 어드민 번들에 "센터 관리"·"새 센터 등록".
   **아직 안 된 것**: `backend/scripts/setup-access-log.sh` 미실행 — 버킷 `access-log-2y`·sink 부재(gcloud describe NOT_FOUND). 즉 접속기록은
   지금 30일 버킷에만 쌓이고 **2년 시계는 시작 전**, privacy.html의 "2년"은 그때까지 미충족(P61 status 진행 중 유지).
2. **[HIGH] L7 — 사업자 정보 12칸 + 센터 신원 3칸 입력(람).** 지금은 대기실·홈이 임시 상호를 찍고
   "센터에 전화하기"가 없다. 어드민 > 설정 > 센터 신원 / 사업자 정보
3. ~~[HIGH] L9 — 접속기록 2년~~ → **[P61](P61-access-log-retention.md) 수리 완료(코드·문서 4칸)**. 남은 것은
   람 실행: 서버 배포 → `backend/scripts/setup-access-log.sh`(버킷·sink, 2년 시계 시작) → README sink 시작일 기입 →
   privacy.html 개정 이력 행 + Hosting 배포 → 잠금(`--lock`, 불가역) 결정 → 매월 첫 영업일 `access-log-review.sh`
4. ~~[MEDIUM] B13 — 스태프 퇴사 시 프로필 사진 파일 잔류~~ → **[P62](P62-staff-photo-purge-on-deactivate.md) 수리 완료**
   (퇴사 ③ 파기·실패 전파, 프로필 PUT의 사진 지우기도 파기, 퇴사자 업로드 400, 어드민 문안·photoEditable,
   privacy.html, 계약 v2.31). 남은 것은 람: 잔류 파일 측정(`gcloud storage ls gs://<STORAGE_BUCKET>/staff/photos/`),
   softDeletePolicy 확인, 서버 → Hosting 순서 배포
5. ~~[MEDIUM] 지뢰~~ → **[P64](P64-session-gone-landing.md) 수리 완료** — 전제 정정: memberId 없는 세션은 타입상 불가,
   실제 트리거는 '셸이 그려진 채 세션 null'(재검증 notLinked는 **지금도 도달 가능**). 종료 이유별 착지
   (notLinked → 대기실, 람이 되돌릴 수 있는 제품 판단)·SessionGoneFailure·플랫폼 초기 라우트 무시·가드 테스트.
   다음 빌드(1.0(5)+) 대상
6. ~~[LOW] A3 — 프로덕션 `installments:null` 실재 여부~~ — **종결**: payments 문서 0건(2026-09-06 실측)
7. ~~[LOW] 대기실 문구 중복~~ → **[P63](P63-lobby-copy-and-deletion-notice.md) 수리 완료** — 단계별 제목/부제/힌트
   역할 분리, 카드 3종 삭제, '번호 다시 인증하기', 배지 삭제, 1.35 배율 테스트. 다음 빌드 대상
8. ~~[LOW] 스토어 스크린샷~~ — **재캡처 완료(2026-09-06)**: Android(에뮬레이터, `ANDROID_SERIAL=emulator-5554` — 실기기 동시
   연결 시 adb 대상 모호로 멈추는 것을 실측) + iOS(iPhone 16 Pro Max 1320×2868) 각 7장 raw → `frame.py` final.
   홈 카드 둘째 줄 "정혜린 코치 · 라이즈 컨디셔닝 센터"(지점명 없음) 확인. `ios/Flutter/Generated.xcconfig`는 trap으로
   `lib/main.dart` 복원 확인(P60 사고 재발 없음). 스토어 콘솔 업로드는 람
9. ~~[LOW] 미연결 계정 삭제 고지의 과잉 열거~~ → **P63** — JoinRequestTrace(unknown/pending/settled): 모르면 '있다면',
   완료 문구는 서버 purged 건수·member_id로
10. **[MEDIUM·람] softDeletePolicy** — 프로덕션 Storage 버킷에 소프트 삭제(기본 7일)가 켜져 있으면 스태프·체형사진
    모두 "삭제" 뒤 최대 7일 복구 가능 상태로 잔존 — privacy.html 백업 콜아웃은 DB만 말한다.
    `gcloud storage buckets describe gs://<STORAGE_BUCKET> --format='value(softDeletePolicy)'` 후 고지 보강 여부 결정
11. **[LOW] 스태프 프로필 나머지 칸(직함·경력·자격·소개)의 퇴사 후 보존 근거** — 유일한 목적이 회원 앱 공개인데
    재고용 편의로만 보존. privacy.html 보유기간 표에 스태프 정보 행 부재(P62 검토 지적)
12. **[LOW] 동시성 창** — 퇴사 ③~④ 사이 업로드는 IsActive 가드를 통과해 새 파일이 고아가 될 수 있다(트랜잭션 없음,
    계약 v2.31 명시). 닫으려면 낙관적 버전 — 별도 결정
13. **[LOW] D3** — 캐시 세션 재검증이 끝나기 전 4탭이 403 → '요청을 처리할 수 없어요'(캐시 선진입 설계의 본질적 창).
    딥링크 도입 시 `overridePlatformDefaultLocation` 해제 + redirect 셸 가드 필요(shell_gate_test가 알린다)

## 참조
- P55(대기실) — 이 클래스가 처음 드러난 곳 · P50(어드민 사용성: 같은 방식의 전 화면 감사 선례)
