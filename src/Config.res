// Build-time flags. `__MCP_VIEWER_DEV__` is replaced by Vite at build time
// (`true` under `vite dev`, `false` in production bundles).

@val external isDevBuild: bool = "__MCP_VIEWER_DEV__"

// Execution is opt-in by default in production bundles and convenient in dev.
let execDefault = isDevBuild
