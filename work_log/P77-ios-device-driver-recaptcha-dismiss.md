---
id: P77
title: iOS 실기기 검증 — XCUITest 드라이버로 실제 앱을 조작해 reCAPTCHA 시트 닫기·재시도 경로 확인 + 개선
status: 완료
domain: app
created: 2026-10-16
completed: 2026-10-16
---

# P77 — "ios실기기 테스트 진행해서 검증 후 개선 작업 부탁해"

## 목표 (람 요청)
P75(reCAPTCHA 복귀 URL 라우터 누수) 뒤 남은 실기기 미확인 위험을 실제 앱(lib/main.dart 릴리스 빌드)에서 직접 잰다.
핵심 질문: 사파리 시트를 완료 버튼·가장자리 스와이프·아래 스와이프로 닫은 뒤 다시 요청하면 시트가 다시 뜨는가,
아니면 Firebase가 "시트가 떠 있음" 상태에 갇히는가(P75 반박 검토의 "확인 못 함", 사실이면 HIGH).

## 결정 사항
- **D1 사람 손 대신 XCUITest 드라이버** — Flutter 통합 테스트는 Flutter 위젯만 누른다. 사파리 시트 닫기(완료·가장자리·
  아래 스와이프)는 네이티브 조작이라 XCUITest로만 된다. 생성기(xcodegen 등)가 없어 최소 Xcode 프로젝트를 직접
  작성(빈 Host 앱 + UI 테스트 번들, `XCUIApplication(bundleIdentifier: "com.han.rise")`). 팀 와일드카드
  프로비저닝으로 서명 — 개발자 계정에 새 App ID를 만들지 않는다(빌드 로그 확인). 저장소 `app/ios_ui_driver/`에 보관.
- **D2 실행은 기기 UI 자동화 승인 대기** — 첫 실행: "Failed to initialize for UI testing: Timed out while enabling
  automation mode"(1분). iOS 17+는 설정 › 개발자 › "UI 자동화 활성화" + 첫 실행 승인(암호)이 필요하다. 람이 지금은
  못 한다고 답함 → 시트 스와이프 닫기는 계속 **확인 못 함**, 드라이버는 승인 즉시 돌릴 수 있게 보관.
- **D3 사람 손 없이 잴 수 있는 입구를 Flutter 하네스로 확장**(`integration_test/phone_auth_recaptcha_return_test.dart`):
  t2 인증번호 재전송(reCAPTCHA 재진입) · t3 코드 화면에서 돌아가 다시 요청(정상 완료 뒤 시트 상태가 풀리나) ·
  t4 심사 번호 다음 테스트 번호(앱 검증 생략 스위치가 남나 — P75 반박 검토의 "범위 밖" 지적).
- **정정(P75 기록)**: P75에서 pbxproj의 빈 inputPaths 제거·SPM 주석 변경을 "Flutter가 띄운 Xcode의 재저장"이라
  적었으나 **틀렸다** — 이번 릴리스 빌드는 Xcode GUI 없이도 같은 변경을 냈고 빌드 로그에 `Running pod install`이
  있다. CocoaPods(Xcodeproj 젬)의 재직렬화다. 메모리(ios-device-headless-run)도 고침.
- **D4 심사 번호 스위치(반박 검토 "범위 밖")를 고쳤으나 iOS에선 플러그인 한계로 무효** — `auth_repository_impl.dart`가
  `appVerificationDisabledForTesting`을 켜기만 해서 같은 실행에서 심사 번호 뒤 다른 번호도 앱 검증 없이 나갔다.
  요청마다 `kDebugMode || 심사 번호`로 명시하게 고침. **실기기 실측: 고친 뒤에도 iOS는 그대로**(테스트 번호 0.80s,
  사파리 시트 없음) → 원인: FlutterFire iOS `setSettings`가 `if (settings.appVerificationDisabledForTesting)`일 때만
  적용(6.5.7·6.7.0·7.0.0 동일 — 소스 확인). Android는 값을 그대로 적용(`FlutterFirebaseAuthPlugin.java:579`)해 유효.
  → 수정은 유지(Android 유효·iOS 무해), 주석에 iOS 한계를 정직하게 적고, 네이티브 채널 우회는 **안 함**(심사자 경로
  한정 LOW · 출시 직전 인증 경로에 네이티브 표면을 늘리는 비용이 더 큼). t4는 iOS에서 "한계가 남아 있음"을 단언하는
  특성 시험으로 — 플러그인이 고쳐지면 깨져서 알린다.
