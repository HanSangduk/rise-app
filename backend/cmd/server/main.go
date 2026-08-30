// Command server는 라이즈 컨디셔닝(PT데스크) 백엔드 HTTP 서버다.
//
// 실행 모드(환경변수):
//
//	기본             : 인메모리 스토어 + dev 헤더 인증(X-Dev-Role/X-Dev-Uid) — 즉시 구동
//	USE_FIRESTORE    : Firestore 실 DB(설계03 §11) — GCP_PROJECT·FIREBASE_PROJECT 필수(빠지면 기동 거부)
//	FIREBASE_PROJECT : Firebase ID 토큰 검증(실 인증) — 미설정 시 dev 헤더 인증(인메모리 모드 한정)
//	STORAGE_BUCKET   : Cloud Storage 버킷(예: rize-218c1.firebasestorage.app). 두 경로가 쓴다 —
//	                   ① 회원탈퇴 시 체형사진 원본 파기(v2.11): 미설정이면 파일이 남고 기동 로그에 경고
//	                   ② 트레이너 프로필 사진 업로드(v2.25): 미설정이면 그 엔드포인트가 **503으로 거부**
//	                   즉 업로드를 쓰려면 이 값이 필수다(파기는 없어도 서비스가 돈다)
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ramsang/rise-backend/internal/api"
	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

