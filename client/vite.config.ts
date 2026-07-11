import { defineConfig } from "vite";

export default defineConfig({
  server: {
    host: true, // bind to all interfaces so friends on the same LAN can connect
    port: 5173,
  },
});
