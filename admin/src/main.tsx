import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import App from "./App";
import { AuthProvider } from "@/lib/auth";
import { ApiError } from "@/lib/api";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import "./index.css";

// 서버상태는 TanStack Query로 관리. staleTime으로 화면 전환 시 잦은 재조회를 완화.
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // 60초: 탭 복귀(refetchOnWindowFocus)의 재조회 빈도를 결정하는 값이다. 대시보드 한
      // 화면이 서로 다른 쿼리 9개를 띄우고 그중 members·payments·contracts는 전체 조회라,
      // 15초로 두면 잠깐 카톡 보고 온 복귀마다 9개가 전부 Firestore를 다시 읽는다. 어드민
      // 데이터가 초 단위로 바뀌지 않으므로 60초가 신선도·비용의 균형점이다.
      staleTime: 60_000,
      // 4xx(권한·검증·없음)는 재시도해도 결과가 같다 — 재시도는 서버·전달 경로가 흔들리는
      // 5xx/네트워크 오류에만 의미가 있다. 종전 retry:1은 방향이 반대였다(4xx에 무의미한
      // 재시도를 붙이고 5xx엔 부족했다 — P35).
      //
      // transport(전달 경로 실패)도 제외한다: 배포가 고쳐지기 전까지 100% 결정적으로 실패하는데
      // 재시도하면 백오프만큼 진단이 늦어지고(대시보드 9쿼리 × 4회 = 36요청) 화면은 그동안
      // 스피너를 돌린다 — 이 변경의 목적(빠른 진단)과 정반대가 된다.
      retry: (failureCount, error) => {
        if (error instanceof ApiError) {
          if (error.transport) return false;
          if (error.status >= 400 && error.status < 500) return false;
        }
        return failureCount < 3;
      },
      retryDelay: (attempt) => Math.min(1_000 * 2 ** attempt, 8_000),
      // 서버가 잠깐 죽었다 살아났을 때 탭 복귀만으로 화면이 복구되게 한다 — 종전 false에선
      // 자동 복구 트리거가 0개라 F5 전까지 죽은 화면이 남았다(queries.ts useJoinRequests가
      // 이미 같은 논거로 켜고 있다).
      refetchOnWindowFocus: true,
    },
    // mutations는 기본 retry:0을 **유지한다** — 결제 기록·예약 생성·환불 실행은 비멱등이라
    // 자동 재시도가 이중 기록을 만든다. 여기에 mutations 블록을 추가하거나 retry를
    // defaultOptions 루트로 올리면 그 안전성이 조용히 사라진다.
  },
});

// 배포 직후 열려 있던 탭(P74 — 화면별 코드 분할): 아직 받지 않은 화면 조각(/assets/X-옛해시.js)을
// 부르면 새 배포에는 그 파일이 없어 실패한다(Hosting은 없는 경로에 index.html을 돌려준다). 단일 번들이던
// 때는 없던 실패다. 새 index를 받도록 **한 번만** 새로 고친다 — 10분 안에 또 실패하면(오프라인·청크만 막힌
// 망처럼 진짜 실패) 되풀이하지 않고 ErrorBoundary 카드에 맡긴다. 창을 30초로 두면 부팅→실패가 30초 넘게 걸리는
// 망에서 매번 창 밖이라 새로고침이 끝없이 돈다(P74 반박). 저장소가 막힌 환경도 되풀이를 막을 수 없으니 카드로.
// (짝: firebase.json의 "/" no-cache — 새로 고친 탭이 1시간 캐시된 옛 index를 다시 받지 않게.)
const CHUNK_RELOAD_KEY = "rize-admin-chunk-reload-at";
window.addEventListener("vite:preloadError", () => {
  try {
    const last = Number(sessionStorage.getItem(CHUNK_RELOAD_KEY) ?? 0);
    if (Date.now() - last < 10 * 60_000) return;
    sessionStorage.setItem(CHUNK_RELOAD_KEY, String(Date.now()));
  } catch {
    return;
  }
  window.location.reload();
});

// ErrorBoundary를 **프로바이더 바깥**에 한 겹 더 둔다. App 안쪽 경계는 자기 자식만 잡으므로
// AuthProvider·QueryClientProvider 자신의 렌더 예외(예: 세션 복원 중 던지는 경우)는 그 위로
// 빠져나가 흰 화면이 된다 — 대표에겐 한국어 한 줄도 없는 죽은 탭이다. 같은 컴포넌트를 재사용해
// 바깥도 덮는다(어드민 UX 감사 후속 3).
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <App />
        </AuthProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>,
);