- **D5 하네스 운영 지식(실측)**: ① 사파리 시트가 떠 있는 동안 Flutter 프레임이 멈춰 하네스의 `pump()`도 멈춘다 —
  시트가 자동 통과하면 몇 초, 그림 문제면 사람이 풀 때까지. ② 같은 기기에서 짧은 간격(≈20초)으로 reCAPTCHA를 연달아
  요청하면 시트가 닫히지 않는 상태가 30~50분 이어졌다(09:30~10:00, 10:21엔 자동 통과 복귀) — 그림 문제로 추정
  (화면 캡처 수단이 없어 확인 못 함). ③ `devicectl … launch -e` 환경변수는 Dart `Platform.environment`에 닿지 않았다 →
  시나리오 선택은 `--dart-define=P77_ONLY`. ④ 기기 화면은 앱이 앞에 있는 동안 SpringBoard 유휴 타이머가 Disabled라
  자동 잠금이 원인이 아니었다(로그 확인 — 처음 세운 자동 잠금 가설은 반증). ⑤ 설치가 한 번씩 0xe8008001로 튕기고
  같은 사본 재시도는 붙는다.
- **정정(계정)**: "HanSangduk은 gh에 로그인돼 있지 않다"는 **틀렸다** — 확인 명령의 `head -5`가 세 번째 계정 줄을
  잘랐다. SC-Deogi(활성·읽기만)·SangDukHan·**HanSangduk(admin·push)** 셋 다 로그인돼 있다(P74 세션이 지적, 재확인).

## 진행 단계
- [x] 사람 손 대신 XCUITest 드라이버 — 빌드·서명 OK, 실행은 기기 UI 자동화 승인 대기(람: 지금은 못 함)
- [x] 실제 앱 릴리스 빌드 설치·실행 경로 확인(설치 OK) · Flutter 하네스 확장(t2·t3·t4 + 시나리오 선택)
- [x] 실기기 측정 — t1 통과 · t4 수정 전/후 · t2·t3는 reCAPTCHA 연속 요청 정지로 측정 불가
- [x] 심사 번호 스위치 수정(Android 유효 · iOS 플러그인 한계 — 주석·특성 시험으로 고정)
- [x] 측정 흔적 원복(pbxproj HEAD · Generated.xcconfig `--config-only --release` · 기기 앱 3개 삭제)
- [x] 커밋 전 검증 라운드(2026-10-17): 반박 1라운드(조건부 GO) → M1·L1~L8 반영 → 같은 자로 재측정

## 변경 파일
- `app/integration_test/phone_auth_recaptcha_return_test.dart` — 시나리오 4개(t1~t4) · 결과/끝 표식 파일 · `--dart-define=P77_ONLY`
  선택 · 머리 주석의 설치 경로 정정(Profile-iphoneos)
- `app/lib/features/auth/data/auth_repository_impl.dart` — `appVerificationDisabledForTesting`을 요청마다 명시(+iOS 한계 주석) ·
  판정식을 `skipAppVerificationFor`(@visibleForTesting)로 추출
- `app/test/features/auth/data/app_verification_switch_test.dart`(신규) — 판정식 단위 시험
- `app/ios_ui_driver/`(신규) — XCUITest 드라이버(RiseUIDriver.xcodeproj · Host · DriverUITests · run.sh · README · .gitignore)
- `work_log/P77…` · `work_log/README.md`

