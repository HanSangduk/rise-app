---
id: P42
title: 재등록/상담 요청 — 앱 데드엔드를 데스크로 잇는 손잡이 (계약 v2.20)
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

# P42 — 재등록/상담 요청 (ConsultRequest)

## 목표
앱의 재등록 안내가 전부 "센터에 문의해주세요" 데드엔드(P41 조사). join_request 선례를 복제해
회원이 앱에서 재등록 의사를 전달 → 어드민 "해야 할 일"에서 데스크가 받아 기존 수기 발급·결제
플로우로 마감. 앱 내 결제·가격 노출·트레이너 지명은 의도적 제외(승인된 추천안).

## 결정 사항
- **엔티티**: `store.ConsultRequest{member_id, kind(renewal|consult), note(≤200자), status(pending|done)}` — 센터 스코프 컬렉션(가입 요청과 달리 이미 센터 귀속). 큐 정렬은 오래된 순(created_at asc → id).
- **중복**: pending 중복 409("이미 보낸 요청이 있어요…"), done 후 재요청 정상(재등록은 반복). **done→done 멱등**(200) — 두 스태프가 나눠 처리하는 동선에서 두 번째 누름이 헛확인을 만들지 않게. JoinApprove가 409인 것과 다른 근거(그쪽은 재실행이 레코드를 하나 더 만든다)를 주석·계약에 명문.
- **역할 스코프**: member=자기 것만(앱 상태 복원 출처, 이름 없음) / owner=전체+member_name(저장 안 하고 응답에서 해석 — 개명 즉시 반영, 회원 문서 소실 건은 owner에게만 이름 없이) / trainer=담당만(P37 경계, 판정 불가는 fail-closed).
- **앱 CTA**: pending이면 버튼 대신 "요청 보냈어요"(사전 판정 — 눌러서 409 받는 흐름 금지), 조회 실패/로딩은 **fail-open**(버튼 유지 — 중복 최종선은 서버 409). 시트 문구로 기대 설정("결제·등록은 센터에서 상담 후 진행"). kind는 앱 v1 renewal 고정. 진입점 2곳: 홈 빈 상태(만료·환불, EmptyPassesView에 action 슬롯 신설) + 회원권 경고 배지 줄(compact 링크 — 배지는 사실, 행동은 CTA로 상태/행동 분리). 예약 탭 빈 상태는 신규(회원권 0) 케이스라 "재등록" 문구와 안 맞아 제외.
- **myConsultRequests 프로바이더 retry 차단**: fail-open 설계라 백그라운드 재시도가 고칠 게 없고, Riverpod 3 기본 backoff 타이머가 기존 홈 위젯 테스트 3건을 "Timer still pending"으로 죽였다 — `@Riverpod(retry: _noRetry)`.
- **어드민**: 대시보드 "해야 할 일"에 가입 요청 바로 다음(의사 확인된 사람이라 "잔여 부족 후보"보다 우선). 이름 NameLink → 회원 상세, note 인용 표시, [완료] 버튼. 조회 실패를 "대기 없음"으로 위장하지 않음 + 빈 상태 판정 조건에도 편입. 폴링·포커스 재조회는 가입 요청 규약 재사용(owner 게이트만 제거 — 서버 스코프).

## 진행 단계
- [x] 백엔드: store 4메서드(Memory·Firestore) + conformance 서브테스트 + service(생성·목록·done) + handlers + router + 서비스 테스트 4그룹
- [x] 앱: ConsultRequestDto(freezed) + ConsultApi + providers(codegen) + CTA·시트 + 진입점 2곳 + 위젯 테스트 5건
- [x] 어드민: types·api·queries(useConsultRequests/useConsultDone) + Dashboard 해야 할 일 + tsc·vite 빌드
- [x] 계약 v2.20 + 전체 검증

## 변경 파일
- `backend/internal/store/store.go`·`memory.go`·`firestore.go`(ConsultRequest+4메서드) · `conformance_test.go`(큐 정렬·필터·404)
- `backend/internal/api/service_consult.go`·`handlers_consult.go`(신설) · `router.go` · `service_consult_test.go`(신설)
- `app/lib/core/api/dto/consult_request_dto.dart`(신설) · `app/lib/features/consult/`(data·providers·CTA·시트 신설) · `app/lib/core/widgets/empty_passes_view.dart`(action 슬롯) · `app/lib/features/home/presentation/home_screen.dart`(진입점 2곳)
- `app/test/features/consult/consult_request_cta_test.dart`(신설 5건)
- `admin/src/lib/types.ts`·`api.ts`·`queries.ts` · `admin/src/features/Dashboard.tsx`
- `docs/API계약_v1.md` v2.20(원래 v2.17로 클레임했다가 P40과 번호 경합 — 내용 무변경, v2.20으로 재번호)

## 검증
- 백엔드: `go vet` 클린 · `go test ./...` 전부 그린(conformance 신규 서브테스트 포함)
- 앱: `flutter analyze` 0 · `flutter test` **1082 pass**(신규 +5, 대규모 1회 실행에서 1건 비재현 플레이크 — 재실행 전량 통과, 의심 파일 contract_sign_gate 3회 반복 통과)
- 어드민: tsc + vite 빌드 그린
- 자문자답: 매칭 전 계정(member_id 없음) 403 / 다른 기기에서 보낸 pending은 409 응답 + CTA 재조회로 복원 / 탈퇴 회원 요청은 owner에게만 이름 없이(트레이너는 담당 판정 불가라 제외) / note 길이 앱 maxLength=서버 상한 미러

## 후속 작업
- slot_list의 재등록 안내 문구(텍스트 노트)는 유지 — 홈 두 진입점이 여정을 커버, 필요 시 후속
- 예약 탭 신규 회원 빈 상태용 "상담 요청"(kind=consult) CTA — 수요 확인 후
- 회원 상세(어드민)에서도 pending 요청 배지 노출 — 대시보드로 충분한지 운영 피드백 후

## 참조
- docs/API계약_v1.md v2.20 · work_log/P41(조사·추천안)
