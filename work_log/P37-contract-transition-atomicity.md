---
id: P37
title: 계약 전이 원자화(send·sign·void CAS) + 서비스 테스트 공백
status: 완료
domain: backend
created: 2026-08-29
completed: 2026-08-29
---

# P37 — 계약 전이 원자화 + 서비스 테스트 공백

## 목표

P36 감사의 백엔드 H·M 해소: ① 계약 상태 전이(send/sign/void)가 비원자 read-modify-write라 재발송 vs 서명 경합 시 signed 문서가 sent 사본으로 덮여 signed_at·signer_ip가 소실될 수 있고, 환불 void 루프 vs 서명 경합 시 "signed는 무효화 불가" 불변식이 깨질 수 있는 것을 P13 하우스 패턴(트랜잭션 동사)으로 봉인. ② SendContract·CreateContract 서비스 테스트 0건(M1) 해소. ③ CreateContract 패스당 유효 계약 1건 read-then-create 경합(M2)은 자연스러우면 포함.

## 결정 사항

(자문자답 사전 확정분)
- 새 패턴 발명 금지 — P13의 UpdatePassWithLedger류(트랜잭션 안 재검증, 정책은 도메인·스토어는 집행)를 그대로 따른다.
- 환불 시 계약 void: 기존 환불 트랜잭션 동사에 접합 가능하면 접합(P04 "완전 트랜잭션화" 종결), 아니면 각 void를 CAS 전이로 바꿔 signed 덮어쓰기만 확실히 차단하고 잔여 갭(refunded 패스 + sent 계약 잔존 가능)을 API계약 문서에 갱신 — 어느 쪽이었는지 아래에 기록.
- API 표면 무변경(라우트·상태 문자열·에러 매핑 동일). signed 재발송 400은 v1.4.1부터 이미 계약된 동작이라 어드민 수정 불요.
- 검증: 전체 go test + 스토어 conformance(Memory·Firestore 에뮬레이터) + latch 결정적 경합 재현 + 뮤테이션 킬 확인(하우스 컨벤션).

(P37 실행 중 확정분)
- **환불 void = 접합안 채택**: `UpdatePassWithLedger`의 시그니처는 건드리지 않고(비환불 3갈래 호출부 무변경) 형제 동사 `UpdatePassWithLedgerAndContracts`를 신설, 두 동사가 Firestore `updatePassInTx` 공용 본체를 공유. 계약 **스캔은 트랜잭션 밖**(서비스가 refundBasis의 목록에서 void 후보 ID를 사전 지목 — 컬렉션 잠금 회피), **재판정은 안**(ID 점읽기 후 sweep 콜백이 CanVoidContract로 재검증, signed는 스킵). 이유: 실측된 두 경합(H)과 "refunded 패스 + sent 계약 잔존" 크래시 잔여를 동시에 닫으면서, P13이 경고한 컬렉션 잠금을 피하는 유일한 모양이었다. 접합으로 v2.6 남은 갭의 **계약 절반**이 닫혔고, 결제 절반(미납 회차 waived_at 종결)은 회차 인덱스 단위 재검증이 필요해 PayInstallment 원자화 후속으로 미룸(문서에 명기).
- **전이 판정 위치**: 서비스 레벨 사전 가드(전이·환불 패스)를 남기지 않고 전부 mutate 콜백(트랜잭션 안)으로 **단일화**. 이중 방어로 남기면 바깥 가드가 어떤 테스트로도 죽일 수 없는 등가 뮤테이션이 되기 때문(뮤테이션 패스 설계상 각 가드는 정확히 한 곳). 트랜잭션 밖에는 권한 판정만 남김 — PassID·MemberID는 불변 필드라 스냅샷 판정이 안전.
- **ContractMutator가 (contract, pass)를 받는다**: 환불 패스 가드가 트랜잭션 밖 GetPass면 send/sign vs 환불 마감 경합 창이 남는다. 패스 문서가 없는 레거시 계약은 nil(기존 서비스의 `err == nil &&` 관용과 동일 허용).
- **M2 = 구현 채택**(`CreateContractGuarded`): Firestore 트랜잭션 내 쿼리(tx.Documents)가 ledgerInTx로 이미 검증된 하우스 패턴이라 "자연스러움" 기준 충족. Memory는 락 구간 스캔으로 자명. 에뮬레이터에서 동시 4건 중 1건만 통과 실측 확인.
- **경합 창 에러 문구 1건 통일**(비경합 표면 무변경): v1.4.1 경합 가드가 그 창에서만 내던 "이미 서명이 완료된 계약이에요" → 이제 다른 전이 위반과 같은 "현재 계약 상태에서는 처리할 수 없어요"(400 동일). v2.15 절에 명기.

