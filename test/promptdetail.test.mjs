// @vitest-environment jsdom
import { describe, test, expect, vi } from "vitest";
import { act } from "react";
import * as PromptDetail from "../src/components/PromptDetail.res.mjs";
import { click, jsonResponse, mount, setInputValue, waitFor } from "./helpers.mjs";

const prompt = {
  name: "trip_plan",
  description: "Plan a trip to a place",
  arguments: [
    { name: "place", required: true },
    { name: "days", required: false },
  ],
};

const result = {
  description: "Plan a trip to a place",
  messages: [
    {
      role: "user",
      content: { type: "text", text: "Plan a 3-day trip to Kyoto." },
    },
  ],
};

const props = (overrides = {}) => ({
  prompt,
  endpoint: "/mcp",
  reopen: undefined,
  onBack: () => {},
  ...overrides,
});

const runButton = (container) =>
  [...container.querySelectorAll("button")].find((button) =>
    button.textContent.includes("Get prompt"),
  );

describe("PromptDetail", () => {
  test("sends required arguments and omits blank optional ones", async () => {
    let body = null;
    globalThis.fetch = vi.fn(async (_url, init) => {
      body = JSON.parse(init.body);
      return jsonResponse(result);
    });

    const container = await mount(PromptDetail.make, props());
    const inputs = container.querySelectorAll("input.text-input");
    expect(inputs.length).toBe(2);

    await act(async () => {
      setInputValue(inputs[0], "Kyoto");
    });
    await click(runButton(container));

    await waitFor(() => body !== null);
    expect(body.method).toBe("prompts/get");
    expect(body.params.name).toBe("trip_plan");
    expect(body.params.arguments).toEqual({ place: "Kyoto" });
    expect("days" in body.params.arguments).toBe(false);

    await waitFor(() => container.querySelector(".content-text") !== null);
    expect(container.querySelector(".content-text").textContent).toBe(
      "Plan a 3-day trip to Kyoto.",
    );
    expect(container.querySelector(".message-role").textContent).toBe("user");
  });

  test("disables the run button until required arguments are filled", async () => {
    globalThis.fetch = vi.fn(async () => jsonResponse(result));

    const container = await mount(PromptDetail.make, props());
    expect(runButton(container).disabled).toBe(true);

    const inputs = container.querySelectorAll("input.text-input");
    // Whitespace-only input does not count as a value.
    await act(async () => {
      setInputValue(inputs[0], "   ");
    });
    expect(runButton(container).disabled).toBe(true);

    await act(async () => {
      setInputValue(inputs[0], "Kyoto");
    });
    expect(runButton(container).disabled).toBe(false);
  });

  test("seeds argument values when reopening a logged prompts/get", async () => {
    let body = null;
    globalThis.fetch = vi.fn(async (_url, init) => {
      body = JSON.parse(init.body);
      return jsonResponse(result);
    });

    const container = await mount(
      PromptDetail.make,
      props({
        reopen: {
          nonce: 1,
          message: {
            method: "PromptsGet",
            name: "trip_plan",
            params: { name: "trip_plan", arguments: { place: "Osaka", days: "2" } },
          },
        },
      }),
    );

    const inputs = container.querySelectorAll("input.text-input");
    expect(inputs[0].value).toBe("Osaka");
    expect(inputs[1].value).toBe("2");

    await click(runButton(container));
    await waitFor(() => body !== null);
    expect(body.params.arguments).toEqual({ place: "Osaka", days: "2" });
  });
});
