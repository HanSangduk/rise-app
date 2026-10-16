# iOS 실기기 UI 드라이버 (P77)

설치된 라이즈 앱(`com.han.rise`)을 **XCUITest로 사람처럼 조작**하는 별도 Xcode 프로젝트다.
Flutter 통합 테스트(`integration_test/`)는 Flutter 위젯만 누를 수 있어서, reCAPTCHA 사파리 시트를
스와이프로 닫는 것 같은 **네이티브 화면 조작**은 못 한다 — 그 빈칸을 채운다.

- `Host/` — XCUITest 러너용 빈 호스트 앱(실제 조작 대상은 번들 ID로 띄우는 라이즈 앱).
- `DriverUITests/DriverUITests.swift` — 시나리오.
- `run.sh` — 기기 찾기 · (선택) 실제 앱 릴리스 빌드·설치 · 실행 · 로그 요약.
- 서명은 팀(ZG9DP757ZM) 와일드카드 프로비저닝으로 된다 — 개발자 계정에 새 App ID를 만들지 않는다.

## 상태 (2026-10-16)
- 빌드·서명: 확인(실기기 iPhone 12 · iOS 26.6.2 · Xcode 26.6).
- `run.sh` 배관: 확인(2026-10-17 — 기기 탐지·빌드·서명·설치·요약 정상, 빌드 실패·Ctrl-C 때 pbxproj 복원 재현 확인).
- **실행: 기기 UI 자동화 승인 대기.** 실행은 "Timed out while enabling automation mode"로 끝난다(2회) —
  시나리오 로직은 아직 기기에서 한 번도 돌지 않았다. 승인 뒤 첫 실행에서 요소 찾기(사파리 "완료" 버튼 이름,
  입력란·버튼 라벨)부터 확인할 것.

## 시나리오 (P75 반박 검토의 "확인 못 함"을 재는 자)
| 시험 | 하는 일 | 통과 조건 |
|---|---|---|
| `test00_happyPath_realApp` | 번호 입력 → 인증번호 받기 → (시트) | 인증번호 화면 도착 |
| `test01_dismissByDoneButton` | 시트가 뜨면 **완료** 버튼으로 닫기 → 다시 요청 | 시트가 다시 뜨거나 인증번호 화면 |
| `test02_dismissByEdgeSwipe` | 시트를 **왼쪽 가장자리 스와이프**로 닫기 → 다시 요청 | 〃 |
| `test03_dismissBySwipeDown` | 시트를 **아래로 스와이프**로 닫기 → 다시 요청 | 〃 |

"막힘"(다시 요청이 시트 없이 곧장 "창이 닫혔어요"만 반복)이면 Firebase `AuthURLPresenter`가 닫힘을 모른 채
"시트가 떠 있음"에 갇힌 것이다 — 앱을 다시 켜기 전까지 인증이 안 된다(사실이면 HIGH).
reCAPTCHA가 닫기 전에 자동 통과해 버리면 "판정 불가"로 건너뛴다(XCTSkip — 통과로 세지 않는다).

## 실행
```bash
# app/ 에서. 처음 한 번: 아이폰 설정 › 개발자 › "UI 자동화 활성화" 켜고, 실행 중 폰에 뜨는 승인 창에 암호.
bash ios_ui_driver/run.sh --install test00_happyPath_realApp   # 실제 앱 릴리스 빌드·설치 + 한 시나리오
bash ios_ui_driver/run.sh test02_dismissByEdgeSwipe              # 다음 시나리오(앱이 이미 깔려 있을 때)
```
- **시나리오는 하나씩, 몇 분 간격으로** 돌린다. 같은 기기에서 몇 분 안에 reCAPTCHA를 다시 요청하면 시트가 자동 통과하지
  않고 머문다(P77 실측 — 30~50분 지속). 그래서 시트가 다시 뜬 뒤의 "최종 도착"은 단언하지 않고 기록만 한다.
- 판정할 수 없는 경우(시트를 못 잡음 · 닫기 전에 끝남 · 제스처 미지원)는 통과가 아니라 **건너뜀(XCTSkip)**으로 나온다.
- `--install`은 빌드가 실패하거나 Ctrl-C로 멈춰도 `ios/Runner.xcodeproj/project.pbxproj`를 빌드 전 사본으로 되돌린다.
- 번호는 Firebase 콘솔 등록 테스트 번호(010-5555-6666 — 실 SMS 없음). 인증번호 화면까지만 가고 코드는 넣지 않는다.
- 끝나면 기기에서 드라이버 앱을 지워도 된다: `com.han.rise.uidriver.host` · `com.han.rise.uidriver.uitests.xctrunner`.
- 관련: `integration_test/phone_auth_recaptcha_return_test.dart`(Flutter 위젯 수준 실기기 하네스 — 시트 조작은 없음).
