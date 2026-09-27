# MCP Explorer

A same-origin, offline-capable single-page viewer for **any MCP server**. It
discovers and renders **tools** and **prompts** and can invoke them. The client
is written in **ReScript + React**, so the whole MCP wire protocol is strongly
typed and malformed payloads are rejected at the decoding boundary instead of at
render time.

It has no dependency on Oxygen (or any host): you pass the MCP endpoint in when
you mount it. [Oxygen](https://github.com/oxygenframework/Oxygen.jl) is one
supported host and gets a ready-made integration snippet.

The distribution builds two artifacts:

| Artifact | Purpose |
| --- | --- |
| `bundle/mcpexplorer/mcpexplorer.js` + `mcpexplorer.css` | Self-contained IIFE exposing the `window.McpExplorer` function. This is the swagger-style integration. |
| `bundle/mcpexplorer/index.html` | A standalone single-file page that mounts itself (handy for direct serving/debugging). |

## What it does

- Talks JSON-RPC 2.0 to the configured MCP endpoint using the modern
  `2026-07-28` protocol era (no initialize handshake).
- Discovers capabilities via `server/discover`, then loads `tools/list` and
  (when advertised) `prompts/list`.
- **Tool viewer:** name/description, a collapsible JSON-Schema inspector
  (collapsed by default), a schema-driven "Try it" form, a `Result`/`Raw`/`cURL`
  view.
- **Schema-driven form:** one typed control per input — `enum` (and `const`)
  becomes a `<select>` of valid options, `boolean` a checkbox,
  `integer`/`number` a validated numeric input, `string` a text input.
  Containers recurse rather than falling back to raw JSON:
  - nested objects (resolving `$ref`/`$defs`) render their fields, including
    `allOf` merged into a single schema;
  - `additionalProperties` / `patternProperties` render a dynamic key/value
    editor (add/rename/remove rows, values typed from the value schema and
    pre-filled with its defaults), and can sit alongside declared `properties`;
  - arrays (singular or tuple `items`/`prefixItems`) render a dynamic list with
    add/remove/reorder and `minItems`/`maxItems` enforcement;
  - `oneOf`/`anyOf` render a branch selector (honouring `discriminator`);
  - `type` unions (e.g. `["string","null"]`) use their non-null control.
  Defaults are pre-filled and `required` fields are enforced by native form
  validation. A `JSON` toggle exposes the raw arguments. If a schema's `default`
  disagrees with its declared `type` (e.g. `"[]"` for an array), the value is
  coerced to the declared type so requests stay valid.
- **Prompt viewer:** argument form with required-field enforcement, rendered
  messages, and a raw JSON view.
- **Navigation:** master–detail split view — the list stays pinned while the
  selected tool/prompt renders beside it, the selection is reflected in history
  so browser back/forward work, and narrow screens collapse to a single pane
  with a back control.
- Prompts tab is hidden when the server does not advertise the capability.
- Execution is behind a toolbar toggle: **on in `vite dev`, off in production
  bundles**.

## Global mount API (swagger-style)

The distribution is an IIFE that registers a top-level global function. It takes
a config object (like `SwaggerUIBundle({ ... })`) and returns an `{ unmount }`
handle:

```js
const viewer = window.McpExplorer({
  endpoint: "http://127.0.0.1:8080/mcp", // or a same-origin path like "/mcp"
  domId: "mcp-explorer",
});
// viewer.unmount();
```

`domId` is the id of an empty container element; `endpoint` is the MCP URL to
call. `dom_id`/`url` are accepted as aliases, `domId` defaults to `"mcp-explorer"`
and `endpoint` defaults to `"/mcp"`. `window.McpExplorer.mount(config)` is the
same function, and `window.McpExplorer("/mcp")` is a shorthand where the string is
the `domId`.

```html
<div id="mcp-explorer"></div>
<script src="/docs/mcp/mcpexplorer.js"></script>
<link rel="stylesheet" href="/docs/mcp/mcpexplorer.css" />
<script>
  window.McpExplorer({ endpoint: "/mcp", domId: "mcp-explorer" });
</script>
```

A minimal Oxygen helper that mirrors `swaggerhtml` lives in
[`integrations/oxygen/mcpexplorer.jl`](integrations/oxygen/mcpexplorer.jl):

```julia
function mcpexplorerhtml(endpoint::String) :: HTTP.Response
    viewerjs = readstaticfile("mcpexplorer/mcpexplorer.js")
    viewerstyles = readstaticfile("mcpexplorer/mcpexplorer.css")

    html("""
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>MCP Explorer</title>
            <style>$viewerstyles</style>
        </head>
        <body>
            <div id="mcp-explorer"></div>
            <script>$viewerjs</script>
            <script>
                window.McpExplorer({ endpoint: "$endpoint", domId: "mcp-explorer" });
            </script>
        </body>
        </html>
    """)
end
```

Mount it only when the MCP endpoint is mounted:

```julia
register_internal(
    ctx,
    router,
    "GET",
    "$docspath/mcp",
    () -> mcpexplorerhtml(join_url_path(ctx.service.prefix[], mcp_path)),
)
```

### Standalone page

`index.html` mounts itself by calling the same API with an explicit endpoint:

```html
<div id="root"></div>
<script type="module" src="/src/Main.res.mjs"></script>
<script>
  window.McpExplorer({ endpoint: "/mcp", domId: "root" });
</script>
```

Edit the `endpoint` there (or override it in the toolbar) to point at another
server. There is no injected global to configure.

## Quick start

Requires Node 20+ (developed against Node 26).

```sh
npm install

# Dev server with the ReScript compiler in watch mode
npm run res:watch      # terminal 1
npm run dev            # terminal 2

# Production artifacts -> bundle/mcpexplorer/{mcpexplorer.js,mcpexplorer.css,index.html}
npm run bundle

# Unit tests (Vitest + an SSR smoke test)
npm test

# Live smoke test against a running MCP server
npm run validate:live
MCP_ENDPOINT=http://127.0.0.1:8080/mcp npm run validate:live
```

`npm run dev` serves the viewer and proxies `/mcp` to the MCP backend, so the
default relative endpoint works in the browser without CORS. The proxy also
strips the browser `Origin` header, which Oxygen otherwise rejects with `403`.
Keep the endpoint as the relative `/mcp`; an absolute
`http://127.0.0.1:8080/mcp` bypasses the proxy and will fail as a cross-origin
request. The target defaults to `http://127.0.0.1:8080`; override it with:

```sh
MCP_DEV_TARGET=http://127.0.0.1:9090 npm run dev
```

`npm run validate:live` exercises the same compiled transport directly from Node
(no proxy) and is useful in CI.

## Module layout

```
src/
  Main.res                 browser entry: window.McpExplorer({ ... }) mount API
  App.res                  tab shell + discovery state
  Config.res               build-time dev/prod exec default
  Curl.res                 cURL export
  History.res              in-app navigation (History API bindings)
  UseDiscovery.res         discover + tools + prompts loading hook
  api/
    Protocol.res           wire types, content blocks, apiError, encoders
    Codec.res              total decoders with error paths
    Mcp.res                typed transport over fetch
    Schema.res             JSON-Schema defaults + required fields
  JsonValue.res            keyed JSON get/set/remove (immutable updates)
  components/
    ConfigBar.res  Tabs.res  ToolList.res  ToolDetail.res
    SchemaForm.res  JsonControl.res
    PromptList.res PromptDetail.res  SchemaView.res  JsonEditor.res
    ResultView.res ContentView.res
  styles.css
test/
  Codec_test.res  Schema_test.res  Mcp_test.res  Vitest.res
  app.smoke.test.mjs  app.navigation.test.mjs  main.mount.test.mjs
  schemaform.test.mjs  tooldetail.form.test.mjs  curl.test.mjs
scripts/
  copy-bundle.mjs          dist*/ -> bundle/mcpexplorer/
  validate-live.mjs        live transport smoke test
vite.config.js             single-file HTML build
vite.lib.config.js         IIFE global build
```

## Type-safety notes

- The wire method string is derived from a `Protocol.method` variant, so the
  `Mcp-Method` header and the body method cannot disagree.
- `Mcp-Name` is only produced for `tools/call` and `prompts/get`; the typed
  surface makes the illegal "list with a name" state unrepresentable.
- Every result is `result<_, Protocol.apiError>`; components pattern-match
  instead of optional-chaining into `undefined`.
- Content blocks are a closed variant with an explicit `Unknown` escape hatch,
  so a future block type does not fail the whole call.
- `inputSchema`/`structuredContent` stay `JSON.t` by design and are only
  stringified for display.

## Version matrix

These are pinned exactly because `@rescript/react` majors track React and
ReScript versions and are the most common setup breakage.

| Package | Version |
| --- | --- |
| `rescript` | 12.3.1 |
| `@rescript/react` | 0.15.0 |
| `react` / `react-dom` | 19.2.0 |
| `@glennsl/rescript-fetch` | 0.3.0 |
| `vite` | 8.3.1 |
| `vite-plugin-singlefile` | 2.3.3 |
| `vitest` | 5.0.2 |

## Testing

- **Unit (`npm test`)** — decoders against captured fixtures (including
  malformed and unknown content), schema defaults/`$ref` resolution, the
  `Mcp-Name`/method/`_meta` invariants, schema-form rendering (enums, typed
  inputs, nested `$ref`s, JSON fallback), the global mount API in a jsdom DOM,
  and an SSR render smoke test.
- **Live (`npm run validate:live`)** — runs `server/discover`, `tools/list`,
  and a `tools/call` against a running server through the compiled transport.
- **Manual** — load the built page from the same origin as the MCP server so
  no CORS proxy is involved.
