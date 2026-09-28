// @vitest-environment jsdom
import { describe, test, expect, vi } from "vitest";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import * as ToolDetail from "../src/components/ToolDetail.res.mjs";

const encoder = new TextEncoder();

const sseResponse = (chunks) =>
  new Response(
    new ReadableStream({
      start(controller) {
        for (const chunk of chunks) {
          controller.enqueue(encoder.encode(chunk));
        }
        controller.close();
      },
    }),
    { status: 200, headers: { "Content-Type": "text/event-stream" } },
  );

const tool = {
  name: "echo",
  description: "Echo text",
  inputSchema: { type: "object", properties: {} },
};

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

describe("ToolDetail streaming", () => {
  test("renders SSE events live and then the final result", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    globalThis.fetch = vi.fn(async () =>
      sseResponse([
        'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1,"total":1}}\n\n',
        'data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"done"}],"isError":false}}\n\n',
      ]),
    );

    const container = document.createElement("div");
    document.body.appendChild(container);
    const root = createRoot(container);

    await act(async () => {
      root.render(
        React.createElement(ToolDetail.make, {
          tool,
          endpoint: "/mcp",
          execEnabled: true,
          onBack: () => {},
          reopen: undefined,
        }),
      );
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
