---
id: P12
title: 고정 스케줄 잔여 캡·규칙 해제 정리 + Home Work 스케줄 판정(H4·M1·M2·M4)
status: 완료
domain: backend
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 고정 스케줄 · Home Work 스케줄

## 목표

감사에서 **curl 실측으로 재현된** 4건을 고친다. 공통점은 "계약에 적혀 있는 값을 아무도 읽지
않는다"이다 — 잔여 캡은 잘못된 값을 세고, `Homework.schedule`은 저장만 되고 판정하는 코드가
코드베이스 어디에도 없었다.

| # | 자리 | 실측 | 파급 |
|---|---|---|---|
| H4 | `CreateRecurring` 잔여 캡 | 잔여 10회 → 규칙 2개 → **confirmed 21건** | 슬롯 정원·코치 일정이 팔린 세션의 2배로 잠김, 완료 시 원장 음수 |
| M1 | `DeleteRecurring` | 규칙 삭제 204 → 예약 10건 **잔존** | "해제"했는데 앱엔 4주치 그대로, 수동 취소는 노쇼 유예 소진 |
| M2 | `until` 과거 | `until:"2020-01-01"` → 200 + 예약 0건 + 목록에서 숨김 | UI로 지울 수 없는 유령 규칙 |
| M4 | `HwSchedule` 미판정 | `{"type":"매일매일","days":["월요일"]}` → 200 저장 | once 영구 노출 · 요일 무시 · `hw_rate` 분모 단조 증가 |

## 결정 사항

