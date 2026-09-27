// @vitest-environment jsdom
import { describe, test, expect, vi } from "vitest";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import * as MessagesPanel from "../src/components/MessagesPanel.res.mjs";

const startedAt = Date.UTC(2024, 0, 2, 20, 30, 46);

const message = (overrides = {}) => ({
  id: "11111111-1111-4111-8111-111111111111",
  direction: "ClientToServer",
  method: "ToolsCall",
  name: "echo",
  params: { arguments: { text: "hi" } },
  request: { jsonrpc: "2.0", method: "tools/call", params: { name: "echo" } },
  startedAt,
  durationMs: 41,
  status: "Succeeded",
  response: { content: [] },
  error: undefined,
  ...overrides,
});

const render = async (props) => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root = createRoot(container);
  await act(async () => {
    root.render(
      React.createElement(MessagesPanel.make, {
        messages: props.messages ?? [],
        onClear: props.onClear ?? (() => {}),
        onReplay: props.onReplay ?? (() => {}),
        onReopen: props.onReopen ?? (() => {}),
      }),
    );
  });
  return container;
};

const click = async (element) => {
  await act(async () => {
    element.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  });
};

describe("MessagesPanel", () => {
  test("renders the local time, direction, duration and method of each call", async () => {
    const d = new Date(startedAt);
    const pad = (n) => String(n).padStart(2, "0");
    const expectedTime = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;

    const container = await render({ messages: [message()] });

    expect(container.querySelector(".message-time").textContent).toBe(expectedTime);
    expect(container.querySelector(".message-direction").textContent).toBe(
      "CLIENT \u2192 SERVER",
    );
    expect(container.querySelector(".message-duration").textContent).toBe("41ms");
    expect(container.querySelector(".message-method").textContent).toBe("TOOLS/CALL");
    expect(container.querySelector(".message-name").textContent).toBe("echo");
  });

  test("renders pending calls with an ellipsis duration", async () => {
    const container = await render({
      messages: [message({ status: "Pending", durationMs: undefined })],
    });
    expect(container.querySelector(".message-duration").textContent).toBe("\u2026");
    expect(container.querySelector(".message-item").className).toContain("pending");
  });

  test("the replay button re-sends without reopening the detail", async () => {
    const onReplay = vi.fn();
    const onReopen = vi.fn();
    const container = await render({
      messages: [message()],
      onReplay,
      onReopen,
    });

    await click(container.querySelector('button[title="Replay this request"]'));

    expect(onReplay).toHaveBeenCalledTimes(1);
    expect(onReplay.mock.calls[0][0].id).toBe(message().id);
    expect(onReopen).not.toHaveBeenCalled();
  });

  test("clicking a reopenable call asks to reopen it with the same inputs", async () => {
    const onReopen = vi.fn();
    const container = await render({ messages: [message()], onReopen });

    await click(container.querySelector(".message-main"));

    expect(onReopen).toHaveBeenCalledTimes(1);
    expect(onReopen.mock.calls[0][0].params.arguments.text).toBe("hi");
  });

  test("clicking a non-reopenable call expands its raw request/response", async () => {
    const onReopen = vi.fn();
    const container = await render({
      messages: [message({ method: "ToolsList", name: undefined })],
      onReopen,
    });

    expect(container.querySelector(".message-detail")).toBeNull();
    await click(container.querySelector(".message-main"));
    expect(onReopen).not.toHaveBeenCalled();
    expect(container.querySelector(".message-detail")).not.toBeNull();
    expect(container.querySelector(".message-detail").textContent).toContain("tools/call");
  });

  test("the expand button toggles the detail, clear is disabled when empty", async () => {
    const onClear = vi.fn();
    const container = await render({ messages: [message()], onClear });

    await click(container.querySelector('button[title="Show request and response"]'));
    expect(container.querySelector(".message-detail")).not.toBeNull();
    await click(container.querySelector('button[title="Show request and response"]'));
    expect(container.querySelector(".message-detail")).toBeNull();

    await click(container.querySelector(".messages-head .btn"));
    expect(onClear).toHaveBeenCalledTimes(1);

    const empty = await render({ messages: [] });
    expect(empty.textContent).toContain("No messages yet");
    expect(empty.querySelector(".messages-head .btn").disabled).toBe(true);
  });
});
