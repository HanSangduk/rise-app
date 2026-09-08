---
id: P60
title: App Store 리젝(1.0(3)) 대응 — 캡처 설정이 실린 iOS 아카이브 수리 · 빌드 가드 3겹 · 고객 지원 페이지(지원 URL)
status: 완료
domain: app
created: 2026-09-04
completed: 2026-09-04
---

# P60 — App Store 리젝 대응 (Guideline 2.1(a) 무한 스피너 · 1.5 지원 URL)

## 목표
2026-09-01 Apple 리젝 2건의 **실제 원인을 실물로 확정**하고, 재발 불가능하게 고친 뒤 재제출 가능한
상태(검증된 아카이브 + 살아 있는 지원 URL + 회신 문안)까지 만든다.

## 결정 사항
- **2.1(a)의 원인은 앱 코드가 아니라 빌드 산출물이다.** `store/screenshots/capture.sh ios`가 돌린
  `flutter drive --target=integration_test/store_screenshots_test.dart --dart-define=API_BASE_URL=http://localhost:8081 …`가
  `app/ios/Flutter/Generated.xcconfig`에 `FLUTTER_TARGET=integration_test/…`와 localhost dart-define을 남겼고
  (mtime 08-30 10:05), 그날 오후 Xcode Organizer Archive 3개(빌드 1·2·3, 17:17/17:34/22:47)가 그 파일을
  그대로 읽어 **통합테스트를 앱 진입점으로 AOT 컴파일**했다.
  - 실물 증거: 세 아카이브 `App.framework/App` 전부 프로덕션 URL 0건 · `http://localhost:8081`/`8082` 각 1건 ·
    `integration_test` 문자열 9건 · `Frameworks/integration_test.framework` 포함. 세 아카이브 크기 동일(9,380,848B).
  - Cloud Run 로그(08-29~09-04): Apple 기기 요청 **0건**. 심사 계정(`review_member_001`) 트래픽은 08-30 람 기기와
    08-30 23:01 KST Google Play 크롤러(66.249.x)뿐 — Android는 정상, iOS만 서버에 닿지 못했다.
  - 심사 스크린샷(기록 탭 > 체형 분석 스피너)은 통합테스트의 5번째 단계와 정확히 일치한다: 테스트가 로그인을
    건너뛰고 가짜 세션(김민지)을 주입해 홈→예약→기록→인바디→체형 분석으로 자동 이동, API는 localhost라
    전부 실패, 이 빌드엔 `appRetry`도 없어(테스트의 `ProviderScope`는 `retry:` 미지정) Riverpod 기본 재시도
    10회 동안 스피너. "로그인 시도 중 스피너"는 로그인 화면을 보던 심사자 앞에서 앱이 저절로 셸로 넘어간 장면.
  - `api_config.dart`의 localhost 릴리스 가드는 **`lib/main.dart`가 진입점일 때만** 돈다 — 진입점이 바뀌면 무력.
    그래서 가드를 Dart가 아니라 **Xcode 빌드 페이즈**에 둔다.
- **1.5의 원인**: 지원 URL(`legal/index.html`)에 문의 수단이 없다. "문의" 칸이 `(보호책임자 이메일 미정)`·
  `(대표 전화 미정)` — 프로덕션 `GET /api/v1/public/business`가 전 필드 빈 문자열(`complete:false`), 즉 어드민
  **설정 → 사업자 정보**가 미등록. 상단 "아직 시행 전 초안입니다 … 앱 스토어 제출에 쓰면 안 됩니다" 배너도
  심사자에게 노출됐다(개인정보처리방침 URL도 같은 상태라 5.1.1 리젝 위험).
- 지원 이메일은 **`richramsang@gmail.com`**(람 지정, 09-06). 최초엔 Play 등록정보의 `ramsang@stra.ai`를 그대로 썼는데 그 주소는 이전 회사 도메인이라(P46이 패키지에서 걷어낸 그 네임스페이스) 스토어 공개 연락처로 남길 이유가 없다. 지원 페이지 3곳·법정 색인 1곳·Play 등록정보 2곳·App Store 심사 담당자 연락처까지 전량 교체(잔여 0건) 후 Hosting 재배포·라이브 확인.
  센터 전화·주소는 사업자 정보 API에서 **값이 있을 때만** 표시한다 — 지원 페이지에 "(미정)" 자리가 있으면 1.5가 재발한다.
