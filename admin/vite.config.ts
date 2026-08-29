import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "node:path";

// Tailwind v4는 @tailwindcss/vite 플러그인으로 통합. 별도 tailwind.config 불필요.
export default defineConfig(({ mode }) => {
  // process.env는 .env 파일을 못 읽는다 — loadEnv로 .env·셸 환경변수 모두 반영.
  const env = loadEnv(mode, process.cwd(), "");
  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: { "@": path.resolve(__dirname, "./src") },
    },
    server: {
      port: 5174,
      // 백엔드로 프록시(개발). VITE_API_TARGET 미설정 시 /api → localhost:8080.
      proxy: {
        "/api": {
          target: env.VITE_API_TARGET || "http://localhost:8080",
          changeOrigin: true,
          rewrite: (p) => p.replace(/^\/api/, ""),
        },
      },
    },
  };
});
