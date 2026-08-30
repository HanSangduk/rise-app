package api

// 센터 운영시간(계약 v2.24, P51).
//
// **이 스위트가 지키는 사실은 하나다: 대표가 손대기 전까지 아무것도 달라지지 않는다.**
// 어드민(`Schedule.tsx DEFAULT_HOURS`)과 앱(`booking_rules.dart`)이 09~21을 하드코딩한
// 채로 배포돼 있고, 서버가 그 두 숫자를 정책으로 승격시키면서 값이 1이라도 어긋나면
// 영업 시간이 조용히 늘거나 준다. 그래서 기본값·구문서 승격·부분 머지를 각각 고정한다.

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 기본값은 **종전 하드코딩과 같은 숫자**여야 한다. 다른 값이면 배포 순간 모든 센터의
// 영업 시간이 바뀐다(대표가 요청한 적 없는 변경).
func TestCenterHoursDefaultsMatchLegacyHardcoding(t *testing.T) {
	s := newTestService()
	res, err := s.GetCenter(context.Background(), ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if res.Policy.OpenHour != 9 || res.Policy.CloseHour != 21 {
		t.Fatalf("기본 운영시간 = %d~%d, want 9~21 — 어드민·앱 하드코딩(09~21)과 같아야 한다",
			res.Policy.OpenHour, res.Policy.CloseHour)
	}
	// 양끝 포함이라 13칸이다. 이 수가 어드민 시간 그리드의 행 수와 같아야 한다.
	if got := len(res.Policy.SlotHours()); got != 13 {
		t.Fatalf("기본 슬롯 수 = %d, want 13(09시~21시 시작, 양끝 포함)", got)
	}
}

// 회원도 운영시간을 본다 — 앱이 예약 가능한 시간대를 그리려면 필요하고, 매출 목표와 달리
// 가릴 이유가 없다(영업시간은 문 앞에 붙어 있는 정보다).
func TestCenterHoursVisibleToMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 10)
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":6,"close_hour":23}`)); err != nil {
		t.Fatal(err)
	}
	res, err := s.GetCenter(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatal(err)
	}
	if res.Policy.OpenHour != 6 || res.Policy.CloseHour != 23 {
		t.Fatalf("회원이 본 운영시간 = %d~%d, want 6~23", res.Policy.OpenHour, res.Policy.CloseHour)
	}
}

// 부분 머지: 운영시간만 보내도 이웃 정책이 초기화되지 않고, 이웃 정책만 보내도 운영시간이
// 되돌아가지 않는다. 후자가 특히 중요하다 — 어드민의 다른 폼(용량·컷오프)이 운영시간 칸을
// 모른 채 저장하면 대표가 맞춰 둔 06~23이 매번 09~21로 돌아간다.
func TestCenterHoursPartialMergePreservesNeighbours(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	full := domain.DefaultPolicy()
	full.CancelCutoffHours = 12
	full.RevenueTarget = 120_000_000
	full.SlotCapacity = 5
	b, err := json.Marshal(full)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), b); err != nil {
		t.Fatal(err)
	}

	// ① 운영시간만 보낸다 → 이웃 보존.
	got, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":6,"close_hour":22}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Policy.OpenHour != 6 || got.Policy.CloseHour != 22 {
		t.Fatalf("운영시간 저장 실패: %+v", got.Policy)
	}
	if got.Policy.CancelCutoffHours != 12 || got.Policy.RevenueTarget != 120_000_000 ||
		got.Policy.SlotCapacity != 5 || !got.Policy.GraceOnce {
		t.Errorf("운영시간 PUT이 이웃 정책을 초기화: %+v", got.Policy)
	}

	// ② 이웃 정책만 보낸다 → 운영시간 보존.
	got, err = s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":3}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Policy.OpenHour != 6 || got.Policy.CloseHour != 22 {
		t.Errorf("이웃 정책 PUT이 운영시간을 되돌렸다: %d~%d, want 6~22 — 대표가 맞춘 값이 매 저장마다 사라진다",
			got.Policy.OpenHour, got.Policy.CloseHour)
	}

	// ③ 한 칸만 보내는 것도 머지다 — open만 바꾸고 close는 유지.
	got, err = s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":7}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Policy.OpenHour != 7 || got.Policy.CloseHour != 22 {
		t.Errorf("한 칸 PUT = %d~%d, want 7~22", got.Policy.OpenHour, got.Policy.CloseHour)
	}
	// 저장까지 갔는지 재조회로 확인(응답만 맞고 저장이 빠지는 뮤턴트를 죽인다).
	fresh, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if fresh.Policy.OpenHour != 7 || fresh.Policy.CloseHour != 22 {
		t.Errorf("재조회 운영시간 = %d~%d, want 7~22 — 응답만 바뀌고 저장되지 않았다",
			fresh.Policy.OpenHour, fresh.Policy.CloseHour)
	}
}

