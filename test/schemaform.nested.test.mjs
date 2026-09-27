// @vitest-environment jsdom
import { describe, test, expect } from "vitest";
import * as React from "react";
import { renderToString } from "react-dom/server";
import { act } from "react";
import { createRoot } from "react-dom/client";
import * as Schema from "../src/api/Schema.res.mjs";
import * as SchemaForm from "../src/components/SchemaForm.res.mjs";

const parse = (text) => JSON.parse(text);

const render = (schema, value) =>
  renderToString(
    React.createElement(SchemaForm.make, {
      schema,
      value,
      onChange: () => {},
      onValidityChange: () => {},
    }),
  );

const mountForm = async (schema, value, onChange = () => {}) => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root = createRoot(container);
  await act(async () => {
    root.render(
      React.createElement(SchemaForm.make, { schema, value, onChange, onValidityChange: () => {} }),
    );
  });
  return container;
};

const setInputValue = (input, value) => {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype,
    "value",
  ).set;
  setter.call(input, value);
  input.dispatchEvent(new window.Event("input", { bubbles: true }));
};

const setSelectValue = (select, value) => {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLSelectElement.prototype,
    "value",
  ).set;
  setter.call(select, value);
  select.dispatchEvent(new window.Event("change", { bubbles: true }));
};

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

describe("Schema composition helpers", () => {
  test("collapses allOf, merging properties and required", () => {
    const schema = parse(
      `{"type":"object","allOf":[{"type":"object","properties":{"a":{"type":"string"}},"required":["a"]},{"type":"object","properties":{"b":{"type":"integer"}},"required":["b"]}]}`,
    );
    expect(Schema.effective(schema, schema, 0)).toEqual({
      type: "object",
      properties: { a: { type: "string" }, b: { type: "integer" } },
      required: ["a", "b"],
    });
    expect(Schema.defaultsFromSchema(schema)).toEqual({ a: "", b: 0 });
  });

  test("resolves type unions to the non-null member", () => {
    const schema = parse(`{"type":["string","null"]}`);
    expect(Schema.primaryType(schema)).toBe("string");
    expect(Schema.isNullable(schema)).toBe(true);
  });

  test("detects oneOf/anyOf, patternProperties and tuples", () => {
    const composed = parse(`{"oneOf":[{"type":"string"},{"type":"integer"}]}`);
    expect(Schema.variantsOf(composed)).toHaveLength(2);
    const patterns = parse(`{"patternProperties":{"^x-":{"type":"string"}}}`);
    expect(Schema.patternPropertiesOf(patterns)).toEqual([["^x-", { type: "string" }]]);
    const tuple = parse(`{"type":"array","prefixItems":[{"type":"string"},{"type":"integer"}]}`);
    expect(Schema.tupleItemsOf(tuple)).toHaveLength(2);
    expect(Schema.itemSchemaOf(tuple)).toBeUndefined();
  });

  test("matches ECMA regex patterns", () => {
    expect(Schema.matchesPattern("^x-", "x-a")).toBe(true);
    expect(Schema.matchesPattern("^x-", "a")).toBe(false);
  });
});

describe("SchemaForm arrays", () => {
  test("renders nested object items and supports add/remove", async () => {
    const schema = {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: { type: "object", properties: { name: { type: "string" } } },
        },
      },
    };
    const html = render(schema, { items: [{ name: "first" }] });
    expect(html).toContain("schema-array");
    expect(html).toContain("first");

    const changes = [];
    const container = await mountForm(schema, { items: [{ name: "first" }] }, (v) =>
      changes.push(v),
    );
    expect(container.querySelectorAll(".array-row").length).toBe(1);

    await act(async () => {
      click(container.querySelector(".map-add"));
    });
    expect(changes.at(-1)).toEqual({ items: [{ name: "first" }, { name: "" }] });

    await act(async () => {
      click(container.querySelector(".map-remove"));
    });
    expect(changes.at(-1)).toEqual({ items: [{ name: "" }] });
  });

  test("renders tuples with per-index schemas", () => {
    const schema = {
      type: "object",
      properties: {
        pair: { type: "array", prefixItems: [{ type: "string" }, { type: "integer" }] },
      },
    };
    const html = render(schema, { pair: ["a", 1] });
    expect(html.match(/array-row/g)).toHaveLength(2);
    expect(html).toContain('pattern="-?[0-9]+"');
  });

  test("enforces minItems when adding/removing", async () => {
    const schema = {
      type: "object",
      properties: { tags: { type: "array", items: { type: "string" }, minItems: 1 } },
    };
    const container = await mountForm(schema, { tags: ["a"] });
    const removeButton = container.querySelector(".map-remove");
    expect(removeButton.disabled).toBe(true);
  });

  test("renders deeply nested arrays of maps of arrays", () => {
    const schema = {
      type: "object",
      properties: {
        groups: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: { type: "array", items: { type: "integer" } },
          },
        },
      },
    };
    const html = render(schema, { groups: [{ scores: [1, 2] }] });
    expect(html).toContain("schema-array");
    expect(html).toContain("schema-map");
    expect(html).toContain('pattern="-?[0-9]+"');
  });
});

