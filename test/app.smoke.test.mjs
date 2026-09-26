import { describe, test, expect } from "vitest";
import * as React from "react";
import { renderToString } from "react-dom/server";
import * as App from "../src/App.res.mjs";

describe("App", () => {
  test("renders the toolbar and shell without throwing", () => {
    const html = renderToString(React.createElement(App.make, { initialEndpoint: "/mcp" }));
    expect(html).toContain("MCP Viewer");
    expect(html).toContain("MCP endpoint");
    expect(html).toContain("Enable execution");
  });
});
