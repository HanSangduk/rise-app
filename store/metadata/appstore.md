# App Store 등록 정보 (ko)

## 이름 (30자 이내)
라이즈 컨디셔닝 - PT 회원 앱
(Play와 통일 — 브랜드 쿼리 정확 일치, ASO 교차검증)

## 부제 (30자 이내)
수업 예약·홈워크·몸의 변화 기록
("PT"는 이름에 있어 색인 중복 — "수업" 신규 토큰 확보, ASO B)

## 프로모션 텍스트 (170자 이내, 심사 없이 수시 변경 가능)
수업 예약부터 인바디 추이, 체형 사진 비교까지 — 코치와 함께하는 몸의 변화를
앱 하나로 기록하세요.

## 키워드 (100자 이내, 쉼표 구분)
피티,헬스,헬스장,피트니스,퍼스널트레이닝,개인트레이닝,인바디,체지방,골격근량,체성분,눈바디,체형,바디체크,바디프로필,운동,웨이트,홈트,홈트레이닝,다이어트,트레이너,체중,근육
(96/100자 — 이름·부제와 중복 토큰 제거, 한글 "피티" 별도 색인, ASO B)

## 설명
(play.md의 "자세한 설명"과 동일 본문 사용 — 두 스토어 동기 유지)

## 카테고리
- 기본: 건강 및 피트니스 (Health & Fitness)
- 보조: 라이프스타일

## 연령 등급
4+ 예상 — ⚠ Apple 2025 등급 체계 개편(4+/9+/13+/16+/18+ 신규 설문, 2026-01-31 이후 전 앱 필수)
기준으로 재답변 필요. "건강 관련 주제" 문항은 개인 피트니스 기록(의료 아님)으로 답변.

## URL
- 지원 URL: https://rize-218c1.web.app/legal/support.html
  (P60 · 2026-09-04 교체 — 종전 `legal/index.html`은 문의 수단이 "(미정)" 자리표시뿐이라 Guideline 1.5로 리젝됐다.
  지원 페이지는 이메일 문의를 **정적으로** 싣고 센터 전화·주소는 사업자 정보가 등록된 뒤에만 표시한다.)
- 마케팅 URL(선택): https://rize-218c1.web.app
- 개인정보처리방침 URL: https://rize-218c1.web.app/legal/app-privacy.html
  (P66 · 2026-09-06 교체 — 이 앱은 **여러 센터가 함께 쓴다**. 종전 `privacy.html`은 특정 센터 하나를
  개인정보처리자로 선언하는 문서라, 두 번째 센터가 들어오는 순간 나머지 센터 회원에게 거짓 고지가 된다.
  앱 스토어에 거는 것은 **앱 운영자(한상덕) 방침**이고, 센터별 방침은 앱 마이 탭에서 자기 센터 것이 열린다.)

> ⚠ **제출 전 필수**: 이 URL들이 지금은 **"(사업자명 미정)" 플레이스홀더를 그대로 보여준다.**
> 법정 문서 5장은 `GET /api/v1/public/business`로 사업자 정보를 받아 채우는데(상호가 바뀔 때
> 5장을 따로 고치다 하나를 빠뜨리는 사고를 막으려 그렇게 설계했다), 프로덕션 응답이
> 전 필드 빈 문자열 · `complete:false`다(2026-08-30 실측).
> 심사자가 개인정보처리방침을 열면 미완성 문서를 보게 된다 → Guideline 5.1.1 리젝 사유이고,
> 보호책임자 연락처 공백은 국내 개인정보보호법 고지 요건 미달이다.
> **어드민 > 설정 > 사업자 정보 12개 항목**을 채우면 5장이 한 번에 정상화된다.

## 저작권 (Copyright) — 버전 정보 탭
`2026 한상덕`
- **URL이 아니라 텍스트다** — Apple이 이 칸에 URL을 넣지 말라고 명시한다. 형식은
  "권리 취득 연도 + 권리 보유자", © 기호 불필요, 170자 이내.
- 사업자 등록 후 법인이 권리 보유자가 되면 상호로 교체(나중 버전에서 변경 가능).

