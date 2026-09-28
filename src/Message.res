// A single logged client↔server message, plus display helpers.
//
// Every request the transport sends is recorded (see `MessageStore`) so the
// Messages sidebar can show a replayable timeline. `method` is the wire method
// string, so the same record serves `server/discover`, `tools/list`,
// `tools/call`, `prompts/get` and anything added later — not just tool calls.
//
// Timestamps are stored as UTC epoch milliseconds and only converted to the
// local timezone when displayed. Each message also carries a v4 UUID so a
// request can be tracked even if it is replayed (the JSON-RPC id is a small
// counter and repeats across calls).

type direction =
  | ClientToServer
  | ServerToClient

type status =
  | Pending
  | Succeeded
  | Failed

type t = {
  id: string,
  direction: direction,
  method: Protocol.method,
  name: option<string>,
  params: JSON.t,
  request: JSON.t,
  startedAt: float,
  durationMs: option<float>,
  status: status,
  response: option<JSON.t>,
  error: option<string>,
}

// The message currently being reopened in a detail pane. `nonce` changes on
// every reopen so the pane remounts and re-applies the same inputs even when
// the same item is reopened twice.
type reopen = {nonce: int, message: t}

let uuid: unit => string = %raw(`(function() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
    var r = (Math.random() * 16) | 0;
    var v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
})`)

let directionLabel = direction =>
  switch direction {
  | ClientToServer => "CLIENT \u2192 SERVER"
  | ServerToClient => "SERVER \u2192 CLIENT"
  }

let statusClass = status =>
  switch status {
  | Pending => "pending"
  | Succeeded => "success"
  | Failed => "failure"
  }

// e.g. "TOOLS/CALL" — derived from the wire method.
let methodLabel = (message: t) => message.method->Protocol.wire->String.toUpperCase

let isReopenable = (message: t) =>
  switch (message.method, message.name) {
  | (Protocol.ToolsCall, Some(_)) | (Protocol.PromptsGet, Some(_)) => true
  | (Protocol.ResourcesRead, Some(_)) => true
  | _ => false
  }

let pad = n => n < 10 ? "0" ++ n->Int.toString : n->Int.toString

// Local wall-clock time in 24-hour ("military") format, e.g. "20:30:46".
let formatTime = (epochMs: float) => {
  let date = Date.fromTime(epochMs)
  pad(date->Date.getHours)
  ++ ":"
  ++ pad(date->Date.getMinutes)
  ++ ":"
  ++ pad(date->Date.getSeconds)
}

let formatDuration = (ms: option<float>) =>
  switch ms {
  | None => "\u2026"
  | Some(value) => value->Float.toInt->Int.toString ++ "ms"
  }

let shortId = (id: string) =>
  id->String.length > 8 ? id->String.slice(~start=0, ~end=8) : id

// `tools/call` arguments, used to prefill the tool form when reopening.
let toolArguments = (message: t): option<JSON.t> =>
  switch message.method {
  | Protocol.ToolsCall => message.params->JsonValue.getField("arguments")
  | _ => None
  }

// A single `prompts/get` argument value, used to prefill the prompt form.
let promptArgument = (message: t, name: string): option<string> =>
  switch message.method {
  | Protocol.PromptsGet =>
    message.params
    ->JsonValue.getField("arguments")
    ->Option.flatMap(arguments => arguments->JsonValue.getField(name))
    ->Option.flatMap(JSON.Decode.string)
  | _ => None
  }

// The `resources/read` URI, used to prefill the resource pane when reopening.
let resourceUri = (message: t): option<string> =>
  switch message.method {
  | Protocol.ResourcesRead =>
    message.params->JsonValue.getField("uri")->Option.flatMap(JSON.Decode.string)
  | _ => None
  }
