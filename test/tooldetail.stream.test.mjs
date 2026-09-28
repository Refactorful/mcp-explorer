// @vitest-environment jsdom
import { describe, test, expect, vi } from "vitest";
import { act } from "react";
import * as ToolDetail from "../src/components/ToolDetail.res.mjs";
import { mount, sseResponse, waitFor } from "./helpers.mjs";

const tool = {
  name: "echo",
  description: "Echo text",
  inputSchema: { type: "object", properties: {} },
};

describe("ToolDetail streaming", () => {
  test("renders SSE events live and then the final result", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    globalThis.fetch = vi.fn(async () =>
      sseResponse([
        'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1,"total":1}}\n\n',
        'data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"done"}],"isError":false}}\n\n',
      ]),
    );

    const container = await mount(ToolDetail.make, {
      tool,
      endpoint: "/mcp",
      execEnabled: true,
      onBack: () => {},
    });

    await act(async () => {
      container
        .querySelector("form")
        .dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
    });

    await waitFor(() => container.querySelector(".stream-event") !== null);
    expect(container.querySelector(".stream-event").className).toContain("notification");
    expect(container.textContent).toContain("notifications/progress");

    await waitFor(() => container.querySelector(".content-text") !== null);
    expect(container.querySelector(".content-text").textContent).toBe("done");
  });
});
