// @vitest-environment jsdom
import { describe, test, expect } from "vitest";
import * as React from "react";
import { act } from "react";
import * as MapControl from "../src/components/MapControl.res.mjs";
import {
  dispatchClick as click,
  mount,
  mountSchemaForm,
  renderSchemaForm as render,
  setInputValue,
} from "./helpers.mjs";

describe("SchemaForm dictionaries (additionalProperties)", () => {
  test("renders a dictionary of strings to objects as nested fields", () => {
    const schema = {
      type: "object",
      required: ["attributes"],
      properties: {
        attributes: {
          type: "object",
          additionalProperties: {
            type: "object",
            properties: { value: { type: "string" }, weight: { type: "integer" } },
          },
        },
      },
    };
    const html = render(schema, { attributes: { color: { value: "red", weight: 0 } } });
    expect(html).toContain("schema-map");
    expect(html).toContain("color");
    expect(html).toContain("weight");
    expect(html).toContain("Add entry");
  });

  test("renders a map of strings with a text input per value", () => {
    const schema = {
      type: "object",
      properties: { labels: { type: "object", additionalProperties: { type: "string" } } },
    };
    const html = render(schema, { labels: { a: "x" } });
    expect(html).toContain("map-key");
    expect(html).toContain('value="a"');
  });
});

describe("MapControl", () => {
  const mountMap = (props) => mount(MapControl.make, props);

  const renderValue = (_key, current, onChange) =>
    React.createElement("input", {
      className: "value-input",
      value: current == null ? "" : String(current),
      onChange: (event) => onChange(event.target.value),
    });

  test("adds, renames, edits and removes entries", async () => {
    const changes = [];
    const container = await mountMap({
      value: { a: "x" },
      newValue: "",
      reserved: [],
      keyPatterns: [],
      allowAdditional: true,
      minProperties: 0,
      maxProperties: undefined,
      onChange: (value) => changes.push(value),
      onValidityChange: () => {},
      renderValue,
    });

    expect(container.querySelectorAll(".map-row").length).toBe(1);

    await act(async () => {
      click(container.querySelector(".map-add"));
    });
    expect(container.querySelectorAll(".map-row").length).toBe(2);
    expect(changes.at(-1)).toEqual({ a: "x", key: "" });

    const keyInputs = container.querySelectorAll(".map-key");
    await act(async () => {
      setInputValue(keyInputs[1], "b");
    });
    expect(changes.at(-1)).toEqual({ a: "x", b: "" });

    const valueInputs = container.querySelectorAll(".value-input");
    await act(async () => {
      setInputValue(valueInputs[0], "y");
    });
    expect(changes.at(-1)).toEqual({ a: "y", b: "" });

    await act(async () => {
      click(container.querySelector(".map-remove"));
    });
    expect(container.querySelectorAll(".map-row").length).toBe(1);
    expect(changes.at(-1)).toEqual({ b: "" });
  });
});

describe("SchemaForm map integration", () => {
  test("adding a dictionary entry uses the value schema's default", async () => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    const schema = {
      type: "object",
      properties: {
        attributes: {
          type: "object",
          additionalProperties: {
            type: "object",
            properties: { value: { type: "string" }, weight: { type: "integer" } },
          },
        },
      },
    };
    const changes = [];
    const container = await mountSchemaForm(schema, { attributes: {} }, (value) =>
      changes.push(value),
    );

    await act(async () => {
      click(container.querySelector(".map-add"));
    });

    expect(changes.at(-1)).toEqual({
      attributes: { key: { value: "", weight: 0 } },
    });
  });
});
