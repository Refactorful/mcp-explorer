// @vitest-environment jsdom
import { describe, test, expect, vi, beforeEach } from "vitest";
import { act } from "react";

beforeEach(() => {
  document.body.innerHTML = '<div id="mcp-explorer"></div><div id="root"></div>';
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

const execCheckbox = (container) => container.querySelector('input[type="checkbox"]');

describe("global mount API", () => {
  test("registers McpExplorer (callable and .mount) and mounts into an element", async () => {
    await import("../src/Main.res.mjs");

    expect(typeof globalThis.McpExplorer).toBe("function");
    expect(typeof globalThis.McpExplorer.mount).toBe("function");

    await act(async () => {
      globalThis.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer" });
    });

    const container = document.getElementById("mcp-explorer");
    expect(container.textContent).toContain("MCP Explorer");
    expect(container.textContent).toContain("MCP endpoint");
  });

  test("accepts a shorthand domId string and returns an unmount handle", async () => {
    await import("../src/Main.res.mjs");

    let handle;
    await act(async () => {
      handle = globalThis.McpExplorer("mcp-explorer");
    });

    expect(typeof handle.unmount).toBe("function");
  });

  test("mount throws a helpful error when the container is missing", async () => {
    await import("../src/Main.res.mjs");
    expect(() => globalThis.McpExplorer({ endpoint: "/mcp", domId: "does-not-exist" })).toThrow(
      /no element with id 'does-not-exist'/,
    );
  });

  test("execEnabled: true enables and locks tool execution", async () => {
    await import("../src/Main.res.mjs");
    await act(async () => {
      globalThis.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer", execEnabled: true });
    });

    const container = document.getElementById("mcp-explorer");
    await waitFor(() => execCheckbox(container) !== null);
    expect(execCheckbox(container).checked).toBe(true);
    expect(execCheckbox(container).disabled).toBe(true);
  });

  test("execEnabled: false disables and locks tool execution", async () => {
    await import("../src/Main.res.mjs");
    await act(async () => {
      globalThis.McpExplorer({ endpoint: "/mcp", domId: "root", execEnabled: false });
    });

    const container = document.getElementById("root");
    await waitFor(() => execCheckbox(container) !== null);
    expect(execCheckbox(container).checked).toBe(false);
    expect(execCheckbox(container).disabled).toBe(true);
  });

  test("omitting execEnabled leaves the toggle user-changeable", async () => {
    await import("../src/Main.res.mjs");
    await act(async () => {
      globalThis.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer" });
    });

    const container = document.getElementById("mcp-explorer");
    await waitFor(() => execCheckbox(container) !== null);
    expect(execCheckbox(container).disabled).toBe(false);
  });
});
