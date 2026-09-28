// A single JSON-RPC message observed on an SSE stream (MCP "Streamable HTTP").
//
// While a request is in flight the server may push notifications (e.g.
// `notifications/progress`) and server requests before it sends the response
// for our id. These are surfaced live so the UI can show partial updates ahead
// of the final result.

type kind =
  | Notification
  | Request
  | Response
  | Unknown

type t = {
  at: float,
  kind: kind,
  method: option<string>,
  id: option<string>,
  payload: JSON.t,
}

let methodOf = (json: JSON.t) =>
  json->JsonValue.getField("method")->Option.flatMap(JSON.Decode.string)

let idOf = (json: JSON.t) =>
  switch json->JsonValue.getField("id") {
  | Some(JSON.String(value)) => Some(value)
  | Some(JSON.Number(value)) => Some(value->Float.toString)
  | _ => None
  }

let hasResult = (json: JSON.t) =>
  json->JsonValue.getField("result")->Option.isSome || json->JsonValue.getField("error")->Option.isSome

let kindOf = (json: JSON.t) =>
  switch methodOf(json) {
  | Some(method) =>
    if method->String.startsWith("notifications/") {
      Notification
    } else if hasResult(json) {
      Response
    } else {
      Request
    }
  | None => hasResult(json) ? Response : Unknown
  }

let ofJson = (json: JSON.t): t => {
  at: Date.now(),
  kind: kindOf(json),
  method: methodOf(json),
  id: idOf(json),
  payload: json,
}

let kindLabel = kind =>
  switch kind {
  | Notification => "notification"
  | Request => "request"
  | Response => "response"
  | Unknown => "event"
  }

let kindClass = kind =>
  switch kind {
  | Notification => "notification"
  | Request => "request"
  | Response => "response"
  | Unknown => "unknown"
  }
