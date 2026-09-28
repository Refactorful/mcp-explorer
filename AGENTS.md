# AGENTS.md

Project notes for agents working in this repo. Read this before changing code.

## What this is

A same-origin, offline-capable single-page viewer for **any MCP server**
(ReScript + React). It discovers tools/prompts/resources, renders a
schema-driven "Try it" form, invokes tools, reads resources, and can be
embedded into any host page. It has **no host dependency**; the MCP endpoint is
passed in at mount time.

Three build artifacts are committed under `bundle/mcpexplorer/`:

- `mcpexplorer.js` + `mcpexplorer.css` — self-contained IIFE exposing the
  `window.McpExplorer` function (the embeddable integration).
- `index.html` — standalone single-file page that mounts itself.
- `icon.svg` — app icon (copied from `assets/icon-compass.svg`). The standalone
  page inlines it as a data-URI favicon via a Vite plugin in `vite.config.js`;
  hosts embedding the lib can reference the file themselves.

## Commands

```sh
npm install

npx rescript build                                  # typecheck + emit .res.mjs
npm run res:watch                                   # compiler in watch mode
npm run dev                                          # Vite dev server (proxies /mcp)
npm test                                             # rescript build + vitest
npm run validate:live                                # live transport smoke test
MCP_ENDPOINT=http://127.0.0.1:8080/mcp npm run validate:live

npm run bundle                                       # build both + copy to bundle/mcpexplorer
npx vite build --config vite.lib.config.js           # lib only
```

The dev MCP server used for validation is usually at
`http://127.0.0.1:8080/mcp`.

**Always run `npx rescript build` (or `npm test`) after editing `.res` files.**
Tests import the compiled `.res.mjs` files, not the sources.

## Layout

```
src/
  Main.res                 browser entry: window.McpExplorer({ ... }) mount API
  App.res                  tab shell + discovery state + master-detail split
  Config.res               build-time dev/prod exec default (__MCP_EXPLORER_DEV__)
  Curl.res                 cURL export (resolves relative endpoint to origin)
  History.res              in-app navigation (History API bindings)
  Message.res / MessageStore.res  transport message log + helpers
  Stream.res               SSE message type (notification/request/response)
  ResourceTemplate.res     RFC 6570 URI-template parsing/substitution helpers
  UseDiscovery.res         discover + tools + prompts + resources loading hook
  api/{Protocol,Codec,Mcp,Sse,Schema}.res
  JsonValue.res            keyed JSON get/set/remove (immutable updates)
  components/…             UI; one component per file (see React notes)
  styles.css
test/…                     *.res unit tests + *.test.mjs DOM/SSR tests
scripts/{copy-bundle,validate-live}.mjs
vite.config.js             single-file HTML build
vite.lib.config.js         IIFE global build
bundle/mcpexplorer/        committed build artifacts
```

`rescript.json`: `sources` = `src` + `test` (dev), `package-specs` esmodule
in-source, suffix `.res.mjs`, `jsx` v4, `dependencies` (NOT the deprecated
`bs-dependencies`).

## Pinned versions

Exact pins matter — `@rescript/react` majors track React and ReScript:

`rescript` 12.3.1 · `@rescript/react` 0.15.0 · `react`/`react-dom` 19.2.0 ·
`@glennsl/rescript-fetch` 0.3.0 · `vite` 8.3.1 ·
`vite-plugin-singlefile` 2.3.3 · `vitest` 5.0.2 · `jsdom` 27 (dev).

`@rescript/react` peer-depends on `@rescript/runtime`; it must be installed.

## ReScript 12 gotchas (learned the hard way)

- **`arr[i]` returns `option<'a>`**, not `'a`. Use `Array.getUnsafe(arr, i)`
  when the index is already bounds-checked, or `Array.get` otherwise.
- **Array patterns**: avoid `[first, ...rest]`. Index manually.
- **`Array.reverse` mutates and returns `unit`.** Do
  `acc->Array.reverse; Ok(acc)`, not `Ok(acc->Array.reverse)`.
