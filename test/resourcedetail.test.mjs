// @vitest-environment jsdom
import { describe, test, expect, vi } from "vitest";
import { act } from "react";
import * as ResourceDetail from "../src/components/ResourceDetail.res.mjs";
import { click, jsonResponse, mount, setInputValue, waitFor } from "./helpers.mjs";

const result = {
  contents: [
    { uri: "file:///notes/today.md", mimeType: "text/markdown", text: "# Today\nHello." },
  ],
};

const props = (overrides = {}) => ({
  uri: "file:///notes/today.md",
  name: "today.md",
  description: "Daily notes",
  mimeType: "text/markdown",
  template: undefined,
  endpoint: "/mcp",
  reopen: undefined,
  onBack: () => {},
  ...overrides,
});

const readButton = (container) =>
  [...container.querySelectorAll("button")].find((button) =>
    button.textContent.includes("Read resource"),
  );

describe("ResourceDetail", () => {
  test("reads a fixed resource and mirrors the URI into Mcp-Name", async () => {
    let request = null;
    globalThis.fetch = vi.fn(async (_url, init) => {
      request = { body: JSON.parse(init.body), headers: init.headers };
      return jsonResponse(result);
    });

    const container = await mount(ResourceDetail.make, props());
    const uriInput = container.querySelector("input.text-input");
    expect(uriInput.value).toBe("file:///notes/today.md");
    expect(uriInput.readOnly).toBe(true);

    await click(readButton(container));
    await waitFor(() => request !== null);
    expect(request.body.method).toBe("resources/read");
    expect(request.body.params.uri).toBe("file:///notes/today.md");
    expect(new Headers(request.headers).get("Mcp-Method")).toBe("resources/read");
    expect(new Headers(request.headers).get("Mcp-Name")).toBe("file:///notes/today.md");

    await waitFor(() => container.querySelector(".content-text") !== null);
    expect(container.querySelector(".content-text").textContent).toBe("# Today\nHello.");
  });

  test("builds the URI from a simple template", async () => {
    let request = null;
    globalThis.fetch = vi.fn(async (_url, init) => {
      request = { body: JSON.parse(init.body) };
      return jsonResponse(result);
    });

    const container = await mount(
      ResourceDetail.make,
      props({
        uri: "",
        name: "Project files",
        description: undefined,
        mimeType: undefined,
        template: "file:///{path}",
      }),
    );

    const input = container.querySelector("input.text-input");
    expect(readButton(container).disabled).toBe(true);

    await act(async () => {
      setInputValue(input, "docs/hello world.md");
    });
    expect(readButton(container).disabled).toBe(false);

    await click(readButton(container));
    await waitFor(() => request !== null);
    expect(request.body.params.uri).toBe("file:///docs%2Fhello%20world.md");
  });

  test("falls back to a raw URI input for complex templates", () => {
    globalThis.fetch = vi.fn(async () => jsonResponse(result));
    return mount(
      ResourceDetail.make,
      props({
        uri: "",
        name: "Search",
        description: undefined,
        mimeType: undefined,
        template: "file:///{?q}",
      }),
    ).then((container) => {
      const input = container.querySelector("input.text-input");
      expect(input.readOnly).toBe(false);
      expect(input.value).toBe("file:///{?q}");
    });
  });

  test("renders binary content with a zoomable image preview", async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({
        contents: [{ uri: "file:///logo.png", mimeType: "image/png", blob: "aGk=" }],
      }),
    );

    const container = await mount(ResourceDetail.make, props());
    await click(readButton(container));
    await waitFor(() => container.querySelector(".image-preview img") !== null);
    expect(container.querySelector(".image-preview img").getAttribute("src")).toBe(
      "data:image/png;base64,aGk=",
    );
    expect(container.querySelector(".image-modal")).toBeNull();

    await click(container.querySelector(".image-preview"));
    await waitFor(() => container.querySelector(".image-modal") !== null);
    expect(container.querySelector(".image-modal-img").getAttribute("src")).toBe(
      "data:image/png;base64,aGk=",
    );

    await click(container.querySelector(".image-modal-close"));
    await waitFor(() => container.querySelector(".image-modal") === null);
  });

  test("closes the image modal with the Escape key", async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({
        contents: [{ uri: "file:///logo.png", mimeType: "image/png", blob: "aGk=" }],
      }),
    );

    const container = await mount(ResourceDetail.make, props());
    await click(readButton(container));
    await waitFor(() => container.querySelector(".image-preview") !== null);

    await click(container.querySelector(".image-preview"));
    await waitFor(() => container.querySelector(".image-modal") !== null);

    await act(async () => {
      document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape" }));
    });
    await waitFor(() => container.querySelector(".image-modal") === null);
  });

  test("seeds the URI when reopening a logged resources/read", async () => {
    globalThis.fetch = vi.fn(async () => jsonResponse(result));
    const container = await mount(
      ResourceDetail.make,
      props({
        reopen: {
          nonce: 1,
          message: {
            method: "ResourcesRead",
            name: "file:///notes/other.md",
            params: { uri: "file:///notes/other.md" },
          },
        },
      }),
    );
    expect(container.querySelector("input.text-input").value).toBe("file:///notes/other.md");
  });
});
