// Browser entry. Server-agnostic: the MCP endpoint is passed in explicitly, so
// there is no injected global to depend on.
//
//   window.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer" })
//   window.McpExplorer({ endpoint: "http://127.0.0.1:8080/mcp", domId: "root" })
//   window.McpExplorer({ endpoint: "/mcp", execEnabled: true })
//   window.McpExplorer({ endpoint: "/mcp", endpointEditable: false })
//   window.McpExplorer("/mcp")            // shorthand: first arg is the domId
//   window.McpExplorer.mount({ ... })     // same function
//
// `execEnabled` (optional boolean) turns tool execution on or off for this
// mount. When omitted the build-time default is used (on in `vite dev`, off in
// production). It is fixed for the lifetime of the mount.
//
// `endpointEditable` (optional boolean) controls whether the endpoint field in
// the toolbar can be edited. Defaults to `true`.
// Returns `{ unmount }` so callers can tear the explorer down.

%%raw(`import "./styles.css"`)

let normalizeConfig: 'config => {..} = %raw(`(function(config) {
  if (typeof config === "string") {
    return { domId: config, endpoint: "/mcp", execEnabled: undefined, endpointEditable: undefined };
  }
  var options = config || {};
  return {
    domId: options.domId || options.dom_id || "mcp-explorer",
    endpoint: options.endpoint || options.url || "/mcp",
    execEnabled: typeof options.execEnabled === "boolean" ? options.execEnabled : undefined,
    endpointEditable:
      typeof options.endpointEditable === "boolean" ? options.endpointEditable : undefined,
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
  // `None` when the caller omitted `execEnabled`; App falls back to the
  // build-time default.
  let initialExecEnabled: option<bool> = normalized["execEnabled"]
  // `None` when the caller omitted `endpointEditable`; App defaults to editable.
  let initialEndpointEditable: option<bool> = normalized["endpointEditable"]
  let container = getElement(domId)
  let root = ReactDOM.Client.createRoot(container)
  ReactDOM.Client.Root.render(
    root,
    <App initialEndpoint=endpoint initialExecEnabled initialEndpointEditable />,
  )
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
