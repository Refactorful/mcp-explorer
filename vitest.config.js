import { defineConfig } from "vitest/config";

export default defineConfig({
  define: {
    __MCP_VIEWER_DEV__: JSON.stringify(true),
  },
  test: {
    include: ["test/**/*_test.res.mjs", "test/**/*.test.mjs"],
  },
});
