# MCP Explorer

A same-origin, offline-capable single-page viewer for **any MCP server**, written
in **ReScript + React**. It discovers and renders tools and prompts, and can
invoke them through a schema-driven "Try it" form.

There is no host dependency — you pass the MCP endpoint in when you mount it.

## The bundle

Everything you need is in `bundle/mcpexplorer/`:

| File | Purpose |
| --- | --- |
| `mcpexplorer.js` + `mcpexplorer.css` | Self-contained IIFE exposing `window.McpExplorer`. This is the embeddable integration. |
| `index.html` | Standalone single-file page that mounts itself. |
| `icon.svg` | App icon, for the host page favicon. |

## Embedding

Load the JS and CSS on any page, drop in an empty container, and mount:

```html
<div id="mcp-explorer"></div>
<link rel="icon" href="/icon.svg" type="image/svg+xml" />
<link rel="stylesheet" href="/docs/mcp/mcpexplorer.css" />
<script src="/docs/mcp/mcpexplorer.js"></script>
<script>
  const viewer = window.McpExplorer({
    endpoint: "/mcp",          // MCP URL (absolute or same-origin path)
    domId: "mcp-explorer",     // id of the container element
    execEnabled: true,         // optional: on in dev, off in production
    endpointEditable: false,   // optional: lock the endpoint field
  });
  // viewer.unmount();
</script>
```

It takes a config object and returns an `{ unmount }` handle. Options:

- **`endpoint`** (alias `url`) — the MCP URL to call. Defaults to `"/mcp"`.
- **`domId`** (alias `dom_id`) — id of an empty container element. Defaults to
  `"mcp-explorer"`.
- **`execEnabled`** — turns tool execution on or off for this mount. When
  omitted, the build default applies (on in `vite dev`, off in production). It
  is fixed for the lifetime of the mount; there is no in-app toggle.
- **`endpointEditable`** — defaults to `true`. Set to `false` to pin the viewer
  to a single server.

`window.McpExplorer.mount(config)` is the same function, and
`window.McpExplorer("some-dom-id")` is a shorthand where the string is the
`domId`.

### Standalone page

`index.html` mounts itself with the same API:

```html
<div id="root"></div>
<script type="module" src="/src/Main.res.mjs"></script>
<script>
  window.McpExplorer({ endpoint: "/mcp", domId: "root" });
</script>
```

## What it does

- Speaks JSON-RPC 2.0 to the configured endpoint using the modern
  `2026-07-28` MCP era (no initialize handshake): `server/discover`, then
  `tools/list` and `prompts/list` when advertised.
- **Tool viewer:** name/description, a collapsible JSON-Schema inspector, a
  schema-driven "Try it" form, and `Result`/`Raw`/`cURL` views.
- **Schema-driven form:** one typed control per input — `enum`/`const` becomes
  a select, `boolean` a checkbox, numbers validated inputs, strings text.
  Nested objects (`$ref`/`$defs`/`allOf`), key/value maps
  (`additionalProperties`/`patternProperties`), arrays and tuples,
  `oneOf`/`anyOf` (with discriminator), and type unions all render as real
  controls; only unrecognized shapes fall back to a JSON editor. Defaults
  pre-fill and `required` fields use native validation.
- **Streaming:** when a call answers with `text/event-stream`, notifications
  such as `notifications/progress` appear live in a "Stream" log before the
  final result.
- **Prompt viewer:** argument form, rendered messages, raw JSON. The tab is
  hidden when the server does not advertise prompts.
- **Messages sidebar:** every request is logged with its wire method,
  round-trip time, direction, and raw payloads. Replay a request or reopen it
  in the detail pane.
- **Navigation:** master–detail split with browser history support, collapsing
  to a single pane on narrow screens.

## Development

Requires Node 20+.

```sh
npm install

npm run res:watch   # terminal 1: ReScript compiler in watch mode
npm run dev         # terminal 2: Vite dev server (proxies /mcp)

npm test            # unit + DOM/SSR tests
npm run bundle      # rebuild bundle/mcpexplorer/*
npm run validate:live               # live smoke test against a running server
MCP_ENDPOINT=http://127.0.0.1:8080/mcp npm run validate:live
```

In dev, the viewer proxies `/mcp` to `http://127.0.0.1:8080` (override with
`MCP_DEV_TARGET`) and strips the `Origin` header, since many MCP hosts reject
cross-origin requests with `403`. Keep the endpoint relative — an absolute URL
bypasses the proxy and fails as a cross-origin request.

## Layout

```
src/                  ReScript app (Main.res = mount API, App.res = shell)
src/api/              protocol, codecs, transport, SSE, schema
src/components/       one React component per file
test/                 Vitest unit tests + jsdom/SSR tests
scripts/              copy-bundle, validate-live
bundle/mcpexplorer/   committed build artifacts
```

## Notes

- The wire protocol is strongly typed: method/header mismatches are
  unrepresentable, decoders return `result` instead of `undefined`, and unknown
  content-block types degrade gracefully rather than failing a call.
- Versions are pinned exactly: `rescript` 12.3.1, `@rescript/react` 0.15.0,
  React 19.2.0, Vite 8.3.1, Vitest 5.0.2.
