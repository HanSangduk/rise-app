---
id: P36
title: 어드민 계약 관리 3관점 감사(읽기 전용)
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P36 — 어드민 계약 관리 3관점 감사 (읽기 전용)

## 목표

"어드민 계약서 관리가 잘 만들어졌는지" 검증. 어드민 UI / 백엔드 도메인 / 3계층 정합·기지 미해결 3개 관점 병렬 감사 후 교차검증. **코드 무변경** — P21과 같은 읽기 전용 스윕.

## 결정 사항

- **판정: 골격(상태머신·요율 스냅샷·권한·보존·3계층 정합)은 돈 경로 수준으로 견고. 그러나 "계약서 문서" 축이 미완이라 어드민은 실질적으로 발송 로그 뷰어** — 계약 내용·서명본을 여는 화면이 없고, 서명이 봉인하는 본문(sha256/pdf)이 없다. 이 축은 P23·P28·v2.8이 이미 기지 갭으로 기록한 로드맵 항목.
- 3계층 상태 문자열·penalty_rate nullability·필드명 전부 일치 확인(API계약 v2.14 기준). CRITICAL/HIGH 계층 불일치 0건.
- 백엔드 계약 테스트 실행 PASS 확인(`TestCanTransitionContract`, `TestContract*`, `TestIssuePassIsAllOrNothing`).

## 진행 단계

- [x] 어드민 UI 감사 (Members/Dashboard/Sales/queries/api/types 전수)
- [x] 백엔드 도메인 감사 (핸들러→서비스→도메인→스토어 2종 + 테스트 실행)
- [x] 계층 정합 감사 (E2E 흐름 + work_log 6건 기지 항목 대조)
- [x] 교차검증 (중복 병합·모순 0건·기지/신규 분리)

## 변경 파일

없음 (읽기 전용).

## 검증

**신규 발견 (work_log 미기재분, severity 순)**

- [H] 미서명 계약 탐색 여정 단절 — Dashboard.tsx:382-386 "계약서 미서명 N건"이 텍스트뿐(클릭·회원명 없음). 바로 아래 "결제 기록 없는 회원권"은 NameLink 직행인데 계약만 끊김. 회원 목록에도 계약 상태 컬럼 없음 → 미서명 건을 찾으려면 상세를 하나씩 열어야 함. 재료(member_id, membersQ)는 이미 로드돼 있음.
- [H] 어드민에서 계약 내용/서명본 열람 불가 — Members.tsx:554-595는 메타데이터 행만. types.ts:375-377의 signer_ip/sha256/pdf_path 사용처 0곳. 백엔드에도 문서 라우트 없음(절반은 기지 갭 v2.8, 어드민이 이미 받는 증적조차 안 보여주는 건 신규).
- [H] 계약 전이 저장 비원자 — firestore.go:1240-1250 UpdateContract가 read-then-Set(CAS 없음), send/sign/void 전부 서비스 레벨 RMW. 재발송 vs 서명 경합 시 signed를 sent 사본으로 덮어 signed_at·signer_ip 소실 가능, 환불 void 루프 vs 서명 시 "signed 무효화 불가" 불변식 파괴 가능. P13 트랜잭션 동사(UpdatePassWithLedger류)가 계약엔 미적용 — P04 후속과 동근원, 경합 창 실측 좁으나 증거 도메인.
- [M] SendContract·CreateContract 서비스 테스트 0건 — FirstSentAt 보존(:2662-2664), 환불패스 send/sign 가드, signed 재발송 400, 패스당 유효 계약 1건 차단 전부 미검증. latch 경합 인프라가 있는데 send-vs-sign엔 미적용.
- [M] 재발송 성공 피드백 부재 — Members.tsx:583-592 토스트 없음 + 화면 변화는 일 단위 날짜뿐이라 같은 날 재발송은 무변화로 보임 → 연타 → 회원에게 서명 요청 중복 발송 경로.
- [M] 탈퇴 회원 상세에 "추가 계약(재등록)"·재발송 버튼 잔존 — 서버 400으로 막히지만, 같은 파일이 세운 "눌러보고야 실패를 아는 버튼을 남기지 않는다"(408-414) 원칙 위반.
- [M] CreateContract "패스당 유효 계약 1건" read-then-create 경합(service.go:2571-2580) — 동시 2건이면 refundBasis 단일 가정 붕괴. 수동 엔드포인트라 실위험 낮음.
- [L] useCreateContract/POST /v1/contracts 소비 화면 0곳(데드 코드) — 계약 누락 패스(v1.1 이전분)에 계약을 만들어 줄 UI 경로도 없음
- [L] 발송 pending/error 행 미식별(payInstallment 패턴 미달) / [L] CONTRACT_STATUS_LABEL 폴백 없음(MEMBER_STATUS_LABEL은 v2.11 사고 후 폴백 있음) / [L] 상담 중 서명해도 화면 미갱신(staleTime 15s·폴링 없음) / [L] trainer 목록 N+1 GetPass / [L] 대시보드 미서명 카운트가 refunded 패스의 잔존 sent 계약 포함(앱은 방어, 어드민 비대칭) / [L] 5년 경과 후 파기 경로 부재(signer_ip 개보법 §21) / [L] 낡은 주석 3건(contract_dto.dart:22, domain ErrInvalidContractStatus voided 누락, createContractForPass 지칭)

