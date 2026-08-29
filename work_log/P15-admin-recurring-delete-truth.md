---
id: P15
title: 어드민 고정 스케줄 — 삭제 확인 문구를 서버 동작(v2.3)과 일치시키고 만료 규칙을 정리 가능하게
status: 완료
domain: admin
created: 2026-08-23
completed: 2026-08-23
---

## 목표

어드민 예약 화면의 고정 스케줄 패널이 계약 v2.3보다 낡아 생긴 결함 2건을 닫는다.

- **HIGH** — 삭제 확인 문구가 서버 동작과 **정반대**였다: "규칙만 삭제됩니다 — 이미 생성된 선행
  예약은 남아 있어요". 실제로 서버는 그 규칙이 만든 **미래 confirmed 예약을 함께 취소**한다.
  대표는 문구를 믿고 규칙을 지우고, 회원 4주치가 통보 없이 사라진 사실을 **회원 전화로** 알게 된다.
  되돌리려면 한 건씩 다시 잡아야 한다.
- **MEDIUM** — 만료(until 경과) 규칙이 목록에 없어 **지울 수단 자체가 없었다**. 서버가
  `?include_expired=true`를 만든 이유가 정확히 그것인데 클라이언트가 붙이지 않았다.

## 결정 사항

**서버 응답 형태는 추측하지 않고 코드에서 확인했다** — `backend/internal/api/service.go:1592`
`RecurringDeleteResult{Cancelled int \`json:"cancelled"\`; Kept int \`json:"kept"\`}`,
핸들러 `handlers_bookings.go:116`이 `writeJSON(w, http.StatusOK, res)`. 즉 **200 `{cancelled, kept}`**
(종전 204). 쿼리는 `keep_bookings=true` / `include_expired=true` **문자열 정확 비교**
(`queryParam(r, ...) == "true"`)라 `1`·`TRUE`는 통하지 않는다. 실서버로도 실측했다(아래 검증).

**응답 타입은 엔티티 재사용이 아니라 전용 타입으로 뒀다**(`RecurringDeleteResult`) —
`HomeworkCreateRequest` 이후 세운 요청/응답 분리 규약과 같은 자리. 삭제의 "요청"은 쿼리
파라미터뿐이라 요청 타입은 만들지 않고 `api.ts` 시그니처에 좁게 박았다(`{ keepBookings?: boolean }`).

**"몇 건이 취소되는지"를 누르기 전에 센다.** 확인 문구만 고치면 대표는 여전히 규모를 모르고
누른다. `GET /v1/bookings?from=오늘`을 패널을 편 동안만 켜서 `recurring_id` 일치 · `confirmed` ·
**아직 시작 전**(서버 `DeleteRecurring`과 같은 판정)인 건수를 표의 "예정 회차" 열과 확인 문구에
같이 쓴다. **집계에 실패하면 `0`으로 단정하지 않는다**(`null` → "?") — "0건 취소"라는 거짓 안심은
지금 고치는 결함과 같은 종류다.

**`?keep_bookings=true`는 확인 단계의 체크박스로 냈다** — "규칙만 끊고 이미 합의된 회차는 진행"이
실제 운영에 있어 서버가 일부러 열어 둔 길이다. 체크 상태에 따라 확인 문구·확정 버튼 라벨이
함께 갈린다(`규칙만 삭제 확정`). 확인을 열고 닫을 때마다 초기화한다 — 앞 규칙에서 켠 옵트아웃이
다음 규칙 삭제에 따라붙으면 그게 곧 다음 사고다.

**만료 규칙은 "숨김 해제"가 아니라 "표시하고 구분"으로 처리했다.** 서버가 숨긴 이유(자동연장
크론 부재와 겹쳐 "살아있는 규칙"으로 오인)는 배지 + 목록 하단 정렬로 갚고, 대신 지울 수 있게
한다. 확인 문구도 상태에 따라 갈린다 — 만료 규칙엔 취소될 미래 예약이 없으므로 파괴적 경고를
띄우지 않고 "규칙만 정리되고 지난 회차는 기록으로 남아요"라고만 말한다. 경고를 남발하면 정작
위험한 경고를 읽지 않는다.

**쿼리 키를 `include_expired` 여부로 갈랐다** — 같은 키에 두 목록을 겹쳐 담으면 만료 포함 목록이
기본 목록(설정 화면 퇴사 blockers 이름 해석)을 덮어 만료 규칙이 다른 화면으로 샌다. 무효화는
`["recurrings"]` 프리픽스로 둘 다 친다.