- 버전 단일 소스 복원: Xcode 프로젝트에 손으로 박힌 `FLUTTER_BUILD_NAME=1.0.0`/`FLUTTER_BUILD_NUMBER=3`
  (Debug·Release·Profile 3곳)을 제거하고 `pubspec.yaml` `1.0.0+4`가 iOS·Android 모두를 정한다.
- 동시 세션(P57 백엔드 · P59 앱 — 진행 중)의 파일은 건드리지 않는다. 앱 빌드는 analyze/test 그린을 확인한 트리
  상태로 만들고, P59 완료 후 재빌드 여부는 람에게 보고한다.

## 진행 단계
- [x] 원인 규명(아카이브 바이너리 · Generated.xcconfig · Cloud Run 로그 · Firebase Auth 설정 교차검증)
- [x] 빌드 가드 3겹: Xcode 빌드 페이즈 가드 · capture.sh xcconfig 복원 trap · 아카이브 실물 검사 스크립트(리젝 아카이브에 적용해 4건 🚨 실증)
- [x] 버전 단일 소스(pbxproj 하드코드 제거 · pubspec 1.0.0+4 · Generated.xcconfig 재생성 → FLUTTER_TARGET=lib/main.dart, BUILD_NUMBER=4)
- [x] 고객 지원 페이지 + 법정 문서 색인 연결 + 스토어 메타(지원 URL·회신 문안·README)
- [x] 정책 리뷰 반영 — FAQ 사실 오류 6건(국가 선택기 없음·재전송 30초·마감 후 취소 가능+차감·동의 철회 시 본인 열람 유지·미연결 문구·인바디 삭제 범위) + 심사 노트 정정(국가 선택·연결 요청) + 회신 문안 축약 + Info.plist 사진 보관함 문구 정정
- [x] 기술 리뷰 반영 — 가드를 Release(플레이버명 포함)만 검사하도록(Profile은 `flutter run --profile`+LAN 서버·`flutter drive --profile`이 정상 경로) · 절대경로 진입점 허용 · capture.sh trap을 ios 분기로(Android drive는 xcconfig를 안 씀) · 검사 스크립트에 pubspec 버전 일치·캡처 하네스 마커 추가 · README "Organizer는 업로드만"
- [x] `flutter build ipa` 1차(파이프라인 검증) → 아카이브 검사 통과(1.0.0 (4) · 프로덕션 URL 1건 · 로컬 0 · integration_test 문자열 0 · Apple Distribution 서명) — **업로드 보류**: 피어 세션(P59 app/lib 편집 중) 완료 후 재아카이브
- [x] Hosting 배포(`./deploy-hosting.sh` 빌드+배포+스모크 통과) + 라이브 검증: support.html 200/16,487B · 로컬과 바이트 동일 · 이메일 3건 · "(미정)" 0건 · index 카드 05 반영 · 피어(P57/P59)의 법정 문서 수정분 함께 반영
- [x] 피어(ptdesk-33) "아카이브 가능" 신호 + 자체 재확인(analyze 0 · 1265 pass) 후 `build-release.sh ios`(23:36) → 검사 통과
- [x] 피어가 직후 P56 L10(센터 상호·전화를 `GET /v1/public/center`에서 읽기, app/lib 6파일)을 추가 → Android 1.0.0+4와 갈리지 않게 **재아카이브(09-05 00:14)**: analyze 0 · **1272 pass** · 검사 전 항목 ✓ · App 바이너리에 `/v1/public/center` 문자열 1건으로 포함 실증 → `~/Downloads/rise_member-1.0.0+4.ipa` 교체(sha256 4b922390…)
- [x] 피어가 제안(후속 7번)을 즉시 반영(`isPublicApiPath` + 테스트, 1276 pass) → **재아카이브 #3(09-05 00:27)**: 검사 전 항목 ✓, `/api/v1/public/` 리터럴로 포함 실증. **IPA 내보내기는 실패** — `exportArchive No Accounts / No signing certificate "iOS Distribution"`: 00:14엔 성공한 같은 명령이 실패했고 `find-identity`에 Distribution identity가 없다(Xcode 클라우드 관리 배포 인증서는 계정 세션으로 받는데, Mac 잠금 후 키체인/계정 세션을 못 읽은 것으로 추정). `flutter build ipa`는 이 실패에도 **exit 0**이라 스크립트가 못 잡았다 → `build-release.sh`에 IPA 신선도 검사 추가(아카이브보다 새 .ipa 없으면 exit 1 + 복구 명령 출력). 아카이브를 `~/Library/Developer/Xcode/Archives/2026-09-05/Runner 1.0.0 (4) P60.xcarchive`로 복사해 Organizer에서 바로 Distribute 가능하게 했고, 리젝 아카이브 3개는 `2026-08-30/rejected-not-for-upload/`로 옮겨 목록에서 숨겼다(삭제 아님).
- [ ] **람**: Organizer → Runner 1.0.0 (4) P60 → Distribute App(업로드) → TestFlight/실기기 검증 → App Store Connect 지원 URL 교체 · 회신 · 빌드 1.0 (4) 연결 · 제출

