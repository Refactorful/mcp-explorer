# MCP Tool & Prompt Viewer — Implementation Plan (ReScript + React)

A same-origin, offline-capable single-page viewer for an Oxygen MCP server. It
discovers and renders **tools** and **prompts**, and can invoke them. The client
is written in **ReScript + React** so the entire MCP wire protocol is strongly
typed and decode errors are caught at the boundary instead of at render time.

---

## 1. Summary

- **What:** a static SPA that talks JSON-RPC to Oxygen's `POST /mcp` endpoint.
- **Where it runs:** served by the same Oxygen server (no CORS, no proxy, no CDN).
- **How it ships:** compiled to a single self-contained HTML bundle vendored under
  `bundle/mcpexplorer/`, following the existing `data/dashboard` and Swagger/Redoc
  precedent (`src/autodoc.jl`, `src/core.jl:937-981`).
- **Why ReScript:** the protocol (method names, required headers, `_meta`, result
  shapes, content-block variants) becomes a set of types with total decoders; the
  runtime can't hand an `undefined` to a component.

---

## 2. Goals / non-goals

### Goals

- Typed, reusable MCP client layer covering `server/discover`, `tools/list`,
  `tools/call`, `prompts/list`, `prompts/get`.
- Tool viewer: list, description, JSON-Schema inspector, "Try it" execution with
  defaults generated from the schema, cURL export.
- Prompt viewer: list, argument form, rendered messages, raw JSON.
- Single-file, minified, offline bundle; no external network at runtime.
- Respects Oxygen's `prefix`, `docspath`, and `mcp_path`.

### Non-goals

- Resources, resource templates, subscriptions.
- Sampling / elicitation / notifications.
- OAuth or bearer-token auth UI (same-origin dev tool).
- MCP-UI / OpenAI Apps SDK widget rendering.
- Legacy (initialize-handshake) protocol era — modern `2026-07-28` only.

---

## 3. Stack & versions

| Concern | Choice | Notes |
| --- | --- | --- |
| Language | ReScript `12.x` | v12 stdlib ships with compiler; `JSON`, `dict{}` patterns built in |
| UI | React `19.2` + `@rescript/react` `0.15.x` | 0.15 requires ReScript 12 + React 19; uncurried mode only |
| HTTP | `@glennsl/rescript-fetch` | Zero-cost WHATWG fetch bindings, ReScript 12-ready |
| Bundler | Vite + `vite-plugin-singlefile` | Emits one HTML with JS/CSS inlined |
| ReScript↔Vite | `@jihchi/vite-plugin-rescript` | Starts compiler, HMR overlay, `.res` imports |
| Tests | Vitest (or `rescript-vitest`) | Decoder + client unit tests |
| Package manager | npm | matches `data/` asset workflow |

Pin the matrix exactly; `@rescript/react` majors track React/ReScript versions
and are the most common source of setup breakage.

---

## 4. Architecture

```
Browser (offline, same-origin)
  GET {docspath}/mcp  ──► bundle/mcpexplorer/index.html (inlined JS/CSS)
        │
        │  POST {prefix}{mcp_path}   JSON-RPC 2.0 (modern 2026-07-28)
        ▼
  Oxygen MCP engine  (src/mcp.jl, src/mcp/*.jl)
        │  server/discover · tools/list · tools/call · prompts/list · prompts/get
        ▼
  registered tools / prompts
```

No proxy. The endpoint is injected at serve time so custom `prefix`/`mcp_path`
work without rebuilding.

---

## 5. Strongly typed MCP API (centerpiece)

The client is split so the untyped JSON only exists inside `Codec.res`. Every
public function returns a typed `result` and never leaks `JSON.t` except for
`inputSchema`/`structuredContent` (which are intentionally arbitrary).

### 5.1 Module layout

```
src/api/
  Protocol.res   # types: method, contentBlock, tool, prompt, results, errors
  Codec.res      # decode/encode combinators + total decoders for each shape
  Mcp.res        # transport: typed client surface over fetch
  Schema.res     # JSON-Schema helpers: defaultsFromSchema, requiredFields
```

### 5.2 Protocol types (`Protocol.res`)

