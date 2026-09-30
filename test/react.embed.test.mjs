// @vitest-environment jsdom
import { describe, test, expect, vi, beforeEach } from "vitest";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { jsonResponse, mount, waitFor } from "./helpers.mjs";
import { make as McpExplorer } from "../src/Embed.res.mjs";

beforeEach(() => {
  document.body.innerHTML = "";
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  globalThis.fetch = vi.fn(async (_url, init) => {
    const method = init && init.body ? JSON.parse(init.body).method : undefined;
    if (method === "tools/list") {
      return jsonResponse({ tools: [] });
    }
    return jsonResponse({
      resultType: "complete",
      supportedVersions: ["2026-07-28"],
      capabilities: { tools: {} },
    });
  });
});

describe("React component entry", () => {
  test("renders the viewer shell and applies the wrapper className", async () => {
    const container = await mount(McpExplorer, {
      endpoint: "/mcp",
      className: "host-viewer",
    });

    await waitFor(() => container.querySelector(".app") !== null);
    const wrapper = container.firstElementChild;
    expect(wrapper.className).toBe("host-viewer");
    expect(container.textContent).toContain("MCP Explorer");
  });

  test("passes the endpoint through to the shell", async () => {
    const container = await mount(McpExplorer, { endpoint: "http://localhost:8080/mcp" });

    await waitFor(() => container.querySelector(".text-input") !== null);
    expect(container.querySelector(".text-input").value).toBe("http://localhost:8080/mcp");
  });

  test("unmounts cleanly", async () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const root = createRoot(container);

    await act(async () => {
      root.render(React.createElement(McpExplorer, { endpoint: "/mcp" }));
    });
    await waitFor(() => container.querySelector(".app") !== null);

    await act(async () => {
      root.unmount();
    });
    expect(container.innerHTML).toBe("");
  });
});
