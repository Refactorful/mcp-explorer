// Public types for the React entry point (`react.js`).
//
// Hand-written on purpose: genType's generated adapter imports the compiled
// runtime module, so it can't ship as a declaration file. Keep this in sync
// with:
//
//   * `src/Embed.res`        — the component and its props
//   * `vite.embed.config.js` — the `export { make as McpExplorer };` footer
//
// `test/embed.types.test.mjs` pins the declared export names against both.
import type * as React from "react";

export interface McpExplorerProps {
  /** MCP endpoint URL. Defaults to "/mcp". */
  endpoint?: string;
  /** Overrides the execution toggle's initial state (on in dev builds, off in production). */
  execEnabled?: boolean;
  /** Allows editing the endpoint in the UI. Defaults to true. */
  endpointEditable?: boolean;
  /** Class name applied to the wrapper element. */
  className?: string;
}

export const McpExplorer: React.ComponentType<McpExplorerProps>;
export const make: typeof McpExplorer;
