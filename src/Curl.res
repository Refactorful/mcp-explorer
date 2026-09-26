// cURL export for reproducing a request from a terminal.

let shellEscape = value => "'" ++ value->String.replaceAll("'", "'\\''") ++ "'"

let protocolVersion = "2026-07-28"

let currentOrigin = (): string =>
  %raw(`(typeof window !== "undefined" && window.location && window.location.origin) || ""`)

// The endpoint may be relative (e.g. `/mcp`); a copy-pasteable cURL command
// needs an absolute URL, so resolve it against the page origin.
let absolute = (endpoint: string): string =>
  if endpoint->String.startsWith("http://") || endpoint->String.startsWith("https://") {
    endpoint
  } else {
    switch currentOrigin() {
    | "" => endpoint
    | origin =>
      if endpoint->String.startsWith("/") {
        origin ++ endpoint
      } else {
        origin ++ "/" ++ endpoint
      }
    }
  }

let forToolCall = (~endpoint: string, ~name: string, ~body: string): string => {
  let lines = [
    "curl -sS " ++ endpoint->absolute->shellEscape ++ " \\",
    "  -H 'Content-Type: application/json' \\",
    "  -H 'Accept: application/json, text/event-stream' \\",
    "  -H 'MCP-Protocol-Version: " ++ protocolVersion ++ "' \\",
    "  -H 'Mcp-Method: tools/call' \\",
    "  -H " ++ ("Mcp-Name: " ++ name)->shellEscape ++ " \\",
    "  --data " ++ body->shellEscape,
  ]
  lines->Array.join("\n")
}
