---
id: P03
title: v1.4 기능 검수·교차검증 + UI/UX 연속 검토 + 보완
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-22
---

# P03 — v1.4 기능 검수·교차검증 + UI/UX 연속 검토 + 보완

## 목표

P02에서 추가된 v1.4 기능 8건(수업기록·서명·환불·정책 편집·고정 스케줄·미수금·정산·시딩)을
새 눈으로 검수하고(신규 코드의 버그·스코프 구멍·엣지), 신규 UI 표면의 UX를 검토해 보완한다.

## 결정 사항

- 환불 실행 시 미래 confirmed 예약 **무차감 일괄 취소**(취소 원장 없이 슬롯만 해제) + complete/noshow에
  refunded 패스 이중 방어선. used는 **원장 파생값이 진실**(불일치 400) — 어드민은 입력 대신 자동 표시.
- PUT /v1/center **머지 시맨틱**(UpdateMember 패턴 재사용) — 누락 필드 초기화 방지.
- CreateWorkoutLog의 owner 대행 trainer_id는 **booking 교차검증으로만** 방어(GetStaff 실존 검증은
  스태프 생성 API 없는 dev 흐름을 막아 채택 안 함 — 자문자답).
- 앱 정책 캐시: 성공 시에만 keepAlive(실패 영구 캐시 제거) + 새로고침 경로에서 정책 동반 재조회.
  서버 강제는 요청 시점 정책이라 항상 최신 — 표시 지연만 새로고침으로 해소(계약 v1.4.1 주의 문구).
- 잔여 LOW 문서화: RefundPass/SendContract 완전 트랜잭션화·휴무 소급 스윕·signer_ip 프록시 전제.

## 진행 단계

- [x] 1. 병렬 검수 3팀 완료 — backend(HIGH 1·MED 4·LOW 7, 실증 테스트로 재현), admin(19건),
      app(HIGH 2·MED 4·LOW 6) — 크래시성 결함 없음, 전부 보완 가능 수준
- [x] 2. 교차검증: 선행 의심 3건 전부 실증(환불 미래예약 HIGH·owner 행·정책 캐시) + 자문자답 반영
- [x] 3-1. backend 보완 11건 + 회귀 테스트 4개(api 통합 30케이스) — go test 그린
- [x] 3-2. admin 19/19 · app 12/12 보완 완료
- [x] 4. 최종 매트릭스 그린(P03_FINAL_EXIT=0) + 계약 v1.4.1 절 + README 3종 갱신

## 변경 파일

- backend: service.go(환불 미래예약 취소·used 파생검증·hold/resume status 가드·recurring 과거회차·
  contract send 경합 가드·workout date/from 검증·PUT center 머지)·service_stats.go(owner 행 제외)·
  handlers_me.go·util.go(decodeJSON 다중문서)·service_test.go(+4, 총 30케이스)
- admin: Settings/Members/Schedule/Dashboard/Sales/Homework/auth 7파일 — 19건
- app: 13파일+테스트 — 12건(HIGH 2 포함), 테스트 50케이스
- docs/API계약_v1.md v1.4.1 절 · backend/admin/app README

## 검증

- 검수: 3팀 병렬(백엔드는 스크래치 사본 실증 테스트로 재현 검증) — 선행 의심 3건 전부 실증
- 보완 후: go test(api 30케이스) 그린 · flutter analyze 0/50 통과 · npm build exit 0 — 동시 매트릭스 exit 0

## 후속 작업

- RefundPass·SendContract의 스토어 트랜잭션화(현재 재확인 가드로 창 축소 — Firestore 멀티 인스턴스 대비)
- 휴무일 소급 등록 시 기존 confirmed 예약 스윕(현재 수동 정리, 카피에서 문구 제거됨)
- 취소 응답 확장(200 {late, waived}) 또는 policy_updated_at — 컷오프 내 취소의 차감 사실을 앱이 알 수단
- 인바디 날짜 파싱 tryParse 통일(records_repository_impl 잔여 1곳 — 앱 실행팀 메모)
- P02 후속 승계: 알림 어댑터·waitlist·리텐션 엔진·Firebase 트랙·실PDF·CSV·크론

## 참조

- work_log/P02-feature-gap-research-v14.md · docs/API계약_v1.md v1.4 섹션
