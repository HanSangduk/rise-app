//go:build firestore_emulator

package store

// Firestore 러너 — conformance_test.go의 **같은 함수**를 에뮬레이터에 대고 돌린다.
//
// 빌드 태그로 분리한 이유: 기본 `go test ./...`은 네트워크·JDK 없이 항상 돌아야 한다(CI의 기본
// 게이트이자 개발 루프). 에뮬레이터가 필요한 검증은 옵트인이다.
//
//	# 사전: JDK 21+ 필수(firebase-tools 15는 그 아래를 거부한다)
//	export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home
//	export PATH="$JAVA_HOME/bin:$PATH"
//	firebase emulators:exec --only firestore --project demo-rize \
//	  --config testdata/firebase.json \
//	  'go test -tags firestore_emulator -count=1 ./internal/store/'
//
// emulators:exec가 자식 프로세스에 FIRESTORE_EMULATOR_HOST를 넣어 준다(SDK가 자동 감지).
// 프로젝트 ID는 GCLOUD_PROJECT로 들어오므로(GOOGLE_CLOUD_PROJECT가 아니다) 아래에서 둘 다 본다.
// demo- 접두 프로젝트는 자격증명을 요구하지 않는다.
//
// 여기서만 잡히는 것: Memory는 전역 뮤텍스 하나로 모든 연산을 직렬화하므로 **순수 경합이
// 재현되지 않는다**(경합 창이 나노초). 동시 환불·동시 홀딩·동시 예약 서브테스트는 이 러너에서
// 비로소 실제 낙관적 동시성 제어(읽은 문서가 커밋 전에 바뀌면 재시도)를 통과한다.

import (
	"context"
	"os"
	"testing"
)

func TestFirestoreStoreConformance(t *testing.T) {
	host := os.Getenv("FIRESTORE_EMULATOR_HOST")
	if host == "" {
		t.Skip("FIRESTORE_EMULATOR_HOST 미설정 — firebase emulators:exec 안에서 실행해야 한다")
	}
	project := firstNonEmpty(os.Getenv("GOOGLE_CLOUD_PROJECT"), os.Getenv("GCLOUD_PROJECT"), "demo-rize")

	ctx := context.Background()
	fs, err := NewFirestore(ctx, project)
	if err != nil {
		t.Fatalf("NewFirestore(%s @ %s): %v", project, host, err)
	}
	t.Cleanup(func() { _ = fs.Close() })

	// 클라이언트 하나를 공유한다. 서브테스트끼리의 격리는 conformanceCenter가 서브테스트
	// 이름에서 만든 centerID로 얻는다(컬렉션 경로가 갈리므로 데이터가 섞이지 않는다).
	runStoreConformance(t, func(*testing.T) Store { return fs })
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
