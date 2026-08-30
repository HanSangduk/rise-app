---
id: P40
title: 계약 검수 후속 — 탈퇴 시 미서명 계약 void·연속발송 마킹·소품
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P40 — 계약 검수 후속 (탈퇴 void · 연속발송 마킹 · 소품)

## 목표

P37·P38 적대 리뷰(2026-08-29)가 확정한 결함 수리. 판정: P37 SHIP(비차단 권고 2건만), P38 FIX-FIRST(H 1·M 2·L 4).

## 결정 사항

- **[H] 탈퇴 잔존 sent 계약은 서버 void로 원인 수리** — 문구 분기(증상 수리)가 아니라 DeleteMyAccount가 탈퇴 회원의 draft/sent 계약을 void한다. 근거: 서명 주체(Firebase 계정)가 파기되므로 "서명 대기"는 더 이상 사실이 아니다. CanVoidContract가 draft/sent만 허용(signed 불가침 유지), 문서는 남고 상태만 바뀌므로 5년 보존 비저촉(P22 "가명만 남긴 채 보존"과 합치), 환불 시 미서명 void와 동일 논리. P37 TransitionContract(CAS)로 계약별 void + 이미 voided/signed는 스킵(재시도 멱등 — P22 "같은 토큰으로 재시도" 순서 안에서 안전).
- **[M] 연속 발송 마킹 유실은 훅-레벨 콜백으로** — react-query v5에서 mutate-레벨 onSuccess는 다음 mutate가 옵저버를 떼는 순간 소실(리뷰가 라이브러리 소스로 실증). mutation 자체 옵션(훅-레벨)은 옵저버 분리와 무관하게 실행되므로 useSendContract(onSent?)로 확장해 variables로 마킹. 같은 패턴의 원조인 대시보드 체크인 마킹도 동일 결함이면 동일 수리.
- **[M] 트레이너 스코프 축 불일치는 이번엔 정직한 표시로만** — 근본 수리(계약 목록의 스코프 축을 회원 축과 정렬)는 API 시맨틱 변경이라 별도 P로. 이번에는 이름 미해석 계약에 죽은 링크를 만들지 않는다(링크 없는 완곡 표기). 탈퇴 케이스는 위 void가 원천 제거하므로 잔여는 담당 이관 드리프트뿐.
- [L] 주석 허위(Members.tsx:602 — 존재하지 않는 send 가드 인용)는 void 이후의 사실로 재서술: 탈퇴 회원 계약은 전부 종단 상태(signed/voided)가 되므로 상태 게이트만으로 버튼이 안 뜬다 — isWithdrawn 숨김은 이중 방어.
- [L] computeTodo 탈퇴 잔류: 동의 미완·만료 임박·장기 미방문 버킷에서 탈퇴 제외(행동 불가능한 항목), **결제 기록 없는 회원권 버킷은 유지**(장부 의무는 탈퇴와 무관).
- P37 리뷰 권고 채택: 스윕 contractIDs dedup 한 줄(트랜잭션 동일 문서 다중 쓰기 방어), ContractMutator 주석에 "포인터 필드는 재할당만, 경유 쓰기 금지" 명기.
- 소품 동봉: 미서명 카드 3명 초과 시 "외 N건", PASS_STATUS_LABEL 폴백.
- 이월(스코프 밖): Modal 포커스트랩·MemberDetail 무-key(모달 인프라 전반), ledgerPass 유령 필터, 스코프 축 근본 정렬.

## 진행 단계

- [x] 백엔드: DeleteMyAccount void 스윕 + 테스트(void·signed 보존·재진입 멱등) + dedup·주석 + API계약 **v2.17**(v2.16은 P41 관리평면이 동시 작업으로 선점 — 코드 인용 전부 v2.17로 정렬)
- [x] 어드민: 훅-레벨 마킹(+체크인 동일 수리 여부 확인) + 죽은 링크 제거 + computeTodo 탈퇴 제외 + 주석 재서술 + 소품 2건 — 체크인 마킹도 mutate-레벨이었음(같은 결함 확인, 동일 수리)
- [x] 검증: 백엔드 전체+race ✅ · 어드민 빌드 ✅ · 오케스트레이터 교차검증 ✅ — void 스윕 4단계(배치 주석·감사 로그) 정독, P41 동시 편집 포함 **현재 트리에서** build·vet·전체 테스트·race 직접 재실행 그린, 어드민 카드·마킹·computeTodo 정독 + 재빌드 그린(lowRemaining 확장 포함), API계약 v2.15→v2.16(P41)→v2.17(P40) 절 순서 정합 확인

## 변경 파일

