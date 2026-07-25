import { defineConfig } from "vite";

export default defineConfig({
  server: {
    host: true, // bind to all interfaces so friends on the same LAN can connect
    port: 5173,
    // shared/worldGeometry.ts sits above the client root, so the dev server has
    // to be allowed to serve it (the production build inlines it either way).
    fs: { allow: [".."] },
  },
});
