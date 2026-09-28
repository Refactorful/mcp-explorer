// Shared scaffolding for the DOM/transport test suites.
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { renderToString } from "react-dom/server";
import * as SchemaForm from "../src/components/SchemaForm.res.mjs";

// Let React flush effects and pending promises. Avoid single-tick assertions;
// use `waitFor` instead.
export const flush = async () => {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
};

export const waitFor = async (predicate, timeout = 2000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    await flush();
    if (predicate()) {
      return;
    }
  }
  throw new Error("timed out waiting for condition");
};

export const click = async (element) => {
  await act(async () => {
    dispatchClick(element);
  });
};

// Raw click dispatch, for use inside an existing `act` block.
export const dispatchClick = (element) =>
  element.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

// Set an input's value through the native setter so React sees the change.
export const setInputValue = (input, value) => {
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
  setter.call(input, value);
  input.dispatchEvent(new window.Event("input", { bubbles: true }));
};

// Render a component into a fresh (or given) container and flush the initial
// effects. Returns the container.
export const mount = async (component, props, container = document.createElement("div")) => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  if (!container.parentNode) {
    document.body.appendChild(container);
  }
  const root = createRoot(container);
  await act(async () => {
    root.render(React.createElement(component, props));
  });
  return container;
};

// Server-render a SchemaForm, for markup assertions.
export const renderSchemaForm = (schema, value, onChange = () => {}) =>
  renderToString(
    React.createElement(SchemaForm.make, {
      schema,
      value,
      onChange,
      onValidityChange: () => {},
    }),
  );

export const mountSchemaForm = (schema, value, onChange = () => {}) =>
  mount(SchemaForm.make, { schema, value, onChange, onValidityChange: () => {} });

export const jsonResponse = (result, status = 200) =>
  new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const encoder = new TextEncoder();

export const sseBody = (chunks) =>
  new ReadableStream({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(encoder.encode(chunk));
      }
      controller.close();
    },
  });

export const sseResponse = (chunks) =>
  new Response(sseBody(chunks), {
    status: 200,
    headers: { "Content-Type": "text/event-stream" },
  });
