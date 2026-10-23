import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev: the R plumber API runs on :8000 (Rscript api/run_api.R); Vite proxies /api to it.
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { "/api": "http://127.0.0.1:8000" } },
  build: {
    chunkSizeWarningLimit: 1600,
    rollupOptions: {
      output: {
        manualChunks: {
          three: ["three", "@react-three/fiber", "@react-three/drei", "@react-three/postprocessing"],
          charts: ["lightweight-charts", "recharts"],
        },
      },
    },
  },
});
