---
id: P06
title: Firebase 실연동 (Blaze) — Auth·Firestore·배포 트랙
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P06 — Firebase 실연동 (Blaze)

## 목표

Blaze 요금제 Firebase 프로젝트에 3계층을 실연동: 앱 전화번호 인증(Firebase Auth) → 백엔드 ID 토큰
검증 + Firestore 실 DB + Cloud Run 배포 → 어드민 이메일 로그인. dev 헤더/인메모리 모드는 로컬
개발용으로 보존(설정 스왑).

## 결정 사항

- 프로젝트: **rize-218c1**(계정 rizejoy91@gmail.com, Blaze 결제 확인). 번들/패키지 ID **ai.stra.rize**.
- 콘솔 클릭 없이 REST/gcloud로 전부 프로비저닝(Identity Platform 초기화 → Auth 설정 → 앱 등록 →
  규칙 배포 → 예산 → 계정 시딩) — firebase login(대화형) 회피, flutterfire configure 대신
  firebase_options.dart 수기 생성.
- **SMS 리전 KR만 허용**(신규 프로젝트 기본값이 전부 차단 — 최대 함정 + SMS 펌핑 방어).
  테스트 번호 2개 등록(+821012345678/123456, +821055556666/654321 — 실 SMS·과금 0).
- 버전(리서치 검증): firebase_core 4.13.0 / firebase_auth 6.5.7 / firebase-tools 15.28.1 /
  firebase(web) 12.x / admin-go 4.21.0·firestore 1.25.0(업그레이드 완료).
- Firestore 규칙: 클라이언트 전면 차단(백엔드 Admin SDK 전용) — firestore.rules가 소스 오브 트루스.
- 인증 마이그레이션 전략: 앱은 Bearer+X-Dev **동시 전송**(백엔드 모드별 택1) — 로컬/프로덕션 무중단 스왑.
- 온보딩 보안 승격: 토큰의 phone_number가 있으면 join/match·confirm의 진실 원천(클라 제공 번호는 dev 폴백).
- owner 계정: rizejoy91@gmail.com (임시 비번 → 재설정 메일 발송, uid 기반 UserIndex+staff 시딩 완료).
- 예산 알림: 월 50,000원, 50/90/100% 임계.
- **헬스체크는 /health** — run.app 도메인에서 Google 프론트엔드(GFE)가 /healthz를 가로채
  컨테이너에 도달하지 않음(실측: 앱 404는 text/plain, /healthz 404는 구글 HTML — 두 URL 모두).
  /healthz는 로컬용으로 유지, /health 별칭 추가 후 재배포(rev 00002)로 200 확인.
- **전화번호 비교 정규화를 domain으로 승격**(P06 최대 발견). E.164 토큰 번호와 어드민이 저장한
  국내 표기는 "숫자만 남기기" 비교로 영원히 불일치한다(821012345678 ≠ 01012345678) — 즉
  **토큰 우선 승격이 프로덕션 가입 매칭을 100% 실패시키는 상태였다.** `domain.NormalizePhone`
  하나로 api·store(Memory·Firestore) 전부를 통일. 계약 v1.7 절에 3계층 공통 규칙으로 명문화.
- **DEV_SESSION을 실제 스위치로**. 앱의 `DevSession.enabled`가 하드코딩 `true`라 릴리스 빌드도
  dev 헤더를 실었다(문서에만 존재하는 플래그). 기본값을 `kDebugMode`로 바꿔 릴리스는 자동 off,
  디버그에서 프로덕션 백엔드를 붙일 때만 `--dart-define=DEV_SESSION=false`.
- **join/request도 토큰 번호 규칙 적용**(자문자답 2차 발견). 세 join 엔드포인트 중 이것만 바디
  번호를 그대로 믿었고, 승인 시 그 값이 회원 레코드로 굳는다 — 타인 번호 선점 체인. 단 여기선
  덮어쓰지 않고 **대조**한다(입력 표기가 어드민 가독성이라 보존할 가치가 있음).
- 어드민 표시 이름은 `staff` 목록(uid→이름)이 진실 — 데모 `identity.name`은 로딩 전 폴백.
  (Firebase 실계정은 identity가 null이라 대시보드 인사말·정산 라벨이 빈 문자열이 되던 갭)

## 진행 단계

- [x] 1. 현황 파악 + CLI 설치(firebase-tools·flutterfire)
- [x] 2. 리서치(전 항목 1차 출처 — SMS 과금·리전 정책·플랫폼 요건·Cloud Run 빌드팩)
- [x] 3. GCP/Firebase 프로비저닝: API enable · Firestore DB(asia-northeast3, native) · 앱 3개 등록 ·
      Auth(전화+이메일+테스트 번호+KR 리전) · 규칙 배포 · 예산 알림 · owner 계정+Firestore 시딩
