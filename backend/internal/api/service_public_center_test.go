package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// GET /v1/public/center(v2.29) — 회원 앱 대기실이 읽는 센터 상호·전화·주소.
//
// 이 경로가 없던 동안의 결함(P56 L10): 어드민 "센터 신원" 폼은 "회원 앱에 이 이름으로 뜬다"고
// 약속했는데 앱은 그 값을 어디서도 읽지 않았다 — 상호는 로컬 상수, 전화·주소는 사업자 정보.
// 아래 테스트는 ① 무인증으로 열리되 인증 라우트는 그대로 잠겨 있고 ② 키 집합이 3칸으로 고정되며
// ③ 전화·주소만 사업자 정보로 폴백하고 상호는 폴백하지 않는다는 세 규칙을 못 박는다.

// 두 접두사 모두 **인증 헤더 없이** 200 — 대기실 사용자는 Principal에 센터가 없다.
func TestPublicCenterNeedsNoAuth(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	ctx := context.Background()
	if _, err := svc.UpdateCenterIdentity(ctx, ownerP(),
		[]byte(`{"name":"라이즈 컨디셔닝 센터","phone":"02-555-0001","address":"서울 강남구 1"}`)); err != nil {
		t.Fatal(err)
	}

	for _, path := range []string{"/v1/public/center", "/api/v1/public/center"} {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("무인증 GET %s = %d %s, want 200", path, rec.Code, rec.Body.String())
		}
		var view CenterIdentityView
		if err := json.Unmarshal(rec.Body.Bytes(), &view); err != nil {
			t.Fatalf("%s 응답 파싱: %v", path, err)
		}
		if view.Name != "라이즈 컨디셔닝 센터" || view.Phone != "02-555-0001" || view.Address != "서울 강남구 1" {
			t.Errorf("%s 응답 = %+v", path, view)
		}
		if cc := rec.Header().Get("Cache-Control"); cc != "public, max-age=300" {
			t.Errorf("%s Cache-Control = %q — 무인증 경로에 캐시가 없으면 대기실 진입마다 Firestore 읽기다", path, cc)
		}
	}

	// 공개 라우트를 하나 늘렸다고 인증 라우트가 함께 열리면 안 된다.
	for _, path := range []string{"/v1/center", "/api/v1/center", "/v1/me", "/v1/members"} {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("무인증 GET %s = %d, want 401(공개 라우트 추가가 인증을 뚫었다)", path, rec.Code)
		}
	}
}

// **키 집합 잠금** — 신원 3칸 + 수업 시간 2칸(v2.34)이다. domain.Center의 id·status·created_at도,
// 정책의 나머지(용량·위약금율·매출 목표)도 익명에게 나가지 않는다. 키를 늘리는 일이 이 테스트에
// 반드시 걸려 의식적인 결정이 되게 한다.
func TestPublicCenterExposesOnlyIdentityKeys(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	ctx := context.Background()
	if _, err := svc.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"name":"라이즈","phone":"02-1","address":"A"}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"revenue_target":120000000}`)); err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/public/center", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/public/center = %d", rec.Code)
	}
	var m map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatal(err)
	}
	assertKeySet(t, "GET /v1/public/center", m, []string{"name", "phone", "address", "open_hour", "close_hour"})
	for _, banned := range []string{"120000000", testCenter, "created_at", "active", "slot_capacity", "penalty_rate", "revenue_target"} {
		if strings.Contains(rec.Body.String(), banned) {
			t.Errorf("공개 응답 본문에 %q가 있다: %s", banned, rec.Body.String())
		}
	}
	// 수업 시간은 정책 실값(기본 9·21)이고 대표가 바꾸면 따라간다 — 대기실 센터 카드가 그린다.
	if m["open_hour"] != float64(9) || m["close_hour"] != float64(21) {
		t.Errorf("hours = %v/%v, want 9/21(기본 정책)", m["open_hour"], m["close_hour"])
	}
	if _, err := svc.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":7,"close_hour":22}`)); err != nil {
		t.Fatal(err)
	}
	rec = httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/public/center", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatal(err)
	}
	if m["open_hour"] != float64(7) || m["close_hour"] != float64(22) {
		t.Errorf("정책 변경 후 hours = %v/%v, want 7/22", m["open_hour"], m["close_hour"])
	}
}

// 전화·주소는 사업자 정보로 폴백하고, 상호는 폴백하지 않는다. 세 상태를 한 번에 본다:
// 아무것도 없음 → 사업자만 등록 → 센터 신원에 전화만 등록(주소는 여전히 사업자 값).
func TestPublicCenterFallsBackToBusinessContactOnly(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	ctx := context.Background()

	get := func() CenterIdentityView {
		t.Helper()
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/public/center", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET /v1/public/center = %d %s — 미등록도 404가 아니라 200 + 빈 값이어야 한다(대기실이 '불러오지 못함'과 '등록 전'을 구분한다)", rec.Code, rec.Body.String())
		}
		var v CenterIdentityView
		if err := json.Unmarshal(rec.Body.Bytes(), &v); err != nil {
			t.Fatal(err)
		}
		return v
	}

	// ① 미등록 — 200 + 세 칸 모두 빈 문자열(키는 있어야 한다: 앱이 키 부재와 빈 값을 구분하지 않게).
	if v := get(); v != (CenterIdentityView{}) {
		t.Fatalf("미등록 응답 = %+v, want 빈 3칸", v)
	}

	// ② 사업자 정보만 등록 — 전화·주소는 사업자 값으로 채워지고, 상호는 **비어 있다**
	//    (사업자명 "라이즈 컨디셔닝"으로 채우지 않는다 — 법인명과 센터 상호는 다른 값).
	if _, err := svc.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	v := get()
	if v.Name != "" {
		t.Errorf("상호가 사업자명으로 폴백됐다: %q", v.Name)
	}
	if v.Phone != "02-1234-5678" || v.Address != "서울특별시 강남구 테헤란로 123, 4층" {
		t.Errorf("사업자 폴백 = %+v", v)
	}

	// ③ 센터 신원에 상호·전화만 — 전화는 센터 값이 이기고, 주소는 아직 사업자 값이다.
	if _, err := svc.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"name":"라이즈 컨디셔닝 센터","phone":"02-555-0001"}`)); err != nil {
		t.Fatal(err)
	}
	v = get()
	if v.Name != "라이즈 컨디셔닝 센터" || v.Phone != "02-555-0001" {
		t.Errorf("센터 값이 사업자 값을 이기지 못했다: %+v", v)
	}
	if v.Address != "서울특별시 강남구 테헤란로 123, 4층" {
		t.Errorf("비어 있는 주소가 사업자 값으로 폴백되지 않았다: %+v", v)
	}
}
