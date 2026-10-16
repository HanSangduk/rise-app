---
id: P75
title: iOS 전화번호 인증 후 "Page Not Found" — reCAPTCHA 복귀 URL이 go_router로 새던 결함 · 플랫폼 딥링크 게이트
status: 완료
domain: app
created: 2026-10-15
completed: 2026-10-16
---

# P75 — "폰 넘버까지 적으면 저렇게 돼요"

## 목표 (람 요청)
카톡 스크린샷(2026-10-14, 소이 pt): iOS에서 전화번호 입력 후 화면 전체가
`Page Not Found / GoException: no routes for location: app-1-773077624928-ios-3b39ab1c6c889eb0b0fb05://firebaseauth/link?deep_link_id=…`
로 바뀜. 원인 확인 · 수정 → `/ram-verify-loop`로 완성도 반복 검증.

## 근본 원인 (소스로 확정 — 로컬 pub-cache · Pods · Flutter 엔진 소스)
1. **왜 reCAPTCHA로 가나**: 저장소에 푸시 엔타이틀먼트(`aps-environment`)가 없고 APNs 키도 미업로드(P46
   후속 메모) → `PhoneAuthProvider.verifyClient`가 APNs 토큰을 못 받아 **iOS 실번호 인증은 전부**
   reCAPTCHA(SFSafariViewController)로 간다. 심사 번호만 `appVerificationDisabledForTesting`이라 심사는 통과.
   **디버그 빌드는 앱 검증을 끈다**(`auth_repository_impl.dart:50` `kDebugMode`) → 개발 중엔 절대 안 보인다.
2. **복귀 URL이 두 번 배달된다**: Firebase 플러그인 등록 시점에 `[FIRApp configure]`(firebase_core
   `sharedInstance`) → Auth(alwaysEager)가 `GULSceneDelegateSwizzler`로 SceneDelegate를 프록시.
   스위즐러의 `scene:openURLContexts:`는 **인터셉터(Auth) 먼저 → 원래 구현 나중** 순서로 둘 다 부른다
   (`GULSceneDelegateSwizzler.m:318-341`). Auth가 먼저 `canHandle` → `finishPresentation`
   (`callbackMatcher = nil`)으로 소비 — reCAPTCHA 자체는 **성공**한다.
3. **두 번째 배달이 라우터로 샌다**: 원래 `FlutterSceneDelegate` → 엔진이 플러그인에 묻고
   (`FLTFirebaseAuthPlugin scene:openURLContexts:` → `canHandleURL` 재호출 → matcher가 이미 nil → NO)
   → 처리한 플러그인이 없으면 `handleDeeplink` → `sendDeepLinkToFramework`
   (`FlutterSceneLifeCycle.mm:289-316`, 462-477). `FlutterDeepLinkingEnabled` 미설정 = 켜짐
   (`FlutterSharedApplication.mm:60-67`) → go_router가 `app-1-…://firebaseauth/link` 매칭 실패 → 기본 에러 화면.
4. **사용자가 갇힌다**: PhoneScreen이 내려가 `_submit`의 `if (!mounted) return;`(phone_screen.dart:151-156)
   에 걸려 codeSent 뒤 `/login/code` 이동이 사라진다. 에러 화면의 Home(`/`)도 라우트가 없다.
   재실행해도 세션이 없어 같은 경로 → **iOS 실사용자 신규 가입·로그인 전면 불가(CRITICAL)**.
5. **같은 결함 클래스(OS → 라우터 유입)**: P64 D4는 **시작 라우트**만 막았다(`overridePlatformDefaultLocation`).
   실행 중 유입 — iOS `openURL` · Android `onNewIntent`의 intent data(`FlutterActivityAndFragmentDelegate.java:965-981`,
   MainActivity exported+singleTop) — 은 열려 있었다. 둘 다 엔진의 같은 스위치가 지킨다
   (iOS `FlutterDeepLinkingEnabled` · Android `flutter_deeplinking_enabled`, 둘 다 미설정 시 켜짐).

