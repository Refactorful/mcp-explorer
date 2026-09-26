import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// In dev the viewer is served from Vite, so a relative endpoint such as `/mcp`
// would hit Vite itself (and get HTML back). Proxy it to the MCP backend so the
// browser sees a same-origin request and no CORS/proxy code is needed.
// Override with `MCP_DEV_TARGET=http://host:port npm run dev`.
const mcpDevTarget = process.env.MCP_DEV_TARGET ?? "http://127.0.0.1:8080";
const mcpDevPath = process.env.MCP_DEV_PATH ?? "/mcp";

// `__MCP_VIEWER_DEV__` lets the bundle default execution to on in `vite dev`
// and off in production builds.
export default defineConfig(({ command }) => ({
  plugins: [viteSingleFile()],
  define: {
    __MCP_VIEWER_DEV__: JSON.stringify(command === "serve"),
  },
  server: {
    proxy: {
      [mcpDevPath]: {
        target: mcpDevTarget,
        changeOrigin: true,
        // Oxygen rejects cross-origin requests (403). The browser sends an
        // Origin header even for same-origin POSTs, so strip it before
        // forwarding to make the proxied request look local.
        configure: proxy => {
          proxy.on("proxyReq", proxyReq => {
            proxyReq.removeHeader("origin");
          });
        },
      },
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "es2022",
    cssCodeSplit: false,
    assetsInlineLimit: 100000000,
  },
}));
