// Guards the hand-written declaration file (assets/react.d.ts) against drifting
// from the two things it describes:
//
//   * the compiled component module (src/Embed.res.mjs), whose named exports
//     must all be declared
//   * the `export { make as McpExplorer };` footer in vite.embed.config.js,
//     which is what the published react.js actually exposes
import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import * as Embed from "../src/Embed.res.mjs";

const dts = readFileSync(new URL("../assets/react.d.ts", import.meta.url), "utf8");
const viteConfig = readFileSync(new URL("../vite.embed.config.js", import.meta.url), "utf8");

const declaredValueNames = (source) =>
  [...source.matchAll(/^export (?:declare )?const ([A-Za-z_$][\w$]*)/gm)].map((match) => match[1]);

describe("embed type declarations", () => {
  test("declares exactly the exported component names", () => {
    const footerAlias = viteConfig.match(/export\s*\{\s*make\s+as\s+([A-Za-z_$][\w$]*)\s*\}/);
    expect(footerAlias).not.toBeNull();
    const expected = new Set([...Object.keys(Embed), footerAlias[1]]);
    expect(new Set(declaredValueNames(dts))).toEqual(expected);
  });

  test("declares the props the runtime honors", () => {
    for (const prop of ["endpoint", "execEnabled", "endpointEditable", "className"]) {
      expect(dts).toContain(`${prop}?:`);
    }
  });

  test("stays self-contained and typed against react", () => {
    expect(dts).toContain('from "react"');
    expect(dts).not.toContain(".res.mjs");
  });
});