## 외부 조사 (에이전트 1팀 · 1차 출처 인용 — 2026-10-15)
- 같은 GoException 공개 보고: flutter/flutter#167836(2025-04, "third party" 종료) · flutterfire#17135(stale 종료)
  · flutterfire#17035(작성자가 `FlutterDeepLinkingEnabled=false`로 해결, "Firebase was still correctly handling
  the deep link events"). react-native-firebase#7258→PR#8203이 **같은 이중 전달**을 독립 분석("intercept the
  openURL call … but then it also passes along the same openURL call"). firebase-ios-sdk#13649(scene 세계의
  `canHandle` 반환 의미 문제, open). **메인테이너 공식 수리 없음.**
- 최신판도 동작 동일: firebase_auth **7.0.0(2026-10-15 게시, iOS SDK 13, breaking)** · Flutter stable 3.47.7의
  `FlutterSceneLifeCycle.mm`/`FlutterSharedApplication.mm`은 3.44.0과 diff 없음 → **업그레이드로 안 풀린다**.
- 공식 문서: Flutter "deep-links-flag-change"(3.27 기본값 false→true, 다른 딥링크 처리 시 false로) ·
  `/ui/navigation/deep-linking`("set FlutterDeepLinkingEnabled to false … flutter_deeplinking_enabled to false").
  Firebase iOS 전화 인증 문서: 스위즐링이 커스텀 스킴 복귀를 가로챈다 · `FirebaseAppDelegateProxyEnabled=NO`는
  다른 Firebase 제품의 스위즐링까지 끈다(비권장).

## 자 (고치기 전에 만든 것 · 실물)
| 자 | 수정 전 | 수정 후 |
|---|---|---|
| **실기기 시나리오**(iPhone 12 · iOS 26.6.2 · 프로필 빌드 · 테스트 번호 010-5555-6666 · `integration_test/phone_auth_recaptcha_return_test.dart`) | **2/2 라우터 누수**(6s·10s) — 위치 `app-1-…://firebaseauth/link`, 화면 = 사용자 스크린샷과 동일, **codeSent가 누수 1~2초 뒤 도착** | **2/2 인증번호 화면**(8s·12s) — 위치 `/login/code`, "010-5555-6666로 보냈어요" |
| 가드 시험 `test/core/router/platform_deeplink_gate_test.dart` | iOS·Android 2건 빨강(키 0개) · 스킴 일치 1건 초록 | 3/3 초록 |
| 아카이브 검사(옛 아카이브 빌드 6) | 스킴 ✓ · 딥링크 스위치 🚨 | (새 아카이브는 출시 빌드에서) |
| 하네스 `store/scripts/test-build-guards.sh` | — | 33/33 |
| 오류 문구 `test/features/auth/data/phone_auth_error_map_test.dart` | 3건 빨강("인증에 실패했어요 (web-context-cancelled)") | 4/4 초록 |
| 전체 스위트 | +1545 −3(내 가드 2 + P74 미완 편집 1) | (아래 검증) |

- **이중 배달 확증**: 수정 전 런에서 에러 화면 **뒤에** codeSent가 왔다 = Firebase는 reCAPTCHA 복귀 URL을 정상 소비했고 같은
  URL이 라우터에도 갔다(조사 에이전트가 남긴 "스위즐러 설치 순서 미확정" 고리를 실측으로 닫음).
