module github.com/ramsang/rise-backend

go 1.26.0

toolchain go1.26.9

// NOTE: 샌드박스 네트워크 봉쇄로 여기서 go mod download 불가.
// 사용자 머신에서 최초 1회 `go mod tidy`로 아래 버전을 최신 호환본으로 고정하고 go.sum을 생성하세요.
// firestore.go가 쓰는 google.golang.org/grpc/{codes,status}·google.golang.org/api/iterator는
// firestore·api 모듈의 간접 의존성으로 go mod tidy가 자동으로 채운다.
require (
	cloud.google.com/go/firestore v1.25.0
	firebase.google.com/go/v4 v4.21.0
	github.com/go-chi/chi/v5 v5.2.1
	google.golang.org/api v0.287.1
)

require (
	cloud.google.com/go/storage v1.62.1
	// golang.org/x/image — webp DecodeConfig 전용(v2.25 트레이너 사진 업로드).
	// stdlib image에는 webp 디코더가 없어 치수 위생 검사를 할 수 없다. 디코더만 쓰고
	// 픽셀은 풀지 않는다(DecodeConfig = 헤더만) — 디코드 폭탄 표면이 늘지 않는다.
	// 2026-08 기준 최신 stable(`go list -m -versions golang.org/x/image`로 확인).
	golang.org/x/image v0.45.0
	// 2026-10 보안 갱신(P74 govulncheck — 호출 경로상 취약): grpc 1.82.1→1.84.0(GO-2026-6348) · 간접 x/net
	// 0.56→0.61(HTTP/2 5건) · otel 1.44→1.47(GO-2026-6505) · toolchain go1.26.9(표준 라이브러리 12건).
	// 2026-10-16 기준 최신 stable(`go list -m -u -json`의 Update·Time으로 확인).
	google.golang.org/grpc v1.84.0
)

require (
	cel.dev/expr v0.25.2 // indirect
	cloud.google.com/go v0.123.0 // indirect
	cloud.google.com/go/auth v0.20.0 // indirect
	cloud.google.com/go/auth/oauth2adapt v0.2.8 // indirect
	cloud.google.com/go/compute/metadata v0.9.0 // indirect
	cloud.google.com/go/iam v1.11.0 // indirect
	cloud.google.com/go/longrunning v1.2.0 // indirect
	cloud.google.com/go/monitoring v1.29.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/detectors/gcp v1.34.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/exporter/metric v0.56.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/internal/resourcemapping v0.56.0 // indirect
	github.com/MicahParks/keyfunc v1.9.0 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/cncf/xds/go v0.0.0-20260202195803-dba9d589def2 // indirect
	github.com/envoyproxy/go-control-plane/envoy v1.37.0 // indirect
	github.com/envoyproxy/protoc-gen-validate v1.3.3 // indirect
	github.com/felixge/httpsnoop v1.1.0 // indirect
	github.com/go-jose/go-jose/v4 v4.1.4 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/golang-jwt/jwt/v4 v4.5.2 // indirect
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/google/s2a-go v0.1.9 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/googleapis/enterprise-certificate-proxy v0.3.17 // indirect
	github.com/googleapis/gax-go/v2 v2.23.0 // indirect
	github.com/planetscale/vtprotobuf v0.6.1-0.20240319094008-0393e58bdf10 // indirect
	github.com/spiffe/go-spiffe/v2 v2.8.1 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/contrib/detectors/gcp v1.44.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.68.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.69.0 // indirect
	go.opentelemetry.io/otel v1.47.0 // indirect
	go.opentelemetry.io/otel/log v1.47.0 // indirect
	go.opentelemetry.io/otel/metric v1.47.0 // indirect
	go.opentelemetry.io/otel/sdk v1.47.0 // indirect
	go.opentelemetry.io/otel/sdk/metric v1.47.0 // indirect
	go.opentelemetry.io/otel/trace v1.47.0 // indirect
	golang.org/x/crypto v0.58.0 // indirect
	golang.org/x/net v0.61.0 // indirect
	golang.org/x/oauth2 v0.36.0 // indirect
	golang.org/x/sync v0.24.0 // indirect
	golang.org/x/sys v0.49.0 // indirect
	golang.org/x/text v0.43.0 // indirect
	golang.org/x/time v0.15.0 // indirect
	google.golang.org/appengine/v2 v2.0.6 // indirect
	google.golang.org/genproto v0.0.0-20260511170946-3700d4141b60 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20260706201446-f0a921348800 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260706201446-f0a921348800 // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)
