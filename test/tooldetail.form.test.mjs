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
          execEnabled: false,
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
          execEnabled: false,
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
});