## 진행 단계

- [x] 서버 진실 확인 — `service.go` `DeleteRecurring`/`ListRecurrings`, 핸들러, 계약 문서 대조
- [x] `types.ts` `RecurringDeleteResult` 신설(요청/응답 분리 규약)
- [x] `api.ts` — `recurrings({includeExpired})` · `deleteRecurring(id, {keepBookings})` → `req<RecurringDeleteResult>`
- [x] `queries.ts` — 키 분리, `useRecurrings(includeExpired)`, `useDeleteRecurring({id, keepBookings})`, `["bookings"]` 무효화 추가
- [x] `Schedule.tsx` — 확인 박스 전면 재작성(사실 문구 + 사전 집계 + 옵트아웃), 만료 배지·정렬, 결과 표시
- [x] 실서버 실측(DEV_SEED) + `npm run build`
- [x] `admin/README.md` 갱신(알려진 한계 2건 해소 처리 + 남은 갭 1건 명시)

## 변경 파일

**admin**
- `src/lib/types.ts` — `RecurringDeleteResult`(cancelled/kept) 신설, `Recurring.until` 주석
- `src/lib/api.ts` — `recurrings({ includeExpired })`, `deleteRecurring(id, { keepBookings })`가
  `req<void>` → `req<RecurringDeleteResult>`
- `src/lib/queries.ts` — `keys.recurrings(includeExpired)` 함수화, `useRecurrings(includeExpired)`,
  `useDeleteRecurring`이 `{id, keepBookings}` 수령, 생성·삭제·이관 시 `["bookings"]`·`["recurrings"]` 무효화
- `src/features/Schedule.tsx` — `RecurringPanelBody`: 만료 포함 조회·배지·하단 정렬, "예정 회차"
  열, 확인 박스(사실 문구 4갈래 + keep_bookings 체크박스 + 확정/돌아가기), 결과 문구(cancelled/kept)
- `README.md` — 계약 v2.3 반영 항목 2개 추가, "알려진 한계"의 해당 2건 해소 표시

## 검증

- **실서버 실측**(:8097, `DEV_SEED=true`):
  - 규칙 생성(목 4회차) → `DELETE /v1/recurrings/{id}` → **`HTTP 200 {"cancelled":4,"kept":0}`**
    (사전 집계 4건과 일치)
  - 규칙 생성(4회차) → `DELETE ...?keep_bookings=true` → **`200 {"cancelled":0,"kept":4}`**,
    이후 예약 조회 시 confirmed 4건 **생존 확인**
  - `GET /v1/recurrings?include_expired=true` → 200(파라미터 수용)
- `npm run build`(tsc ×2 + vite) 통과
- 사전 집계 판정이 서버와 같은 규칙임을 코드 대조로 확인(`recurring_id` · `confirmed` ·
  `SlotStart > now`, 파싱 실패 시 취소 대상에서 제외 — 서버도 `kept`)

## 후속 작업

- **사전 집계의 원천적 정확도** — "예정 회차"는 `GET /v1/bookings?from=오늘`을 클라이언트에서 센
  값이라 집계·삭제 사이의 신규 예약/시작 경과와 이론상 어긋날 수 있다. **사후 표시는 서버
  응답을 그대로 쓰므로** 대표가 회원에게 전하는 숫자는 항상 서버 값이다. 백엔드가
  `GET /v1/recurrings` 응답에 규칙별 `upcoming_count`를 실어 주면 사전 집계도 왕복 없이 정확해진다
  (지금은 패널을 열 때마다 센터 전체 예약을 한 번 끌어온다).
- **만료 규칙은 여전히 손으로 지운다** — 자동연장/자동정리 크론이 없다는 사실은 그대로다.
- **회원 통보 채널 부재**(v1) — cancelled 건수를 화면에 띄우는 것이 대표가 회원에게 알릴 유일한
  근거다. 알림 채널이 생기면 이 자리가 "N명에게 알림 보내기"로 승격되어야 한다.

## 참조

- 서버 진실: `backend/internal/api/service.go:1562-1657`(`ListRecurrings`·`RecurringDeleteResult`·
  `DeleteRecurring`), `backend/internal/api/handlers_bookings.go:101-125`
- 계약: `docs/API계약_v1.md` §기존 계약 변경(v2.3) — `include_expired` / `keep_bookings`
- 선행: `work_log/P12-recurring-hw-schedule.md`(서버 v2.3 구현),
  `work_log/P12-admin-contract-defects.md`(요청/응답 타입 분리 규약·2단 확인 패턴)