## 변경 파일
| 파일 | 무엇을 |
|---|---|
| `app/ios/scripts/check_release_target.sh` **신설** | Xcode 빌드 페이즈 가드 — Release/Profile에서 `FLUTTER_TARGET≠lib/main.dart`, DART_DEFINES의 localhost·127.0.0.1·10.0.2.2·DEV_UID·DEMO_PHOTO_BASE·DEV_SESSION=true, `API_BASE_URL`/`LEGAL_BASE_URL`이 https가 아니면 빌드 실패. Debug는 통과. 시험 8건(마지막 define 누락 버그를 자체 시험이 잡아 `read \|\| [ -n ]`로 수리) |
| `app/ios/Runner.xcodeproj/project.pbxproj` | Flutter "Run Script"가 `$SRCROOT/scripts/check_release_target.sh && xcode_backend.sh build`로 · Runner Debug/Release/Profile의 `FLUTTER_BUILD_NAME=1.0.0`/`FLUTTER_BUILD_NUMBER=3` 하드코드 3쌍 제거(pubspec 단일 소스) |
| `app/ios/Runner/Info.plist` | `NSPhotoLibraryUsageDescription`을 실제 용도로 정정(체형 사진은 보관함에 저장하지 않음 · 인바디 결과지 불러오기만) — 정책 리뷰 M4 |
| `app/pubspec.yaml` | `version: 1.0.0+2 → 1.0.0+4` (Apple에 1·2·3 업로드됨) |
| `app/ios/Flutter/Generated.xcconfig` (생성 파일) | `flutter build ios --config-only --release`로 재생성 — `FLUTTER_TARGET=lib/main.dart`, 캡처 dart-define 제거 |
| `store/scripts/verify-ios-archive.sh` **신설** | 아카이브 실물 검사 — 번들 ID · 프로덕션 URL ≥1 · 로컬/사설망 http URL 0 · `integration_test` 문자열 0 · 심사 번호 존재. `integration_test.framework`는 정상 릴리스에도 링크돼(실측) 정보성 |
| `store/scripts/build-release.sh` | iOS: `flutter build ipa --export-method app-store` + 검사 스크립트 호출 · `SCRIPT_DIR` 고정 · 헤더에 사고 기록 |
| `store/screenshots/capture.sh` | EXIT trap `restore_xcconfig` — 어떻게 끝나든 xcconfig를 릴리스 값으로 복원 |
| `store/README.md` | 빌드 절차 경고(Organizer 직접 Archive 금지·방어선 3겹) · 업로드 단계(Transporter) · 상태표에 지원 URL ✅ / 사업자 정보 ❌ |
| `store/metadata/appstore.md` | 지원 URL → `legal/support.html` · 심사 노트 정정(국가 선택기 없음 · "연결 요청") · 심사 회신 문안(발송 전 체크 2건 포함) |
| `admin/public/legal/support.html` **신설** (+ `admin/dist/legal/`) | 고객 지원 페이지 — 이메일 문의(정적) · 센터 연락처(사업자 정보 있을 때만) · 문의 시 알려줄 것 · FAQ 8건(앱 코드 대조 완료) · 답변 시간표 |
| `admin/public/legal/index.html` | 카드 05 고객 지원 · "문의" 콜아웃에 지원 페이지 연결 |
| `store/app-store-todo-1.0.4.html` **신설** | 람용 재제출 체크리스트(다크·오프라인 단일 파일 · 체크 상태 localStorage · 회신 문안 복사 버튼) |
| `work_log/P60-*.md`, `work_log/README.md` | 이 문서 · 인덱스 |