describe("SchemaForm composition", () => {
  test("renders a oneOf selector and switches branches", async () => {
    const schema = {
      type: "object",
      properties: {
        contact: {
          oneOf: [
            {
              title: "Email",
              type: "object",
              properties: { email: { type: "string" } },
              required: ["email"],
            },
            {
              title: "Phone",
              type: "object",
              properties: { phone: { type: "string" } },
              required: ["phone"],
            },
          ],
        },
      },
    };
    const changes = [];
    const container = await mountForm(schema, { contact: { email: "a@b.c" } }, (v) =>
      changes.push(v),
    );

    const select = container.querySelector(".variant-select");
    expect(select).not.toBeNull();
    expect([...select.options].map((option) => option.text)).toEqual(["Email", "Phone"]);
    expect(container.textContent).toContain("email");

    await act(async () => {
      setSelectValue(select, "1");
    });
    expect(changes.at(-1)).toEqual({ contact: { phone: "" } });
    expect(container.textContent).toContain("phone");
  });

  test("selects the matching branch from a discriminator value", async () => {
    const schema = {
      type: "object",
      properties: {
        shape: {
          oneOf: [
            {
              type: "object",
              properties: { kind: { const: "circle" }, radius: { type: "number" } },
            },
            {
              type: "object",
              properties: { kind: { const: "square" }, side: { type: "number" } },
            },
          ],
          discriminator: { propertyName: "kind" },
        },
      },
    };
    const container = await mountForm(schema, { shape: { kind: "circle", radius: 1 } });
    const select = container.querySelector(".variant-select");
    expect(select.value).toBe("0");
    expect(container.querySelector(".variant-body").textContent).toContain("radius");
  });

  test("merges allOf properties into one form", () => {
    const schema = {
      type: "object",
      allOf: [
        { type: "object", properties: { a: { type: "string" } }, required: ["a"] },
        { type: "object", properties: { b: { type: "integer" } } },
      ],
    };
    const html = render(schema, { a: "", b: 0 });
    expect(html).toContain("a");
    expect(html).toContain("b");
    expect(html).toContain("required-mark");
  });

  test("treats anyOf like oneOf", async () => {
    const schema = {
      type: "object",
      properties: {
        value: { anyOf: [{ type: "string" }, { type: "integer" }] },
      },
    };
    const changes = [];
    const container = await mountForm(schema, { value: "hello" }, (v) => changes.push(v));
    await act(async () => {
      setSelectValue(container.querySelector(".variant-select"), "1");
    });
    expect(changes.at(-1)).toEqual({ value: 0 });
  });
});

describe("SchemaForm mixed objects", () => {
  test("renders declared properties plus additional properties", async () => {
    const schema = {
      type: "object",
      properties: { name: { type: "string" } },
      additionalProperties: { type: "integer" },
    };
    const html = render(schema, { name: "", extra: 0 });
    expect(html).toContain("name");
    expect(html).toContain("schema-map");
    expect(html).toContain("extra");

    const changes = [];
    const container = await mountForm(schema, { name: "keep", extra: 1 }, (v) =>
      changes.push(v),
    );
    await act(async () => {
      click(container.querySelector(".map-add"));
    });
    expect(changes.at(-1)).toEqual({ name: "keep", extra: 1, key: 0 });
  });

  test("validates patternProperties keys", async () => {
    const schema = {
      type: "object",
      patternProperties: { "^x-": { type: "string" } },
      additionalProperties: false,
    };
    const container = await mountForm(schema, { "x-a": "" });
    expect(container.textContent).not.toContain("allowed pattern");

    await act(async () => {
      setInputValue(container.querySelector(".map-key"), "bad");
    });
    expect(container.textContent).toContain("allowed pattern");
  });
});

describe("SchemaForm scalar edge cases", () => {
  test("renders const as a single-option select", () => {
    const schema = {
      type: "object",
      properties: { kind: { const: "fixed" } },
    };
    const html = render(schema, { kind: "fixed" });
    expect(html).toContain(">fixed<");
  });

  test("renders nullable type unions as their non-null control", () => {
    const schema = {
      type: "object",
      properties: { note: { type: ["string", "null"] } },
    };
    const html = render(schema, { note: null });
    expect(html).toContain("<input");
    expect(html).not.toContain("<textarea");
  });
});
