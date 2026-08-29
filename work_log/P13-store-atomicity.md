---
id: P13
title: 저장 계층 원자성 — 돈과 세션이 움직이는 경로를 전부 스토어 트랜잭션으로
status: 완료
domain: backend
created: 2026-08-23
completed: 2026-08-23
---

# P13 — 발급·환불·홀딩·취소·예약의 원자성 결함(C1·C2·C3·H1·H2·H3·M4 + M1)

## 목표

전용 감사가 Firestore 에뮬레이터로 **전부 실측 재현한** 저장 계층 결함을 막는다. 일곱 건이
각각 다른 엔드포인트에 있었지만 한 문장으로 묶인다: **한 사건(발급·환불·홀딩·취소)이 여러
스토어 호출로 쪼개져 있었고, 그 사이를 막는 것이 아무것도 없었다.**

가장 위험한 성질은 **Memory 스토어에서는 재현되지 않는다**는 것이다(전역 뮤텍스라 경합 창이
나노초). `go test`는 전부 통과하는데 프로덕션에서만 터진다 — 이 프로젝트가 이미 한 번 겪은
사고의 형태다(P06 전화번호 정규화: 테스트 전부 통과, 프로덕션 회원 온보딩 100% 불능).
게다가 이 시스템에는 **되돌리는 동사가 없다**(`domain.ReasonRevert`는 상수만 있고 사용처 0건,
패스 삭제·원장 정정 라우트 없음) — 한 번 어긋나면 Firestore 직접 편집 외에 복구 경로가 없다.

| ID | 증상(감사 실측) |
|---|---|
| C1 | 동시 환불 2건이 **둘 다 200** — 환불 승인액 495,000원이 두 번, 원장 합 −10 |
| C2 | `UpdatePass`만 실패 → 500인데 원장엔 refund 1건 + 패스는 `active/remaining=0`으로 영구 고착(회원 예약 400, 담당 코치 퇴사 409) |
| C3 | 계약 자동생성만 실패 → **HTTP 500 × 3인데 패스 3개 + 원장 issue 3건 = 60회 지급** |
| H1 | 잔여 2회 패스에 순차 4건 예약 성공 → 4건 완료 → `remaining = −2`(경합이 아니라 검사 자체가 없었다) |
| H2 | 겹치지 않는 홀딩 5건 동시 → 200 × 5인데 저장 holds 1건, 유효기간 5일만 연장, 원장 hold 5건 |
| H3 | 완전히 같은 from/to로 3회 순차 호출이 전부 200 — 유효기간이 3번 연장 |
| M4 | 원장 적재만 실패 → 취소는 확정인데 페널티 없음, 재시도는 400에 막혀 **페널티 영구 소실** |
| M1 | 패스 목록 순서가 Firestore에서 무작위(문서 ID 체계 차이) — 회원 앱 기본 회원권 선택이 제비뽑기 |

## 결정 사항

### 패턴은 이미 코드베이스 안에 있었다 — 예약 상태 전이를 베낀다
감사 결론: 원자성이 제대로 된 곳은 `BookAtomic`·`CancelAtomic`·`SetBookingStatusWithLedger`
하나뿐이었다. 이들은 **서비스 가드 + 스토어 내부 재검증**(락/트랜잭션 안에서 `ErrStateConflict`)의
이중 방어가 실제로 작동한다. 새 동사도 같은 모양으로 만들었다 — 새 개념을 도입하지 않았다.

### 새 스토어 동사 2개 + 기존 2개 확장
- `IssuePass(pass, ledger, contract)` — 발급 3단을 한 트랜잭션(C3).
- `UpdatePassWithLedger(passID, mutate)` — 패스 갱신 + 원장 적재를 한 트랜잭션(C1·C2·H2·이관).
- `CancelAtomic(..., entry)` — 취소 + 페널티 원장을 한 트랜잭션(M4). complete/noshow는 처음부터
  한 트랜잭션이었는데 **취소만** 쪼개져 있었다.
- `BookAtomic` — 트랜잭션 **안에서** 잔여 청구권을 재판정(H1).

`UpdatePassWithLedger`만 클로저(`PassMutator`)를 받는다. 환불·홀딩·재개·이관 네 갈래가 각각
전용 동사를 가지면 두 구현에 8개를 쓰게 되고, 판정 로직이 도메인에서 스토어로 새어 나간다.
클로저는 **트랜잭션 안에서 읽은 최신 패스 + 그 패스의 원장 전체**를 받으므로 판정은 서비스에
남고 원자성만 스토어가 책임진다. 대가는 두 가지 제약이고 인터페이스 주석에 못박았다:
mutate는 순수해야 하고(재시도 시 여러 번 호출), **Store를 다시 부르면 안 된다**(Memory는 전역
락을 쥔 채라 교착).

