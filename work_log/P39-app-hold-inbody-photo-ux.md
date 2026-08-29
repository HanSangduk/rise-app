---
id: P39
title: 앱 UI/UX 개선 — 일시정지 신청 · 인바디 곡선 차트 · 체형 사진 뷰어
status: 완료
domain: app
created: 2026-08-29
completed: 2026-08-29
---

# P39 — 앱 UI/UX 개선 (일시정지 · 인바디 차트 · 체형 사진)

## 목표
1. **일시정지 신청 UX**: 날짜가 유효할 때만 신청 버튼 활성화, 일시정지 가능 잔여 일수 표시
2. **환불 예상액 표시 여부 판단**: 검토 후 의견만 제시 (코드 무변경)
3. **인바디 추이 차트**: 직선 → 곡선(smooth) 개선
4. **체형 분석 사진 뷰어**: 정체불명 `'⤢'` 텍스트 pill → 제대로 된 전체화면 SVG 아이콘

## 결정 사항
- **진행 방식**: 병렬 조사 3팀 → UI/UX 디자이너 관점 검수 2팀(모바일 UX / 비주얼) → 권고안 반영 구현.
- **일시정지 시트** — 버튼 위 **단일 메시지 슬롯 상태 머신**으로 통합: 거부(danger) → 날짜 미입력 적응형 안내(muted, "종료일을 선택하면…") → 신청 미리보기(중립, "이번 신청: N일 정지 · 신청 후 남은 M일"). 버튼은 날짜 완성 전 disable(안내가 상시라 죽은 버튼 아님). `_submit`의 미입력 가드는 이중 방어 규약대로 유지.
- **잔여 표시** — `HoldRules.allowance()` → `HoldAllowance` 신설(서버 미러 모듈에 표시·판정 동일 출처). 헤드라인은 **구속 조건(min) 반영**: 일수가 남아도 횟수 0이면 "남은 일시정지가 없어요"(danger). 무제한(-1) 축은 숫자를 지어내지 않음. 이력 0건은 "N일 · M회 사용 가능" 프레이밍. 기존 `usageLabel`은 대체되어 삭제. 상단 정책 줄의 상한 수치도 요약 박스와 중복이라 제거.
- **날짜 피커** — 종료일 firstDate=시작일(역전 조합 원천 차단), 시작일 lastDate=min(오늘+365, validUntil)(서버 `HoldStartsAfterValidUntil` 미러), initialDate는 현재값에서 시작 + [first,last] 클램프. 시작일을 종료일 뒤로 재선택하면 종료일 초기화(기간 이동 의도로 해석, 안내 슬롯이 다음 행동 안내).
- **인바디 차트** — 라이브러리 미도입, monotone cubic(Fritsch–Carlson) 보간. Catmull-Rom 반대 근거: min-max 정규화라 극값이 패딩 경계에 붙어 overshoot 확정 + "오르내림만 읽어라" 차트에 가짜 오르내림 생성. 그라디언트 fill은 반대(baseline이 min이라 면적 무의미). 점은 흰 링(r+1.5)+시리즈색 2겹, 마지막 점만 r3.5(최신 측정), 13개 이상이면 중간 점 숨김. PBF는 파선(4-3) — 적록색각 대응(범례 스와치도 파선). CustomPaint에 Semantics 수치 요약 추가.
- **체형 사진 pill** — 제거가 아닌 **교체**: 전체화면이 판독의 전제인 UI라 발견성 힌트 유지, `'⤢'`는 아이콘 시스템 자기규칙(이모지 금지) 위반 + OEM 폰트 tofu 위험. `RiseIcons.expand`(lucide maximize-2 대각) 신설, 원 20dp/아이콘 13px/α0.55, 날짜 pill과 수직 중심 정렬(bottom 5). 탭 핸들러 금지 주석(44dp 미달 독립 타깃 방지), `ExcludeSemantics`(장식) + 타일 `Semantics.onTapHint('크게 보기')`로 비시각 등가물 제공.
- **환불 예상액** — 사용자 결정(2026-08-29 후속): 회원 앱에서 **완전 제거**, 견적은 어드민(RefundQuoteModal)과 서버 `POST /v1/passes/{id}/refund-quote`만 담당. 회원 상시 노출은 환불 유도로 읽히고 앱 숫자가 협의 금액의 앵커가 되는 문제. P38 선례(소비처 0곳 코드 제거, 백엔드 라우트 유지)에 따라 앱 쪽 죽은 체인 전체 제거: `_RefundEstimateLink`/`_EstimateRow`(my_screen), `fetchRefundQuote`(view model·repository 인터페이스·impl·remote data source), `RefundQuote`/`RefundCalculator`(ledger_summary — `ledgerRemaining`·`MoneyFormat`은 유지), `refund_quote_dto.*` 3파일 삭제. 제거 이유는 my_screen.dart 원장 카드 자리에 주석으로 남김.