**잘된 점(교차 확인)**: 상태머신 순수 함수+골든 테이블 완전 커버 / 발급 3단(패스+원장+계약) 단일 트랜잭션 + 실패주입 스윕 / 요율 스냅샷 3중 방어(null=레거시 vs 0=동의 구분이 앱·어드민까지 보존) / first_sent_at 최초 고지 증적 / 센터 격리 구조적 봉인 / 서명 member 본인 강제 / 탈퇴 가명화 계약 비접촉 / P28 서명 전 4종 고지·P23 재열람 코드 실재.

**기지 미해결(재확인, work_log 기록분)**: 계약서 본문 렌더링(TemplateVersion·Vars·sha256) 구현 P 부재(P28) / RefundPass·SendContract 트랜잭션화(P04·v2.6) / 사업자 정보 12칸 등록+약관 시행일(P27, 람 몫) / 체육시설업 신고 여부 결정(P28, 람 몫) / 귀책 환불·청약철회 판정·위약금 재량 인하 입구(P28 D1·D5·D7) / Contract에 회차·유효기간 없음(계약서 §B-3 C2) / 계약가 정정 불가(v2.5).

## 후속 작업

우선순위 제안 (구현은 별도 P로):

1. **계약 전이 트랜잭션 동사** — CAS형 `TransitionContract(id, from, to)` 도입 + send/sign/void 이관 + latch 경합 테스트. P04 후속을 닫으면서 신규 H도 함께 해소, 위 M(테스트 0건)도 이때 같이.
2. **미서명 여정 연결** — 대시보드 카운트 → 회원명 리스트+NameLink (재료 이미 로드됨). 반나절감.
3. **재발송 피드백**(토스트+행 단위 pending) + 탈퇴 회원 버튼 숨김. 소품.
4. **계약서 본문 축**(P28 §D 렌더링 → sha256 봉인 → 어드민/앱 열람) — 가장 크고, 람 결정 2건(체육시설업 신고 여부·사업자 정보 등록)이 선행 조건.

## 참조

- 감사 대상: admin/src/features/Members.tsx·Dashboard.tsx, backend/internal/api/{handlers_contracts,service}.go, internal/domain/contract.go, internal/store/{firestore,memory}.go, app/lib/features/my/*
- 기준 문서: docs/API계약_v1.md(v2.14) · docs/계약서_PT이용계약_v1.md(P28 초안, 코드 참조 0곳)
- 선행 P: P04 · P12 · P13 · P21 · P23 · P27 · P28