- 조건: 프로필 빌드(kDebugMode=false → 앱 검증 켜짐), 유선, 기기 잠금 해제, Mac 화면 잠김(→ Xcode 자동화 대신 devicectl 헤드리스).
- **측정 무효 1회**(정정): 첫 헤드리스 런은 `tester.enterText`가 입력란에 닿지 않아(통합 테스트 바인딩
  `registerTestTextInput => false`) 빈 번호로 "다시 확인해주세요" — reCAPTCHA까지 가지 않은 무효 측정. 하네스에
  가짜 키보드 등록 + "입력이 실제로 들어갔나" 자체 단언을 넣고 다시 쟀다. (P09 live_flow_test의 "SMS 인증이 하네스
  안에서 완주 안 된다"도 같은 원인일 수 있다 — 후속 작업.)
- **설치 불가 산출물 1회**: `flutter build ios`가 "Built build/ios/iphoneos/Runner.app"이라 출력하지만 그 사본은 서명이
  깨져 있다(설치 0xe8008001 — 처음엔 23:40 런의 낡은 사본인 줄 알았으나 00:51 재빌드 직후 새 사본도 `codesign --verify`
  실패: Flutter.framework/Info.plist가 서명 뒤 원본으로 덮인다). 설치는 `build/ios/Profile-iphoneos/`에서 — 스크립트가
  mtime·서명·바이너리 안 표식 문자열(`harness v3`)을 확인한 사본만 설치한다.

## 결정 사항
- **D1 입구에서 닫는다 — 두 플랫폼의 Flutter 딥링크 스위치 끔.** iOS `Info.plist` `FlutterDeepLinkingEnabled=false`,
  Android `MainActivity` 메타데이터 `flutter_deeplinking_enabled=false`. 이 앱은 딥링크가 없다(라우터 주석·매니페스트·
  엔타이틀먼트 확인). Firebase는 스위치와 무관하게 URL을 네이티브에서 먼저 받는다(스위즐러 인터셉터 → 플러그인 →
  그다음에야 딥링크 단계) — 실기기로 확인(수정 후 codeSent·인증번호 화면 2/2).
- **D2 안드로이드도 실재하는 구멍이었다**(예방이 아님): 실행 중 앱에 `am start -n …/.MainActivity -d <URL>` 한 번이면
  같은 "Page Not Found"(에뮬레이터 실측). exported+singleTop이라 아무 앱이나 보낼 수 있다. 같은 한 줄로 닫힘(실측).
- **D3 기계 가드 3겹**: ① `platform_deeplink_gate_test.dart` — 두 스위치(주석 걷어 내고 · iOS는 최상위 dict 직속 · Android는
  액티비티 범위·병합 마커 없음 — 뒤 둘은 반박 N1·N2로 보강) + reCAPTCHA 복귀
  스킴 ↔ Firebase 앱 ID 3원천 대조(P46의 크래시 형제) ② `verify-ios-archive.sh` — **산출물** Info.plist에서 같은 두 가지
  ③ `test-build-guards.sh` 하네스 칸 5개(메시지로 1건만 실패하는지). 사람 기억에 맡기던 P46 "앱 ID 바뀌면 스킴 교체"도 기계화.
- **D4 같은 장면의 인접 증상 — reCAPTCHA 시트 오류 문구.** 수정 후엔 iOS 실사용자 전원이 사파리 시트를 지나는데, 시트를
  닫으면 "인증에 실패했어요 (web-context-cancelled)"(영문 코드)가 떴다. `mapPhoneAuthError`를 시험 가능한 최상위 함수로
  꺼내(동작 동일) 시트 닫음(iOS cancelled·Android canceled 두 철자)·시트 안 망 오류·internal-error·앱 검증 코드를
  한국어로, 그리고 **web-*·*recaptcha* 계열 전체**를 한 규칙으로 받는다(반박에서 목록 방식이 둘을 빠뜨린 게 드러나
  클래스로 닫음). 시트 닫음 문구는 번호 화면·코드 화면(재전송) 공통이라 버튼 이름을 말하지 않는다.
- **D5 codeSent 상한 70→180초**(반박 F1, MEDIUM): 사람이 그림 퍼즐을 푸는 동안 70초가 지나면 "지연" 오류 뒤 SMS가
  나가고(늦은 codeSent는 버려짐) 재시도 시 두 번째 SMS. reCAPTCHA 문제 화면 만료(약 2분)보다 넉넉하게. 비용은 "콜백이
  영영 안 오는" 병적 경우의 대기뿐(시트가 떠 있으면 회원이 닫아 즉시 오류를 받는다).
- **안 하기로 한 것**
  - 라우터 단 필터(go_router `onException`/`onEnter`로 `firebaseauth/link` 무시): 두 입구가 닫힌 지금 프로덕션에선 도달
    불가 코드다. 딥링크를 넣는 날 가드 시험이 빨개지며 "라우터가 그 URL을 무시하게 만든 뒤 켜라"를 요구한다 — 그때 넣는다.
  - firebase_auth 7.0.0(오늘 게시, breaking) 업그레이드: 이 결함 수리 없음(조사 확인) — 이번 수리에 섞지 않는다.
  - `FirebaseAppDelegateProxyEnabled=NO`(이중 배달 자체를 끔): 다른 Firebase 제품 스위즐링까지 꺼진다(공식 문서) — 비권장.
  - 푸시 엔타이틀먼트 추가(사파리 시트 자체를 줄이는 근본 UX): APNs 키 업로드 없이 넣으면 사일런트 푸시를 기다리다
    타임아웃 뒤 reCAPTCHA로 가 더 느려진다 — 람의 Apple 개발자 계정 작업과 짝으로만(후속 작업).

## 진행 단계
- [x] 근본 원인 — 소스로 경로 확정(Flutter 엔진 · firebase_auth 플러그인 · FirebaseAuth iOS SDK · GoogleUtilities)
- [x] 자(재현) — 시뮬레이터는 디버그만 돼 앱 검증이 꺼져 못 잼 → **람 지적("실기기 연결돼 있는데 왜 시뮬로")으로 실기기
      프로필 빌드 전환**, Mac 잠김이라 devicectl 헤드리스. 수정 전 빨강 2/2(사용자 스크린샷과 같은 화면)
- [x] 수정 — iOS·Android 스위치, 기계 가드 3겹, reCAPTCHA 오류 문구, codeSent 상한
- [x] 같은 자로 초록 + 실물 — iOS 3/3 인증번호 화면, Android 탐침 v2(기준선으로 검정)
- [x] 교차검증 루프 — 외부 조사 1팀 → 반박(opus, 새 컨텍스트) 1라운드: CRITICAL·HIGH 0 → 지적 반영 → 2차 변이 6/6
- [x] 측정 흔적 원복 — Generated.xcconfig·flutter_export_environment.sh(`--config-only --release`), project.pbxproj
      (Flutter 마이그레이션 objectVersion 60→54 + 내 drive 런이 띄운 Xcode의 재저장: 빈 inputPaths 제거·SPM 주석 변경)
      > **정정(P77)**: 빈 inputPaths 제거·SPM 주석 변경은 Xcode가 아니라 빌드가 부른 `pod install`(CocoaPods Xcodeproj 젬)의
      > 재직렬화다 — Xcode GUI 없이도 재현(work_log/P77).
      → "HEAD − P73 리터럴 6줄"로, 권한 600→644, Xcode 종료, 아이폰 시험 앱 삭제, 에뮬레이터 종료, 서명 깨진
      build/ios/iphoneos/Runner.app 삭제

## 변경 파일 (P75 몫 — 같은 파일의 다른 세션 변경 제외)
- `app/ios/Runner/Info.plist` — `FlutterDeepLinkingEnabled=false`(+주석)
- `app/android/app/src/main/AndroidManifest.xml` — MainActivity 메타데이터 `flutter_deeplinking_enabled=false`(+주석)
- `app/lib/core/router/app_router.dart` — 주석(실행 중 유입은 네이티브 스위치가 막는다 · 딥링크 넣는 날의 조건)
- `app/lib/features/auth/data/auth_repository_impl.dart` — `mapPhoneAuthError` 최상위 추출(@visibleForTesting) + reCAPTCHA
  계열 매핑 + `_codeSentTimeout` 70→180초
- `app/test/core/router/platform_deeplink_gate_test.dart`(신규) · `app/test/features/auth/data/phone_auth_error_map_test.dart`(신규)
- `app/integration_test/phone_auth_recaptcha_return_test.dart`(신규 — 실기기 하네스, 실행법은 머리 주석)
- `store/scripts/verify-ios-archive.sh`(산출물 검사 2줄) · `store/scripts/test-build-guards.sh`(mk_archive recaptcha 모드 ·
  expect_one · 칸 5개 — 버전 리터럴 칸 4개는 P74 몫)
- `store/README.md`(틀린 주장 정정 + 검사 목록) · `work_log/P46…`(정정 표시) · `work_log/README.md`(인덱스)

## 검증
**실기기 iOS(iPhone 12 · iOS 26.6.2 · 프로필 · 테스트 번호 010-5555-6666 · 같은 하네스로 Dart 바이너리 동일, Info.plist만 다름)**
| 런 | 스위치 | 라우터 누수 | codeSent | 최종 위치 |
|---|---|---|---|---|
| baseline_v2 | 없음 | **10s** | 11s(누수 뒤) | `app-1-…://firebaseauth/link` |
| baseline_v3 | 없음 | **6s** | 8s(누수 뒤) | 〃 |
| fixed_v2 | false | 없음 | 12s | `/login/code` |
| fixed_v3 | false | 없음 | 8s | `/login/code`(캡처: "010-5555-6666로 보냈어요") |
| final_fixed(최종 코드) | false | 없음 | 8s | `/login/code` |

**Android 에뮬레이터(rise_test · 디버그 APK · 실행 중 앱에 `am start -n …/.MainActivity -d app-1-…://firebaseauth/link…`)**
| 탐침 | 기준선(스위치 없음) | 수정(false) |
|---|---|---|
| v1(캡처) | 로그인 → **Page Not Found** | 판별력 없음(반박 F8: 첫 프레임 전에 인텐트) — 폐기 |
| v2(접근성 덤프로 로그인 화면 확인 뒤 · 글자 판정) | routerLeak=**true** · 로그인 사라짐 | routerLeak=false · 로그인 유지 |

**시험·정적 검사**
| 자 | 착수 | 완료 |
|---|---|---|
| 전체 스위트 | +1545 −3 | **1561 전부 통과**(+4는 P75, 나머지는 같은 시간 P74 추가분) |
| `flutter analyze` | — | 0건 |
| 빌드 가드 하네스 | — | 33/33(원복 뒤 재실행 포함) |

**변이 검사(ram-mutate · 백업·sha256 복구 확인)**
| 회차 | 대상 | 결과 |
|---|---|---|
| 1 | 가드 시험(스위치 켬·삭제·주석 처리 / 매니페스트 true·application 단 이동·주석 / 스킴·앱 ID 어긋남·REVERSED_CLIENT_ID 등장) | 9/9 KILLED |
| 1 | 아카이브 검사 스크립트(판정 느슨화·통째 통과·아무 스킴·파일 존재 가드 제거) | 4/4 KILLED |
| 2 | 반박 N1(하위 dict로 이동)·N2(`tools:node="remove"`)·매핑 MP1~MP4 | 첫 실행 5/6 — **MP1(Android 철자 제거) 생존**: 계열 규칙이 "…다시 시도"로 받아 "다시"만 보던 단언이 통과 → "창이 닫혔" 의미 단언 추가 → **6/6 KILLED** |
| — | `_codeSentTimeout` 180초 | 시험 없음 — FirebaseAuth.instance 직접 의존이라 타이머 경로를 단위로 못 잰다(확인 못 함) |

**반박 라운드**
| 라운드 | CRITICAL | HIGH | MEDIUM | LOW | 처리 |
|---|---|---|---|---|---|
| 1(opus · 새 컨텍스트 · 원본 diff·실기기 로그) | 0 | 0 | 1(F1) | 10 | 주장 1~3 CONFIRMED. F1·F2·F3·F4·F5·F6·F7·F8·F11 반영, F9 원복 완료, F10 의도된 결정 유지 |

**정정** — "APNs 없어도 reCAPTCHA로 동작은 한다"(P46 184행 · store/README) → 실제로는 막혀 있었다(실기기 재현) → 두 곳에 정정 표시.

## 확인 못 한 것 (수단 부재)
- **사파리 시트를 스와이프(가장자리·아래)로 닫을 때** `safariViewControllerDidFinish`가 불리는지 — 안 불리면 Firebase가
  "시트가 떠 있음"에 갇혀 이후 시도가 즉시 web-context-cancelled(앱을 다시 켤 때까지)일 수 있다(반박 지적, 영향 HIGH 가능).
  사람 손이 필요해 람 확인으로 넘김(후속 3). 웹 검색으로 1차 근거 없음.
- 실번호 + 그림 퍼즐 + 배포 서명 릴리스 경로(테스트 번호는 6~12초 자동 통과) · 180초 상한의 사람 퍼즐 실측.
- Android Custom Tab 실제 취소 코드(SDK 바이너리 문자열 `ERROR_WEB_CONTEXT_CANCELED`로만 확인).

## 안 한 것 (결정)
- 결정 사항의 "안 하기로 한 것" 4건 + 반박 F10(라우터 단 방어) 유지.
- 범위 밖 메모(반박): 같은 프로세스에서 심사 번호 뒤 실번호를 넣으면 `appVerificationDisabledForTesting`이 켜진 채 남는다 —
  심사자 경로 한정.

## 후속 작업
1. **[람 · 필수] iOS 새 빌드 심사 제출** — 지금 스토어 앱은 업데이트 전까지 계속 막힌다(서버·콘솔로 완화할 수단 없음 —
   바이너리에 스위치도 푸시 엔타이틀먼트도 없다). pubspec 버전 올린 뒤 `bash store/scripts/build-release.sh ios`
   (검사 스크립트가 스위치·스킴까지 본다).
2. [람 · 권장] 사파리 시트 자체를 줄이기: Apple 개발자 › Keys › APNs 키(.p8) → Firebase 콘솔 업로드 **+** Xcode Runner에
   Push Notifications · Background Modes(Remote notifications). 둘은 반드시 함께.
3. [람 · 확인 1분] 실기기에서 인증번호 받기 → 사파리 시트를 **왼쪽 가장자리 스와이프**로 닫기 → 다시 인증번호 받기.
   시트가 다시 뜨면 정상, "창이 닫혔어요"만 반복되면 갇힘(→ AuthUIDelegate로 직접 띄우기 검토).
4. P09 `integration_test/live_flow_test.dart`의 `enterText`도 가짜 키보드 미등록일 수 있다("SMS 인증이 하네스 안에서
   완주 안 된다"의 진짜 원인 후보) — 고칠 때 `tester.testTextInput.register()`.
5. Android는 다음 정기 릴리스에 포함(긴급 아님 — 외부 앱이 인텐트를 보내야 열리는 구멍).
6. 다시 열 조건: 딥링크 도입(가드 시험이 빨개진다 → 라우터가 `firebaseauth/link` 무시 + shell_gate 손본 뒤 스위치 켜기).

## 자문자답 (해소)
- 개발 중엔 왜 안 보였나 → 디버그는 앱 검증을 끈다. 심사는 왜 통과했나 → 심사 번호만 앱 검증 우회.
- 스위치를 끄면 Firebase 인증이 깨지나 → 아니다: 스위치는 딥링크 단계만, Firebase는 그 앞(스위즐러·플러그인)에서 소비(실측 codeSent).
- 업그레이드로 풀리나 → firebase_auth 7.0.0·Flutter 3.47.7 동작 동일. 잃는 기능 → 딥링크·유니버설/앱 링크 0건,
  들어오는 URL을 쓰는 플러그인은 firebase_auth뿐(반박자 확인).

## 참조
- P46(reCAPTCHA 폴백용 URL 스킴 등록 · APNs 키 미업로드 메모) · P64 D4(`overridePlatformDefaultLocation`) · P60(xcconfig 원복)
- 하네스·스크립트(세션 스크래치): p75_device_run.sh · p75_build_variant.sh · p75_android_probe2.sh · mut_*.json
- 메모리: ios-device-headless-run(Mac 잠김 시 실기기 헤드리스 점검 요령)
