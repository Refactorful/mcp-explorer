import { defineConfig } from "vite";

// Library build: emits an IIFE bundle exposing the global `McpExplorerBundle`
// (which registers the callable `window.McpExplorer`), plus the extracted
// stylesheet. This is the artifact a server such as Oxygen embeds into its own
// HTML (swagger-style).
export default defineConfig({
  define: {
    // Library mode does not replace `process.env.NODE_ENV`, which would pull
    // React's development build (and its warnings) into the bundle.
    "process.env.NODE_ENV": JSON.stringify("production"),
    __MCP_EXPLORER_DEV__: JSON.stringify(false),
  },
  build: {
    outDir: "dist-lib",
    emptyOutDir: true,
    target: "es2022",
    lib: {
      entry: "src/Main.res.mjs",
      // Rollup assigns this name to the module namespace. Keep it distinct from
      // the public global so it can't overwrite the callable `window.McpExplorer`.
      name: "McpExplorerBundle",
      formats: ["iife"],
      fileName: () => "mcpexplorer.js",
      cssFileName: "mcpexplorer",
    },
  },
});
