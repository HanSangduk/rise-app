// Command server는 라이즈 컨디셔닝(PT데스크) 백엔드 HTTP 서버다.
//
// 실행 모드(환경변수):
//
//	기본             : 인메모리 스토어 + dev 헤더 인증(X-Dev-Role/X-Dev-Uid) — 즉시 구동
//	USE_FIRESTORE    : Firestore 실 DB(설계03 §11) — GCP_PROJECT·FIREBASE_PROJECT 필수(빠지면 기동 거부)
//	FIREBASE_PROJECT : Firebase ID 토큰 검증(실 인증) — 미설정 시 dev 헤더 인증(인메모리 모드 한정)
//	STORAGE_BUCKET   : 체형사진 버킷(예: rize-218c1.firebasestorage.app) — 회원탈퇴 시 원본 파일 파기용.
//	                   미설정이면 파일이 버킷에 남고 기동 로그에 경고가 뜬다(v2.11)
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
	svc := api.NewService(st, cfg, authenticator.Provisioner()).
		WithMediaPurger(authenticator.MediaPurger(ctx, cfg.StorageBucket))
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
	select {
	case <-stop:
		log.Println("shutdown 신호 수신 — graceful 종료")
	case err := <-serveErr:
		log.Printf("서버 종료(리스너 에러): %v", err)
	}

	// 8초: Cloud Run은 SIGTERM 후 기본 10초에 SIGKILL을 보낸다. 종전 15초는 유예보다 길어
	// 10초 넘게 걸리는 드레이닝이 한 번도 완주하지 못하고 강제 종료됐다(P35 H-2) — 유예 안에서
	// 끝나야 defer st.Close()까지 도달한다.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown 실패: %v", err)
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