## 검증
**실기기(iPhone 12 · iOS 26.6.2 · 프로필 빌드 · 테스트 번호 010-5555-6666 · 기기 로그 idevicesyslog)**
| 런 | 결과 | 근거 |
|---|---|---|
| t1(현재 코드, 09:30) | 인증번호 화면 10.2s · 누수 없음 | 결과 JSON |
| t1(10:21) | 인증번호 화면 8.6s · 시트 탭 1s 뒤 | 결과 JSON + 기기 로그 SafariViewService |
| t4 수정 전 | 심사 1.08s → 테스트 번호 **1.07s · 시트 없음** = 스위치 남음(버그 재현) | 결과 JSON + 기기 로그 |
| t4 수정 후 | 심사 1.36s → 테스트 번호 **0.80s · 시트 없음** = iOS에선 여전히 남음 → 플러그인 소스로 원인 확정 | 〃 |
| t2(10:24) | 첫 요청의 시트가 뜬 뒤(10:24:16) 2분간 진행 없음 — 3분 전 t1에 이은 두 번째 reCAPTCHA | 기기 로그(SafariViewService) — 측정 불가 |
| t2(09:30) | 결과 파일 없음(t1 직후 실행) — 정지로 **추정**(그 런은 기기 로그를 안 받았다) | 결과 파일 부재 |
| t3 | **시작조차 못 함**(앞 시험에서 멈춤 · 단독 실행 안 함) | — 측정 불가 |
| XCUITest 드라이버 | "Timed out while enabling automation mode" | xcodebuild 로그 |

**시험·정적 검사**: 전체 스위트 1561 통과 · `flutter analyze` 0건(직접 재실행). 심사 스위치 수정은 단위 시험 없음
(FirebaseAuth.instance 직접 의존) — Android 효과는 플러그인 소스(값 그대로 적용)로만 확인.

**검증 라운드 2 — 커밋 전(2026-10-17, 람 "작업 한거 모두 /ram-verify-loop 후 문제 없으면 커밋 푸시")**
| 반박 라운드 | CRITICAL | HIGH | MEDIUM | LOW | 판정 |
|---|---|---|---|---|---|
| 1(opus · 새 컨텍스트 · 스냅샷 diff·기기 로그·원본 소스) | 0 | 0 | 1(M1) | 8(L1~L8) | 조건부 GO — 전부 반영 |

| 지적 | 반영 | 같은 자로 재측정 |
|---|---|---|
| M1 `run.sh --install` 빌드 실패·중단 때 pbxproj 미복원 | EXIT trap `restore_pbx` + INT/TERM → exit 130 | 가짜 flutter 재현: 실패 rc=1 · 그룹 SIGINT rc=130 — **둘 다 sha256 원복·권한 644** |
| L1 스위치 수정을 지키는 시험이 도는 곳 없음 | 판정식 `skipAppVerificationFor` 추출 + 단위 시험 2건 | 변이 S1~S4 **4/4 KILLED**(배선은 미측정 — 함수 시험은 배선을 안 잰다) |
| L2 t4 Android 문턱이 iOS 데이터뿐 | t4는 iOS 전용(Android 건너뜀, 사유 주석) | — |
| L3 t4 iOS 분기가 기기에서 안 돎 | 실기기 실행(하네스 v7) | 심사 1.10s → 테스트 번호 0.80s · **All tests passed** |
| L4 `P77_ONLY` 오타면 전부 건너뛰고 초록 | setUpAll에서 이름 단언 | (분석 0건 · 로직 확인) |
| L5 문서 낡음 4곳 | P75 정정 표시 · P77 후속 2번(푸시 완료) · 측정 표 t2/t3 · 하네스 머리 주석 | — |
| L6 t1 codeSent 시각 의미 | 누수 때만 기록 | — |
| L7 드라이버 "판정 불가"가 통과로 집계 | XCTSkip · 최종 도착은 기록만 | 서명 없는 build-for-testing 성공 |
| L8 run.sh 재시도·신선도·python3 | 설치 1회 재시도 · `-nt` 신선도 · python3 안내 | `bash -n` · 기기 배관 실행 |
| (반박 전 자체 발견) run.sh 기기 탐지 실패 | `tunnelState`(평소 disconnected) 대신 페어링·유선·부팅으로 | 기기 실행: 탐지·빌드·서명·설치·요약 정상, 자동화 승인 대기에서 예상대로 종료 |