```rescript
type method =
  | Discover
  | ToolsList
  | ToolsCall
  | PromptsList
  | PromptsGet

let wire = method =>
  switch method {
  | Discover => "server/discover"
  | ToolsList => "tools/list"
  | ToolsCall => "tools/call"
  | PromptsList => "prompts/list"
  | PromptsGet => "prompts/get"
  }

// --- content blocks (mirror MCP_CONTENT_TYPES in serialization.jl:255) ---
type media = {data: string, mimeType: string}

type contentBlock =
  | Text(string)
  | Image(media)
  | Audio(media)
  | ResourceLink(JSON.t) // pass-through: {uri, name?, mimeType?, ...}
  | Resource(JSON.t)     // {uri, mimeType?, blob?}
  | Unknown(JSON.t)

// --- discovery ---
type capabilities = {tools: bool, prompts: bool}
type discoverResult = {
  supportedVersions: array<string>,
  capabilities: capabilities,
  instructions: option<string>,
}

// --- tools (tools_list, tools.jl:250) ---
type tool = {
  name: string,
  description: option<string>,
  inputSchema: JSON.t, // intentionally untyped
}

// --- prompts (prompts_list, prompts.jl:117) ---
type promptArgument = {name: string, required: bool}
type prompt = {
  name: string,
  description: option<string>,
  arguments: array<promptArgument>,
}

type role = User | Assistant
type promptMessage = {role: role, content: contentBlock}
type promptResult = {messages: array<promptMessage>, description: option<string>}

// --- tool calls (toolresult, serialization.jl:342) ---
type callResult = {
  content: array<contentBlock>,
  structuredContent: option<JSON.t>,
  isError: bool,
}

// --- errors ---
type jsonRpcError = {code: int, message: string, data: option<JSON.t>}

type apiError =
  | Transport(string)          // fetch/network failure
  | Http(int, string)          // non-2xx
  | ProtocolMismatch(string)   // malformed JSON-RPC envelope
  | JsonRpc(jsonRpcError)      // {error: ...}
  | Decode(string)             // typed decode failure (path + reason)
```

### 5.3 Codecs (`Codec.res`)

A tiny combinator set keeps decoders readable and produces good error paths:

```rescript
type t<'a> = (JSON.t, string) => result<'a, string>

let field: (dict<JSON.t>, string, t<'a>) => result<'a, string>
let optField: (dict<JSON.t>, string, t<'a>) => result<option<'a>, string>
let array: t<'a> => t<array<'a>>
let string: t<string>
let bool: t<bool>
let int: t<int>
let object: t<dict<JSON.t>>
let unknown: t<JSON.t> // identity, for inputSchema / structuredContent
```

Decoders own the wire quirks:

- `inputSchema` → `unknown` (never parsed by the client).
- Content block dispatch on the `"type"` discriminator; unknown types become
  `Unknown(json)` rather than failing the whole call (forward-compatible).
- Envelope decoder returns `ProtocolMismatch` when neither `result` nor `error`
  is present, and `JsonRpc` when `error` is.

Alternative if the combinator layer proves heavy: ReScript 12's native
`dict{}` pattern match, e.g.

```rescript
switch body {
| JSON.Object(dict{"result": JSON.Object(dict{"tools": JSON.Array(tools)})}) => ...
| JSON.Object(dict{"error": err}) => ...
| _ => Error(ProtocolMismatch("unrecognized tools/list response"))
}
```

### 5.4 Typed client surface (`Mcp.res`)

```rescript
type t = {endpoint: string, clientName: string, clientVersion: string}

let make: (~endpoint: string, ~clientName: string=?, ~clientVersion: string=?) => t

let discover: t => promise<result<discoverResult, apiError>>
let listTools: t => promise<result<array<tool>, apiError>>
let callTool: (t, ~name: string, ~arguments: JSON.t) => promise<result<callResult, apiError>>
let listPrompts: t => promise<result<array<prompt>, apiError>>
let getPrompt: (t, ~name: string, ~arguments: dict<string>) => promise<result<promptResult, apiError>>
```

`~name` is a labelled argument only where the protocol requires `Mcp-Name`
(`ToolsCall`, `PromptsGet`), so the illegal "list with a name" state cannot be
expressed. Header construction is derived from the `method` variant, making it
impossible to send a body method and a `Mcp-Method` header that disagree (a
`400` from the server, `src/mcp/errors.jl:158`).

Internal request builder:

```rescript
let envelope: (~id: int, ~method: Protocol.method, ~name: option<string>, JSON.t) => JSON.t
let headersFor: Protocol.method => array<(string, string)>
```

Headers (exact, verified against `src/mcp/errors.jl:155-160` and `mcp.md`):

```
Content-Type: application/json
Accept: application/json, text/event-stream
MCP-Protocol-Version: 2026-07-28
Mcp-Method: <method-string>
Mcp-Name: <name>          # only tools/call, prompts/get
```

Request `params._meta`:

```json
{
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
  "io.modelcontextprotocol/clientInfo": { "name": "<clientName>", "version": "<clientVersion>" }
}
```

### 5.5 Type-safety checklist (what this buys)

- The wire method string is derived from a variant; header/body can't drift.
- `Mcp-Name` presence is enforced by the function signature, not by convention.
- Every result is `result<_, apiError>`; components pattern-match instead of
  optional-chaining into potential `undefined`.
