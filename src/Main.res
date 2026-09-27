// Browser entry. Server-agnostic: the MCP endpoint is passed in explicitly, so
// there is no injected global to depend on.
//
//   window.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer" })
//   window.McpExplorer({ endpoint: "http://127.0.0.1:8080/mcp", domId: "root" })
//   window.McpExplorer("/mcp")            // shorthand: first arg is the domId
//   window.McpExplorer.mount({ ... })     // same function
//
// Returns `{ unmount }` so callers can tear the explorer down.

%%raw(`import "./styles.css"`)

let normalizeConfig: 'config => {..} = %raw(`(function(config) {
  if (typeof config === "string") {
    return { domId: config, endpoint: "/mcp" };
  }
  var options = config || {};
  return {
    domId: options.domId || options.dom_id || "mcp-explorer",
    endpoint: options.endpoint || options.url || "/mcp",
  };
})`)

let getElement: string => 'element = %raw(`(function(id) {
  var el = document.getElementById(id);
  if (!el) {
    throw new Error("McpExplorer: no element with id '" + id + "'");
  }
  return el;
})`)

let mount = (config: 'config): {..} => {
  let normalized = normalizeConfig(config)
  let domId: string = normalized["domId"]
  let endpoint: string = normalized["endpoint"]
  let container = getElement(domId)
  let root = ReactDOM.Client.createRoot(container)
  ReactDOM.Client.Root.render(root, <App initialEndpoint=endpoint />)
  {"unmount": () => ReactDOM.Client.Root.unmount(root, ())}
}

let register: (string, 'a) => unit = %raw(`(function(name, value) {
  if (typeof window !== "undefined") {
    window[name] = value;
  }
})`)

// Make the function callable as `McpExplorer(config)` and also expose
// `McpExplorer.mount(config)`, like `SwaggerUIBundle`.
let withMountAlias: 'a => {..} = %raw(`(function(fn) { fn.mount = fn; return fn; })`)

let () = register("McpExplorer", withMountAlias(mount))
