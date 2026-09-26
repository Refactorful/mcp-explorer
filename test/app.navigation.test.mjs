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

describe("App navigation", () => {
  test("selecting a tool opens the detail and back returns to the list", async () => {
    const container = document.getElementById("host");
    const root = createRoot(container);

    await act(async () => {
      root.render(React.createElement(App.make, { initialEndpoint: "/mcp" }));
    });

    // List view is visible (after discovery + tools/list resolve).
    await waitFor(() => container.querySelector(".item") !== null);

    // Open the tool detail.
    await act(async () => {
      container
        .querySelector(".item")
        .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    });
    await waitFor(() => container.querySelector(".back-btn") !== null);
    expect(container.querySelector(".detail-header h2").textContent).toBe("add");

    // In-app back button returns to the list (via history.back -> popstate).
    await act(async () => {
      container
        .querySelector(".back-btn")
        .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    });
    await waitFor(() => container.querySelector(".item-list") !== null);
    expect(container.querySelector(".back-btn")).toBeNull();
  });
});
