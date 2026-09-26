// @vitest-environment jsdom
import { describe, test, expect, vi, beforeEach } from "vitest";
import { act } from "react";

beforeEach(() => {
  document.body.innerHTML = '<div id="mcp-viewer"></div><div id="root"></div>';
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  globalThis.fetch = vi.fn(async () =>
    new Response(
      JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        result: {
          resultType: "complete",
          supportedVersions: ["2026-07-28"],
          capabilities: { tools: {} },
        },
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    ),
  );
});

describe("global mount API", () => {
  test("registers McpViewer (callable and .mount) and mounts into an element", async () => {
    await import("../src/Main.res.mjs");

    expect(typeof globalThis.McpViewer).toBe("function");
    expect(typeof globalThis.McpViewer.mount).toBe("function");

    await act(async () => {
      globalThis.McpViewer({ endpoint: "/mcp", domId: "mcp-viewer" });
    });

    const container = document.getElementById("mcp-viewer");
    expect(container.textContent).toContain("MCP Viewer");
    expect(container.textContent).toContain("MCP endpoint");
  });

  test("accepts a shorthand domId string and returns an unmount handle", async () => {
    await import("../src/Main.res.mjs");

    let handle;
    await act(async () => {
      handle = globalThis.McpViewer("mcp-viewer");
    });

    expect(typeof handle.unmount).toBe("function");
  });

  test("mount throws a helpful error when the container is missing", async () => {
    await import("../src/Main.res.mjs");
    expect(() => globalThis.McpViewer({ endpoint: "/mcp", domId: "does-not-exist" })).toThrow(
      /no element with id 'does-not-exist'/,
    );
  });
});