## 진행 단계
- [x] 1단계: 병렬 조사 (일시정지 화면 / 인바디 차트 / 체형 사진 뷰어)
- [x] 2단계: 교차검증 + UI/UX 디자이너 검수 2팀
- [x] 3단계: 구현 (도메인 → 시트 → 차트 → 아이콘 → 타일)
- [x] 4단계: 테스트 갱신·추가 + 전체 회귀

## 변경 파일 (환불 제거분)
- `app/lib/features/my/presentation/my_screen.dart` — `_RefundEstimateLink`·`_EstimateRow` 제거 + 제거 이유 주석
- `app/lib/features/my/presentation/my_view_model.dart` / `domain/my_repository.dart` / `data/my_repository_impl.dart` / `data/my_remote_data_source.dart` — `fetchRefundQuote` 체인 제거
- `app/lib/features/my/domain/ledger_summary.dart` — `RefundQuote`·`RefundCalculator` 제거
- `app/lib/core/api/dto/refund_quote_dto.dart`(+.freezed/.g) — 삭제
- 테스트 6파일 페이크 리포지토리 override 제거 + `ledger_summary_test.dart` RefundCalculator 그룹 제거

## 변경 파일
- `app/lib/features/my/domain/hold_rules.dart` — `HoldAllowance` 신설(잔여 계산·headline/detail 문구), `usageLabel` 삭제
- `app/lib/features/my/presentation/widgets/hold_request_sheet.dart` — 잔여 요약 박스, 단일 메시지 슬롯, 버튼 disable 조건, 피커 제약·역전 초기화
- `app/lib/features/records/presentation/widgets/inbody_chart.dart` — monotone cubic 곡선, 2겹 점, PBF 파선, Semantics, 파선 범례
- `app/lib/core/icons/rise_icons.dart` — `expand` 아이콘 추가
- `app/lib/features/records/presentation/widgets/body_photo_timeline.dart` — `'⤢'` pill → 원형 스크림+RiseIcon, onTapHint
- `app/test/features/my/domain/hold_rules_test.dart` — usageLabel 테스트 그룹 → HoldAllowance 테스트 7건(구속조건·무제한·음수 클램프 포함)
- `app/test/features/my/presentation/widgets/hold_precheck_test.dart` — 잔여 문구 기대값 갱신 + 버튼 disable→활성 전이·적응형 안내·미리보기 위젯 테스트 추가

## 검증
- `flutter analyze` — 0 issues (환불 제거 후 재확인 포함)
- `flutter test` 전체 — 1차 **1017 pass / 0 fail** → 환불 제거 후 **1013 pass / 0 fail** (RefundCalculator 테스트 4건 제거분)
- 어드민 `Members.tsx` RefundQuoteModal이 같은 서버 견적을 계속 사용함을 확인(회원만 비노출)
- 자문자답: 패스 전환 시 날짜 유지+재판정(기존 동작 보존), 잔여 0이어도 드롭다운 유지(다른 패스 후보), 미리보기 음수 불가(사전판정 통과 후에만 표시), 피커 initialDate 범위 밖 assert 방어, 기록 정렬 오래된 순 확인(마지막 점=최신 측정)

## 후속 작업
- 인바디 차트 다음 이터레이션 후보: 시리즈당 40px 스파크라인 2단 분리(이중 정규화 캡션 자체가 불필요해짐)
- 뷰어 상단바 Material 아이콘(close/delete) → RiseIcons 통일 검토
- RiseButton disabled 시각 상태가 "신청 중…"과 구분되는지 실기기 확인

## 참조
- work_log/P12-app-hold-judgment.md (HoldRules 신설 배경)
- work_log/P09-completeness-sweep.md (시트 useRootNavigator)
