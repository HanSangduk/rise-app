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
               build-release.sh             — AAB/IPA 빌드
               register-sha.sh              — Firebase에 서명 인증서 SHA 등록
```

## 준비 상태 (감사 결과 요약)

| 항목 | 상태 |
|---|---|
| 식별자 `com.han.rise` · 표시명 "라이즈" · 버전 단일 소스 | ✅ |
| iOS 서명(팀 ZG9DP757ZM, Automatic) · 1024 아이콘(알파 없음) | ✅ |
| 권한 문구(카메라·사진·동작) 한국어 · 불필요 권한 제거 | ✅ (모범적 — RECORD_AUDIO 제거, allowBackup=false) |
| 개인정보처리방침·계정삭제 공개 URL | ✅ https://rize-218c1.web.app/legal/privacy.html · …/account-deletion.html |
| **지원 URL(Guideline 1.5)** | ✅ https://rize-218c1.web.app/legal/support.html (P60 — 이메일 문의 정적 · 센터 연락처는 사업자 정보 등록 후 표시) |
| **사업자 정보 12항목 + 시행일 등록** | ❌ **미등록** — 법정 문서 5장이 "(미정)"·"초안" 배너를 라이브로 띄운다(5.1.1 리젝 위험). 어드민 > 설정 > 사업자 정보 |
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
3. **[완료] 심사용 계정 셋업** — 2026-08-30 실제 등록·검증 완료
   - Firebase Auth 테스트 번호 `+82 10-0000-0000 / 000000` 등록(기존 테스트 번호 2개 보존)
   - 프로덕션에 심사 회원 등록: 이름 "심사용 계정", 담당 정혜린 코치, PT 20회(잔여 14),
     인바디 2회, 수업 기록 2건, 민감정보 동의 ON
   - **실기기(에뮬레이터) 릴리스 APK로 심사자와 동일한 경로 전 구간 검증**:
     번호 입력 → 인증번호 받기 → 000000 → 자동 매칭("심사용 계정 님으로 등록되어 있어요")
     → 시작하기 → 홈(담당 코치 사진·잔여 링 14/20) → 기록(수업 2건·인바디 추이 곡선)
   - 데이터 위치: Firestore `centers/rise/{members,passes,ledger,inbody,workout_logs}`의
     `review_*` 문서. 지우려면 그 문서들만 삭제하면 된다(다른 회원과 무관).

4. **[CRITICAL] Android 서명 인증서(SHA) Firebase 등록** — 키 생성 직후·Play 업로드 직후 2번
   전화 인증은 **APK를 서명한 인증서의 SHA 지문이 Firebase에 있어야** Play Integrity를
   통과한다. 현재 등록된 건 **디버그 키 하나뿐**이라 릴리스 빌드는 무방비다
   (등록이 없으면 reCAPTCHA 웹뷰로 떨어지거나 인증이 실패한다).
   ```bash
   bash store/scripts/register-sha.sh                    # ① 업로드 키(자동)
   bash store/scripts/register-sha.sh <SHA1> <SHA256>    # ② Play 앱 서명 키(수동)
   ```
   ②는 **AAB를 처음 업로드한 뒤** Play Console > 테스트 및 출시 > 앱 무결성 >
   앱 서명 키 인증서에서 값을 복사해 넣는다. 사용자가 설치하는 APK는 Google이 다시
   서명하므로 **②가 없으면 실사용자 전화 인증이 깨진다**(심사 계정은 앱 검증을
   건너뛰므로 심사는 통과하고 출시 후에 터진다 — 가장 위험한 종류).

5. **[권장] iOS APNs 인증 키 업로드** — Firebase 콘솔 > 프로젝트 설정 > 클라우드 메시징 >
   Apple 앱 구성 > APNs 인증 키(.p8). 없으면 iOS 전화 인증이 사일런트 푸시 대신
   **reCAPTCHA 웹뷰**로 떨어진다(동작은 하지만 사용자에게 한 단계가 더 보인다 —
   URL 스킴은 이미 넣어 뒀다). 심사에는 지장 없다.
   - iOS teamId(ZG9DP757ZM)는 등록 완료(2026-08-30).
   - App Store ID는 앱 생성 후 채우면 된다(선택).

6. [완료] iOS 배포 타겟 15.5로 상향 — ML Kit pod이 15.0에서 pod install 자체를 거부해
   빌드가 불가능했다(캡처 중 실측). Podfile + pbxproj 3곳 동시 반영.
7. [완료] Firebase Phone Auth URL 스킴 등록 — 시뮬레이터에서 "인증번호 받기" 순간
   PhoneAuthProvider가 fatal로 죽던 실버그(실기기는 APNs 경로라 P09 실측에서 안 드러남).
   `Info.plist`의 `CFBundleURLTypes`에 인코딩 앱 ID 스킴 추가.

### 1. 빌드
```bash
bash store/scripts/build-release.sh android   # → app-release.aab
bash store/scripts/build-release.sh ios       # → build/ios/ipa/*.ipa + 아카이브 실물 검사(통과해야 업로드)
```
> 🚨 **iOS는 Xcode Organizer에서 직접 Archive하지 않는다(P60).** `flutter run/drive`가 마지막으로 남긴
> `app/ios/Flutter/Generated.xcconfig`(진입점·dart-define)를 Xcode가 그대로 읽는다. 2026-08-30 아카이브 3개는
> 스크린샷 캡처(`capture.sh`)가 남긴 `FLUTTER_TARGET=integration_test/…` + `API_BASE_URL=http://localhost:8081`로
> 컴파일돼 **통합테스트가 앱으로 올라갔고** 1.0 (3)이 2.1(a)로 리젝됐다. 방어선 3겹:
> ① `build-release.sh ios`가 `flutter build ipa`로 xcconfig를 다시 쓴다 ② Xcode 빌드 페이즈 가드
> `app/ios/scripts/check_release_target.sh`가 Release/Profile에서 테스트 진입점·localhost를 거부한다
> ③ `store/scripts/verify-ios-archive.sh`가 산출물에서 프로덕션 주소·로컬 주소·`integration_test` 잔재·심사 번호를 검사한다.
> 부득이 Organizer로 만들었다면 업로드 전에 `bash store/scripts/verify-ios-archive.sh ~/Library/Developer/Xcode/Archives/<날짜>/<이름>.xcarchive`.
릴리스 기본값이 이미 프로덕션 API이고(`api_config.dart`), 디버그만 로컬을 봅니다 —
스크립트는 `DEV_SESSION=false`만 강제합니다. 스테이징으로 돌리려면
`API_BASE_URL=https://... bash store/scripts/build-release.sh android`.

