---
id: P38
title: 어드민 계약 여정 연결(미서명 링크·재발송 피드백·탈퇴 버튼)
status: 완료
domain: admin
created: 2026-08-29
completed: 2026-08-29
---

# P38 — 어드민 계약 여정 연결

## 목표

P36 감사의 어드민 H·M·L 해소: ① 대시보드 "계약서 미서명 N건"이 텍스트뿐이라 미서명 건을 찾으려면 회원 상세를 하나씩 열어야 하던 여정 단절(H) — 회원명 NameLink로 연결. ② 같은 날 재발송이 화면상 무변화라 연타→중복 발송으로 이어지던 피드백 부재(M) — 행 단위 pending/성공/에러. ③ 탈퇴 회원에 남아 있던 발급·재발송 버튼(M) — "눌러보고야 실패를 아는 버튼을 남기지 않는다" 원칙 정렬. ④ L 3건 동봉: 미서명 카운트의 refunded 잔존 계약 제외(앱과 비대칭 해소), CONTRACT_STATUS_LABEL 폴백, 데드 훅(useCreateContract) 제거.

## 결정 사항

(자문자답 사전 확정분)
- 새 패턴 발명 금지 — NameLink는 "결제 기록 없는 회원권" 카드 패턴, 행 단위 pending은 payInstallment 패턴(variables로 행 식별), 버튼 숨김은 수정 버튼 선례(Members.tsx 408-414), 라벨 폴백은 MEMBER_STATUS_LABEL v2.11 선례를 그대로 따른다.
- refunded 제외는 대시보드에 이미 로드된 passes 데이터로만 — 새 fetch가 필요하면 하지 않고 사실대로 기록.
- 성공 피드백은 새 라이브러리 없이 파일 내 기존 규약 우선, 없으면 행 인라인 일시 표시.
- 백엔드 POST /v1/contracts 라우트는 유지(제거는 제품 결정) — 어드민 미소비 훅만 제거.

(구현 중 확정분)
- **미서명 카드 중복 표기: 회원 dedupe 안 함** — 이웃 "결제 기록 없는 회원권" 카드가 패스 **건별**로 늘어놓는 규약(key=항목 id, slice(0,3), "·" 구분)을 그대로 따랐다. 한 회원의 계약 2건이면 이름이 2번 나온다 — 건수(`N건`)와 나열 개수가 어긋나지 않는 쪽이 집 규약이다. key는 contract.id.
- **성공 피드백: 대시보드 체크인(checkedInIds) 방식** — 파일 어디에도 토스트 인프라가 없다(성공 규약은 ① RefundQuoteModal의 isSuccess 화면 전환 ② Dashboard 체크인의 세션 로컬 Set + 버튼 "체크인됨" 비활성 2종뿐). 행 버튼에는 ②가 정확히 같은 문제("눌렀는데 반응 없음 → 연타")의 선례라 그대로 미러: 성공 시 계약 id를 `sentMarkIds`에 넣고 버튼을 "발송됨"(Check 아이콘) + disabled로. 자동 해제 없음(체크인 선례와 동일 — 새로고침/섹션 전환 시 초기화).
- **refunded 제외: 실행함(새 fetch 0)** — 대시보드 membersQ(useMembers)가 `MemberWithPasses[]`라 passes가 이미 임베드돼 있고, 기존 "결제 기록 없는 회원권" 집계(unrecordedPasses)가 같은 `m.passes`를 이미 소비 중이었다. refunded 패스 id Set을 만들어 sent 계약에서 pass_id 매칭 제외. 패스를 못 찾은 계약은 제외하지 않음(모르는 것을 "처리 불요"로 단정 금지 — 집 원칙).
- 카드 꼬리 문구는 "회원 관리에서 재발송 처리" → "회원 상세에서 재발송 처리"로 — 링크가 회원 상세 직행이 됐고, 연체 미납 항목("회원 상세에서 납부 처리")과 같은 어휘.

## 진행 단계

- [x] Dashboard·Members·lib 정독(기존 패턴 확인)
- [x] 미서명 카드: 회원명 NameLink + refunded 제외
- [x] 재발송: 행 단위 pending/에러 + 성공 피드백
- [x] 탈퇴 회원 버튼 숨김 + 라벨 폴백 + 데드 훅 제거
- [x] 타입체크·빌드 그린 + diff 정독

## 변경 파일

- `admin/src/features/Dashboard.tsx`
  - :75-78 — pendingContractsQ 주석 정정(v1.5 "별도 처리 불필요" → refunded 잔존 sent는 클라이언트가 거른다)
  - :144-157 — `pendingContracts` useMemo 신설(refunded 패스 id Set으로 잔존 sent 제외), `pendingContractsCount`를 필터 결과 길이로 교체(빈 상태 판정 :478도 자동으로 필터 기준)
  - :395-413 — 미서명 카드: 텍스트 → 건수 + NameLink 최대 3명(slice(0,3), "·" 구분, key=contract.id, 이름 폴백 `?? c.member_id`) + "회원 상세에서 재발송 처리"