- Content blocks are a closed variant with an explicit `Unknown` escape hatch.
- `inputSchema`/`structuredContent` remain `JSON.t` by design and are only ever
  stringified for display.

---

## 6. Wire contract (verified against source)

One `POST` per request; the server replies with a single JSON object (not SSE).
`GET`/`DELETE` on the endpoint return `405` in the modern era.

| Method | Params | `result` shape | Source |
| --- | --- | --- | --- |
| `server/discover` | `_meta` | `{supportedVersions, capabilities, instructions?}` | `src/mcp.jl:100` |
| `tools/list` | `_meta` | `{tools:[{name,description,inputSchema}]}` | `src/mcp/tools.jl:250` |
| `tools/call` | `name`, `arguments` | `{content,structuredContent?,isError}` + envelope | `src/mcp/tools.jl:268` |
| `prompts/list` | `_meta` | `{prompts:[{name,description,arguments}]}` | `src/mcp/prompts.jl:117` |
| `prompts/get` | `name`, `arguments` | `{messages,description?}` + envelope | `src/mcp/prompts.jl:135` |

Modern results carry `resultType:"complete"` and
`_meta["io.modelcontextprotocol/serverInfo"]` (`modern_envelope`,
`serialization.jl:370`); the client ignores both but should not choke if present.

---

## 7. UI (React components)

```
src/
  Main.res            # ReactDOM.Client.createRoot mount
  App.res             # tab shell + discovery state
  state/
    useDiscovery.res  # load discover + tools + prompts; loading/error
  components/
    ConfigBar.res     # endpoint (injected default), refresh, exec toggle
    Tabs.res
    ToolList.res
    ToolDetail.res    # schema + try-it
    PromptList.res
    PromptDetail.res  # args + rendered messages
    SchemaView.res    # pretty JSON
    JsonEditor.res    # controlled textarea with parse error
    ResultView.res    # tabs: Result | Raw; cURL export
    ContentView.res   # contentBlock -> DOM (text/img/audio/resource)
```

State stays local: `useState`/`useReducer` for discovery results, selected item,
editor text, and last call result. No global store needed. Each `.res` component
gets a `.resi` exporting only the component so Vite Fast Refresh works.

UX notes:

- Prompts tab hidden when `discoverResult.capabilities.prompts == false`.
- Tool execution behind a toggle (dev default on); the plan is a dev tool, but
  destructive tools with the server's privileges warrant an explicit opt-in.
- `ToolDetail` pre-fills the editor from `inputSchema` and lists required fields.
- `ContentView` renders `text` as preformatted, `image`/`audio` as
  `data:<mimeType>;base64,...`, and `resource`/`resource_link` as JSON.

---

## 8. Build & bundle

`rescript.json`:

```json
{
  "name": "oxygen-mcp-explorer",
  "sources": [{ "dir": "src", "subdirs": true }],
  "package-specs": [{ "module": "esmodule", "in-source": true }],
  "suffix": ".res.mjs",
  "jsx": { "version": 4 },
  "bs-dependencies": ["@rescript/react", "@glennsl/rescript-fetch"]
}
```

- Dev: `rescript build -w` + `vite` (via `@jihchi/vite-plugin-rescript`).
- Prod: `vite build` with `vite-plugin-singlefile` → one `index.html`.
- Copy output to `bundle/mcpexplorer/index.html`.

Offline guarantee: no CDN, no external fonts; everything inlined. Verify by
opening the built file with the network disabled.

---

## 9. Oxygen integration

Follows the Swagger/Redoc + dashboard patterns.

1. **Vendor:** commit `bundle/mcpexplorer/index.html`.
2. **Constants:** add `MCP_EXPLORER_VERSION = "mcpexplorer"` (or reuse the literal)
   in `src/constants.jl`.
3. **Render helper:** add `mcpexplorerhtml(mcp_endpoint)` in a new
   `src/mcpexplorer.jl` (or `src/autodoc.jl`), modeled on `swaggerhtml`
   (`autodoc.jl:830`):

   ```julia
   function mcpexplorerhtml(endpoint::String)::HTTP.Response
       page = readstaticfile("mcpexplorer/index.html")
       config = JSON.json(Dict("endpoint" => endpoint))
       page = replace(page, "/*__MCP_CONFIG__*/null", "/*__MCP_CONFIG__*/$config")
       return html(page)
   end
   ```

4. **Route:** in `setupdocs` (`src/core.jl:937`), register
   `register_internal(ctx, router, "GET", "$docspath/mcp", () -> mcpexplorerhtml(join_url_path(ctx.service.prefix[], mcp_path)))`.
   Route is mounted only when the MCP endpoint is mounted.
