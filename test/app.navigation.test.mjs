// @vitest-environment jsdom
import { describe, test, expect, vi, beforeEach } from "vitest";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import * as App from "../src/App.res.mjs";

const response = (result) =>
  new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  document.body.innerHTML = '<div id="host"></div>';
  window.history.replaceState(null, "", "/");

  globalThis.fetch = vi.fn(async (_url, init) => {
    const method = JSON.parse(init.body).method;
    switch (method) {
      case "server/discover":
        return response({
          resultType: "complete",
          supportedVersions: ["2026-07-28"],
          capabilities: { tools: {} },
        });
      case "tools/list":
        return response({
          tools: [
            {
              name: "add",
              description: "Add two integers",
              inputSchema: {
                type: "object",
                required: ["a", "b"],
                properties: { a: { type: "integer" }, b: { type: "integer" } },
              },
            },
          ],
        });
      default:
        return response({});
    }
  });
});

const flush = async () => {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
};

const waitFor = async (predicate, timeout = 2000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    await flush();
    if (predicate()) {
      return;
    }
  }
  throw new Error("timed out waiting for condition");
};

describe("App master-detail navigation", () => {
  test("the list stays visible while a tool detail is open, and back clears it", async () => {
    const container = document.getElementById("host");
    const root = createRoot(container);

    await act(async () => {
      root.render(React.createElement(App.make, { initialEndpoint: "/mcp" }));
    });

    // Both panes exist; the detail pane starts empty.
    await waitFor(() => container.querySelector(".item") !== null);
    expect(container.querySelector(".split")).not.toBeNull();
    expect(container.querySelector(".empty-detail")).not.toBeNull();
    expect(container.querySelector(".detail-header")).toBeNull();

    // Select a tool: detail renders, list is still there.
    await act(async () => {
      container
        .querySelector(".item")
        .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    });
    await waitFor(() => container.querySelector(".detail-header") !== null);
    expect(container.querySelector(".detail-header h2").textContent).toBe("add");
    expect(container.querySelector(".item-list")).not.toBeNull();
    expect(container.querySelector(".empty-detail")).toBeNull();

    // Back (history.back -> popstate) clears the detail but keeps the list.
    await act(async () => {
      container
        .querySelector(".back-btn")
        .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    });
    await waitFor(() => container.querySelector(".empty-detail") !== null);
    expect(container.querySelector(".item-list")).not.toBeNull();
    expect(container.querySelector(".detail-header")).toBeNull();
  });
});
