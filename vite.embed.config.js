import { defineConfig } from "vite";

// ESM component build: the package's React entry (`react.js`). React is
// external (the host app provides it), everything else is bundled. The footer
// alias exposes the component under the public name, since ReScript values are
// always lowercase.
export default defineConfig({
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
    __MCP_EXPLORER_DEV__: JSON.stringify(false),
  },
  build: {
    outDir: "dist-embed",
    emptyOutDir: true,
    target: "es2022",
    assetsInlineLimit: 100000000,
    lib: {
      entry: "src/Embed.res.mjs",
      formats: ["es"],
      fileName: () => "react.js",
    },
    rollupOptions: {
      external: ["react", "react/jsx-runtime"],
      output: {
        footer: "export { make as McpExplorer };",
      },
    },
  },
});
