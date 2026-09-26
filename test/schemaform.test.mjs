import { describe, test, expect } from "vitest";
import * as React from "react";
import { renderToString } from "react-dom/server";
import * as SchemaForm from "../src/components/SchemaForm.res.mjs";

const render = (schema, value) =>
  renderToString(
    React.createElement(SchemaForm.make, {
      schema,
      value,
      onChange: () => {},
      onValidityChange: () => {},
    }),
  );

describe("SchemaForm", () => {
  test("renders enum values as a select", () => {
    const schema = {
      type: "object",
      required: ["from"],
      properties: { from: { type: "integer", enum: [1, 2], description: "the source unit" } },
    };
    const html = render(schema, { from: 1 });
    expect(html).toContain("<select");
    expect(html).toContain(">1<");
    expect(html).toContain(">2<");
    expect(html).toContain("the source unit");
  });

  test("renders booleans as checkboxes and numbers with a numeric pattern", () => {
    const schema = {
      type: "object",
      properties: { flag: { type: "boolean" }, count: { type: "integer" } },
    };
    const html = render(schema, { flag: true, count: 0 });
    expect(html).toContain('type="checkbox"');
    expect(html).toContain('pattern="-?[0-9]+"');
    expect(html).toContain('inputMode="numeric"');
  });

  test("renders required markers and string inputs", () => {
    const schema = {
      type: "object",
      required: ["name"],
      properties: { name: { type: "string" } },
    };
    const html = render(schema, { name: "" });
    expect(html).toContain("required-mark");
    expect(html).toContain('required=""');
  });

  test("renders nested $ref objects recursively", () => {
    const schema = {
      type: "object",
      properties: { place: { $ref: "#/$defs/Place" } },
      $defs: {
        Place: {
          type: "object",
          properties: {
            name: { type: "string" },
            coordinates: { $ref: "#/$defs/Coords" },
          },
        },
        Coords: { type: "object", properties: { lat: { type: "number" } } },
      },
    };
    const html = render(schema, { place: { name: "", coordinates: { lat: 0 } } });
    expect(html).toContain("place");
    expect(html).toContain("coordinates");
    expect(html).toContain("lat");
  });

  test("renders arrays as a JSON fallback editor", () => {
    const schema = {
      type: "object",
      properties: { tags: { type: "array", items: { type: "string" } } },
    };
    const html = render(schema, { tags: [] });
    expect(html).toContain("<textarea");
  });
});