## 심사 노트 (App Review Information) — ASO B 최종본
```
[About this app]
이 앱은 피트니스 센터 "라이즈 컨디셔닝"의 등록 회원 전용 앱입니다.
계정은 센터가 회원 등록 시 생성·승인하므로 앱 내 신규 가입 기능은 없습니다
(특정 시설 회원 전용 — 미등록 번호는 센터에 "가입 요청"만 보낼 수 있고, 센터 승인 전에는
기능이 열리지 않습니다). 심사를 위해 아래 데모 계정을 준비했습니다.
개발사는 본 서비스의 운영 주체로서 직접 제출합니다.

[Demo account]
1) 로그인 화면에 전화번호 010-0000-0000 입력 (국가 선택은 없고 한국 번호만 지원합니다.
   하이픈은 있어도 없어도 됩니다.)
2) "인증번호 받기" → SMS 인증코드: 000000 (실제 SMS가 발송되지 않는 가공 번호입니다.)
3) 로그인하면 회원권·예약·홈워크·인바디 추이·체형 사진·수업 기록이 채워진
   승인된 테스트 회원으로 자동 연결됩니다.

[Sensitive data consent — 5.1.1]
- 체형 사진·인바디 수치 등 건강 관련 데이터는 앱 내 별도 명시적 동의
  (마이 > 동의 관리) 후에만 저장됩니다. 동의 없는 저장 요청은 서버가 거부합니다.
- 데모 계정은 동의 완료 상태이며, 마이 > 동의 관리에서 토글을 확인할 수 있습니다.
- HealthKit은 사용하지 않습니다. 사용자가 직접 입력·촬영한 값만 자체 서버에 저장합니다.

[Sign-in — 4.8]
- 자체 전화번호(SMS OTP) 인증만 사용합니다. 제3자/소셜 로그인이 없으므로
  Sign in with Apple 요건 대상이 아닙니다.

[Permissions]
- 카메라: 체형 사진 촬영(수평계·격자 가이드), 데스크 QR 체크인
- 동작 센서: 촬영 시 수평 안내에만 사용

[Payments]
- 앱 내 결제 없음. 회원권 결제는 센터 오프라인에서 이루어지며 앱은 내역 조회만 제공합니다.

[Account deletion — 5.1.1(v)]
- 마이 > 회원탈퇴에서 앱 내 계정 삭제를 제공합니다.
- 센터에 아직 연결되지 않은 계정(가입 요청 대기·미등록 번호)도 센터 연결 화면 하단의
  "계정 삭제"에서 인증 계정과 보낸 가입 요청을 삭제할 수 있습니다.
```

## 심사 담당자 연락처
- 이름: 람 / 이메일: richramsang@gmail.com

## 심사 회신 · 재제출 노트 (2026-09-04 — 1.0 (3) 리젝 대응, P60)

App Store Connect의 리젝 메시지에 답글로 붙이고, 빌드 1.0 (4)를 연결해 재제출한다. 영문이 기본이고
아래 한국어 요약은 내부 확인용이다.

> ⚠ **발송 전 두 가지가 끝나야 한다.** ① `https://rize-218c1.web.app/legal/support.html`이 라이브에서 실제 지원
> 페이지로 열리는지(`curl -s <URL> | grep -c richramsang@gmail.com` ≠ 0) ② **1.0 (4) IPA(또는 TestFlight)를 실제 iPhone에
> 설치해 심사 계정으로 로그인 → 홈·예약·기록·마이를 한 번 돌려본다.** 문안의 "verified on a physical iPhone"은
> 그 뒤에만 참이다.

```
Thank you for the detailed review.

Guideline 2.1(a) — Root cause identified: build 1.0 (3) was produced with an incorrect
build configuration that pointed the app at a non-production server address, so it could
not load any data after launch. Build 1.0 (4) is built with the correct production
configuration, and we added an automated check to our release process so this cannot
recur. We verified 1.0 (4) on a physical iPhone with the demo account: sign-in, home,
booking, records (workout, InBody, body check), and profile all load correctly.

Guideline 1.5 — The Support URL now points to a dedicated support page,
https://rize-218c1.web.app/legal/support.html, with a support email address, response
times, and FAQs covering sign-in, bookings, records, and account deletion. The page is
publicly accessible without sign-in and works without JavaScript.

Demo account (unchanged): enter phone number 010-0000-0000 on the sign-in screen
(Korean numbers only, no country selector), then SMS code 000000.
```

한국어 요약: 2.1(a)는 스크린샷 캡처 도구가 남긴 Xcode 설정(테스트 진입점 + localhost API)으로 빌드된
바이너리가 원인 — 릴리스 스크립트 단일 경로 + 빌드 페이즈 가드 + 아카이브 검사로 재발 차단(내부 사정은
회신에 적지 않는다 — Apple은 원인 요약과 수정 사실만 필요하다). 1.5는 지원 URL을 전용 지원 페이지로 교체.