- **`Array.join`**, not `Array.joinWith` (deprecated).
- **`Array.mapWithIndex` callback is `(value, index)`**, not `(index, value)`.
- There is **no `Option.toResult`, no `JSON.Decode.int`, no `JSON.Decode.field`**.
  Use `Float`/`Bool` decode + your own combinators.
- Functions with **optional args can't be passed as arity-1 functions**
  (`Option.map(JSON.stringify)` fails). Wrap: `Option.map(v => v->JSON.stringify)`.
- **Partial application is not allowed in uncurried mode.** Wrap a curried
  value: `let arrayOf = inner => (json, path) => array(inner, json, path)`.
- Operators bind tighter than `->`: `"Protocol " ++ version->React.string`
  parses as `"Protocol " ++ (version->React.string)`. Wrap the concat:
  `("Protocol " ++ version)->React.string`.
- `String.replaceAll`, `String.split`, `String.trim`, `String.startsWith` exist.
- `Int.fromFloat`, `Float.toInt`, `Float.fromString`, `Float.toString`,
  `Int.toString` exist.

### ReScript 12 JSON stdlib (what actually works here)

```rescript
JSON.parseOrThrow(text)                   // string -> JSON.t (throws)
JSON.stringify(json, ~space=2)            // pretty print
JSON.Decode.string / bool / float / null / object / array   // all option<_>
JSON.Encode.string / bool / int / float / null / object / array
type JSON.t = Object(dict<JSON.t>) | Array(array<JSON.t>) | String(...) | ...
Dict.make / get / set / toArray / fromArray / keysToArray   // set MUTATES
```

When unsure about a stdlib signature, grep the installed runtime sources, e.g.
`node_modules/@rescript/runtime/lib/ocaml/JsxDOM.res` (DOM/JSX prop types) and
`node_modules/@rescript/react/src/*.res`. The stdlib API docs live at
`rescript-lang.org/docs/manual/api/stdlib` (see the `json` subpage).

### Interop

Use `%raw` / `@val` for globals and DOM:

```rescript
let getElement: string => 'element = %raw(`(function(id) { ... })`)
@val external isDevBuild: bool = "__MCP_EXPLORER_DEV__"
@get external state: popStateEvent => nullable<{..}> = "state"
```

## React / JSX v4 gotchas

- **One `@react.component let make` per module.** Stateful controls must live in
  their own file (e.g. `JsonControl.res`); stateless render helpers can be plain
  functions returning `React.element` inside a bigger module.
- JSX prop arrow functions need braces: `onX={a => ...}` (bare `onX=a => ...`
  is a syntax error).
- `React.string/int/float/array/null` are the children constructors.
- Hooks: `useState`, `useEffect0/1/2` (deps tuple, e.g. `useEffect2(fn, (a,b))`),
  `useRef`, `act` (from `"react"` in tests). `useEffect` callbacks return
  `option<unit => unit>`.
- DOM prop types are in `JsxDOM.res`. Notably **`step?: float`** (you cannot pass
  `"any"`). For validated numeric inputs use `type_="text"` + `inputMode` +
  `pattern` instead of `type_="number"`.
- `.resi` files that export only `make` work with `@react.component` and keep
  Fast Refresh happy. Component modules here have a `.resi`; add one when you
  add a component.
- Prefer native `<details>/<summary>` (e.g. collapsible schema) and native
  `<form>` validation (`required`, `pattern`) over hand-rolled equivalents.

## Vite / bundling gotchas

- **Library mode does not replace `process.env.NODE_ENV`.** Without
  `define: { "process.env.NODE_ENV": JSON.stringify("production") }` in
  `vite.lib.config.js`, the full React **development** build (all the dev
  warnings) is bundled (609 KB vs 220 KB). Both define `__MCP_EXPLORER_DEV__`.
- The IIFE `build.lib.name` becomes a global `var`. Keep it **distinct** from
  the public global (`McpExplorerBundle` vs `McpExplorer`) so it cannot clobber the
  callable mount function.
- Exposing a callable global with a property (swagger-style):

  ```rescript
  let withMountAlias: 'a => {..} = %raw(`(function(fn){ fn.mount = fn; return fn; })`)
  register("McpExplorer", withMountAlias(mount))   // window.McpExplorer({...}) and .mount(...)
  ```

