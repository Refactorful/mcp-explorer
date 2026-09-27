// @vitest-environment jsdom
import { describe, test, expect } from "vitest";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import * as ToolDetail from "../src/components/ToolDetail.res.mjs";

const tool = {
  name: "convert_temperature",
  description: "Convert a temperature",
  inputSchema: {
    type: "object",
    required: ["value", "from", "to"],
    properties: {
      value: { type: "number", description: "the temperature" },
      from: { type: "integer", enum: [1, 2], description: "the source unit" },
      to: { type: "integer", enum: [1, 2], description: "the target unit" },
    },
  },
};

describe("ToolDetail form", () => {
  test("mounts a select for enums and a numeric input for numbers", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
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
        }),
      );
    });

    expect(container.querySelectorAll("select").length).toBe(2);
    const patterns = [...container.querySelectorAll("input")].map((input) =>
      input.getAttribute("pattern"),
    );
    expect(patterns).toContain("-?[0-9]+(\\.[0-9]+)?");
    expect(container.textContent).toContain("the source unit");

    // The raw schema is collapsed by default.
    const disclosure = container.querySelector("details.disclosure");
    expect(disclosure).not.toBeNull();
    expect(disclosure.hasAttribute("open")).toBe(false);
  });

  test("the back button invokes onBack", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    let backCalls = 0;
    const container = document.createElement("div");
    document.body.appendChild(container);
    const root = createRoot(container);

    await act(async () => {
      root.render(
        React.createElement(ToolDetail.make, {
          tool,
          endpoint: "/mcp",
          execEnabled: true,
          onBack: () => {
            backCalls += 1;
          },
        }),
      );
    });

    const back = container.querySelector(".back-btn");
    expect(back).not.toBeNull();
    await act(async () => {
      back.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    });
    expect(backCalls).toBe(1);
  });

  test("disables the whole Try-it area and explains why when execution is off", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    const container = document.createElement("div");
    document.body.appendChild(container);
    const root = createRoot(container);

    await act(async () => {
      root.render(
        React.createElement(ToolDetail.make, {
          tool,
          endpoint: "/mcp",
          execEnabled: false,
          onBack: () => {},
        }),
      );
    });

    const fieldset = container.querySelector("fieldset.tryit-fieldset");
    expect(fieldset).not.toBeNull();
    expect(fieldset.disabled).toBe(true);
    expect(container.querySelector("form").className).toContain("tryit-disabled");
    expect(container.textContent).toContain("Tool execution is disabled");
    expect(container.querySelector('button[type="submit"]').disabled).toBe(true);
  });
});