### H1은 서비스와 스토어 양쪽에 넣는다
잔여는 완료 시점에 차감되므로(P4) 예약이 늘어도 줄지 않는다 — "잔여 이내"는 `Σdelta −
confirmed건수 > 0`이어야 성립한다. 이 뺄셈은 `CreateRecurring`에만 있었고(P12 H4) **일반 예약이
더 싼 우회로**였다. 서비스 검사만 추가하면 동시 요청 2건이 같은 마지막 회차를 각자 통과하므로
`BookAtomic` 트랜잭션 안에서도 재판정한다. 부수효과로 `pass.remaining` 저장 스냅샷을 원장 합에
맞춘다(M3 완화).

트레이드오프: Firestore 트랜잭션에서 쿼리 읽기의 충돌 단위는 **컬렉션 전체**다(에뮬레이터
실측). 예약 생성이 센터의 bookings·ledger 컬렉션 쓰기와 광범위하게 충돌한다는 뜻이다.
친구 샵 규모(회원 수십 명)에선 문제가 아니고, 프로덕션 Firestore는 인덱스 범위 락이라
에뮬레이터보다 **덜** 충돌한다. 규모가 커지면 패스별 색인 필드를 추가할 자리다.

### H3은 "완전 동일 구간"만 막는다
스태프가 `ValidateHoldWindow`(겹침 금지)를 건너뛰는 것은 데스크 예외(과거 정정)라 유지한다.
다만 **from/to가 완전히 같은** 재신청은 정당한 정정이 아니라 재시도다 — 그것만 400으로 막는다.

### 패스 목록 정렬 기준은 `valid_from`(M1)
문서 ID 정렬은 "같은 규칙, 다른 순서"였다: Memory는 발급 순 시퀀스, Firestore는 무작위 20자.
`valid_from`은 두 스토어에 똑같이 저장돼 있고(substrate 중립) "먼저 시작한 것부터 쓴다"가 실제
소진 순서다. 남은 한계: 같은 날 시작하는 두 패스는 문서 ID로 갈려 순서가 다를 수 있다 —
없애려면 `Pass.created_at` 추가(계약 변경)가 필요해 보류.

### 남긴 것: 환불 뒷정리(미납 종결·미서명 계약 무효화)는 여전히 트랜잭션 밖
결제·계약은 센터 전체 컬렉션 스캔으로 찾으므로 트랜잭션에 넣으면 그 컬렉션 전체가 잠긴다.
돈의 방향을 결정하는 마감을 먼저 확정하고, 뒷정리 실패는 사람이 볼 수 있는 500으로 남기는
쪽을 골랐다(재시도는 "이미 환불 처리된 패스예요" 400으로 이유가 설명된다). 뒷정리 전용
재시도 경로는 후속 과제.

## 진행 단계

- [x] 감사 항목 재현 경로 파악(service.go 발급·환불·홀딩·취소·예약, memory/firestore 대조)
- [x] 선작성 테스트 — 두 구현 공통 계약 스위트 11종 + 서비스 원자성 9종(서브테스트 64)
- [x] 스토어 인터페이스 확장(IssuePass·UpdatePassWithLedger·CancelAtomic entry·BookAtomic 재판정)
- [x] Memory·Firestore 두 구현 반영
- [x] 서비스 레이어 이관(CreatePass·HoldPass·ResumePass·RefundPass·CreateBooking·CancelBooking·TransferStaff)
- [x] Firestore 유령 문서 가드(Pass·Payment·Contract·JoinRequest·DeleteRecurring)
- [x] 패스 목록 정렬(M1)
- [x] 에뮬레이터 러너(빌드 태그 `firestore_emulator`) — 같은 스위트를 실제 Firestore에 대고 실행
- [x] 뮤테이션 검증 13/13 kill

## 변경 파일

