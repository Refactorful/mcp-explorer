// Live smoke test against a running Oxygen MCP server.
//
//   node scripts/validate-live.mjs
//   MCP_ENDPOINT=http://127.0.0.1:8080/mcp node scripts/validate-live.mjs
//
// This exercises the same compiled Mcp/Codec modules the browser bundle uses,
// so a pass here means the transport and decoders agree with the server.
import * as Mcp from "../src/api/Mcp.res.mjs";
import * as Protocol from "../src/api/Protocol.res.mjs";

const endpoint = process.env.MCP_ENDPOINT ?? "http://127.0.0.1:8080/mcp";
const client = Mcp.make(endpoint, "mcp-viewer-validator", "0.1.0");

let failures = 0;

const log = (label, value) => {
  console.log(`\n=== ${label} ===`);
  console.log(JSON.stringify(value, null, 2));
};

const expectOk = (label, result) => {
  if (result.TAG === "Ok") {
    log(label, result._0);
    return result._0;
  }
  failures += 1;
  console.error(`\n!!! ${label} FAILED: ${Protocol.apiErrorToString(result._0)}`);
  return null;
};

console.log(`Validating ${endpoint}`);

const discover = expectOk("server/discover", await Mcp.discover(client));

if (discover) {
  const tools = expectOk("tools/list", await Mcp.listTools(client));
  if (tools) {
    if (tools.some(tool => tool.name === "add")) {
      expectOk("tools/call add", await Mcp.callTool(client, "add", { a: 2, b: 3 }));
    } else {
      const first = tools[0];
      if (first) {
        log("tools/call first tool (no `add` registered)", first.name);
        expectOk(
          `tools/call ${first.name}`,
          await Mcp.callTool(client, first.name, {}),
        );
      }
    }
  }

  if (discover.capabilities.prompts) {
    expectOk("prompts/list", await Mcp.listPrompts(client));
  } else {
    console.log("\n(server advertises no prompts capability; skipping prompts/list)");
  }
}

if (failures > 0) {
  console.error(`\n${failures} live check(s) failed.`);
  process.exit(1);
}
console.log("\nAll live checks passed.");
