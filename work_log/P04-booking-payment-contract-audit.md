---
id: P04
title: 예약·결제·전자계약 도메인 수직 감사 + 보완
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P04 — 예약·결제·전자계약 도메인 수직 감사 + 보완

## 목표

세 도메인을 생애주기 전체로(생성→상태 전이→정산·통계 반영→타 도메인과의 이음새) 풀스택 추적해
교차검증·자문자답으로 버그와 정합 구멍을 찾아 보완한다.

## 결정 사항 (자문자답 — 계약·결제 감사 후, 예약 감사 대기 중)

- **환불 정산식 재정의(P5의 본래 의미)**: 환불액 = clamp(실수납(Σ paid installments) − 이용금액 − 위약금, 0).
  이용금액·위약금은 계약가(pass.paid_amount) 기준 유지(회당 단가는 계약 조건). 결제 기록이 아예 없으면
  계약가 폴백(레거시). refund-quote·refund 실행 모두 동일 식 + 응답에 paid_sum 필드 추가.
- **위약금율 스냅샷**: Contract에 penalty_rate(생성 시점 정책) 저장 — 환불 계산은 패스의 최신 유효
  계약 스냅샷 우선, 없으면 현재 정책(정책 변경의 소급 적용 차단 — 회원이 동의한 요율로 정산).
- **환불 시 결제 종결**: 미납 회차에 waived_at 마킹(원장주의 — 삭제 아님 표식) → Outstanding/미수금
  제외, PayInstallment는 paid 재호출·waived·refunded 패스 전부 400(멱등+가드).
- **미수금 = 연체(due<오늘)만**: unpaid_total/count는 연체 기준으로 재정의, 미도래는 upcoming_total
  별도 필드. 시드도 연체 1건으로 교체(미도래를 미수금으로 시연하던 것 정정).
- **순매출**: monthly/ytd/by_trainer revenue에서 refunded 패스 결제 제외 + 라벨 "(순액, 환불 제외)".
- **계약 voided 상태 신설**: RefundPass가 해당 패스의 draft/sent 계약을 voided로(서명된 계약은 기록
  보존 — 패스 상태로 맥락 표시). sign/send/create는 refunded 패스에 400. 패스당 유효(비voided) 계약
  1건 불변식. first_sent_at 추가(재발송이 최초 고지 시각을 지우지 않게).
- **signer_ip**: XFF 마지막 홉 파싱 헬퍼로 교체(Cloud Run append 시맨틱 — 첫 항목은 클라이언트 위조 가능).
- **CreatePayment 검증 게이트**: total>0 · Σ회차==total · 회차>0 · due 형식 · method enum · pass 실존/
  소유 일치 · trainer는 담당 패스만.
- **무결제 패스 가시화**: 대시보드 "해야 할 일"에 "결제 기록 없는 회원권 N건"(owner, 클라 조인) +
  재등록 모달 재진입 시 기존 무결제 패스 감지 → "결제만 기록" 모드(이중 발급 차단).

## 진행 단계

- [x] 1. 도메인 수직 감사 3팀 완료 — 전 선행 의심 실증(스크래치 사본 재현 테스트): 예약(HIGH 2·MED 6),
      결제(HIGH 2·MED 4 — 분할 50만 수납 패스 환불 견적 90만 실측), 계약(HIGH 1 — 환불 후 사후 서명 성립)
- [x] 2. 교차검증 + 자문자답 — 결정 사항 절에 기록(핵심: 환불 = 4종 부수효과의 단일 사건, 실수납 정산)
- [x] 3-1. backend v1.5 보완 완료: 정산 리워크 + 검증 게이트 + 회원 동시 1팀 + 무차감 취소 + voided 등
      (계약 v1.5 절 · 회귀 테스트 — 정산 골든 포함 · go test 전부 그린)
- [x] 3-2. admin v1.5 반영 9/9(build exit 0 — 실수납 표기·연체/예정/종결 4상태·voided 배지·무결제
      패스 감시·waive 취소·pay-only 모드) / app v1.5 반영 5/5(analyze 0 · 53/53 — 빈 시간대 합성·
      실수납 견적·voided 라벨·최소노출 가드)
- [x] 4. 통합 검수 라운드(3계층 새 눈): backend MEDIUM 2(납부 쓰기 스코프·0% 스냅샷 포인터)+LOW 3,
      admin MEDIUM 3(트레이너 오탐·에러 위장·slots 무효화)+LOW 6, app UX 갭 6(동작 버그 0) —
      전부 보완 후 최종 매트릭스 그린(P0405_FINAL=0). 잔여는 후속 작업 절에 문서화
- (병렬) P05: 백엔드 v1.6 완료, 앱·어드민 실행팀 가동 중

## 변경 파일

- backend: domain/{payment,refund,booking,contract,pass,staff*,stats}.go · api/{service,service_stats,
  handlers_*,router,util}.go · store/{memory,firestore,seed}.go · 테스트(정산 골든·P04 회귀 — api 36+)
  (*staff.go의 v1.6은 P05 트랙)
- admin: types/api/queries + Members/Sales/Dashboard/Schedule/Settings — v1.5 정산 표기·4상태·voided·
  무결제 감시·waive 취소·pay-only + 통합검수 보완 9건
- app: 빈 슬롯 합성·실수납 견적(출처 표시)·voided·최소노출 가드·절삭 미러 + 테스트 58케이스
- docs/API계약_v1.md: v1.5 정산·정합 패치 절(+통합검수 개정)

## 검증

- 감사: 도메인 3팀 실증(스크래치 재현 테스트 — 분할 50만 수납 환불 견적 90만, 환불 후 사후 서명,
  유령 미수금, 회원 이중 예약 등 전부 실측)
- 보완 후: go test(-race 포함) 그린 · flutter 58/58 · npm build exit 0 — P0405_FINAL=0
- 정산 골든: 완납 550,000 / 분할 50만 수납 50,000 / 실수납<공제 0원 클램프

## 후속 작업

- RefundPass·SendContract 완전 트랜잭션화(부수효과 순서: 현재는 상태 확정 후 waive/void 실패 시
  sent 계약 잔존 가능 — 무효화 단독 API 또는 재시도 경로, Firestore 전환 전 처리)
- GCLB 토폴로지 추가 시 signer_ip 홉 재검토(현재 Cloud Run 직결 전제 — 마지막 홉)
- 충돌 recurring 규칙 저장 자체는 허용됨(회차는 안 생김) — 생성 시 충돌 감지 안내 후속
- 트레이너 본인 프로필 편집 UI 입구(백엔드는 허용 — 트레이너 모바일 트랙에서)
- "미수금" 어드민 미납자 드릴다운(현재 건수만), 계약가≠실수납 대사 리포트

## 참조

- docs/API계약_v1.md (v1~v1.4.1) · work_log/P01~P03