- [x] 4-1. backend: admin-go 4.21.0/firestore 1.25.0 업그레이드(테스트 그린) + 토큰 phone 우선 사용
- [x] 4-2. app(안드로이드·iOS 스캐폴딩 + 전화인증 실연동 + Bearer 이중화 + 세션 복원/로그아웃) /
      admin(이메일 로그인 + Bearer 우선·X-Dev 폴백 + 데모 공존)
- [x] 5. Cloud Run 배포(rize-api, 서울) → 프로덕션 스모크 통과(무토큰 401 · dev 헤더 401 ·
      owner Bearer → /v1/me OK · staff/policy 지연 시딩 OK) → /healthz GFE 가로채기 발견 →
      /health 별칭 재배포(rev 00002) 200 확인
- [x] 6. 자문자답 1차: 프로덕션 전화인증 E2E(테스트 번호 → ID 토큰 → 백엔드) 실측 중
      전화번호 정규화 버그·DEV_SESSION 유령 플래그·어드민 이름 폴백 갭 발견 → 수정 → 재배포(rev 00003)
      → 실 Firestore 매칭 E2E로 수정 검증(PASS)
- [x] 7. 자문자답 2차: join 3형제 중 `join/request`만 바디 번호를 신뢰하던 선점 구멍 발견 →
      토큰 대조 가드 + 테스트 4케이스 → 재배포(rev 00004) → 프로덕션 400 실측(PASS)
- [x] 8. 디버그 키스토어 SHA-1/SHA-256 콘솔 등록(REST) — 안드로이드 실기기 실번호 인증 준비 완료
- [x] 9. 문서 마감: 계약 v1.7 절 + 3계층 README(배포 실값·Firebase 실연동 절) + 본 로그

## 변경 파일

**backend**
- `internal/domain/phone.go`(신규) — `NormalizePhone` 공용 비교 키(E.164 ↔ 국내 표기 수렴)
- `internal/domain/phone_test.go`(신규) — 10케이스 + 토큰/저장 표기 일치 명시 가드
- `internal/api/service.go` — `digitsOnly` 제거 → `domain.NormalizePhone`으로 통일 +
  `JoinRequestCreate`에 토큰 번호 대조(불일치 400 · 미입력 시 토큰으로 채움 · 일치 시 표기 보존)
- `internal/api/service_test.go` — `TestJoinUsesVerifiedTokenPhone`(E.164 매칭 + 바디 위조 방어 +
  토큰만으로 confirm) · `TestJoinRequestPhoneMustMatchToken`(선점 방어 4케이스)
- `internal/store/memory.go` — `normalizePhone`을 domain 위임으로(Firestore 구현과 동일 경로 보장)
- `internal/api/router.go` — `GET /health` 별칭(GFE 가로채기 우회)
- `README.md` — 배포 절을 실배포 값으로(서비스명·리전·env 표·헬스체크·규칙)

**app**
- 신규: `lib/firebase_options.dart`, `lib/core/utils/phone_format.dart`,
  `lib/features/auth/presentation/session_restore.dart`, `test/core/utils/phone_format_test.dart`,
  `android/`·`ios/` 스캐폴딩 + `google-services.json`·`GoogleService-Info.plist`
- 수정: `pubspec.yaml`, `main.dart`, `app.dart`, `core/router/app_router.dart`,
  `core/network/dio_client.dart`(Bearer+dev 이중화), `core/network/dev_session.dart`(kDebugMode 기본값),
  `features/auth/{domain,data,presentation}/*`(verifyPhoneNumber 4콜백·재전송 토큰·한국어 매핑),
  `features/my/presentation/my_screen.dart`(로그아웃), `analysis_options.yaml`(build/ 제외)

**admin**
- 신규: `src/lib/firebase.ts`
- 수정: `src/lib/api.ts`(Bearer 우선·X-Dev 폴백), `src/lib/auth.tsx`(loginEmail·세션 복원·로그아웃),
  `src/features/Login.tsx`(실제 제출+한국어 에러 + **비밀번호 재설정 메일 발송** — 최초 로그인
  경로 겸용, 이메일 열거 방지), `src/App.tsx`(pill 데모 한정),
  `src/features/Dashboard.tsx`(표시 이름을 staff 기준으로), `package.json`

**docs**
- `docs/API계약_v1.md` — **v1.7 인증 실연동 패치** 절 추가(모드 판정·토큰 phone 진실 원천·
  전화번호 정규화 공통 규칙·헬스체크)