func main() {
	cfg := config.Load()
	// 위험한 조합이면 뜨지 않는다(fail-closed) — 실 DB + dev 헤더 인증으로 기동하는 사고를
	// 여기서 끊는다. 근거는 config.Validate 주석.
	if err := cfg.Validate(); err != nil {
		log.Fatalf("설정 오류: %v", err)
	}
	ctx := context.Background()

	st, err := buildStore(ctx, cfg)
	if err != nil {
		log.Fatalf("store 초기화 실패: %v", err)
	}
	defer st.Close()

	if cfg.DevSeed && !cfg.UseFirestore {
		// v1.4: 데모 시딩 — 어드민 owner1/t1/t2, 회원 앱 member1(김민지)로 즉시 시연 가능.
		if err := store.SeedDemo(ctx, st, cfg.DefaultCenterID); err != nil {
			log.Fatalf("DEV_SEED 시딩 실패: %v", err)
		}
		log.Println("DEV_SEED: 데모 데이터 시딩 완료 (어드민 X-Dev-Uid: owner1|t1|t2 · 앱 X-Dev-Uid: member1)")
	}

	authenticator, err := api.NewAuthenticator(ctx, cfg, st)
	if err != nil {
		log.Fatalf("인증 초기화 실패: %v", err)
	}
	if cfg.FirebaseProject == "" {
		// 여기까지 왔다는 건 인메모리 모드라는 뜻이다 — 실 DB와의 조합은 위 Validate가 이미 거부했다.
		log.Println("경고: FIREBASE_PROJECT 미설정 — dev 헤더 인증(X-Dev-Role/X-Dev-Uid) 모드(인메모리 로컬 개발 전용, 배포 시 필수 설정)")
	}

	// 스태프 생성(POST /v1/staff)의 로그인 계정 발급기 — 인증과 같은 기준으로 모드를 가른다
	// (Firebase 모드면 Authenticator가 초기화한 Admin SDK 클라이언트를 재사용).
	// 회원탈퇴(v2.11)는 체형사진 **원본 파일**까지 파기해야 완결된다 — storage.rules가
	// 클라이언트 삭제를 막고 있어(allow delete: if false) Admin SDK만이 지울 수 있다.
	// STORAGE_BUCKET 미설정이면 no-op으로 떨어지고 경고 로그가 남는다(MediaPurger 주석).
	// 트레이너 프로필 사진 업로드(v2.25)도 같은 버킷을 쓴다 — 다만 **미설정 시 동작이
	// 반대다**: 파기는 no-op으로 떨어져도 서비스가 돌지만, 업로드는 503으로 거부한다
	// (조용히 성공하면 "저장했어요"가 거짓말이 된다 — MediaUploader 주석).
	svc := api.NewService(st, cfg, authenticator.Provisioner()).
		WithMediaPurger(authenticator.MediaPurger(ctx, cfg.StorageBucket)).
		WithMediaUploader(authenticator.MediaUploader(ctx, cfg.StorageBucket))
	if cfg.DevSeed && !cfg.UseFirestore {
		// P43: 데모 시드 계약 재발송 — 실제 조립·스탬프 경로(SendContract →
		// gatherContractVars → TransitionContract)를 그대로 태워, 회원 앱(member1)이 계약서
		// 본문·끝-스크롤 서명 게이트를 첫 구동부터 시연한다. 시드 값은 전부 명백한 테스트
		// 값(seed.go P43 절) — 실값 교체가 §F 체크리스트다.
		//
		// P48(계약 v2.22)부터 **발행 래치는 프로덕션에서도 켜져 있다** — 여기 훅은 no-op이
		// 됐지만 호출을 남긴다: 래치를 되돌리는 날에도 데모는 계속 본문을 보여줘야 하고,
		// 그때 이 한 줄이 없으면 데모가 조용히 요약 고지로 후퇴한다(훅 자체가 멱등).
		// 종전 이 자리의 "프로덕션 래치 OFF 보장" 문구는 P48로 사실이 아니게 됐다.
		api.EnableContractTemplatesForDemo()
		owner := api.Principal{UID: "owner1", Role: domain.RoleOwner, CenterID: cfg.DefaultCenterID}
		sentContracts, err := st.ListContracts(ctx, cfg.DefaultCenterID, "", string(domain.ContractStatusSent))
		if err != nil {
			log.Fatalf("DEV_SEED 계약 조회 실패: %v", err)
		}
		for _, c := range sentContracts {
			if _, err := svc.SendContract(ctx, owner, c.ID); err != nil {
				log.Fatalf("DEV_SEED 계약 Vars 스탬프 실패(%s %s): %v", c.Product, c.ID, err)
			}
		}
		log.Printf("DEV_SEED: 발행 래치 ON(데모 전용) · sent 계약 %d건 Vars 스탬프 완료", len(sentContracts))
	}
	handlers := api.NewHandlers(svc)
	router := api.NewRouter(handlers, authenticator, cfg.CORSOrigins)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: router,
		// chi의 middleware.Timeout(30s)은 r.Context()에 데드라인을 심을 뿐 커넥션을 닫지
		// 못한다 — 바디를 1바이트씩 흘리는 요청, 응답을 안 읽는 클라이언트, 방치된 keep-alive는
		// 전부 ctx를 안 보는 net.Conn 레벨 블록이라 아래 서버 타임아웃만이 실제로 회수한다(P35).
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	// 리스너 오류는 Fatalf로 즉사하지 않고 종료 채널로 합류시킨다 — os.Exit는 defer st.Close()를
	// 건너뛰어 Firestore gRPC 정리 없이 죽는다. 리스너 오류든 SIGTERM이든 같은 경로로 나간다.
	serveErr := make(chan error, 1)
	go func() {
		log.Printf("라이즈 백엔드 listening on :%s (firestore=%v, firebase_auth=%v, center=%s)",
			cfg.Port, cfg.UseFirestore, cfg.FirebaseProject != "", cfg.DefaultCenterID)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
		}
	}()

	// graceful shutdown (Cloud Run SIGTERM 대응).
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	// listenFailed — 리스너 에러로 끝났는지. 이 경우 **종료코드 1**로 나가야 한다: 포트 충돌
	// 같은 이유로 요청을 한 번도 받지 못하고 죽었는데 0으로 끝내면 Cloud Run이 "정상 종료"로
	// 읽어 배포 실패가 크래시 루프로 드러나지 않는다(조용히 사라진다).
	listenFailed := false
	select {
	case <-stop:
		log.Println("shutdown 신호 수신 — graceful 종료")
	case err := <-serveErr:
		log.Printf("서버 종료(리스너 에러): %v", err)
		listenFailed = true
	}

	// 8초: Cloud Run은 SIGTERM 후 기본 10초에 SIGKILL을 보낸다. 종전 15초는 유예보다 길어
	// 10초 넘게 걸리는 드레이닝이 한 번도 완주하지 못하고 강제 종료됐다(P35 H-2) — 유예 안에서
	// 끝나야 defer st.Close()까지 도달한다.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown 실패: %v", err)
	}
	if listenFailed {
		// defer들(st.Close 등)을 먼저 돌린 뒤 실패 코드로 나간다 — os.Exit은 defer를 건너뛴다.
		cancel()
		_ = st.Close()
		os.Exit(1)
	}
}

func buildStore(ctx context.Context, cfg config.Config) (store.Store, error) {
	if cfg.UseFirestore {
		if cfg.GCPProject == "" {
			return nil, errors.New("USE_FIRESTORE=true 인데 GCP_PROJECT 미설정")
		}
		log.Printf("스토어: Firestore(project=%s)", cfg.GCPProject)
		return store.NewFirestore(ctx, cfg.GCPProject)
	}
	log.Println("스토어: 인메모리(개발 모드)")
	return store.NewMemory(), nil
}
