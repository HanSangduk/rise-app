---
id: P43
title: 계약서 데모 경로(시드 사업자 정보·데모 래치) + 검증 프리뷰
status: 완료
domain: backend
created: 2026-08-29
completed: 2026-08-29
---

# P43 — 계약서 데모 경로 + 검증 프리뷰

## 목표

람 요청: "테스트용이니까 사업자 정보 12칸 임의로 넣어서 계약서가 정말 그렇게 나오는지 보고 싶다." 두 갈래로 해소 — ① 로컬 데모(DEV_SEED)가 첫 구동부터 계약서 본문을 스탬프·렌더하도록(실제 조립 경로로), ② 그 결과를 즉시 눈으로 확인할 프리뷰 아티팩트.

## 결정 사항

- **데모 래치 훅** `EnableContractTemplatesForDemo()` — 발행 래치(issuable=false)는 dev에서도 꺼져 있어 사업자 정보만 넣어서는 본문이 안 나온다. 훅의 도달 조건을 시딩과 정확히 같게(main의 `DevSeed && !UseFirestore` 블록) 묶어 **프로덕션(Firestore 모드)에서 켤 경로 자체가 없다** — v2.18 "래치 OFF 배포" 보장 유지. 레지스트리 리터럴은 그대로 false(배포 진실).
- **스탬프는 실제 경로로** — 시드가 Vars를 하드코딩하지 않는다(조립 로직 이중화 = 드리프트). main 데모 블록이 sent 전건을 owner1로 **재발송**해 SendContract → gatherContractVars → TransitionContract 실경로가 스탬프한다.
- **시드 값은 전부 명백한 테스트 값** — 등록번호 123-45-67890, .example 도메인, 신고번호 제2026-서울강남-0001호. 상호·대표자는 시드 페르소나(라이즈 컨디셔닝·박관장) 일치. Insurance는 일부러 비워 "가입하지 않았습니다" 폴백(제20조③)이 실렌더되는 표본으로. facility는 reported(더 풍부한 변형 시연 — 법적 판단 아님, 데모 데이터).
- **member1(김민지)의 sent 계약 자리** — 기존 모빌리티 8회 패스(계약 없던 자리)에 결제(완납 1회차+미도래 2회차 — {{납부일정}} 완료/예정 혼합 표본, 연체 KPI 불변)와 sent 계약을 붙였다. PT 20회 signed는 그대로(레거시 요약 열람 분기 시연).
- **프리뷰는 검증물** — 실제 앱 번들 자산 2종에, 데모 서버가 실제로 스탬프한 Vars 덤프를 치환(잔존 {{}} 검사·마크 수 38/37 = P42 슬롯 출현 실측과 일치). 브라우저 렌더임을 명시.

## 변경 파일

- `backend/internal/store/seed.go` — 사업자·시설 신원 절(SaveBusiness 12칸 + SaveFacility reported) + 모빌리티 패스 캡처·결제·sent 계약. ⚠ 같은 시각 타 세션(ptdesk-5a)이 체형 사진 블록을 동시 추가 — 비중첩 공존 확인(전체 스위트 그린)
- `backend/internal/api/contract_template.go` — EnableContractTemplatesForDemo(도달 조건·원복 규약 주석)
- `backend/cmd/server/main.go` — 데모 블록 2: 래치 ON + sent 전건 재발송 + 로그(domain import 추가)
- `backend/internal/api/service_demo_seed_test.go` — **신규** 데모 경로 통합 테스트: 레지스트리 리터럴 OFF 사전 단언(v2.18 보장 뮤테이션 방어) → SeedDemo → 훅 ON(Cleanup 원복) → 재발송 → 모빌리티 계약 reported 25종·스팟 값 3종·납부일정 혼합·signed 무접촉·스탬프 수=전송 수 단언

## 검증

- `go build`·`go vet`·`go test -count=1 ./...` 전건 그린(-race 포함, 타 세션 시드 사진 블록 포함 트리)
- 뮤테이션: 훅 무력화 → TestDemoSeedStampsSentContracts FAIL 확인 → 원복 ok (리터럴 true 뮤테이션은 테스트 서두 단언이 방어)
- **실서버 E2E**: `PORT=18099 DEV_SEED=true go run ./cmd/server` → "발행 래치 ON(데모 전용) · sent 계약 2건 Vars 스탬프 완료" → member1 curl: 모빌리티 계약 `pt-v1-reported`·vars 25·사업자명 라이즈 컨디셔닝·신고번호·보증보험 폴백·납부일정 `1회차 200,000원 (완료)\n2회차 120,000원 (예정)` 실측
- 프리뷰: 치환 마크 38/37(슬롯 출현 수 일치), exempt 문서 내 "체육시설" 언급 0(감사 유지), 별지 서식·폴백·혼합 일정 실렌더, 38KB 자립 파일

## 후속 작업

- 실값 교체는 §F 체크리스트 그대로(이 P는 테스트 값임을 어디에도 숨기지 않음 — 시드 주석·프리뷰 배지·본문 콜아웃 3중 고지)
- 앱 실기기 확인(선택): `DEV_SEED=true`로 서버 → 앱 member1 → 마이 → 모빌리티 계약 → 본문 스크롤·서명 게이트

## 참조

- [P39](P39-contract-document-machinery.md)(래치·조립·시트) · [P42](P42-contract-template-variants.md)(변형 2종·facility) · 프리뷰 아티팩트(2026-08-29 발행)