**재측정(직접 재실행)**: 전체 스위트 **1563 통과**(+2 새 단위 시험) · `flutter analyze` 0건 · 빌드 가드 33/33 ·
P75 가드 변이 9/9 · 4/4 · 6/6 재확인 · 백엔드 `go build`·`go vet`·`go test`(4패키지 ok) · 어드민 `tsc` 0건(백엔드·어드민은
이번 커밋과 무관 — 같은 브랜치 상태 확인용). **자 검정 1건**: 첫 백엔드·어드민 점검은 셸 PATH에 go/npx가 없어 "command not
found"였는데 출력의 exit=0은 뒤 `echo`의 값이었다 — 초록으로 세지 않고 경로를 잡아 다시 돌렸다.

## 확인 못 한 것 (수단 부재)
- **사파리 시트 스와이프 닫기 후 재시도**(P75 반박 지적, 사실이면 HIGH) — 기기 UI 자동화 승인이 필요하다. 드라이버는 준비됨:
  `cd app && bash ios_ui_driver/run.sh --install`(아이폰 설정 › 개발자 › UI 자동화 활성화 + 첫 실행 승인 뒤).
- **재전송(t2)·돌아가 다시 요청(t3)** — 같은 기기에서 몇 분 안에 reCAPTCHA를 다시 요청하면 시트가 자동 통과하지 않고
  머문다(그림 문제 추정, 화면 캡처 수단 없음). 무인 자동화로는 못 잰다. 위험은 낮다 — P75 수정은 엔진 단계에서 모든
  복귀 URL을 같은 스위치로 막는다(입구 무관).
- 심사 스위치 수정의 Android 실기기 효과(안드로이드 실기기 없음 · 에뮬레이터는 프로필 모드 불가).

## 안 한 것 (결정)
- iOS 심사 스위치를 네이티브 채널로 강제 해제 — 심사자 경로 한정(LOW) · 출시 직전 인증 경로에 네이티브 표면 추가 비용이 큼.
  다시 열 조건: 심사 리젝 사유로 "심사 계정 뒤 실번호 실패"가 나오거나, FlutterFire가 iOS에서 false를 받기 시작할 때(t4가 깨진다).
- firebase_auth 업그레이드 — 7.0.0까지 iOS 동작 동일(소스 확인).

## 후속 작업
1. [람 · 1회] 아이폰 설정 › 개발자 › "UI 자동화 활성화" → `cd app && bash ios_ui_driver/run.sh --install` 실행 중 폰의 승인 창
   허용 — 시트 스와이프 닫기 판정(드라이버 첫 실행이라 요소 이름부터 확인).
2. ~~[람] 푸시~~ — 3f9f054·1ffd8ab는 람이 gh 계정을 HanSangduk으로 바꿔 2026-10-17 00:27에 푸시했다(원격 추적 ref reflog).
   P77은 이 기록의 검증 라운드 뒤 커밋·푸시. PR·머지는 별도 요청 때.
3. 하네스를 나중에 다시 돌릴 땐 시나리오를 **하나씩, 몇 분 간격**으로(`--dart-define=P77_ONLY=t1` …) — 연속 요청은 시트를 멈춘다.

## 참조
- P75(근본 원인·하네스) · 메모리 ios-device-headless-run · FlutterFire `FLTFirebaseAuthPlugin.m:1549`(iOS setSettings) ·
  `FlutterFirebaseAuthPlugin.java:579`(Android)