| 파일 | 변경 |
|---|---|
| `internal/store/store.go` | `PassMutator` 타입, `IssuePass`·`UpdatePassWithLedger` 추가, `CancelAtomic`에 entry, `BookAtomic`·`UpdatePass` 계약 주석 |
| `internal/store/memory.go` | 새 동사 2종, `CancelAtomic` entry, `BookAtomic` 잔여 재판정, `listLedgerLocked`/`appendLedgerLocked` 분리 |
| `internal/store/firestore.go` | 새 동사 2종(`ledgerInTx`·`countOpenPassBookingsInTx` 포함), `CancelAtomic` entry, `BookAtomic` 잔여 재판정, Update*/Delete 존재 확인 5곳 |
| `internal/store/order.go` | `sortPasses`(valid_from 기준) 신설, `passDocID` 제거 |
| `internal/store/errors.go` | (변경 없음 — `checkDocID`를 새 자리에서 재사용) |
| `internal/domain/booking.go` | `ErrNoSessionsLeft` 신설 |
| `internal/api/service.go` | `CreatePass`·`HoldPass`·`ResumePass`·`RefundPass`·`CreateBooking`·`CancelBooking` 재구성, `usedFromLedger`·`cancelPenaltyEntry`·`buildContractForPass` |
| `internal/api/service_staff.go` | 패스 이관을 `UpdatePassWithLedger`로 |
| `internal/api/util.go` | `ErrNoSessionsLeft` 400 매핑 + 한국어 문구 |
| `internal/store/conformance_test.go` | **신규** — 두 구현 공통 계약 스위트 + Memory 러너 |
| `internal/store/firestore_conformance_test.go` | **신규** — 에뮬레이터 러너(`//go:build firestore_emulator`) |
| `internal/api/hookstore_test.go` | **신규** — 실패·래치 주입 스토어 데코레이터 |
| `internal/api/service_atomicity_test.go` | **신규** — 찢어진 쓰기 스윕 + 결정적 경합 재현 |
| `internal/store/order_test.go` | 패스 정렬 테스트를 새 규칙으로 |
| `internal/api/service_recurring_hw_test.go` | 픽스처가 잔여를 꽉 채우지 않게(H1 가드에 걸림) |
| `testdata/firebase.json` | **신규** — 에뮬레이터 설정(루트 firebase.json 미변경) |
| `.gitignore` | 에뮬레이터 로그 |

## 검증

```
go build ./... && go vet ./... && go vet -tags firestore_emulator ./...   # OK
go test ./... -race -count=1                                              # 4/4 패키지 ok
```

**에뮬레이터(실제 Firestore 트랜잭션)** — JDK 21 필수:
```
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
firebase emulators:exec --only firestore --project demo-rize \
  --config backend/testdata/firebase.json \
  'cd backend && go test -tags firestore_emulator -count=1 ./internal/store/'
```
→ `TestFirestoreStoreConformance` 11/11 PASS(동시 환불·동시 홀딩·동시 예약 포함, 9.2s).

**뮤테이션 13/13 kill** — 새 가드를 하나씩 되돌려 대응 테스트가 실제로 깨지는지 확인 후 복구.

| 뮤테이션 | 죽인 테스트 |
|---|---|
| 발급 3단 분리(C3) | `TestIssuePassIsAllOrNothing` |
| 환불 원장/패스 분리(C1·C2) | `TestRefundIsAllOrNothing`, `TestConcurrentRefundPaysOnce` |
| 홀딩 read-modify-write 복원(H2) | `TestConcurrentHoldsBothLand` |
| 홀딩 멱등 가드 제거(H3) | `TestDuplicateHoldIsRejected` |
| 취소 페널티 분리(M4) | `TestCancelPenaltyIsAllOrNothing` |
| 예약 잔여 검사 제거 — 서비스(H1) | `TestBookingCannotExceedRemaining` |
| 예약 잔여 재판정 제거 — Memory(H1) | 공통 스위트 `BookAtomicEnforcesPassBudget` |
| mutate가 원장을 못 보게(스냅샷 사용) | 공통 스위트 다수 |
| 패스 정렬 문서 ID 회귀(M1) | `TestSortPassesByValidFromThenID`, 공통 스위트 |
| 이관 원장/담당 분리 | `TestTransferPassKeepsLedgerAndOwnerTogether` |
| Firestore `UpdatePass` 유령 가드 제거 | 공통 스위트(에뮬레이터) |
| Firestore `BookAtomic` 재판정 제거 | 공통 스위트(에뮬레이터) |
| Firestore `DeleteRecurring` 존재 확인 제거 | 공통 스위트(에뮬레이터) |

## 후속 작업

- **환불 뒷정리 재시도 경로** — 미납 종결·미서명 계약 무효화가 마감 뒤에 실패하면 재실행 수단이
  없다(위 "남긴 것" 참고).
- **되돌리는 동사** — `domain.ReasonRevert`는 여전히 사용처 0건. 원장 정정 라우트가 없으면
  잘못 적재된 이벤트는 손댈 수 없다.
- **`Pass.created_at`** — 같은 `valid_from` 두 패스의 순서 결정(계약 변경 필요).
- **M3 완전 해소** — `BookAtomic`·`UpdatePassWithLedger`가 스냅샷을 갱신하지만
  `SetBookingStatusWithLedger`(완료·노쇼)는 아직 패스를 건드리지 않아 그 경로에서 다시 벌어진다.
- **L1 원장 동시각 정렬 비결정** — 미처리.
- **CI** — 에뮬레이터 잡 추가(아래 참조).

## 참조

- 감사 지시 및 실측 수치: 본 작업 지시서
- `internal/store/conformance_test.go` 상단 주석 — 공통 스위트가 존재하는 이유
- `internal/api/hookstore_test.go` 상단 주석 — Memory에서 경합·부분 실패를 재현하는 방법
- P12 감사 계열(`P12-money-integrity-refund-payment.md`, `P12-recurring-hw-schedule.md`)