5. **Injection:** the bundle ships with
   `<script>window.__OXYGEN_MCP__ = /*__MCP_CONFIG__*/null;</script>` and starts
   with `/mcp`; serve-time replacement supplies the real prefixed path.

The same built `index.html` can optionally be copied to `docs/mcp/` for the
static docs site; the injected config there would point at whatever origin the
reader runs.

---

## 10. File layout

```
viewer/
  PLAN.md
  package.json
  rescript.json
  vite.config.js
  index.html
  src/
    Main.res
    App.res
    api/{Protocol,Codec,Mcp,Schema}.res
    state/useDiscovery.res
    components/{ConfigBar,Tabs,ToolList,ToolDetail,PromptList,PromptDetail,SchemaView,JsonEditor,ResultView,ContentView}.res
    styles.css
  test/{Codec_test.res,Mcp_test.res}
bundle/mcpexplorer/index.html          # committed build artifact
src/mcpexplorer.jl                   # mcpexplorerhtml() + route wiring
```

---

## 11. Phases & acceptance criteria

| Phase | Work | Acceptance |
| --- | --- | --- |
| 0 | Lock versions, scaffold ReScript+React+Vite | `npm run build` emits a runnable page |
| 1 | `Protocol.res` + `Codec.res` + unit tests | Decoders round-trip fixtures for all five methods; unknown content block → `Unknown` |
| 2 | `Mcp.res` transport | Live `server/discover` + `tools/list` against a demo server; header/body method match asserted in tests |
| 3 | Shell + discovery state + tabs | Tools and Prompts populate; Prompts tab capability-gated |
| 4 | Tool viewer + try-it | Object-arg tool executes end-to-end; error results render as errors; cURL export correct |
| 5 | Prompt viewer | Multi-message prompt renders; required args enforced |
| 6 | Single-file bundle + Oxygen route + injection | `GET /docs/mcp` serves it; default endpoint hits `/mcp`; honors `prefix`/`mcp_path` |
| 7 | Tests + docs | Julia route test passes; `viewer/README.md` rebuild instructions; MCP tutorial section |

---

## 12. Testing

- **ReScript unit tests** (`rescript-vitest` or Vitest over compiled `.res.mjs`):
  - `Codec`: each decoder against captured fixtures, including malformed input.
  - `Mcp.headersFor`: `Mcp-Name` only for call/get; method string matches body.
  - `Schema.defaultsFromSchema`: strings/numbers/booleans/arrays/objects/enums,
    graceful `{}` for exotic schemas.
- **Julia integration** (`test/mcptests.jl`): `GET /docs/mcp` → `200 text/html`;
  body contains the bundle marker; injected endpoint equals
  `prefix + mcp_path` for parametrized prefix/path combinations.
- **Drift check (optional CI):** rebuild the bundle and assert the committed
  `bundle/mcpexplorer/index.html` is byte-identical to source output.
- **Manual E2E:** run `demo/` MCP server, load viewer, exercise a tool and a
  prompt.

---

## 13. Risks / mitigations

| Risk | Mitigation |
| --- | --- |
| `@rescript/react` / ReScript / React version mismatch | Pin exact versions; lock in `package.json`; document the matrix in `viewer/README.md` |
| Decoder/combinator weight | Start with native `dict{}` patterns; add the combinator module only if decoders get repetitive |
| Arbitrary `inputSchema` (including `$defs`) | Treat as `JSON.t`; `Schema.defaultsFromSchema` best-effort with `{}` fallback |
| Large media content blocks | Render images/audio lazily; avoid inlining huge blobs into React state more than once |
| Committed bundle drift | Rebuild script + optional CI drift check |
| Viewer can invoke privileged tools | Exec toggle default-off in production builds; document; recommend mounting only in dev |
| Fast Refresh disabled by extra exports | `.resi` per component exporting only the component |

---

## 14. Effort

| Area | Estimate |
| --- | --- |
| 0 scaffold + version pinning | 1–2 h |
| 1–2 typed API + transport | 4–5 h |
| 3–5 UI (tools + prompts) | 5–7 h |
| 6 bundle + Oxygen integration | 2–3 h |
| 7 tests + docs | 3–4 h |
| **Total** | **~2.5–3 days** |

---

## 15. Open decisions

1. **Exec toggle default:** on (dev convenience) vs off (safe-by-default).
2. **Route name:** `{docspath}/mcp` vs a dedicated `{docspath}/mcp-explorer`.
3. **Docs mirror:** also copy the bundle into `docs/mcp/` for the static site?
4. **JSON layer:** native `dict{}` patterns vs a small combinator module vs
   `jzon`/`rescript-json-combinators` (check ReScript 12 compatibility first).