### 2. Play Console (play.google.com/console)
1. 앱 만들기: "라이즈 컨디셔닝 - PT 회원 앱" / 앱 / 무료
2. 스토어 등록정보: `metadata/play.md` 복붙 + `graphics/` 2종 + `screenshots/android/final/`
3. 데이터 보안: `privacy/play-data-safety.md` 그대로
4. 콘텐츠 등급·앱 액세스(테스트 계정): play.md 하단 가이드
5. AAB 업로드 → 비공개 테스트(내부 테스트 권장) → 프로덕션

### 3. App Store Connect (appstoreconnect.apple.com)
0. **먼저 App ID를 등록한다** — developer.apple.com > Certificates, Identifiers & Profiles >
   Identifiers > `+` > App IDs > App > **Explicit** `com.han.rise`.
   이걸 안 하면 App Store Connect의 신규 앱 **번들 ID 드롭다운에 아예 안 뜬다**(Xcode에서
   팀만 고른 상태로는 등록되지 않는다 — 실기기 빌드나 Archive를 해야 자동 등록된다).
   - **팀 선택기를 `Sangduk Han`(ZG9DP757ZM)으로.** `STRA Co,. Ltd.`(4RQD93MV57)에도
     소속돼 있어서 잘못 고르면 그쪽 계정에 생기고 본인 App Store Connect엔 안 보인다.
   - Capabilities는 **Push Notifications만** 체크(Firebase 전화 인증의 APNs 사일런트 검증.
     없으면 reCAPTCHA 웹뷰로 떨어진다). Broadcast 등 나머지는 끈다 — 안 쓰는 entitlement이
     프로파일에 박히면 심사 문의 사유가 된다.
1. 앱 등록: 번들 ID `com.han.rise`, 이름 "라이즈 컨디셔닝 - PT 회원 앱"
   - **SKU `rise-member-ios`** — 내부 식별자(사용자 비노출, 판매 보고서용).
     **저장 후 변경 불가**라 여기 고정한다. 트레이너 앱이 생기면 `rise-trainer-ios`.
   - 사용자 액세스 권한: **제한 없음**(1인 팀이라 제한할 대상이 없다)
2. 등록 정보: `metadata/appstore.md` + `screenshots/ios/final/`(6.9" 슬롯 — 1320x2868 그대로)
3. 앱 개인정보: `privacy/apple-app-privacy.md` 그대로
4. 심사 정보: appstore.md의 심사 노트 + 데모 계정
5. 업로드: **Transporter** 앱(App Store)에 `app/build/ios/ipa/*.ipa`를 넣거나 `open app/build/ios/archive/Runner.xcarchive`
   → Organizer > Distribute App(**Organizer의 Archive 버튼은 누르지 않는다** — 이미 만들어진 아카이브를 올리기만).
   처리(약 10~30분) 뒤 App Store Connect에서 버전에 빌드 연결 → 제출.
   재제출이면 리젝 메시지에 `metadata/appstore.md`의 "심사 회신" 문안으로 답글을 남긴다.

## 스크린샷 재캡처
```bash
bash store/screenshots/capture.sh ios       # iPhone 16 Pro Max 시뮬(6.9")
bash store/screenshots/capture.sh android   # rise_test AVD
```
> **UI가 바뀌면 반드시 다시 찍는다 — 색만 덧칠하지 말 것.** P54에서 브랜드가 로즈에서
> 네이비로 바뀌었을 때 "이미 있는 이미지의 색만 바꾸면 되지 않나"를 검토했는데 안 된다:
> ① 탭 바가 FAB 헤드룸만큼 **높아져 레이아웃이 이동**했고 ② 바뀐 건 브랜드만이 아니라
> 비활성 탭 회색·배지 회색·입력 보더·다이얼로그 모서리까지이며 ③ FAB 글로우가 브랜드
> 알파 40%라 안티에일리어싱된 가장자리를 색 치환하면 지저분해진다.
> 스토어 심사는 스크린샷이 실제 앱을 반영할 것을 요구한다(Apple 2.3 정확한 메타데이터).
> 업로드가 막히지는 않지만 리젝 여지가 있고, 무엇보다 받은 앱이 스토어와 달라 보인다.
>
> **실기기가 함께 꽂혀 있으면** `ANDROID_SERIAL=emulator-5554`를 앞에 붙인다 —
> 스크립트의 `adb`가 대상을 못 골라 "more than one device"로 죽는다.
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
