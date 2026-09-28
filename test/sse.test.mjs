import { describe, test, expect, vi, beforeEach } from "vitest";
import * as Mcp from "../src/api/Mcp.res.mjs";
import * as Sse from "../src/api/Sse.res.mjs";
import * as MessageStore from "../src/MessageStore.res.mjs";

const encoder = new TextEncoder();

const sseBody = (chunks) =>
  new ReadableStream({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
      controller.close();
    },
  });

const sseResponse = (chunks) =>
  new Response(sseBody(chunks), {
    status: 200,
    headers: { "Content-Type": "text/event-stream" },
  });

beforeEach(() => {
  MessageStore.clear();
});

describe("Sse.read", () => {
  test("decodes data frames and stops once isFinal matches", async () => {
    const stream = sseBody([
      'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n',
      'data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}\n\n',
      'data: {"jsonrpc":"2.0","id":1,"result":{"ignored":true}}\n\n',
    ]);
    const seen = [];
    const result = await Sse.read({ body: stream }, (m) => seen.push(m), (m) => m.id === 1);

    expect(seen.length).toBe(2);
    expect(result.length).toBe(2);
    expect(result[1].id).toBe(1);
    expect(result[0].method).toBe("notifications/progress");
  });

  test("handles frames split across chunks and CRLF endings", async () => {
    const stream = sseBody([
      'data: {"jsonrpc":"2.0","method":"notifications/message"}\r\n\r\n',
      'data: {"jsonrpc":"2.0","id":',
      '7,"result":{"ok":true}}\r\n\r\n',
    ]);
    const seen = [];
    const result = await Sse.read({ body: stream }, (m) => seen.push(m), (m) => m.id === 7);

    expect(seen.length).toBe(2);
    expect(result[1].id).toBe(7);
    expect(result[0].method).toBe("notifications/message");
  });

  test("rejects when the response has no readable body", async () => {
    await expect(Sse.read({}, () => {}, () => false)).rejects.toThrow();
  });
});

describe("Mcp.callTool over SSE", () => {
  test("emits notifications live and resolves with the final result", async () => {
    globalThis.fetch = vi.fn(async () =>
      sseResponse([
        'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1,"total":2}}\n\n',
        'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":2,"total":2}}\n\n',
        'data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"done"}],"isError":false}}\n\n',
      ]),
    );

    const events = [];
    const result = await Mcp.callTool(Mcp.make("/mcp"), "echo", { text: "hi" }, (event) =>
      events.push(event),
    );

    expect(result.TAG).toBe("Ok");
    expect(result._0.content[0]._0).toBe("done");
    expect(events.length).toBe(2);
    expect(events[0].kind).toBe("Notification");
    expect(events[0].method).toBe("notifications/progress");
  });

  test("still handles a single application/json response", async () => {
    globalThis.fetch = vi.fn(
      async () =>
        new Response(
          JSON.stringify({ jsonrpc: "2.0", id: 1, result: { content: [], isError: false } }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
    );

    const result = await Mcp.callTool(Mcp.make("/mcp"), "echo", {});
    expect(result.TAG).toBe("Ok");
    expect(result._0.isError).toBe(false);
  });

  test("turns an SSE stream with no response into a protocol error", async () => {
    globalThis.fetch = vi.fn(async () =>
      sseResponse(['data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n']),
    );

    const result = await Mcp.callTool(Mcp.make("/mcp"), "echo", {});
    expect(result.TAG).toBe("Error");
    expect(result._0.TAG).toBe("ProtocolMismatch");
  });
});