어드민 절반:
- `admin/src/lib/queries.ts` — useSendContract(onSent?)·useCheckin(onCheckedIn?) 훅-레벨 성공 콜백 추가(variables로 대상 식별, 기존 캐시 무효화는 같은 onSuccess에 유지). API 호출 모양 무변경(api.ts 비접촉).
- `admin/src/features/Members.tsx` — 발송 성공 마킹을 훅 인스턴스화 시점 콜백으로 이전(mutate-레벨 옵션 제거, 행 단위 pending/error는 variables 식별 그대로), 발송 버튼 주석 재서술(존재하지 않는 send 가드 인용 제거 → P40 void 이후 사실: 종단 상태 게이트 + isWithdrawn 이중 방어), PASS_STATUS_LABEL `?? p.status` 런타임 폴백(Record<string,string>로 완화 — v2.11 CONTRACT_STATUS_LABEL 선례, 사용처 1곳 전수 확인).
- `admin/src/features/Dashboard.tsx` — 체크인 마킹 동일 수리(checkedInIds — 원조 패턴도 mutate-레벨이라 같은 유실 결함), 미서명 카드에서 이름 미해석 계약은 NameLink 대신 링크 없는 "(조회 불가)"(원시 member_id 죽은 링크 제거, 건수는 전체 유지), 3건 초과 시 "외 N건" 표기, computeTodo에서 탈퇴 회원을 동의 미완·만료 임박·장기 미출석 버킷에서 제외(결제 기록 없는 회원권 감시는 탈퇴 포함 유지).

백엔드 절반:
- `backend/internal/api/service_account.go` — **4단계 신설: 미서명 계약 voided 종결**(단계 재번호 4→5, 5→6). `voidContractsForWithdrawal`(후보를 외부 호출 ①② **뒤에** 신선하게 재조회 — cancelFutureBookingsForWithdrawal과 대칭) + 계약별 `TransitionContract`(CAS). 스킵 신호는 sentinel 에러 `errWithdrawalVoidSkip` — ContractMutator는 error만 반환하고 에러는 두 스토어 모두 무쓰기 롤백이라, 호출측이 이 에러만 삼키면 RefundPass 스윕의 save=false와 같은 의미를 **동사 계층 무변경**으로 표현(P40 결정 "smallest consistent change"). 배치 근거 주석(②보다 뒤: 좌초 시 산 회원 계약 오염 방지 / ⑤·⑥보다 앞: 미완료 가시성 + 같은 토큰 재시도, P22). 감사 로그에 voided_contracts 추가(응답 와이어 무변경 — retained.contracts 수 불변).
- `backend/internal/api/service.go` — CreateContract에 탈퇴 회원 가드(v2.11 후속 차단 목록의 누락 자리): 탈퇴 void가 "패스당 유효 계약 1건" 가드의 분모(비voided)를 비우는 순간 같은 패스에 영원히 미서명인 draft를 재생산할 수 있던 유일한 경로. send/sign은 가드 불요(잔여 계약이 전부 종단 상태라 전이 규칙이 이미 차단 — P37 SHIP 경계 비접촉).
- `backend/internal/store/store.go` — ContractMutator 주석에 포인터 필드 재할당 규약 명문화(`*c.SentAt = t` 금지 — Memory 얕은 사본 롤백 전제, P37 리뷰 권고 ②).
- `backend/internal/store/firestore.go` — updatePassInTx contractIDs dedup(같은 문서 이중 tx.Set 방어, P37 리뷰 권고 ①. 사본으로 걸러 호출측 슬라이스 비접촉).
- `backend/internal/store/conformance_test.go` — PassCloseVoidsContractsAtomically ①정상 마감에 중복 지목 케이스("중복은 1회로 접힌다" 규약 고정 — Memory·에뮬레이터 공통).
- `backend/internal/api/service_account_test.go` — P22 스위트 의식적 개정: 보존 단언이 이제 **voided 상태 + 발송 증적(sent_at·first_sent_at) 보존**까지 검사(건수 1 유지 — 문서 보존 불변), 외부 파기 실패 케이스에 "계약 무접촉(sent 유지)" 단언 추가(배치 검증). 신규 3종: `TestDeleteMyAccountVoidsUnsignedContracts`(sent·draft→voided, signed 불가침, retained 3 불변, sent 필터 0건), `TestDeleteMyAccountVoidSweepRetryIsIdempotent`(hookstore fail 주입 n=2 — 부분 실패 후 같은 토큰 재시도, TransitionContract 총 3회로 스킵-무트랜잭션까지 고정), `TestDeleteMyAccountVoidSkipsContractSignedMidflight`(latch — 막판 서명 보존 + 탈퇴 완주, P37 TestRefundVoidSkipsContractSignedMidflight의 탈퇴판, reached 5s 가드 동봉). TestWithdrawnMemberBlocksNewWrites에 "계약 생성" 서브테스트.
- `docs/API계약_v1.md` — v2.11 개정 2곳(보존 블록: "계약은 무접촉이 아니다 — 미서명은 voided 종결" / 실행 순서: ④ 신설·⑥까지 재번호·재시도 문구 정합) + **v2.17 신설**(근거·signed 불가침·재시도 멱등·자리·후속 차단 추가·"탈퇴 후 환불은 정책 폴백" 명문화·하드닝 2건·남은 갭).

