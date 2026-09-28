// Typed transport over an MCP server's `POST /mcp` endpoint.
//
// The wire method string is derived from a `Protocol.method` variant and the
// `Mcp-Name` header is only produced where the protocol requires it, so the
// body and headers can never disagree.

let protocolVersion = "2026-07-28"

type t = {
  endpoint: string,
  clientName: string,
  clientVersion: string,
}

let make = (~endpoint: string, ~clientName="mcp-explorer", ~clientVersion="0.1.0") => {
  endpoint,
  clientName,
  clientVersion,
}

let nextId = ref(0)

let newId = () => {
  nextId := nextId.contents + 1
  nextId.contents
}

let meta = (~id: int, client: t): JSON.t => {
  let m = Dict.make()
  m->Dict.set("io.modelcontextprotocol/protocolVersion", JSON.Encode.string(protocolVersion))
  m->Dict.set("io.modelcontextprotocol/clientCapabilities", JSON.Encode.object(Dict.make()))
  // Ask the server to stream `notifications/progress` (and other partial
  // updates) for this request. The JSON-RPC id is unique per request.
  m->Dict.set("progressToken", JSON.Encode.int(id))
  let info = Dict.make()
  info->Dict.set("name", JSON.Encode.string(client.clientName))
  info->Dict.set("version", JSON.Encode.string(client.clientVersion))
  m->Dict.set("io.modelcontextprotocol/clientInfo", JSON.Encode.object(info))
  JSON.Encode.object(m)
}

let headersFor = (method: Protocol.method): array<(string, string)> => [
  ("Content-Type", "application/json"),
  ("Accept", "application/json, text/event-stream"),
  ("MCP-Protocol-Version", protocolVersion),
  ("Mcp-Method", Protocol.wire(method)),
]

// `Mcp-Name` values (tool/prompt names, resource URIs) must be plain ASCII HTTP
// field values. Anything else — including values that already look like the
// Base64 sentinel — is encoded as `=?base64?{utf8-base64}?=` per the spec.
let encodeHeaderValue: string => string = %raw(`(function(value) {
  var safe = value.length > 0 &&
    /^[\x21-\x7E\t ]+$/.test(value) &&
    value === value.trim() &&
    !(value.indexOf("=?base64?") === 0 && value.slice(-2) === "?=");
  if (safe) return value;
  var bytes = new TextEncoder().encode(value);
  var binary = "";
  for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return "=?base64?" + btoa(binary) + "?=";
})`)

let envelope = (~id: int, ~method: Protocol.method, ~params: JSON.t, client: t): JSON.t => {
  let paramsDict = switch JSON.Decode.object(params) {
  | Some(dict) => dict
  | None => Dict.make()
  }
  paramsDict->Dict.set("_meta", meta(~id, client))
  let body = Dict.make()
  body->Dict.set("jsonrpc", JSON.Encode.string("2.0"))
  body->Dict.set("id", JSON.Encode.int(id))
  body->Dict.set("method", JSON.Encode.string(Protocol.wire(method)))
  body->Dict.set("params", JSON.Encode.object(paramsDict))
  JSON.Encode.object(body)
}

let emptyParams = (): JSON.t => JSON.Encode.object(Dict.make())

// The `tools/call` params object, shared with the cURL preview in the UI.
let callParams = (~name: string, ~arguments: JSON.t): JSON.t => {
  let params = Dict.make()
  params->Dict.set("name", JSON.Encode.string(name))
  params->Dict.set("arguments", arguments)
  JSON.Encode.object(params)
}

let parseBody = (text: string): result<JSON.t, Protocol.apiError> =>
  switch JsonValue.parse(text) {
  | Some(json) => Ok(json)
  | None => Error(Protocol.ProtocolMismatch("response was not valid JSON"))
  }