## 검증
- **최종 아카이브(1.0.0 (4), 09-05 00:14 — 23:36 아카이브를 L10 포함 트리로 재빌드)** — `store/scripts/verify-ios-archive.sh` 전 항목 ✓: 번들 `com.han.rise` · pubspec 일치 · 프로덕션 API 주소 1건 · 로컬/사설망 http URL 0 · `integration_test` 문자열 0 · 캡처 마커 0 · 심사 번호 존재. `Apple Distribution: Sangduk Han (ZG9DP757ZM)` 서명, ExportOptions `app-store-connect`, MinimumOSVersion 15.5, 아카이브 Info.plist에 정정된 사진 보관함 문구 확인. 같은 스크립트가 리젝 아카이브(1.0(3))는 **5건 🚨로 거부**(진양성) — 진음성·진양성 둘 다 실물로.
- 빌드 직전 트리: `flutter analyze` 0 issues · `flutter test` **1265 pass / 0 fail**(P59 완료 후; 이전 8건 실패는 전부 P59 편집 중 파일이었고 해소됨).
- 빌드 페이즈 가드 시험 매트릭스 8+8건 통과(Release/Release-prod/FLUTTER_BUILD_MODE 차단 5종, 절대경로·Profile·Debug·정상 Release 통과). `xcodebuild -showBuildSettings`로 `FLUTTER_TARGET`·`DART_DEFINES`·`SRCROOT`가 빌드 설정(= 스크립트 페이즈 env)임을 확인.
- Hosting: `./deploy-hosting.sh` 빌드+배포+스모크(릴리스 config·공개 API·인증 경계) ✓. 라이브 `legal/support.html` 200 · 16,487B · 로컬과 바이트 동일 · "(미정)" 0건 · index 카드 05.
- 교차검증: 리뷰 에이전트 2개(기술·정책) 병렬 → 정책 리뷰가 FAQ 사실 오류 6건·심사 노트 오류 1건(국가 선택기)·Info.plist 문구 불일치를 잡았고, 기술 리뷰가 검사 스크립트의 정상 릴리스 오탐(`integration_test.framework`는 Flutter 3.44 iOS에서 dev_dependency 제외 미지원 — flutter/flutter#163874)·`$fails건` 식별자 버그·Profile 오탐을 잡았다. 자체 시험이 `while read` 마지막 define 누락을 잡았다.
- 최종 교차검증(마무리 패스): `~/Downloads/rise_member-1.0.0+4.ipa`를 독립적으로 풀어 재검사 — 프로덕션 URL 1 · 로컬 0 · integration_test 0 · 캡처 마커 0 · 심사 번호 1 · `ITSAppUsesNonExemptEncryption=false` · 프로파일 "iOS Team Store Provisioning Profile: com.han.rise". 프로덕션 Firestore의 심사 회원 `review_member_001` 존재·active·담당 코치 배정 확인(P53/P57의 파기 작업에 휩쓸리지 않았음). Firebase 테스트 번호 `+821000000000/000000` 등록 확인. 지원 페이지 HTML 태그 균형 로컬·라이브 동일(불일치 0).
- 자문자답: (a) Dart 가드가 왜 못 막았나 → 진입점이 바뀌면 main.dart가 안 돈다 → 빌드 페이즈로 이동. (b) Release.xcconfig에 `FLUTTER_TARGET=lib/main.dart`를 박으면 Organizer도 안전하지 않나 → `flutter build ipa -t lib/main_staging.dart` 같은 정당한 `-t`를 **조용히** 덮어 쓰므로 채택하지 않음(가드는 크게 실패한다). (c) 스킴 Archive pre-action은 종료코드가 빌드를 막지 못해 게이트로 부적합. (d) 지원 페이지에 센터 전화가 없어도 1.5를 만족하나 → 이메일 문의가 정적으로 있고 "(미정)"이 없으면 충족; 센터 연락처는 사업자 정보 등록 시 자동 표시. (e) 심사 회신에 내부 사정을 얼마나 적나 → 원인 요약+수정 사실만.

## 후속 작업
1. **[CRITICAL · 람]** 어드민 → 설정 → **사업자 정보 12항목 + 약관 시행일** 등록. 지금 라이브 개인정보처리방침이 "아직 시행 전 초안 … 앱 스토어 제출에 쓰면 안 됩니다" 배너와 "(보호책임자 이메일 미정)"을 띄운다 — 5.1.1 리젝 사유이자 개인정보보호법 §30 기재 요건 미달. 등록하면 법정 문서 5장 + 지원 페이지 센터 연락처가 한 번에 정상화된다. 등록 값은 개발자가 지어낼 수 없어 남긴다.
2. **[HIGH · 람]** `~/Downloads/rise_member-1.0.0+4.ipa`를 Transporter로 업로드 → TestFlight로 실제 iPhone에 설치 → 심사 계정(010-0000-0000 / 000000)으로 로그인·홈·예약·기록·마이 확인 → App Store Connect **지원 URL을 `https://rize-218c1.web.app/legal/support.html`로 교체** → 리젝 스레드에 `store/metadata/appstore.md` 회신 문안 → 빌드 1.0 (4) 연결 → 제출. Xcode Organizer의 옛 아카이브 3개(8/30)는 삭제 권장(잘못 올리는 사고 방지 — 검사 스크립트가 잡긴 한다).
3. **[HIGH · 커밋]** `app/ios/scripts/check_release_target.sh`는 `project.pbxproj`와 **같은 커밋**에 — 스크립트 없는 체크아웃에선 Debug 포함 모든 iOS 빌드가 127로 실패한다.
4. [MEDIUM] `integration_test.framework`가 릴리스 번들에 링크됨(Flutter 3.44 iOS dev_dependency 제외 미지원). 심사에 영향 없으나 Flutter가 지원하면 사라진다 — 추적만.
5. [LOW] `legal/index.html`·법정 문서의 초안 배너 문구("앱 스토어 제출에 쓰면 안 됩니다")는 내부 지침이 공개 페이지에 노출되는 형태 — 1번 등록으로 사라지지만 외부용 문구로 바꾸는 것도 고려(P57/P59 세션이 편집 중이던 파일이라 이번엔 손대지 않음).
6. ~~[MEDIUM · 람] 백엔드 배포~~ — **해소**(09-05): 람이 리비전 00030 + Hosting을 배포해 `GET /v1/public/center`가 200. 값은 아직 빈 문자열이라 앱은 폴백 "라이즈 컨디셔닝 센터"를 보인다 → 어드민 설정의 센터 상호·전화 등록(1번과 같은 자리)이 남은 일.
7. [MEDIUM · 앱] 방어선 하나 더 — `dio_client.dart` 401 인터셉터가 `/v1/public/*` 응답에는 세션을 비우지 않게 예외를 두는 것을 권한다. 지금은 유토큰 요청이 404로 떨어져 로그아웃이 나지 않지만, 토큰 첨부가 실패한 순간의 401은 공개 엔드포인트라도 세션을 지운다(공개 경로의 401은 "신원 상실"이 아니다). P56 L10 소유 세션에 전달함.
8. [LOW] 앱에 버전 표시가 없어 지원 페이지가 OS 설정 경로를 안내한다 — 마이 탭 하단에 버전 표기를 넣으면 문의 품질이 오른다(package_info_plus).

## 참조
- work_log/P46-store-release-prep.md(스토어 준비 · 캡처 파이프라인 · 심사 계정)
- store/README.md · store/metadata/appstore.md
- 메모리: ios-archive-stale-xcconfig
