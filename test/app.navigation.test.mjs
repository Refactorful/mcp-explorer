// @vitest-environment jsdom
import { describe, test, expect, vi, beforeEach } from "vitest";
import { act } from "react";
import * as App from "../src/App.res.mjs";
import * as MessageStore from "../src/MessageStore.res.mjs";
import { click, jsonResponse, mount, waitFor } from "./helpers.mjs";

beforeEach(() => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  document.body.innerHTML = '<div id="host"></div>';
  window.history.replaceState(null, "", "/");
  MessageStore.clear();

  globalThis.fetch = vi.fn(async (_url, init) => {
    const method = JSON.parse(init.body).method;
    switch (method) {
      case "server/discover":
        return jsonResponse({
          resultType: "complete",
          supportedVersions: ["2026-07-28"],
          capabilities: { tools: {} },
        });
      case "tools/list":
        return jsonResponse({
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
        return jsonResponse({});
    }
  });
});

describe("App master-detail navigation", () => {
  test("the list stays visible while a tool detail is open, and back clears it", async () => {
    const container = await mount(
      App.make,
      {
        initialEndpoint: "/mcp",
        initialExecEnabled: undefined,
        initialEndpointEditable: undefined,
      },
      document.getElementById("host"),
    );

    // Both panes exist; the detail pane starts empty.
    await waitFor(() => container.querySelector(".item") !== null);
    expect(container.querySelector(".split")).not.toBeNull();
    expect(container.querySelector(".empty-detail")).not.toBeNull();
    expect(container.querySelector(".detail-header")).toBeNull();

    // Select a tool: detail renders, list is still there.
    await click(container.querySelector(".item"));
    await waitFor(() => container.querySelector(".detail-header") !== null);
    expect(container.querySelector(".detail-header h2").textContent).toBe("add");
    expect(container.querySelector(".item-list")).not.toBeNull();
    expect(container.querySelector(".empty-detail")).toBeNull();

    // Back (history.back -> popstate) clears the detail but keeps the list.
    await click(container.querySelector(".back-btn"));
    await waitFor(() => container.querySelector(".empty-detail") !== null);
    expect(container.querySelector(".item-list")).not.toBeNull();
    expect(container.querySelector(".detail-header")).toBeNull();
  });

  test("lists every call in the Messages sidebar and can collapse it", async () => {
    const container = await mount(
      App.make,
      {
        initialEndpoint: "/mcp",
        initialExecEnabled: undefined,
        initialEndpointEditable: undefined,
      },
      document.getElementById("host"),
    );

    // Discovery itself is logged: server/discover then tools/list.
    await waitFor(() => container.querySelectorAll(".message-item").length >= 2);
    expect(container.querySelector(".messages-panel")).not.toBeNull();
    expect(container.textContent).toContain("TOOLS/LIST");
    expect(container.textContent).toContain("SERVER/DISCOVER");
    expect(container.textContent).toContain("CLIENT");

    // Collapse hides the column; the toggle brings it back.
    await click(container.querySelector(".sidebar-toggle"));
    expect(container.querySelector(".messages-panel")).toBeNull();
    await click(container.querySelector(".sidebar-toggle"));
    expect(container.querySelector(".messages-panel")).not.toBeNull();
  });

  test("shows an unread dot when messages arrive while collapsed", async () => {
    const container = await mount(
      App.make,
      {
        initialEndpoint: "/mcp",
        initialExecEnabled: undefined,
        initialEndpointEditable: undefined,
      },
      document.getElementById("host"),
    );
    await waitFor(() => container.querySelector(".sidebar-toggle") !== null);

    await click(container.querySelector(".sidebar-toggle"));
    expect(container.querySelector(".messages-panel")).toBeNull();
    expect(container.querySelector(".sidebar-badge")).toBeNull();

    // A message arrives while the column is hidden.
    await act(async () => {
      MessageStore.start(undefined, "ToolsList", undefined, {}, {}, Date.now());
    });
    expect(container.querySelector(".sidebar-badge")).not.toBeNull();

    // Opening the column clears the badge.
    await click(container.querySelector(".sidebar-toggle"));
    expect(container.querySelector(".sidebar-badge")).toBeNull();
  });

  test("clicking a logged tool call reopens the tool with the same inputs", async () => {
    const container = await mount(
      App.make,
      {
        initialEndpoint: "/mcp",
        initialExecEnabled: true,
        initialEndpointEditable: undefined,
      },
      document.getElementById("host"),
    );
    await waitFor(() => container.querySelector(".item") !== null);

    // Simulate a previously captured tools/call for `add`.
    await act(async () => {
      MessageStore.start(undefined, "ToolsCall", "add", { arguments: { a: 3, b: 4 } }, {}, Date.now());
    });
    await waitFor(() => container.querySelector(".message-main") !== null);

    await click(container.querySelector(".message-main"));

    await waitFor(() => container.querySelector(".detail-header h2") !== null);
    expect(container.querySelector(".detail-header h2").textContent).toBe("add");
    const values = [...container.querySelectorAll(".schema-form input")].map(
      (input) => input.value,
    );
    expect(values).toContain("3");
    expect(values).toContain("4");
  });
});