let decodeResult = (decoder: Codec.t<'a>, json: JSON.t): result<'a, Protocol.apiError> =>
  switch decoder(json, "$") {
  | Ok(v) => Ok(v)
  | Error(e) => Error(Protocol.Decode(e))
  }

// Unwrap a JSON-RPC envelope, mapping {error} and malformed shapes onto the
// typed error surface. Shared by the JSON-body and SSE response paths.
let unwrapEnvelope = (json: JSON.t): result<JSON.t, Protocol.apiError> =>
  switch Codec.responseEnvelope(json, "$") {
  | Ok(Codec.Success(result)) => Ok(result)
  | Ok(Codec.RpcFailure(err)) => Error(Protocol.JsonRpc(err))
  | Error(e) => Error(Protocol.Decode(e))
  }

let post = async (
  client: t,
  ~method: Protocol.method,
  ~name: option<string>,
  ~params: JSON.t,
  ~onEvent: option<Stream.t => unit>=?,
): result<JSON.t, Protocol.apiError> => {
  let startedAt = Date.now()
  let jsonRpcId = newId()
  let body = envelope(~id=jsonRpcId, ~method, ~params, client)
  let headers = switch name {
  | Some(name) => headersFor(method)->Array.concat([("Mcp-Name", encodeHeaderValue(name))])
  | None => headersFor(method)
  }
  let init: Fetch.Request.init = {
    method: #POST,
    headers: Fetch.Headers.fromArray(headers),
    body: Fetch.Body.string(JSON.stringify(body)),
  }

  // Record the outbound request so the Messages sidebar can show and replay it.
  let messageId = MessageStore.start(~method, ~name, ~params, ~request=body, ~startedAt)

  // Surface a streamed message (notification / server request) to the caller.
  let emit = (json: JSON.t) =>
    switch onEvent {
    | Some(callback) => callback(Stream.ofJson(json))
    | None => ()
    }

  // Classic path: one JSON body holding a single JSON-RPC response.
  let decodeJson = (response: Fetch.Response.t, text: string): result<JSON.t, Protocol.apiError> =>
    switch parseBody(text) {
    | Error(_) as err => err
    | Ok(json) =>
      switch unwrapEnvelope(json) {
      | Ok(result) => Ok(result)
      | Error(Protocol.Decode(_)) as err =>
        if response->Fetch.Response.ok {
          err
        } else {
          Error(Protocol.Http(response->Fetch.Response.status, text))
        }
      | Error(err) => Error(err)
      }
    }

  // Streamable-HTTP path: a stream of SSE messages. Emit partial updates as
  // they arrive and resolve once our request id shows up in a response.
  let decodeSse = async (
    response: Fetch.Response.t,
  ): result<JSON.t, Protocol.apiError> => {
    let finalResult = ref(None)
    let isFinal = (json: JSON.t) =>
      switch json->JsonValue.getField("id")->Option.flatMap(JSON.Decode.float) {
      | Some(id) => id->Float.toInt == jsonRpcId
      | None => false
      }
    let onMessage = (json: JSON.t) =>
      if isFinal(json) {
        finalResult := Some(unwrapEnvelope(json))
      } else {
        emit(json)
      }
    switch (
      try {
        let _ = await Sse.read(response, onMessage, isFinal)
        Ok()
      } catch {
      | JsExn(e) =>
        Error(Protocol.Transport(JsExn.message(e)->Option.getOr("failed to read SSE stream")))
      }
    ) {
    | Error(_) as err => err
    | Ok(_) =>
      switch finalResult.contents {
      | Some(result) => result
      | None =>
        Error(
          Protocol.ProtocolMismatch(
            "SSE stream ended without a response for request " ++ jsonRpcId->Int.toString,
          ),
        )
      }
    }
  }

  let result = switch (
    try {
      Ok(await Fetch.fetch(client.endpoint, init))
    } catch {
    | JsExn(e) =>
      Error(Protocol.Transport(JsExn.message(e)->Option.getOr("network request failed")))
    }
  ) {
  | Error(_) as err => err
  | Ok(response) =>
    let contentType =
      response->Fetch.Response.headers->Fetch.Headers.get("content-type")->Option.getOr("")
    if contentType->String.includes("text/event-stream") {
      await decodeSse(response)
    } else {
      let bodyText = try {
        Ok(await response->Fetch.Response.text)
      } catch {
      | JsExn(e) =>
        Error(Protocol.Transport(JsExn.message(e)->Option.getOr("failed to read response body")))
      }
      switch bodyText {
      | Error(_) as err => err
      | Ok(text) => decodeJson(response, text)
      }
    }
  }

  let durationMs = Date.now() -. startedAt
  switch result {
  | Ok(json) =>
    MessageStore.finish(
      messageId,
      ~status=Message.Succeeded,
      ~durationMs,
      ~response=Some(json),
      ~error=None,
    )
  | Error(err) =>
    MessageStore.finish(
      messageId,
      ~status=Message.Failed,
      ~durationMs,
      ~response=None,
      ~error=Some(Protocol.apiErrorToString(err)),
    )
  }
  result
}

// Re-send a previously captured request (used by the Messages sidebar). The new
// attempt is logged like any other request.
let replay = async (
  client: t,
  ~method: Protocol.method,
  ~name: option<string>,
  ~params: JSON.t,
): unit => {
  let _ = await post(client, ~method, ~name, ~params)
}

// POST one request and decode its result. Optional args are trailing so callers
// pass only what they need.
let request = async (
  client: t,
  ~method: Protocol.method,
  ~decoder: Codec.t<'a>,
  ~name: option<string>=?,
  ~params: JSON.t=emptyParams(),
  ~onEvent: option<Stream.t => unit>=?,
): result<'a, Protocol.apiError> => {
  let response = await post(client, ~method, ~name, ~params, ~onEvent?)
  response->Result.flatMap(json => decodeResult(decoder, json))
}