- **CSS must be imported from JS** (`%%raw("import \"./styles.css\"")` in
  `Main.res`), otherwise the lib build emits no CSS. The HTML build inlines it
  via `vite-plugin-singlefile`.
- `.gitignore` ignores `*.res.mjs`, `lib/`, `dist/`, `dist-lib/`. The committed
  artifacts are only under `bundle/mcpexplorer/`.

## Testing

- Vitest imports compiled `.res.mjs`. `vitest.config.js` sets
  `test.include: ["test/**/*_test.res.mjs", "test/**/*.test.mjs"]` and defines
  `__MCP_EXPLORER_DEV__`.
- `.res` unit tests use the bindings in `test/Vitest.res` (`describe`, `test`,
  `expect(...)->toBe/toEqual/toBeTruthy`).
- DOM tests use a per-file pragma `// @vitest-environment jsdom`, `act` from
  `"react"`, and `createRoot`. Mock `globalThis.fetch` with a `Response`.
- **Avoid single-tick assertions after async effects** — they're flaky. Poll:
  a `waitFor(predicate)` helper that loops `await flush()`.
- SSR smoke tests use `renderToString` from `react-dom/server`.

## MCP protocol contract (modern `2026-07-28` era)

- One `POST` per request to the endpoint. The server may reply either with a
  single JSON object **or** with a `text/event-stream` (SSE) stream
  (Streamable HTTP). `GET`/`DELETE` return `405`.
- **Streaming:** when the response `Content-Type` is `text/event-stream`,
  `Sse.read` decodes each `data:` frame and `Mcp.post` emits every non-final
  JSON-RPC message (notifications / server requests) through an optional
  `~onEvent` callback as it arrives; it resolves when the message whose `id`
  matches the request shows up. Servers that keep the stream open are handled
  (the reader is cancelled once the response arrives). A stream that closes with
  no matching response is a `ProtocolMismatch`. JSON responses still take the
  original single-body path. `ToolDetail` and `ResourceDetail` pass `onEvent`
  and render the events live in a shared `StreamLog` before the final result.
- `params._meta.progressToken` is set to the request id so servers emit
  `notifications/progress`. `Mcp.envelope` derives it from `~id`.
- Headers (exact):

  ```
  Content-Type: application/json
  Accept: application/json, text/event-stream
  MCP-Protocol-Version: 2026-07-28
  Mcp-Method: <method-string>
  Mcp-Name: <name>          # for tools/call, resources/read, prompts/get
  ```

- `Mcp-Name` mirrors `params.name` (`tools/call`, `prompts/get`) or `params.uri`
  (`resources/read`). `Mcp.encodeHeaderValue` passes plain ASCII values through
  and otherwise uses the spec's Base64 sentinel form `=?base64?{...}?=` (also
  for values that already look like the sentinel), so non-ASCII names/URIs are
  transmitted safely.

- `params._meta` is required on every request:
  `io.modelcontextprotocol/protocolVersion`, `.../clientCapabilities`,
  `.../clientInfo` (`{name, version}`). `Mcp.envelope` adds it and derives the
  method string from the `Protocol.method` variant, so body and headers can't
  drift.
- `server/discover` `capabilities` are **presence-based objects**
  (`{"tools":{}}`), not booleans. Decode by key presence.
- Response is `{result}` or `{error}` (`Codec.responseEnvelope`). Results carry
  `resultType:"complete"` and `_meta[.../serverInfo]`; the client ignores both
  but must not choke.
- Content blocks dispatch on `"type"`; **unknown types become `Unknown(json)`**
  (forward-compatible) rather than failing the call.
- Resources decode into typed records (`Codec.resourcesResult`,
  `resourceTemplatesResult`, `readResult`); unknown result metadata (`nextCursor`,
  `ttlMs`, `cacheScope`) is ignored. Resource subscriptions
  (`subscriptions/listen` → `notifications/resources/updated`) are not
  implemented; the Refresh button re-runs discovery instead.
- `inputSchema` is intentionally `JSON.t`; never assume its shape.

### Schema defaults quirk (real bug we fixed)

