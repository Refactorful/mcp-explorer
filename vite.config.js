import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// Inline the app icon as a data URI so the standalone single-file page keeps
// its favicon without emitting a separate asset (vite-plugin-singlefile only
// inlines JS/CSS; a plain <link rel="icon"> would leak an extra .svg file).
const iconSvg = readFileSync(
  fileURLToPath(new URL("./assets/icon-compass.svg", import.meta.url)),
  "utf8"
);
const iconHref = `data:image/svg+xml;base64,${Buffer.from(iconSvg).toString("base64")}`;

function faviconPlugin() {
  return {
    name: "mcp-explorer:favicon",
    enforce: "pre",
    transformIndexHtml() {
      return [
        {
          tag: "link",
          attrs: { rel: "icon", type: "image/svg+xml", href: iconHref },
          injectTo: "head",
        },
      ];
    },
  };
}

// In dev the viewer is served from Vite, so a relative endpoint such as `/mcp`
// would hit Vite itself (and get HTML back). Proxy it to the MCP backend so the
// browser sees a same-origin request and no CORS/proxy code is needed.
// Override with `MCP_DEV_TARGET=http://host:port npm run dev`.
const mcpDevTarget = process.env.MCP_DEV_TARGET ?? "http://127.0.0.1:8080";
const mcpDevPath = process.env.MCP_DEV_PATH ?? "/mcp";

// `__MCP_EXPLORER_DEV__` lets the bundle default execution to on in `vite dev`
// and off in production builds.
export default defineConfig(({ command }) => ({
  plugins: [faviconPlugin(), viteSingleFile()],
  define: {
    __MCP_EXPLORER_DEV__: JSON.stringify(command === "serve"),
  },
  server: {
    proxy: {
      [mcpDevPath]: {
        target: mcpDevTarget,
        changeOrigin: true,
        // Many MCP hosts reject cross-origin requests (403). The browser sends an
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
