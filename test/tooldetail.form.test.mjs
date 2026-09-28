// @vitest-environment jsdom
import { describe, test, expect } from "vitest";
import * as ToolDetail from "../src/components/ToolDetail.res.mjs";
import { click, mount } from "./helpers.mjs";

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

const props = (overrides = {}) => ({
  tool,
  endpoint: "/mcp",
  execEnabled: true,
  onBack: () => {},
  ...overrides,
});

describe("ToolDetail form", () => {
  test("mounts a select for enums and a numeric input for numbers", async () => {
    const container = await mount(ToolDetail.make, props());

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
    let backCalls = 0;
    const container = await mount(
      ToolDetail.make,
      props({
        onBack: () => {
          backCalls += 1;
        },
      }),
    );

    const back = container.querySelector(".back-btn");
    expect(back).not.toBeNull();
    await click(back);
    expect(backCalls).toBe(1);
  });

  test("disables the whole Try-it area and explains why when execution is off", async () => {
    const container = await mount(ToolDetail.make, props({ execEnabled: false }));

    const fieldset = container.querySelector("fieldset.tryit-fieldset");
    expect(fieldset).not.toBeNull();
    expect(fieldset.disabled).toBe(true);
    expect(container.querySelector("form").className).toContain("tryit-disabled");
    expect(container.textContent).toContain("Tool execution is disabled");
    expect(container.querySelector('button[type="submit"]').disabled).toBe(true);
  });
});
