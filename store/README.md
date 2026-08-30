# store/ — 스토어 제출 자산 (P46, 2026-08-29)

Google Play + App Store 제출에 필요한 것 전부. 릴리스 준비도 감사(P46) 결과와 함께.

```
store/
  metadata/    play.md · appstore.md        — 등록 문구(이름·설명·키워드·심사 노트)
  privacy/     play-data-safety.md          — Play 데이터 보안 설문 답
               apple-app-privacy.md         — App Privacy 답
  graphics/    icon-512.png                 — Play 스토어 아이콘(512, 풀블리드)
               feature-graphic-1024x500.png — Play 피처 그래픽
  screenshots/ capture.sh                   — 캡처 재현 스크립트(시드 백엔드 + 사진서버 + drive)
               frame.py                     — raw → ASO 캡션 프레임 이미지 생성
               ios/raw/ · android/raw/      — 앱 실행 원본(iOS 1320x2868 = 6.9" 요건)
               ios/final/ · android/final/  — **제출용**(캡션 + 디바이스 목업)
  demo-photos/ stand-{front,side}-{before,after}.jpg — 체형 비교용 AI 생성 데모 사진(P46)
  scripts/     make-keystore.sh             — Android 업로드 키 생성(최초 1회)
               build-release.sh             — AAB/IPA 빌드(API_BASE_URL 주입 포함)
```

## 준비 상태 (감사 결과 요약)

| 항목 | 상태 |
|---|---|
| 식별자 `ai.stra.rize` · 표시명 "라이즈" · 버전 단일 소스 | ✅ |
| iOS 서명(팀 4RQD93MV57, Automatic) · 1024 아이콘(알파 없음) | ✅ |
| 권한 문구(카메라·사진·동작) 한국어 · 불필요 권한 제거 | ✅ (모범적 — RECORD_AUDIO 제거, allowBackup=false) |
| 개인정보처리방침·계정삭제 공개 URL | ✅ https://rize-218c1.web.app/legal/privacy.html · …/account-deletion.html |
| 계정 삭제(5.1.1(v)) 앱 내 구현 | ✅ 마이 > 회원탈퇴 |
| 광고·분석·추적 SDK | ✅ 없음(ATT 불필요, "추적 없음" 답변) |
| targetSdk 36 / minSdk 24 / **iOS 15.5**(ML Kit pod 요구로 상향, P46) | ✅ |
| 스크린샷 7종 × 2플랫폼(실행 캡처 + ASO 캡션 프레임) | ✅ |
| 메타데이터·설문(ASO 2팀 교차검증 반영) | ✅ |
| **Android 릴리스 서명** | ❌ **유일한 차단 항목** — 아래 1번 |

## 제출 순서

### 0. 남은 사용자 액션 (이것만 하면 제출 가능)
1. **[CRITICAL] Android 업로드 키 생성** — `bash store/scripts/make-keystore.sh`
   (gradle 배선은 완료 — key.properties가 생기면 자동으로 릴리스 키 서명.
   ⚠ keystore+비밀번호는 분실 시 복구 불가, 반드시 백업)
2. **[HIGH] 버전 올리기** — `app/pubspec.yaml` `version: 0.1.0+1` → `1.0.0+1`
3. **[HIGH] 심사용 테스트 번호 확인** — Firebase 콘솔 > Authentication > 로그인 방법 >
   전화 > 테스트 전화번호에 `+82 10-1234-5678 / 123456`이 등록돼 있는지,
   프로덕션 백엔드에 그 번호의 **승인된 회원**(회원권·기록 보유)이 있는지 확인.
   (P09 실플로우가 이 번호로 프로덕션 홈까지 통과했으므로 있을 것 — 재확인만)
4. [완료] iOS 배포 타겟 15.5로 상향 — ML Kit pod이 15.0에서 pod install 자체를 거부해
   빌드가 불가능했다(캡처 중 실측). Podfile + pbxproj 3곳 동시 반영.
5. [완료] Firebase Phone Auth URL 스킴 등록 — 시뮬레이터에서 "인증번호 받기" 순간
   PhoneAuthProvider가 fatal로 죽던 실버그(실기기는 APNs 경로라 P09 실측에서 안 드러남).
   `Info.plist`의 `CFBundleURLTypes`에 인코딩 앱 ID 스킴 추가.

### 1. 빌드
```bash
bash store/scripts/build-release.sh android   # → app-release.aab
bash store/scripts/build-release.sh ios       # → Xcode Organizer로 업로드
```
(API_BASE_URL 프로덕션 주입 + DEV_SESSION=false 강제 — 빠뜨리면 앱이 기동 시 스스로 멈춘다)

### 2. Play Console (play.google.com/console)
1. 앱 만들기: "라이즈 컨디셔닝 - PT 회원 앱" / 앱 / 무료
2. 스토어 등록정보: `metadata/play.md` 복붙 + `graphics/` 2종 + `screenshots/android/final/`
3. 데이터 보안: `privacy/play-data-safety.md` 그대로
4. 콘텐츠 등급·앱 액세스(테스트 계정): play.md 하단 가이드
5. AAB 업로드 → 비공개 테스트(내부 테스트 권장) → 프로덕션

### 3. App Store Connect (appstoreconnect.apple.com)
1. 앱 등록: 번들 ID `ai.stra.rize`, 이름 "라이즈 컨디셔닝 - PT 회원 앱"
2. 등록 정보: `metadata/appstore.md` + `screenshots/ios/final/`(6.9" 슬롯 — 1320x2868 그대로)
3. 앱 개인정보: `privacy/apple-app-privacy.md` 그대로
4. 심사 정보: appstore.md의 심사 노트 + 데모 계정
5. Xcode Organizer에서 빌드 업로드 → 버전에 연결 → 제출

## 스크린샷 재캡처
```bash
bash store/screenshots/capture.sh ios       # iPhone 16 Pro Max 시뮬(6.9")
bash store/screenshots/capture.sh android   # rise_test AVD
```
시드 백엔드(8081) + 데모 사진 서버(8082)를 띄우고, 데모 회원 김민지(패스 2·예약·홈워크·
인바디 2회·수업기록·체형사진 4장·사진 코치 3명)로 **앱을 실제 실행**해 7화면을 순회 캡처한다.
시나리오: `app/integration_test/store_screenshots_test.dart`.

로그인은 세션 직접 주입으로 우회한다 — Firebase SMS 인증은 드라이브 하네스 안에서 완주가
안 되고(reCAPTCHA/APNs 경로), API 신원은 `--dart-define=DEV_UID=member1` dev 헤더가 시드
김민지를 가리키므로 **이후 모든 화면은 실서버 데이터로 실동작**한다.

캡처 뒤 프레임 이미지 생성(제출용):
```bash
python3 -m venv .venv && .venv/bin/pip install pillow    # 최초 1회
.venv/bin/python store/screenshots/frame.py ios
.venv/bin/python store/screenshots/frame.py android
```
캡션·순서는 `metadata/play.md`의 표와 `frame.py`의 `PLAN`이 단일 진실 — 수정 시 양쪽 함께.
