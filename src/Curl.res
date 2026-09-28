// cURL export for reproducing a request from a terminal.

let shellEscape = value => "'" ++ value->String.replaceAll("'", "'\\''") ++ "'"

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
  // Derive the header list from the transport so the export cannot drift from
  // what `Mcp.post` actually sends.
  let headers = Mcp.headersFor(Protocol.ToolsCall)->Array.concat([("Mcp-Name", name)])
  let lines = Array.concat(
    ["curl -sS " ++ endpoint->absolute->shellEscape ++ " \\"],
    headers->Array.map(((key, value)) => "  -H " ++ (key ++ ": " ++ value)->shellEscape ++ " \\"),
  )
  Array.concat(lines, ["  --data " ++ body->shellEscape])->Array.join("\n")
}