## 진행 단계

- [x] 기존 코드 정독(스토어 동사 시그니처·latch·conformance 러너·API계약 문서)
- [x] 트랜잭션 전이 동사 설계·구현(Firestore·Memory 양쪽) — TransitionContract + UpdatePassWithLedgerAndContracts + CreateContractGuarded
- [x] SendContract·SignContract 이관
- [x] 환불 void 경로 처리(접합 or CAS) + 결정 기록 — **접합** (위 결정 사항)
- [x] M1 테스트(FirstSentAt 보존·signed 재발송 400·권한 403·환불패스 400·중복 계약 차단) + latch 경합 테스트 3종
- [x] 뮤테이션 패스(9/9 킬) + 전체 테스트 그린(-race 포함)
- [x] docs/API계약_v1.md v2.15 절 + v2.6 남은 갭 갱신 + 낡은 주석 2건(ErrInvalidContractStatus voided 누락, createContractForPass 지칭) 정정
- [x] Firestore 에뮬레이터 conformance 실행(신규 4종 포함 통과)

## 변경 파일

- `backend/internal/store/store.go` — ContractMutator(:65-74)·ContractSweepMutator(:76-81) 타입, 인터페이스에 UpdatePassWithLedgerAndContracts(:189-201)·CreateContractGuarded(:273-279)·TransitionContract(:281-291) + CreateContract/UpdateContract 사용 경계 주석
- `backend/internal/store/firestore.go` — UpdatePassWithLedger를 공용 본체 updatePassInTx(:474-)로 분리 + UpdatePassWithLedgerAndContracts(:466), CreateContractGuarded(:1280), TransitionContract(:1341, 계약+패스 동시 tx.Get)
- `backend/internal/store/memory.go` — UpdatePassWithLedger 위임(:469) + UpdatePassWithLedgerAndContracts(:477, 판정 후 일괄 커밋), CreateContractGuarded(:1020), TransitionContract(:1067)
- `backend/internal/api/service.go` — SendContract(:2647)·SignContract(:2689) TransitionContract 이관(판정 전부 콜백 안), RefundPass void 접합(:1059-1090, 옛 트랜잭션 밖 루프 삭제·뒷정리 주석 갱신), refundBasis 계약 목록 동시 반환(:1139), CreateContract → CreateContractGuarded(:2563), createContractForPass 낡은 주석 정정
- `backend/internal/domain/contract.go` — ErrInvalidContractStatus 주석 voided 누락 정정(:43)
- `backend/internal/api/hookstore_test.go` — GetContract·TransitionContract·CreateContractGuarded·UpdatePassWithLedgerAndContracts 래핑 + hookedOps 4종 추가 + latchOnFirstWrite 쓰기 집합 확장(신·구 동사 병기 — 뮤테이션 후에도 같은 창)
- `backend/internal/api/service_atomicity_test.go` — TestRefundIsAllOrNothing에 "마감⇔무효화 동시성" 검증 추가(찢어지면 refunded+sent 잔존을 모든 주입 지점에서 검출)
- `backend/internal/api/service_contract_test.go` — **신규**, M1 스위트 7종 + latch 경합 3종(total 10 func Test)
- `backend/internal/store/conformance_test.go` — 러너 4종 등록 + 없는 ID 테이블 2행, testContractTransitionFresh(:902)·testConcurrentContractTransition(:979)·testPassCloseWithContracts(:1045)·testConcurrentContractCreate(:1143)
- `backend/README.md` — v1.4.1 잔여 서술·갭 목록·conformance 서브테스트 수(12→20)·테스트 총계 재집계(274) 갱신
- `docs/API계약_v1.md` — v2.15 절 신설(보장·잔여 갭·스토어 계약), v2.6 남은 갭 문단 갱신

## 검증