## 검증

어드민 절반:
- `npm run build` 통과(tsc strict 2종 + vite, 2026-08-29) — 타입·컴파일 회귀 없음.
- 훅 사용처 전수 grep: useSendContract=Members.tsx 1곳, useCheckin=Dashboard.tsx 1곳 — 옵셔널 파라미터라 다른 호출부 영향 없음.
- ["contracts"] 무효화는 발송 성공 시 훅-레벨 onSuccess에서 그대로 발화(마킹 콜백과 같은 자리).
- mutate-레벨 마킹 잔재 0건(grep), 미서명 카드 원시 id 폴백(`?? c.member_id`) 잔재 0건.
- "(조회 불가)" 로딩 오탐 없음 — 카드 콘텐츠는 membersQ 로딩·에러 분기 통과 후에만 렌더(memberName 맵 완성 상태).

백엔드 절반 (2026-08-29):
- `go build ./...` · `go vet ./...` · `go test ./...` 전 패키지 green, `-race`(api+store) green.
- 탈퇴 스위트 11개 전부 PASS(기존 8 + 신규 3).
- Firestore 에뮬레이터(zulu-21 + firebase emulators:exec): 계약 동사 서브테스트 3종(중복 지목 포함) PASS. ⚠ 전체 러너는 `CenterIdentityRoundTripAndCoexist` 1건 FAIL — **P41(관리평면) 동시 작업의 신규 코드**로 본 작업 무관(P41 마무리에서 확인 필요).
- 뮤테이션 6종 — **5/6 KILLED**:
  - M1 사전 필터 반전(`!CanVoidContract`→`CanVoidContract`) KILLED
  - M2 트랜잭션 내 재판정(sentinel) 제거 KILLED — 잡는 건 latch 테스트 단독(존재 이유 실증)
  - M3 sentinel 삼킴 제거(스킵을 에러로) KILLED
  - M4 스윕을 가명화 뒤로 이동(배치 뮤테이션) KILLED
  - M5 CreateContract 탈퇴 가드 제거 KILLED
  - M6 dedup 제거 **SURVIVED**(Memory·에뮬레이터 모두) — 에뮬레이터도 같은 문서 이중 tx.Set을 허용(마지막 쓰기 승리, 스윕은 같은 값이라 무해). 순수 방어 가드로 확인: 실서버/SDK 버전별 거부 가능성과 미래의 값-상이 스윕에 대한 보험. 공통 스위트의 중복 지목 케이스는 "중복=1회" **규약**을 고정하므로 별개 가치.
- 자문자답(해소): ① 탈퇴 후 그 패스 환불 시 위약금율? → 유효(비voided) 계약이 없어 refundBasis 정책 폴백 — 미서명 요율은 동의된 적 없는 숫자라 스냅샷 자격이 애초 없음(의도된 결과로 v2.17 명문화). ② 수동 생성 경로가 방금 닫은 불변식을 재생산? → 재생산 가능했음 — CreateContract 가드로 봉인 + 서브테스트. ③ 후보 스캔과 void 사이 생성 창? → 밀리초 창, v2.15 남은 갭과 동형으로 v2.17에 문서화(돈이 움직이는 상태 아님).

## 후속 작업

- **문서 버전 경합 정리**(오케스트레이터 교차검증 시): P41이 v2.16을 선점해 이 패치는 v2.17로 넘버링(문서 말미 append + 코드 인용 정렬 완료). 두 섹션의 최종 순서·중복 여부 한 번 훑을 것. 에뮬레이터 러너의 Center 서브테스트 FAIL도 P41 마무리 확인 대상.
- ~~computeTodo 잔여<3(lowRemaining) 버킷~~ → **오케스트레이터가 즉시 확정·반영**(2026-08-29): 같은 "행동 불가능" 논리(재계약 상담할 상대가 없다 — 잔여 회차의 실제 남은 행동은 환불 정산이고 그건 이 버킷 문구가 아니다)로 4버킷 전부 `actionable` 필터로 통일. 빌드 재확인 그린.
- (이월 재확인, 결정 사항 참조) Modal 포커스트랩·MemberDetail 무-key, ledgerPass 유령 필터, 계약 목록 스코프 축 근본 정렬(별도 P).

## 참조

- 발견: P37·P38 적대 리뷰(2026-08-29, 세션 기록), [P38](P38-admin-contract-journey.md) 후속, [P22](P22-account-deletion.md)(탈퇴 순서·멱등), [P37](P37-contract-transition-atomicity.md)(TransitionContract)
