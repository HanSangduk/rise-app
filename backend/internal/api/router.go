package api

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// NewRouter — chi 라우터. API계약_v1.md의 모든 엔드포인트를 그대로 매핑한다(단일 진실 문서 기준).
func NewRouter(h *Handlers, auth *Authenticator, corsOrigins []string) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	// chi 기본 Recoverer 대신 계약 포맷 500 + 구조화 스택 로그(health.go 주석 — P35 M-7).
	r.Use(recoverJSON)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors(corsOrigins))

	// chi 기본 404/405는 평문 + 캐시 지시자 없음 — 캐시 지시자 없는 404가 CDN/브라우저에
	// 눌러앉아 복구를 무효화한 사고(P34)와 같은 계열이라, 이 두 응답도 계약 포맷 + no-store로
	// 통일한다(writeJSON이 둘 다 보장한다).
	r.NotFound(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusNotFound, errBody{Error: "찾을 수 없음"})
	})
	r.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusMethodNotAllowed, errBody{Error: "허용되지 않는 메서드예요"})
	})

	// liveness — 프로세스 생존만(의존성 체크 없음, health.go 주석).
	r.Get("/healthz", h.Healthz)
	// Cloud Run의 run.app 도메인은 /healthz를 Google 프론트엔드가 가로채
	// 컨테이너에 도달하지 않는다(GFE 예약 경로) — 외부 모니터링은 /health를 쓴다.
	// /health는 Firestore를 얕게 확인한다(P35 H-3) — DB가 죽으면 503으로 알림이 울린다.
	r.Get("/health", h.Health)
	// Hosting 경유 감시용 미러(P35) — /api/** 리라이트는 접두사를 안 벗기므로(P07) 사용자
	// 진입 경로(web.app/api/health)를 감시하려면 이 경로가 컨테이너에 실재해야 한다.
	r.Get("/api/health", h.Health)

	// v1 라우트 정의 — 아래에서 두 경로에 마운트한다(정의는 여기 한 곳뿐).
	v1 := func(r chi.Router) {
		r.Use(auth.Middleware)

		r.Get("/me", h.Me)
		// 회원탈퇴(v2.11) — 앱 안의 계정 삭제(App Store Guideline 5.1.1(v)). 회원 본인 전용.
		r.Delete("/me", h.DeleteMe)

		r.Post("/join/match", h.JoinMatch)
		r.Post("/join/confirm", h.JoinConfirm)
		r.Post("/join/request", h.JoinRequest)
		r.Get("/join/requests", h.JoinRequests) // v1.1 정합 패치(어드민 가정 승인)
		r.Post("/join/approve", h.JoinApprove)

		// ---- 재등록/상담 요청(v2.20) — 가입 요청과 같은 "회원발 요청 큐" 패턴 ----
		r.Post("/consult-requests", h.CreateConsultRequest)
		r.Get("/consult-requests", h.ListConsultRequests)
		r.Post("/consult-requests/{id}/done", h.DoneConsultRequest)

		r.Get("/members", h.ListMembers)
		r.Post("/members", h.CreateMember)
		r.Put("/members/{id}", h.UpdateMember)
		r.Get("/members/{id}/ledger", h.MemberLedger)

		r.Post("/passes", h.CreatePass)
		r.Get("/passes", h.ListPasses) // v1.1 정합 패치(앱 가정 승인)
		r.Post("/passes/{id}/hold", h.HoldPass)
		r.Post("/passes/{id}/resume", h.ResumePass)
		r.Post("/passes/{id}/refund-quote", h.RefundQuote)
		r.Post("/passes/{id}/refund", h.RefundPass) // v1.4 환불 실행(owner)

		r.Get("/slots", h.ListSlots)
		r.Post("/bookings", h.CreateBooking)
		r.Get("/bookings", h.ListBookings) // v1.1 정합 패치(앱 가정 승인)
		r.Delete("/bookings/{id}", h.CancelBooking)
		r.Post("/bookings/{id}/complete", h.CompleteBooking)
		r.Post("/bookings/{id}/noshow", h.NoshowBooking)

		r.Post("/recurrings", h.CreateRecurring)
		r.Get("/recurrings", h.ListRecurrings) // v1.4 고정 스케줄 관리
		r.Delete("/recurrings/{id}", h.DeleteRecurring)

		r.Post("/checkin", h.Checkin)

		r.Get("/homeworks", h.ListHomeworks)
		r.Post("/homeworks", h.CreateHomework)
		r.Post("/hw-checks", h.CreateHwCheck)
		r.Get("/hw-checks", h.ListHwChecks) // v1.1 정합 패치(어드민·앱 가정 승인)

		r.Get("/stats", h.Stats)

		r.Post("/payments", h.CreatePayment)
		r.Get("/payments", h.ListPayments) // v1.1 정합 패치
		r.Post("/payments/{id}/installments/{i}/pay", h.PayInstallment)

		// ---- 전자계약(Contract, v1.1 정합 패치) ----
		r.Get("/contracts", h.ListContracts)
		r.Post("/contracts", h.CreateContract)
		r.Post("/contracts/{id}/send", h.SendContract)
		r.Post("/contracts/{id}/sign", h.SignContract) // v1.4 회원 자체서명(P27)

		// ---- 수업 기록(WorkoutLog, v1.4) ----
		r.Get("/workout-logs", h.ListWorkoutLogs)
		r.Post("/workout-logs", h.CreateWorkoutLog)

		r.Get("/body-photos", h.ListBodyPhotos)
		r.Post("/body-photos", h.CreateBodyPhoto)
		// v2.13 — 회원 본인은 즉시 파기, 스태프는 소프트 삭제 + 30일 유예.
		// purge를 {id}보다 **먼저** 선언한다: chi는 정적 경로를 우선하지만, 순서를
		// 뒤집으면 "purge"가 id로 잡히는 사고가 읽는 사람에게 안 보인다.
		r.Post("/body-photos/purge", h.PurgeBodyPhotos)
		r.Post("/body-photos/reconcile", h.ReconcileBodyPhotos) // v2.15 고아 파일 훑기(정적 경로 — {id}보다 먼저)
		r.Delete("/body-photos/{id}", h.DeleteBodyPhoto)
		r.Post("/body-photos/{id}/restore", h.RestoreBodyPhoto)

		r.Get("/inbody", h.ListInbody)
		r.Post("/inbody", h.CreateInbody)
		r.Delete("/inbody/{id}", h.DeleteInbody) // v2.9 정정 경로(PUT은 없다 — 삭제 후 재입력)

		r.Get("/staff", h.ListStaff)
		r.Post("/staff", h.CreateStaff) // 스태프 온보딩(owner) — 계정+레코드+인덱스
		r.Post("/staff/{uid}/offdays", h.SetOffdays)
		r.Put("/staff/{uid}/profile", h.UpdateStaffProfile) // v1.6 트레이너 프로필(P05)
		// v2.25 프로필 사진 업로드(owner 전용, P51) — 서버가 Admin SDK로 올리고 다운로드
		// 토큰 URL을 프로필에 박는다. 응답 한 번으로 끝나므로 어드민이 profile PUT을
		// 이어 부르지 않는다(그 왕복 사이의 동시 편집이 사진을 되감던 자리).
		r.Post("/staff/{uid}/photo", h.UploadStaffPhoto)
		// ---- 직원 생애주기(v2.0) — 정정은 PUT, 상태 전이는 전용 동사 ----
		r.Put("/staff/{uid}", h.UpdateStaff)
		r.Post("/staff/{uid}/transfer", h.TransferStaff)
		r.Post("/staff/{uid}/deactivate", h.DeactivateStaff)
		r.Post("/staff/{uid}/reactivate", h.ReactivateStaff)

		r.Get("/center", h.Center)                        // v1.1 정합 패치(v1.4: member에게도 공개)
		r.Put("/center", h.UpdateCenter)                  // v1.4 운영 정책 편집(owner)
		r.Put("/center/facility", h.UpdateCenterFacility) // v2.19 시설 신고 상태 선언(owner, P42)
		// 데스크 체크인 QR 토큰(v2.23, P49) — **owner 전용**(서비스 가드). 종전엔 이 값이
		// 환경변수라 돌려주는 API 자체가 없었고, 대표가 알 수 없는 문자열을 손으로 옮겨
		// 적어야 했다. rotate는 바디 없는 POST이고 직전 인쇄물을 무효로 만든다.
		r.Get("/center/checkin-qr", h.CheckinQR)
		r.Post("/center/checkin-qr/rotate", h.RotateCheckinQR)

		// ---- 관리 평면(멀티센터 Phase A) — superadmin 전용(서비스 가드 + 인증
		// 미들웨어의 superadminAllowedPath 경계) ----
		r.Post("/admin/centers", h.CreateCenter)
		r.Get("/admin/centers", h.ListCenters)
	}

	r.Route("/v1", v1)
	// 같은 API를 /api/v1 에도 붙인다(P07). 어드민은 Firebase Hosting에서 서비스되고 /api/**가
	// Cloud Run으로 리라이트되는데, Hosting은 경로 접두사를 벗겨주지 못해 여기 도착하는 경로가
	// /api/v1/... 이 된다. 이 미러 덕에 개발(vite 프록시가 /api를 벗김)과 운영의 클라이언트 코드가
	// 완전히 동일해지고, 어드민이 API와 같은 오리진을 쓰므로 CORS 자체가 발생하지 않는다.
	// 앱(Flutter)은 Cloud Run URL을 직접 부르므로 /v1/... 경로를 그대로 쓴다.
	r.Route("/api/v1", v1)

	// ---- 공개(무인증) 라우트 — v2.13 ----
	//
	// 법정 고지 HTML(admin/public/legal/*.html)은 **로그인 없이 열리는 웹 페이지**다. 앱 스토어
	// 심사자·미가입 방문자·회원 모두가 보는 문서라 인증을 요구할 수가 없는데, /v1/* 전체에는
	// auth.Middleware가 걸려 있다. 그래서 인증 그룹 **밖에** 이 경로 하나만 따로 붙인다.
	//
	// v1 클로저 안에 넣지 않은 것은 의도다: 클로저에 넣으면 "인증되는 라우트 목록" 한가운데에
	// 무인증 경로가 섞여 다음 사람이 그 줄을 인증되는 것으로 읽는다. 여기서는 이 두 줄이
	// **무인증 표면 전체**라는 사실이 파일에서 눈에 보인다(/healthz·/health 제외).
	// 노출 범위는 service.PublicBusiness가 전용 응답 타입으로 잠근다 — 정책·센터 ID는 나가지 않는다.
	r.Get("/v1/public/business", h.PublicBusiness)
	r.Get("/api/v1/public/business", h.PublicBusiness) // Hosting 리라이트가 접두사를 안 벗긴다(P07)

	return r
}

// cors — 최소 CORS 미들웨어(어드민 오리진 허용). 외부 dep 없이 stdlib로(wodshot 패턴 재사용).
func cors(origins []string) func(http.Handler) http.Handler {
	allow := map[string]bool{}
	wildcard := false
	for _, o := range origins {
		if o == "*" {
			wildcard = true
		}
		allow[o] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" && (wildcard || allow[origin]) {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization,X-Dev-Uid,X-Dev-Role")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
