package domain

import "testing"

// 회원권 상태는 **파생값**이다(P25).
//
// 종전에는 `CreatePass`가 무조건 active를 박고, expired·scheduled를 대입하는 코드가
// 프로덕션에 **한 줄도 없었다**. 결과로 ① 유효기간이 지난 회원권이 앱·어드민에서
// 영원히 "이용 중"으로 보이고 ② 재등록률(§8)의 분모가 `status=expired` 개수라
// 영구 0이었다. 예약은 날짜를 직접 비교(`slotDate > ValidUntil`)해서 무사했다 —
// 즉 돈이 새는 결함은 아니고, **말이 사실과 다른** 결함이다.
//
// 배치 잡으로 뒤늦게 뒤집는 대신 읽는 시점에 날짜에서 계산한다. Remaining이 이미
// 같은 방식(원장 합산의 캐시)이고, 잡은 "안 돌면 조용히 틀린다"는 실패 모드를 새로 만든다.
func TestEffectiveStatus(t *testing.T) {
	base := Pass{ValidFrom: "2026-08-01", ValidUntil: "2026-08-31", Status: PassStatusActive}

	cases := []struct {
		name  string
		pass  Pass
		today string
		want  string
	}{
		{"기간 안이면 active", base, "2026-08-15", PassStatusActive},
		{"시작일 당일도 active — 경계 포함", base, "2026-08-01", PassStatusActive},
		{"종료일 당일도 active — 그날까지 예약이 된다", base, "2026-08-31", PassStatusActive},
		{"종료일 다음날부터 expired", base, "2026-09-01", PassStatusExpired},
		{"시작 전이면 scheduled", base, "2026-07-31", PassStatusScheduled},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := c.pass.EffectiveStatus(c.today); got != c.want {
				t.Fatalf("EffectiveStatus(%s) = %s, want %s", c.today, got, c.want)
			}
		})
	}
}

// 환불은 **저장된 종단 상태**다 — 날짜로 되살리면 안 된다.
// 환불한 회원권이 기간이 남았다는 이유로 다시 active가 되면 예약·잔여 표시가 전부 거짓이 된다.
func TestEffectiveStatusRefundedIsTerminal(t *testing.T) {
	p := Pass{ValidFrom: "2026-08-01", ValidUntil: "2026-08-31", Status: PassStatusRefunded}
	for _, today := range []string{"2026-07-01", "2026-08-15", "2026-09-30"} {
		if got := p.EffectiveStatus(today); got != PassStatusRefunded {
			t.Fatalf("today=%s: %s, want refunded", today, got)
		}
	}
}

// 날짜가 망가진 레코드는 **추측하지 않는다**.
// ValidatePassPeriod가 지금은 빈 값을 막지만 그 이전에 만들어진 레코드가 있을 수 있다.
// 빈 ValidUntil을 문자열로 비교하면 어떤 today보다도 작아 전부 expired로 뒤집힌다 —
// 멀쩡히 쓰던 회원권이 하루아침에 "만료"로 보이는 쪽이 모르는 채 두는 것보다 나쁘다.
func TestEffectiveStatusMalformedDatesKeepStoredStatus(t *testing.T) {
	cases := []Pass{
		{ValidFrom: "", ValidUntil: "", Status: PassStatusActive},
		{ValidFrom: "2026-08-01", ValidUntil: "", Status: PassStatusActive},
		{ValidFrom: "", ValidUntil: "2026-08-31", Status: PassStatusActive},
		{ValidFrom: "2026-08-01", ValidUntil: "31/08/2026", Status: PassStatusActive},
	}
	for _, p := range cases {
		if got := p.EffectiveStatus("2026-09-15"); got != PassStatusActive {
			t.Fatalf("ValidFrom=%q ValidUntil=%q: %s, want 저장값 유지(active)", p.ValidFrom, p.ValidUntil, got)
		}
	}
}

// 홀딩으로 늘어난 유효기간이 그대로 반영돼야 한다.
// ApplyHold가 ValidUntil을 직접 늘리므로, 파생 상태는 **늘어난 뒤의 값**을 본다 —
// 일시정지한 회원이 원래 종료일에 "만료"로 뒤집히면 정지한 만큼을 빼앗기는 셈이다.
func TestEffectiveStatusFollowsExtendedValidUntil(t *testing.T) {
	p := Pass{ValidFrom: "2026-08-01", ValidUntil: "2026-09-14", Status: PassStatusActive,
		Holds: []Hold{{From: "2026-08-20", To: "2026-08-31", Reason: "여행"}}}
	if got := p.EffectiveStatus("2026-09-05"); got != PassStatusActive {
		t.Fatalf("연장된 기간 안인데 %s", got)
	}
	if got := p.EffectiveStatus("2026-09-15"); got != PassStatusExpired {
		t.Fatalf("연장된 종료일 다음날인데 %s", got)
	}
}
