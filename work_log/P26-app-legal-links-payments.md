---
id: P26
title: 앱 안 약관 접근 + 회원 결제 내역 — 서버는 주는데 화면이 없던 것들
status: 완료
domain: app
created: 2026-08-25
completed: 2026-08-25
---

# P26 — 앱 안 약관 접근 · 회원 결제 내역

## 목표

P21 감사가 남긴 "서버는 주는데 앱에 그리는 UI가 0" 두 건 + 스토어 심사 요건 하나.

## 결정 사항

### 약관을 앱에 복사하지 않고 링크로 보낸다

스토어 메타데이터의 처리방침 URL만으로는 부족하다 — Apple 5.1.1(i)·Play 모두 앱 **안에서**
접근 가능할 것을 본다. 특히 이 앱은 인바디·체형사진이라는 민감정보를 다뤄 동의의 근거
문서를 회원이 언제든 다시 읽을 수 있어야 한다.

문구를 앱에 박지 않는 이유: 개인정보처리방침은 **변경 시 고지 의무**가 있는데(법 제30조②)
앱에 박아 두면 갱신할 때마다 스토어 심사를 다시 통과해야 한다. 웹에 두면 대표가 고친
즉시 모두가 같은 문서를 본다.

### 웹뷰가 아니라 외부 브라우저

`url_launcher` + `LaunchMode.externalApplication`. 회원이 주소창으로 출처를 확인하고
저장·공유할 수 있어야 하고, 문서 안의 외부 링크(분쟁조정위·KISA)까지 앱이 떠안는
표면이 되지 않게 한다.

주소는 `dart-define=LEGAL_BASE_URL`로 뺐다(스테이징·자체 도메인 전환). 기본값은 배포된
Hosting. **확장자(.html)까지가 정식 주소다** — 떼면 `**` → `/index.html` 폴백에 걸려
어드민 SPA로 떨어진다. 테스트가 이걸 잠근다.

브라우저를 못 열면 조용히 실패하지 않고 주소를 문구로 보여준다 — 법정 고지 문서로 가는
길이 막혔다는 건 회원이 알아야 하고, 아무 반응 없는 행은 앱이 고장 난 것으로 보인다.

### 결제 내역 — 미납이 있는데 앱이 모르던 상태

`GET /v1/payments?member=`는 **회원 스코프로 이미 열려 있었다**(`memberScopeID`). 서버는
본인 분할 내역을 그대로 내려주는데 앱에 그리는 화면이 하나도 없어서, 분할로 결제한 회원이
"2차가 언제 얼마인지" 확인하려면 센터에 물어보는 수밖에 없었다.

미납 합계는 서버 `Payment.Outstanding()`과 **같은 규칙**으로 센다(미납이고 종결되지 않은
회차). 두 값이 갈리면 앱은 "미납 30만원"이라 하고 데스크는 "완납"이라 한다.

**`waived_at`(청구 종결)은 미납이 아니다.** v1.5에서 패스 환불 시 남은 회차에 붙는 표식이고
(삭제가 아니라 표식 — 원장주의 P3와 같은 철학), 이걸 미납으로 세면 이미 환불받은 회원에게
"아직 낼 돈이 있다"고 말하게 된다. 배지도 warn이 아니라 muted다.

빈 목록과 조회 실패를 가른다 — 결제가 없으면 카드를 아예 안 띄우고(아직 아무것도 안 산
회원에게 빈 상자를 줄 이유가 없다), 실패면 카드를 띄우고 실패라고 말한다.

한 번에 낸 결제는 회차를 펼치지 않는다 — 총액과 같은 줄이 하나 더 생길 뿐이다.

## 진행 단계

- [x] `url_launcher ^6.3.2` 추가 (2026-08-25 pub.dev API로 최신 stable 확인)
- [x] `LegalLinks` + `LegalLinksCard` 4행, 마이 탭 연결
- [x] 실기기 확인 — 탭 → Chrome 실행(`mCurrentFocus=com.android.chrome`)
- [x] `PaymentDto`/`InstallmentDto` + codegen
- [x] `PaymentItem`/`InstallmentItem` 도메인 + repository best-effort 조회
- [x] `PaymentsCard` + 마이 탭 연결
- [x] 테스트 14건(약관 4 · 결제 10) + 뮤테이션 3건 kill
- [x] 실기기 확인 — 프로덕션 회원은 결제 레코드가 없어 카드가 숨음(설계대로)

## 변경 파일

- `pubspec.yaml` — `url_launcher: ^6.3.2`
- `lib/core/config/legal_links.dart` (신규)
- `lib/core/api/dto/payment_dto.dart` (신규, freezed)
- `lib/features/my/presentation/widgets/legal_links_card.dart` (신규)
- `lib/features/my/presentation/widgets/payments_card.dart` (신규)
- `lib/features/my/domain/my_models.dart` — `PaymentItem`·`InstallmentItem`·`MySummary.payments`
- `lib/features/my/data/my_remote_data_source.dart` — `fetchPayments`
- `lib/features/my/data/my_repository_impl.dart` — best-effort 조립
- `lib/features/my/presentation/my_screen.dart` — 두 카드 연결
- `test/features/my/presentation/widgets/legal_links_test.dart` (신규 4건)
- `test/features/my/presentation/widgets/payments_card_test.dart` (신규 10건)

## 검증

- `flutter analyze` 0 · 전체 **862건** 그린
- 뮤테이션 3/3 kill (되돌리면 실패 → 복구 확인)
  - `isOpen`에서 `waivedAt` 조건 제거 → 환불 회원에게 미납 표시 → 실패
  - 조회 실패를 빈 상태로 위장 → 실패
  - 약관 주소에서 `.html` 제거 / 두 주소를 같게 → 실패
- 실기기: 마이 탭에 약관 4행 노출, 이용약관 탭 → Chrome 실행 확인

## 후속 작업

- 약관 페이지 내용은 **배포 후에** 뜬다(현재 Hosting 미배포). 링크 자체는 동작 확인함
- 결제 카드의 채워진 렌더링은 위젯 테스트로만 확인 — 프로덕션에 결제 레코드가 생기면 실기기 재확인
- 체크인 상태가 앱 재시작 시 사라짐(`CheckedInBookingId`가 메모리 전용) — 서버 Booking에
  `checked_in_at`이 필요하다. 백엔드 작업이 겹쳐 미착수

## 참조

- `work_log/P21-hollow-feature-audit.md` — 두 항목의 출처(검증 §3)
- `admin/public/legal/` — 링크 대상 문서
