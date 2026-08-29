import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import App from "./App";
import { AuthProvider } from "@/lib/auth";
import { ApiError } from "@/lib/api";
import "./index.css";

// 서버상태는 TanStack Query로 관리. staleTime으로 화면 전환 시 잦은 재조회를 완화.
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 15_000,
      // 4xx(권한·검증·없음)는 재시도해도 결과가 같다 — 재시도는 서버·전달 경로가 흔들리는
      // 5xx/네트워크 오류에만 의미가 있다. 종전 retry:1은 방향이 반대였다(4xx에 무의미한
      // 재시도를 붙이고 5xx엔 부족했다 — P35).
      retry: (failureCount, error) => {
        if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
        return failureCount < 3;
      },
      retryDelay: (attempt) => Math.min(1_000 * 2 ** attempt, 8_000),
      // 서버가 잠깐 죽었다 살아났을 때 탭 복귀만으로 화면이 복구되게 한다 — 종전 false에선
      // 자동 복구 트리거가 0개라 F5 전까지 죽은 화면이 남았다. staleTime 15초가 연타를
      // 흡수한다(queries.ts useJoinRequests가 이미 같은 논거로 켜고 있다).
      refetchOnWindowFocus: true,
    },
  },
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </QueryClientProvider>
  </StrictMode>,
);
