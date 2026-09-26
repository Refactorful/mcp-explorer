// @vitest-environment jsdom
import { describe, test, expect } from "vitest";
import * as Curl from "../src/Curl.res.mjs";

describe("Curl", () => {
  test("resolves a relative endpoint against the page origin", () => {
    const command = Curl.forToolCall("/mcp", "greet", "{}");
    expect(command).toContain(`${window.location.origin}/mcp`);
    expect(command).toContain("Mcp-Name: greet");
  });

  test("leaves an absolute endpoint untouched", () => {
    const command = Curl.forToolCall("http://127.0.0.1:8080/mcp", "greet", "{}");
    expect(command).toContain("http://127.0.0.1:8080/mcp");
  });
});