let discover = async (client: t): result<Protocol.discoverResult, Protocol.apiError> => {
  await request(client, ~method=Protocol.Discover, ~decoder=Codec.discoverResult)
}

let listTools = async (client: t): result<array<Protocol.tool>, Protocol.apiError> => {
  await request(client, ~method=Protocol.ToolsList, ~decoder=Codec.toolsResult)
}

let listPrompts = async (client: t): result<array<Protocol.prompt>, Protocol.apiError> => {
  await request(client, ~method=Protocol.PromptsList, ~decoder=Codec.promptsResult)
}

let listResources = async (client: t): result<array<Protocol.resource>, Protocol.apiError> => {
  await request(client, ~method=Protocol.ResourcesList, ~decoder=Codec.resourcesResult)
}

let listResourceTemplates = async (
  client: t,
): result<array<Protocol.resourceTemplate>, Protocol.apiError> => {
  await request(
    client,
    ~method=Protocol.ResourcesTemplatesList,
    ~decoder=Codec.resourceTemplatesResult,
  )
}

// `resources/read` requires the `Mcp-Name` header to mirror `params.uri`.
let readResource = async (
  client: t,
  ~uri: string,
  ~onEvent: option<Stream.t => unit>=?,
): result<Protocol.readResult, Protocol.apiError> => {
  let params = Dict.make()
  params->Dict.set("uri", JSON.Encode.string(uri))
  await request(
    client,
    ~method=Protocol.ResourcesRead,
    ~name=uri,
    ~params=JSON.Encode.object(params),
    ~onEvent?,
    ~decoder=Codec.readResult,
  )
}

let callTool = async (
  client: t,
  ~name: string,
  ~arguments: JSON.t,
  ~onEvent: option<Stream.t => unit>=?,
): result<Protocol.callResult, Protocol.apiError> => {
  await request(
    client,
    ~method=Protocol.ToolsCall,
    ~name,
    ~params=callParams(~name, ~arguments),
    ~onEvent?,
    ~decoder=Codec.callResult,
  )
}

let getPrompt = async (
  client: t,
  ~name: string,
  ~arguments: dict<string>,
  ~onEvent: option<Stream.t => unit>=?,
): result<Protocol.promptResult, Protocol.apiError> => {
  let argsJson = Dict.make()
  arguments->Dict.toArray->Array.forEach(((key, value)) =>
    argsJson->Dict.set(key, JSON.Encode.string(value))
  )
  let params = Dict.make()
  params->Dict.set("name", JSON.Encode.string(name))
  params->Dict.set("arguments", JSON.Encode.object(argsJson))
  await request(
    client,
    ~method=Protocol.PromptsGet,
    ~name,
    ~params=JSON.Encode.object(params),
    ~onEvent?,
    ~decoder=Codec.promptResult,
  )
}
