# App Store Connect — 앱 개인정보(App Privacy) 답변 (P46 감사 기준)

추적(Tracking): **없음** — 광고·분석 SDK 0건, 타사 데이터 결합 없음 → ATT 불필요.

## Data Linked to You (사용자와 연결된 데이터)
전부 "앱 기능(App Functionality)" 목적, 추적 아님:

| Apple 카테고리 | 실제 항목 |
|---|---|
| Contact Info > Name | 이름(회원 매칭) |
| Contact Info > Phone Number | 전화번호(로그인 인증·매칭) |
| Identifiers > User ID | 회원 ID·Firebase UID(계정 식별 — 앱 기능, 추적 아님). Firebase Auth SDK privacy manifest와 일치시켜야 함(ASO B) |
| Health & Fitness > Health | 인바디 수치, 부상 메모 (민감정보 동의 후) |
| Health & Fitness > Fitness | 수업·운동 기록, 홈워크 수행 |
| User Content > Photos or Videos | 체형 사진, 인바디 결과지 사진 (동의 후) |
| User Content > Other User Content | 코치 메모·요청 메모 |
| Purchases > Purchase History | 회원권·결제 내역(조회 전용 — 앱 내 결제 없음) |
| Usage Data | **수집 안 함** (분석 SDK 없음) |
| Identifiers > Device ID | **수집 안 함** (기기 ID·광고 ID 없음 — User ID는 위에서 신고) |
| Diagnostics | **수집 안 함** (크래시 SDK 없음) |

## Data Not Collected
위치, 이메일(로그인에 미사용), 연락처, 메시지, 검색/브라우징 기록, 진단, 기기 식별자·광고 ID

## 참고 문구(심사 대비)
- 건강 데이터는 HealthKit 미사용 — 사용자가 직접 입력/촬영한 값만 자체 서버에 저장.
- 민감정보(체형 사진·인바디)는 앱 내 별도 동의(마이 > 동의 관리) 후에만 저장 가능하며,
  서버도 동의 없는 저장을 400으로 거부한다.