- `admin/src/features/Members.tsx`
  - :390-393 — `sentMarkIds` 세션 로컬 상태(발송 성공 표식)
  - :532-541 — 탈퇴 회원이면 "추가 계약(재등록)" 버튼 숨김(수정 버튼 :412-414 선례 인용 주석)
  - :562-638 — 계약 행 map을 블록 바디로: `isThis/rowPending/rowFailed/justSent` 행 식별(payInstallment :684-690 패턴), 발송 버튼 행 단위 disabled + "발송 중…/발송됨" 라벨, 탈퇴 회원 발송·재발송 숨김, 행 내 에러 표시, 테이블 아래 전역 에러 블록 제거
  - :585 — `CONTRACT_STATUS_LABEL[c.status] ?? c.status` 폴백
  - :900-908 — CONTRACT_STATUS_LABEL 타입 `Record<Contract["status"], string>` → `Record<string, string>`(v2.11 MEMBER_STATUS_LABEL 선례 주석)
- `admin/src/lib/queries.ts` — useCreateContract 제거(구 :158-164, 소비처 0곳 grep 확인)
- `admin/src/lib/api.ts` — createContract 제거(구 :213-214) + 섹션 주석에 제거 사유·백엔드 라우트 유지 명시(:231-233)

## 검증

- `npm run build` = `tsc -p tsconfig.json && tsc -p tsconfig.node.json && vite build` → **그린**(1.73s, 에러 0). 청크 705KB 경고는 기존부터 있던 것(무관).
- 변경 구역 전체 재정독: import 잔여물 없음(Send/Check/Plus/Contract 전부 사용 유지), API 호출 모양 무변경(sendContract.mutate 인자 동일 — 두 번째 인자는 react-query 로컬 콜백), `useSendContract`의 `["contracts"]` 무효화 유지 — 대시보드 카운트 키 `["contracts","","sent"]`가 prefix 매치로 함께 갱신돼 재발송·서명 후 카운트가 내려간다.
- `grep -rn "useCreateContract\|createContract" src/` → 잔존 참조 0(주석 2곳: 백엔드 함수명 인용 1, 제거 사유 1).
- 자문자답: 회원 전환 시 sentMarkIds는 유지되지만 계약 id가 전역 유일이라 오표시 없음 / 탈퇴 회원의 registerOpen은 버튼이 유일한 진입로라 도달 불가 / 이름 미해석 계약은 member_id 원문 폴백(오늘 일정 표 :308 선례).
- ⚠ 작업 중 api.ts가 **다른 세션에 의해 동시 수정**됨(req()에 P34 후속 — 비JSON 응답 방어 + cache:no-store, +21줄). 본 P와 무관한 영역이라 건드리지 않았고, 본 P의 편집은 충돌 없이 적용·빌드 그린 확인.
- 오케스트레이터 교차검증: Dashboard 카드·Members 행 블록·lib 제거분 직접 정독 + `npm run build` 재실행 그린(2.10s) + grep 잔존 참조 0 재확인. 추가로 queries.ts:142 낡은 주석(`createContractForPass` → 실제 함수는 v2.6부터 `buildContractForPass`) 정정 — P36 L 항목 중 어드민 쪽 1건.

## 후속 작업

- 미서명 카드가 3명 초과 시 "…" 없이 잘린다 — 이웃 카드들과 동일한 기존 관례라 그대로 뒀지만, 건수가 커지면 "외 N건" 표기를 카드 공통으로 검토.
- PASS_STATUS_LABEL(Members.tsx :895)은 여전히 union 키 Record — 계약 라벨과 같은 폴백을 원하면 별도 소품(P36 미지적 항목이라 이번 스코프에서 제외).
- 발송 성공 표식은 세션 로컬 — 서버 sent_at이 시각 단위로 내려오면(현재 표시만 일 단위) 표식 없이도 재발송이 보이게 되므로 그때 제거 검토.
- P36 H 잔여: 계약 전이 비원자(send vs sign 경합) — 백엔드 P(트랜잭션 동사) 별도.

## 참조

- 발견: [P36](P36-admin-contract-audit.md) 어드민 H(여정 단절)·M(재발송 피드백·탈퇴 버튼)·L(refunded 카운트·라벨 폴백·데드 훅)
- 패턴 출처: Dashboard "결제 기록 없는 회원권" NameLink, Members payInstallment 행 식별, v2.11 라벨 폴백 사고
