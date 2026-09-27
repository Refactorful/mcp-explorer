// Typed transport over Oxygen's `POST /mcp` endpoint.
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

let meta = (client: t): JSON.t => {
  let m = Dict.make()
  m->Dict.set("io.modelcontextprotocol/protocolVersion", JSON.Encode.string(protocolVersion))
  m->Dict.set("io.modelcontextprotocol/clientCapabilities", JSON.Encode.object(Dict.make()))
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

let envelope = (~id: int, ~method: Protocol.method, ~params: JSON.t, client: t): JSON.t => {
  let paramsDict = switch JSON.Decode.object(params) {
  | Some(dict) => dict
  | None => Dict.make()
  }
  paramsDict->Dict.set("_meta", meta(client))
  let body = Dict.make()
  body->Dict.set("jsonrpc", JSON.Encode.string("2.0"))
  body->Dict.set("id", JSON.Encode.int(id))
  body->Dict.set("method", JSON.Encode.string(Protocol.wire(method)))
  body->Dict.set("params", JSON.Encode.object(paramsDict))
  JSON.Encode.object(body)
}

let emptyParams = (): JSON.t => JSON.Encode.object(Dict.make())

let parseBody = (text: string): result<JSON.t, Protocol.apiError> =>
  try {
    Ok(JSON.parseOrThrow(text))
  } catch {
  | JsExn(_) => Error(Protocol.ProtocolMismatch("response was not valid JSON"))
  }

let decodeResult = (decoder: Codec.t<'a>, json: JSON.t): result<'a, Protocol.apiError> =>
  switch decoder(json, "$") {
  | Ok(v) => Ok(v)
  | Error(e) => Error(Protocol.Decode(e))
  }

let post = async (
  client: t,
  ~method: Protocol.method,
  ~name: option<string>,
  ~params: JSON.t,
): result<JSON.t, Protocol.apiError> => {
  let startedAt = Date.now()
  let jsonRpcId = newId()
  let body = envelope(~id=jsonRpcId, ~method, ~params, client)
  let headers = switch name {
  | Some(name) => headersFor(method)->Array.concat([("Mcp-Name", name)])
  | None => headersFor(method)
  }
  let init: Fetch.Request.init = {
    method: #POST,
    headers: Fetch.Headers.fromArray(headers),
    body: Fetch.Body.string(JSON.stringify(body)),
  }

  // Record the outbound request so the Messages sidebar can show and replay it.
  let messageId = MessageStore.start(~method, ~name, ~params, ~request=body, ~startedAt)

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
    let bodyText = try {
      Ok(await response->Fetch.Response.text)
    } catch {
    | JsExn(e) =>
      Error(Protocol.Transport(JsExn.message(e)->Option.getOr("failed to read response body")))
    }
    switch bodyText {
    | Error(_) as err => err
    | Ok(text) =>
      switch parseBody(text) {
      | Error(_) as err => err
      | Ok(json) =>
        switch Codec.responseEnvelope(json, "$") {
        | Ok(Codec.Success(result)) => Ok(result)
        | Ok(Codec.RpcFailure(err)) => Error(Protocol.JsonRpc(err))
        | Error(e) =>
          if response->Fetch.Response.ok {
            Error(Protocol.Decode(e))
          } else {
            Error(Protocol.Http(response->Fetch.Response.status, text))
          }
        }
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

let discover = async (client: t): result<Protocol.discoverResult, Protocol.apiError> => {
  let response = await post(client, ~method=Protocol.Discover, ~name=None, ~params=emptyParams())
  response->Result.flatMap(json => decodeResult(Codec.discoverResult, json))
}

let listTools = async (client: t): result<array<Protocol.tool>, Protocol.apiError> => {
  let response = await post(client, ~method=Protocol.ToolsList, ~name=None, ~params=emptyParams())
  response->Result.flatMap(json => decodeResult(Codec.toolsResult, json))
}

let callTool = async (
  client: t,
  ~name: string,
  ~arguments: JSON.t,
): result<Protocol.callResult, Protocol.apiError> => {
  let params = Dict.make()
  params->Dict.set("name", JSON.Encode.string(name))
  params->Dict.set("arguments", arguments)
  let response = await post(
    client,
    ~method=Protocol.ToolsCall,
    ~name=Some(name),
    ~params=JSON.Encode.object(params),
  )
  response->Result.flatMap(json => decodeResult(Codec.callResult, json))
}

let listPrompts = async (client: t): result<array<Protocol.prompt>, Protocol.apiError> => {
  let response = await post(client, ~method=Protocol.PromptsList, ~name=None, ~params=emptyParams())
  response->Result.flatMap(json => decodeResult(Codec.promptsResult, json))
}

let getPrompt = async (
  client: t,
  ~name: string,
  ~arguments: dict<string>,
): result<Protocol.promptResult, Protocol.apiError> => {
  let argsJson = Dict.make()
  arguments->Dict.toArray->Array.forEach(((key, value)) =>
    argsJson->Dict.set(key, JSON.Encode.string(value))
  )
  let params = Dict.make()
  params->Dict.set("name", JSON.Encode.string(name))
  params->Dict.set("arguments", JSON.Encode.object(argsJson))
  let response = await post(
    client,
    ~method=Protocol.PromptsGet,
    ~name=Some(name),
    ~params=JSON.Encode.object(params),
  )
  response->Result.flatMap(json => decodeResult(Codec.promptResult, json))
}