// 자정 개점(0시)이 **머지 경로에서도** 살아남는가. 0을 필드 단위 부재로 읽었다면 여기서
// 매 저장마다 9시로 되돌아간다 — 24시간 헬스장이 자기 여는 시각을 저장할 수 없게 된다.
func TestCenterHoursMidnightOpenSurvivesRoundTrip(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":0,"close_hour":23}`)); err != nil {
		t.Fatalf("자정 개점 저장이 거부됐다: %v", err)
	}
	res, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if res.Policy.OpenHour != 0 || res.Policy.CloseHour != 23 {
		t.Fatalf("자정 개점 재조회 = %d~%d, want 0~23", res.Policy.OpenHour, res.Policy.CloseHour)
	}
	// 이후 다른 필드를 저장해도 0시가 유지된다(머지 + 읽기 승격 둘 다 통과).
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":2}`)); err != nil {
		t.Fatal(err)
	}
	res, _ = s.GetCenter(ctx, ownerP())
	if res.Policy.OpenHour != 0 {
		t.Errorf("이웃 저장 후 여는 시각 = %d시, want 0시 — 0을 부재로 오독했다", res.Policy.OpenHour)
	}
}

// 거부 표(엔드포인트 레벨). 도메인 표와 중복이 아니다 — 여기서 잠그는 것은 **거부가
// 저장을 남기지 않는다**는 것과 400 문구가 두 숫자를 말한다는 것이다.
func TestCenterHoursValidationRejectsAndLeavesPolicyUntouched(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":6,"close_hour":22}`)); err != nil {
		t.Fatal(err)
	}
	cases := []struct{ name, body string }{
		{"open == close", `{"open_hour":9,"close_hour":9}`},
		{"open > close", `{"open_hour":21,"close_hour":9}`},
		{"close 24", `{"close_hour":24}`},
		{"open 음수", `{"open_hour":-1}`},
		{"둘 다 0(명시 전송은 거부 — 조용히 기본값으로 바꾸지 않는다)", `{"open_hour":0,"close_hour":0}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(c.body))
			if !errors.Is(err, domain.ErrInvalidPolicy) {
				t.Fatalf("통과했다: %v", err)
			}
			if !strings.Contains(err.Error(), "시") {
				t.Errorf("문구가 시각을 말하지 않는다: %q", err)
			}
			res, gerr := s.GetCenter(ctx, ownerP())
			if gerr != nil {
				t.Fatal(gerr)
			}
			if res.Policy.OpenHour != 6 || res.Policy.CloseHour != 22 {
				t.Errorf("거부됐는데 저장이 바뀌었다: %d~%d, want 6~22", res.Policy.OpenHour, res.Policy.CloseHour)
			}
		})
	}
}

// 트레이너·회원은 운영시간을 바꿀 수 없다(정책 편집 전체와 같은 경계).
func TestCenterHoursEditIsOwnerOnly(t *testing.T) {
	s := newTestService()
	if _, err := s.UpdateCenterPolicy(context.Background(), trainerP(), []byte(`{"open_hour":6}`)); !errors.Is(err, ErrForbidden) {
		t.Fatalf("트레이너 운영시간 편집이 통과: %v", err)
	}
}

// 라우터 레벨 — 상태코드와 응답 키가 계약대로인지(어드민이 이 JSON을 그대로 읽는다).
func TestCenterHoursHTTPRoundTrip(t *testing.T) {
	r := newTestRouter(t)

	body := `{"policy":{"open_hour":6,"close_hour":23}}`
	req := httptest.NewRequest(http.MethodPut, "/v1/center", strings.NewReader(body))
	req.Header.Set("X-Dev-Role", "owner")
	req.Header.Set("X-Dev-Uid", "owner1")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /v1/center = %d, body=%s", w.Code, w.Body.String())
	}
	var got struct {
		Policy struct {
			OpenHour  int `json:"open_hour"`
			CloseHour int `json:"close_hour"`
		} `json:"policy"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Policy.OpenHour != 6 || got.Policy.CloseHour != 23 {
		t.Fatalf("응답 키(open_hour/close_hour)가 계약과 다르다: %s", w.Body.String())
	}

	// 범위 위반은 400 + 두 숫자를 담은 한국어 문구.
	req = httptest.NewRequest(http.MethodPut, "/v1/center", strings.NewReader(`{"policy":{"open_hour":22,"close_hour":7}}`))
	req.Header.Set("X-Dev-Role", "owner")
	req.Header.Set("X-Dev-Uid", "owner1")
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("범위 위반 = %d, want 400", w.Code)
	}
	if !strings.Contains(w.Body.String(), "22") || !strings.Contains(w.Body.String(), "7") {
		t.Errorf("400 본문이 두 숫자를 말하지 않는다: %s", w.Body.String())
	}
}