## 검증

- backend `go test ./... -race` 그린, `go vet` 클린 — 신규 회귀 가드 4종
  (`TestNormalizePhone` 10케이스 · `TestNormalizePhoneTokenMatchesStored` ·
  `TestJoinUsesVerifiedTokenPhone` · `TestJoinRequestPhoneMustMatchToken`)
- app `flutter analyze` 0 issues · `flutter test` **64/64** · `./gradlew :app:assembleDebug` exit 0(실 APK)
- admin `npm run build` exit 0
- **프로덕션 전화인증 E2E**(REST, 실 Cloud Run): 테스트 번호 → `sendVerificationCode` 200(실 SMS 0) →
  `signInWithPhoneNumber` 200 → ID 토큰에 `phone_number:+821012345678` 확인 →
  `GET /v1/me` → `{role:"member", center_id:"rise"}` → `POST /v1/join/match` 200. 테스트 유저 삭제 완료.
- **프로덕션 매칭 실경로 E2E**: 실 Firestore에 국내 표기(010-1234-5678) 회원 1건 생성 →
  E.164 토큰만으로 `join/match` 매칭 성공 + 바디에 다른 번호를 실어도 토큰이 이김 → 문서·유저 정리.
- **프로덕션 선점 가드 E2E**: 두 번째 테스트 번호로 로그인 후 타인 번호로 `join/request` →
  400 "인증한 번호와 다른 번호로는 가입을 요청할 수 없어요" 확인 → 유저 정리.
- 앱에 배치된 `google-services.json`·`GoogleService-Info.plist`가 프로비저닝 원본과 바이트 일치 확인
- iOS 프로젝트(pbxproj 수기 편집) 파싱·SwiftPM 해석 확인 — `xcodebuild -list`에 Runner 타깃과
  firebase-auth·firebase-core 스킴 정상 노출
- **iOS 릴리스 빌드 성공** — `flutter build ios --no-codesign` exit 0,
  `build/ios/iphoneos/Runner.app` 22.7MB, 번들 `ai.stra.rize`(안드로이드 APK와 함께 양 플랫폼 확인)
- 복합 인덱스 불필요 확인 — Firestore 쿼리에 `OrderBy` 0건, 전부 동등 필터 또는 동일 필드 범위
  (정렬은 Go에서) → 자동 단일 필드 인덱스로 충분. README의 과보수적 경고를 실측 결과로 교체.
- 최종 리비전 **rize-api-00004-m5d** 스모크: `/health` 200 · 무토큰 `/v1/me` 401
- 정리 확인: 프로덕션 Firestore에 테스트 문서 0건, Auth 유저는 owner 1명만 잔존

## 후속 작업

- **⚠ 최우선 — 트레이너를 추가할 방법이 없다**. 계약에 스태프 생성 엔드포인트가 없고
  `SetOffdays`·`UpdateStaffProfile`은 둘 다 `GetStaff` 선행이라 **기존 레코드만 수정**한다.
  프로덕션 Firestore엔 owner 1명뿐이라 대표가 실제 트레이너를 온보딩할 수 없다(지금까지는
  DEV_SEED가 가려주던 갭). 실사용 전 `POST /v1/staff` 초대/등록 경로가 필요하다 — 별도 트랙.
- **사용자 몫**: (1) rizejoy91@gmail.com 앞으로 발송된 비밀번호 재설정 메일 완료 — 어드민 실로그인
  전제조건. (2) iOS 실기기에서 실번호 인증할 때 APNs 인증키(.p8) 업로드. (3) 스토어 배포 시
  릴리스 키스토어 SHA-1/256 추가 등록(디버그 키는 등록 완료).
- 어드민 호스팅 시 Cloud Run `CORS_ORIGINS`에 오리진 추가(현재 `http://localhost:5174`만)
- Firebase Storage 트랙: 체형 사진 업로드 + 트레이너 `photo_url` 실파일(현재 URL 입력만)
- `Me`에 name 추가하면 어드민이 staff 목록 조회 없이도 이름 표시 가능(현재는 staff 조인으로 해결)
- 이월: RefundPass/SendContract 전체 스토어 트랜잭션화 · 알림 어댑터 · 대기열 · CSV 등록 · 크론 연장

## 참조

- backend/README.md "배포(Cloud Run) — P06 실배포 완료" · app/README.md "Firebase 실연동 (P06 — 완료)"
- admin/README.md "Firebase Auth 실연동 (P06 — 완료)" · docs/API계약_v1.md "v1.7 인증 실연동 패치"
