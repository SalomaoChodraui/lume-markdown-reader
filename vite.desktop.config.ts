import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  build: {
    emptyOutDir: true,
    outDir: "../dist-desktop",
  },
  plugins: [react()],
  publicDir: false,
  root: "desktop",
  server: {
    port: 1420,
    strictPort: true,
  },
});