Servers can emit a **type-mismatched `default`** (e.g. `"default": "[]"` for a
`type: "array"` field) which a Julia server then rejects with
`convert(String, Vector{String})`. `Schema.coerceToType` coerces a `default` to
the declared type, parsing JSON-looking strings, so the viewer never sends an
invalid value. Keep that behavior.

## Dev server / CORS

- Many MCP hosts **reject cross-origin requests**: `OPTIONS` → `405`,
  `POST` with an `Origin` header → `403`.
- `vite.config.js` proxies `/mcp` to `MCP_DEV_TARGET`
  (default `http://127.0.0.1:8080`) and **strips the `Origin` header**. Keep the
  endpoint relative (`/mcp`) in dev; an absolute cross-origin URL bypasses the
  proxy and fails. On failure the UI shows a dev-only hint.
- `MCP_DEV_TARGET` / `MCP_DEV_PATH` override the proxy target/path.

## Distribution / mount API

- `window.McpExplorer({ endpoint, domId })` (aliases `url`, `dom_id`; defaults
  `"/mcp"`, `"mcp-explorer"`), returns `{ unmount }`. `window.McpExplorer.mount(...)`
  is the same function; `window.McpExplorer("/mcp")` uses the string as `domId`.
- No injected globals. The standalone `index.html` mounts itself by calling the
  same API; embedded hosts do `window.McpExplorer({ endpoint, domId })`.
- cURL export must be absolute: `Curl.absolute` prefixes `window.location.origin`
  for relative endpoints.

## UI conventions

- Master–detail split: list pinned left (sticky, own scroll), detail right.
  No back button on desktop; `.back-btn` appears only under 860px where the
  layout collapses. History is kept via `History.push/popstate`.
- Tool "Try it": schema-driven form (enum/const→select, boolean→checkbox,
  integer/number→pattern-validated text, nested objects recurse with `$ref` and
  `allOf` resolution, `additionalProperties`/`patternProperties` maps→dynamic
  key/value rows whose values are typed by the value schema (and can coexist
  with declared `properties`), arrays/tuples→dynamic list with add/remove/
  reorder, `oneOf`/`anyOf`→branch selector with optional discriminator, type
  unions use the non-null control; only unrecognised shapes fall back to the
  JSON editor), native `required`/`pattern` validation, Form/JSON toggle, Reset.
  Raw schema is a **collapsed `<details>`**.
- Recursive renderer lives in `SchemaForm.res` (`renderFields`/`renderField`/
  `renderControl`); stateful containers are separate components —
  `MapControl.res` (key/value), `ArrayControl.res` (lists), `VariantControl.res`
  (composition). They receive a `renderValue`/`renderItem`/`renderBranch`
  callback so nested values reuse the same recursive controls (avoids a module
  cycle). `Schema.res` owns schema normalisation (`effective` collapses
  `allOf`/`$ref`, `primaryType`/`isNullable`, tuple/pattern helpers).
- Execution toggle defaults **on in `vite dev`, off in production**.
- Prompts tab is hidden unless `capabilities.prompts`. `prompts/get` only sends
  arguments that were filled in: blank/whitespace-only optional arguments are
  omitted (servers reject empty strings), and a whitespace-only required
  argument keeps the Get button disabled.
- Resources tab is hidden unless `capabilities.resources`. It lists
  `resources/list` entries by URI plus `resources/templates/list` entries.
  Simple `{var}` templates build the read URI from per-variable inputs
  (`ResourceTemplate.res`, percent-encoded); complex expressions or reopened
  reads use a raw URI input. Reads render text, images/audio and binary
  downloads, and the URI is mirrored into `Mcp-Name`.

## Workflow checklist

1. Edit `.res` → `npx rescript build` (fix warnings; they're treated as
   signals).
2. `npm test` (all tests, including DOM/SSR).
3. `npm run validate:live` against `http://127.0.0.1:8080/mcp`.
4. `npm run bundle` to refresh `bundle/mcpexplorer/*` and eyeball the diff.
5. Keep the human-facing docs (`README.md`) in sync with behavior changes.

Do not commit unless asked.