- **테스트 수**: P37 이전 264 → **274**(func Test; api 169→179). conformance 서브테스트 16→20종.
- **go build / go vet / go test ./... 전부 그린**, `-race`(api·store)도 그린.
- **Firestore 에뮬레이터 conformance 실행 완료**(JDK zulu-21 + firebase-tools, `emulators:exec` — 15.8s ok): 신규 4종이 실제 OCC 위에서 통과 — 동시 서명 vs 재발송 3건에서 signed 증적 보존, 환불 마감+무효화 원자성(롤백·signed 스킵·없는 ID 전무), 동시 계약 생성 4건 중 정확히 1건(트랜잭션 내 쿼리의 팬텀 차단 실증), 전이 fresh 재검증.
- **결정적 경합(latch) 3종**: 재발송 vs 서명(서명 선착 → 재발송 400 + signed_at/signer_ip 무손상), 서명 vs 무효화(무효화 선착 → 서명 400·voided 유지), 무효화 vs 서명(후보 선정 후 끼어든 서명 → 스윕이 스킵·signed 보존 + 패스는 refunded).
- **뮤테이션 9/9 킬, 초기 생존 0** (각각 임시 반전→최소 1 테스트 적색→원복→전체 그린 확인):
  1. send 콜백 CanTransitionContract 제거 → TestSendContractSignedIsRejected + TestResendCannotClobberSignedContract
  2. FirstSentAt set-once 가드 제거 → TestSendContractFirstAndResendKeepsFirstSentAt(저장본까지 검증)
  3. 환불 스윕 CanVoidContract 스킵 제거 → TestRefundVoidSkipsContractSignedMidflight(설계대로 순차 테스트가 아닌 midflight 래치가 킬 — 사전 필터 때문에 순차로는 등가)
  4. CreateContract 중복 가드 제거 → TestCreateContractOnePerPass
  5. SendContract를 옛 read-modify-write로 회귀 → TestResendCannotClobberSignedContract(래치가 UpdateContract 쓰기 지점을 잡음)
  6. SignContract를 옛 경로로 회귀 → TestSignCannotResurrectVoidedContract
  7. 접합 해제(트랜잭션 밖 사후 void 루프로 회귀) → TestRefundIsAllOrNothing/GetContract·UpdateContract 주입 지점에서 "refunded 패스+sent 계약 잔존" 검출
  8. send 환불 패스 가드 제거 → TestSendAndSignContractRefundedPassGuard
  9. sign 환불 패스 가드 제거 → TestSendAndSignContractRefundedPassGuard
- 오케스트레이터 교차검증: `go build`·`go vet`·`go test ./...`(4패키지 ok)·`-race`(api·store) 직접 재실행 그린, func Test 274개 실측 일치. SendContract/SignContract 이관부(:2647·:2689 — 권한만 밖, 판정 전부 콜백 안)·환불 접합부(:1059-1092 — 후보 밖 선정 + 안 재판정·signed 스킵)·Firestore TransitionContract(:1341 — 계약+패스 동시 tx.Get, 재시도 초기화) 정독 확인. API계약 v2.15 절(:1692)·v2.6 갭 갱신(:901) 실재 확인. 에이전트가 작업 중 1회 스톨(watchdog 600s)해 재개시켜 완주 — 산출물 이상 없음.

## 후속 작업

- 미납 회차 종결(waived_at)의 트랜잭션 접합 — PayInstallment 원자화와 같은 후속으로(v2.15 남은 갭 명기). CreatePayment 상한 검사 경합도 그 자리.
- 환불 진행 중 끼어든 **수동** 계약 생성은 무효화 스윕이 못 보는 창 잔존(생성 가드 + send/sign 트랜잭션 내 환불 패스 가드가 실해는 차단 — 발송·서명 불가). 수동 생성 경로 자체가 어드민 소비처 0곳(P36 L)이라 경로 폐기 여부 결정이 먼저.
- README 테스트 표의 파일별 숫자는 여러 P에 걸쳐 낡아 있었음 — 총계만 재집계(274)하고 표에 주석을 달아 둠. 필요 시 별도 정리.
- P36의 나머지 후속(미서명 여정 연결·재발송 피드백·계약서 본문 축)은 본 P 범위 밖 그대로.

## 참조

- 발견: [P36](P36-admin-contract-audit.md) 신규 H(전이 비원자)·M1(테스트 0건)·M2(중복 생성 경합)
- 선행 갭 기록: P04 후속("무효화 단독 API 또는 재시도 경로"), API계약 v2.6 "남은 갭"
- 패턴 출처: P13(UpdatePassWithLedger·latch 데코레이터·공통 conformance 스위트)
- 결과 계약: API계약 v2.15 절(이 P가 신설)