### H4 — 캡의 기준을 "이 호출이 만든 수"에서 "이 패스의 살아있는 예약 총량"으로
잔여는 완료 시점 차감(P4)이라 예약이 늘어도 줄지 않는다. 따라서 `created >= remaining`은
**한 번의 호출 안에서만** 성립하고 규칙을 두 번 만들면 통째로 무력화된다. 예산을
`remaining − 기존 confirmed`로 바꿔야 주석이 약속한 보장("recurring이 예약 규칙의 우회로가
되지 않도록")이 실제로 성립한다. 예산이 0이면 규칙도 만들지 않고 400 — v1엔 자동연장 크론이
없어 "0건 만드는 규칙"은 영원히 아무것도 만들지 않는다(대표는 걸었다고 믿고 회원은 예약이 없다).

스토어 인터페이스는 **건드리지 않았다**. `ListBookingsByMember`로 충분하고,
`RefundPass`의 잔존 예약 정리도 같은 방식으로 필터한다.

### M1 — 미래 예약 동반 취소(무차감) + `keep_bookings` 탈출구
네 안을 놓고 골랐다.

1. **미래 confirmed 취소, 무차감** ← 채택. 대표가 "해제"에 기대하는 의미가 기본값이어야 한다.
   지난 회차는 정산될 이력이라 손대지 않는다. `CancelBooking`이 아니라 `CancelAtomic`을 직접
   써서 원장 자체를 만들지 않는다 — 센터 사정으로 지우는데 회원이 노쇼 유예를 잃으면 안 된다
   (v1.5 `waive=true`, `RefundPass`의 잔존 예약 정리와 같은 취급).
2. 규칙만 삭제(현행) — 기각. 실측 증상 그 자체.
3. 삭제를 막고 "향후 예약 취소" 옵션 제공 — 기각. 두 단계로 나누면 1단계만 하고 떠난 절반
   상태가 지금 버그와 같아진다.
4. 무조건 취소(옵트아웃 없음) — 기각. 취소는 슬롯을 풀어 되돌릴 수 없고, "규칙만 끊고 잡힌
   회차는 진행"이 실제 운영에 있다. `?keep_bookings=true`를 남겼다.

**회원 통보**는 v1에 채널이 없다(README 갭). 대신 응답을 204 → `200 {cancelled, kept}`로 바꿔
어드민이 "예정 10건 취소됨"을 띄우고 대표가 직접 연락할 근거를 준다.

순서는 예약 정리 → 규칙 삭제. 반대면 중간 실패 시 규칙만 사라져 지금 버그가 재현되고 재시도할
손잡이도 없어진다.

### M2 — 생성 시 거부 + 만료 규칙을 꺼내 볼 통로
`until < today()`면 400(형식만 보던 자리에 값 검사 추가). 다만 **자연 만료로 생긴 기존 유령**은
그것만으로 못 지운다 — 목록이 숨기기 때문이다. `GET /v1/recurrings?include_expired=true`를 열어
정리 통로를 만들었다(기본값은 종전대로 숨김).

### M4 — 판정은 domain 순수 함수, 규칙은 **이미 출시된 앱과 동일**
`domain.HwSchedule.IsActiveOn/IsEndedOn/ValidateHwSchedule`(stdlib만 사용).
회원 앱에 이미 같은 판정을 하는 순수 함수가 있었다
(`app/lib/features/home/domain/homework_schedule_rules.dart`) — 서버가 다른 해석을 들고 오면
같은 배정이 앱과 어드민에서 다르게 보인다. 그쪽 의미론을 그대로 채택하고 서버를 진실의
정의로 삼아 계약에 명문화했다.

**목록과 통계가 다른 함수를 쓰는 이유**(자문자답): 처음엔 둘 다 `IsActiveOn`을 쓰려 했는데,
주3회(mon/wed/fri) 배정은 화요일에 `IsActiveOn=false`지만 **여전히 진행 중인 배정**이다.
통계 분모에 그걸 쓰면 `hw_rate`가 요일마다 출렁인다(화요일엔 주3회 배정이 통째로 분모에서
빠진다). 그래서 목록은 "오늘 하는가"(`IsActiveOn`), 분모는 "끝났는가"(`IsEndedOn`)로 가르되
판정 근거(from/to/type)는 두 함수가 공유한다.

`once`는 `to`가 없으면 `from` 당일로 끝난다 — "한 번만"이 기한 없이 남지 않게 하는 유일한
장치다. 그래서 `ValidateHwSchedule`은 `once`에 `from`을 요구한다.

## 진행 단계

- [x] 실패하는 테스트 먼저 — 4건 전부 실측 그대로 재현(confirmed 20/10, 잔존 5건, 유령 규칙 1건, 미판정 2건)
- [x] `domain/homework.go` 순수 함수 3종 + 단위 테스트
- [x] H4 캡 재정의(`countOpenPassBookings`) · M2 `until` 검증 · M1 삭제 시 예약 정리 · M4 목록/통계 판정
- [x] 뮤테이션 검증 10종 — **전부 검출**(고친 곳을 되돌리면 해당 테스트가 깨진다)
- [x] `go build ./... && go test ./...` 통과 · gofmt clean
- [x] 계약 v2.3 · README `hw_rate` 갭 갱신

## 변경 파일

| 파일 | 내용 |
|---|---|
| `backend/internal/domain/homework.go` | `IsActiveOn` / `IsEndedOn` / `ValidateHwSchedule` / `ErrInvalidHwSchedule` |
| `backend/internal/domain/hwschedule_test.go` | 순수 함수 골든 테이블(신규) |
| `backend/internal/api/service.go` | `countOpenPassBookings`, `CreateRecurring` 예산 캡·`until` 검증, `ListRecurrings(includeExpired)`, `DeleteRecurring(keepBookings)→RecurringDeleteResult`, `ListHomeworks(date)` |
| `backend/internal/api/service_stats.go` | `homeworkCompletion(..., today)` — 종료된 배정 분모 제외 |
| `backend/internal/api/handlers_bookings.go` | `include_expired` · `keep_bookings` 쿼리, DELETE 204→200 |
| `backend/internal/api/handlers_homework.go` | `date` 쿼리 |
| `backend/internal/api/util.go` | `ErrInvalidHwSchedule` → 400 매핑 |
| `backend/internal/api/service_recurring_hw_test.go` | 회귀 8종(신규) |
| `docs/API계약_v1.md` | v2.3 섹션 |
| `backend/README.md` | `hw_rate` 분모 정의 갱신 |

## 검증

```
go build ./... && go test ./... -count=1   →  전 패키지 ok
gofmt -l internal/                          →  없음
뮤테이션 10/10 검출
```

## 후속 작업

- **`domain.ValidateHwSchedule`을 `CreateHomework`에서 호출해야 한다** — 이 작업 범위 밖
  (병렬 담당 분리). 호출 전까지 M4의 "아무 값이나 저장" 경로는 열려 있다.
- `CreateBooking`도 잔여 캡이 `remaining > 0`뿐이라 수동 예약으로 잔여를 초과할 수 있다.
  `countOpenPassBookings`를 그대로 쓰면 막힌다(같은 이유로 범위 밖).
- `CompleteBooking`이 잔여를 재검사하지 않는다 — 위 두 캡이 닫히면 원장 음수 경로는 사라지지만
  이중 방어선으로는 남는다.
- 고정 스케줄 자동연장 크론 부재(4주치만 선행 생성)는 여전한 갭.
