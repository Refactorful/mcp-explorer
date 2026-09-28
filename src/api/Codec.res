// Total decoders for the MCP wire format.
//
// A decoder is `(JSON.t, path) => result<'a, string>` where `path` is a
// human-readable breadcrumb used to build precise error messages. The
// untyped JSON only lives here; every public decoder returns a typed value.

type t<'a> = (JSON.t, string) => result<'a, string>

let error = (path, msg) => Error(path ++ ": " ++ msg)

let run = (decoder: t<'a>, json: JSON.t): result<'a, string> => decoder(json, "$")

// --- primitives ---

let string: t<string> = (json, path) =>
  switch JSON.Decode.string(json) {
  | Some(v) => Ok(v)
  | None => error(path, "expected string")
  }

let bool: t<bool> = (json, path) =>
  switch JSON.Decode.bool(json) {
  | Some(v) => Ok(v)
  | None => error(path, "expected boolean")
  }

let int: t<int> = (json, path) =>
  switch JSON.Decode.float(json) {
  | Some(v) => Ok(v->Int.fromFloat)
  | None => error(path, "expected integer")
  }

let float: t<float> = (json, path) =>
  switch JSON.Decode.float(json) {
  | Some(v) => Ok(v)
  | None => error(path, "expected number")
  }

// Identity decoder: for intentionally untyped payloads (inputSchema,
// structuredContent, resource blocks, ...).
let unknown: t<JSON.t> = (json, _path) => Ok(json)

// Every record decoder starts by requiring an object; `what` keeps the error
// message precise ("expected tool object", ...).
let objectOf = (json: JSON.t, path: string, what: string): result<dict<JSON.t>, string> =>
  switch JSON.Decode.object(json) {
  | Some(dict) => Ok(dict)
  | None => error(path, "expected " ++ what ++ " object")
  }

let object: t<dict<JSON.t>> = (json, path) =>
  switch JSON.Decode.object(json) {
  | Some(v) => Ok(v)
  | None => error(path, "expected object")
  }

let array = (inner: t<'a>, json: JSON.t, path: string): result<array<'a>, string> =>
  switch JSON.Decode.array(json) {
  | None => error(path, "expected array")
  | Some(items) =>
    let rec loop = (i: int, acc: array<'a>): result<array<'a>, string> =>
      if i >= Array.length(items) {
        acc->Array.reverse
        Ok(acc)
      } else {
        switch inner(Array.getUnsafe(items, i), path ++ "[" ++ i->Int.toString ++ "]") {
        | Ok(v) => loop(i + 1, [v, ...acc])
        | Error(e) => Error(e)
        }
      }
    loop(0, [])
  }

// Curried wrapper so `array(inner)` can be passed where a decoder is expected
// (uncurried partial application is not allowed).
let arrayOf = (inner: t<'a>): t<array<'a>> => (json, path) => array(inner, json, path)

// --- object field helpers ---

let field = (dict: dict<JSON.t>, name: string, inner: t<'a>): result<'a, string> =>
  switch dict->Dict.get(name) {
  | Some(v) => inner(v, name)
  | None => Error("missing required field: " ++ name)
  }

let optField = (dict: dict<JSON.t>, name: string, inner: t<'a>): result<option<'a>, string> =>
  switch dict->Dict.get(name) {
  | Some(JSON.Null) | None => Ok(None)
  | Some(v) =>
    switch inner(v, name) {
    | Ok(x) => Ok(Some(x))
    | Error(e) => Error(e)
    }
  }

// --- MCP shapes ---

let media: t<Protocol.media> = (json, path) =>
  objectOf(json, path, "media")->Result.flatMap(dict =>
    field(dict, "data", string)->Result.flatMap(data =>
      field(dict, "mimeType", string)->Result.map(mimeType => {Protocol.data, mimeType})
    )
  )

let contentBlock: t<Protocol.contentBlock> = (json, path) =>
  objectOf(json, path, "content block")->Result.flatMap(dict =>
    switch dict->Dict.get("type")->Option.flatMap(JSON.Decode.string) {
    | Some("text") => field(dict, "text", string)->Result.map(text => Protocol.Text(text))
    | Some("image") => media(json, path)->Result.map(m => Protocol.Image(m))
    | Some("audio") => media(json, path)->Result.map(m => Protocol.Audio(m))
    | Some("resource_link") => Ok(Protocol.ResourceLink(json))
    | Some("resource") => Ok(Protocol.Resource(json))
    // Forward-compatible: unknown block kinds are preserved, not fatal.
    | Some(_) | None => Ok(Protocol.Unknown(json))
    }
  )

let tool: t<Protocol.tool> = (json, path) =>
  objectOf(json, path, "tool")->Result.flatMap(dict =>
    field(dict, "name", string)->Result.flatMap(name =>
      optField(dict, "description", string)->Result.flatMap(description =>
        switch dict->Dict.get("inputSchema") {
        | Some(schema) => Ok({Protocol.name, description, inputSchema: schema})
        | None =>
          Ok({Protocol.name, description, inputSchema: JSON.Encode.object(Dict.make())})
        }
      )
    )
  )

let promptArgument: t<Protocol.promptArgument> = (json, path) =>
  objectOf(json, path, "prompt argument")->Result.flatMap(dict =>
    field(dict, "name", string)->Result.flatMap(name =>
      optField(dict, "required", bool)->Result.map(required => {
        Protocol.name,
        required: required->Option.getOr(false),
      })
    )
  )

let prompt: t<Protocol.prompt> = (json, path) =>
  objectOf(json, path, "prompt")->Result.flatMap(dict =>
    field(dict, "name", string)->Result.flatMap(name =>
      optField(dict, "description", string)->Result.flatMap(description =>
        switch dict->Dict.get("arguments") {
        | Some(JSON.Array(items)) =>
          array(promptArgument, JSON.Array(items), "arguments")->Result.map(arguments =>
            {Protocol.name, description, arguments}
          )
        | _ => Ok({Protocol.name, description, arguments: []})
        }
      )
    )
  )

let role: t<Protocol.role> = (json, _path) =>
  switch JSON.Decode.string(json) {
  | Some("assistant") => Ok(Protocol.Assistant)
  | Some("user") => Ok(Protocol.User)
  | Some(_) | None => Ok(Protocol.User)
  }

let promptMessage: t<Protocol.promptMessage> = (json, path) =>
  objectOf(json, path, "prompt message")->Result.flatMap(dict =>
    field(dict, "role", role)->Result.flatMap(role =>
      field(dict, "content", contentBlock)->Result.map(content => {Protocol.role, content})
    )
  )

let promptResult: t<Protocol.promptResult> = (json, path) =>
  objectOf(json, path, "prompts/get result")->Result.flatMap(dict =>
    optField(dict, "description", string)->Result.flatMap(description =>
      switch dict->Dict.get("messages") {
      | Some(messages) =>
        array(promptMessage, messages, "messages")->Result.map(messages => {
          Protocol.messages,
          description,
        })
      | None => Ok({Protocol.messages: [], description})
      }
    )
  )

let callResult: t<Protocol.callResult> = (json, path) =>
  objectOf(json, path, "tools/call result")->Result.flatMap(dict =>
    switch dict->Dict.get("content") {
    | Some(content) =>
      array(contentBlock, content, "content")->Result.flatMap(content =>
        optField(dict, "structuredContent", unknown)->Result.flatMap(structuredContent =>
          optField(dict, "isError", bool)->Result.map(isError => {
            Protocol.content,
            structuredContent,
            isError: isError->Option.getOr(false),
          })
        )
      )
    | None => error(path, "missing content array")
    }
  )

let capability = (dict: dict<JSON.t>, name: string): bool =>
  switch dict->Dict.get(name) {
  | Some(JSON.Null) | None => false
  | Some(_) => true
  }

let capabilities = (dict: dict<JSON.t>): Protocol.capabilities => {
  tools: capability(dict, "tools"),
  prompts: capability(dict, "prompts"),
}

let discoverResult: t<Protocol.discoverResult> = (json, path) =>
  objectOf(json, path, "server/discover result")->Result.flatMap(dict =>
    field(dict, "supportedVersions", arrayOf(string))->Result.flatMap(supportedVersions =>
      optField(dict, "capabilities", object)->Result.flatMap(caps =>
        optField(dict, "instructions", string)->Result.map(instructions => {
          Protocol.supportedVersions,
          capabilities: caps->Option.map(capabilities)->Option.getOr({
            tools: false,
            prompts: false,
          }),
          instructions,
        })
      )
    )
  )

let jsonRpcError: t<Protocol.jsonRpcError> = (json, path) =>
  objectOf(json, path, "error")->Result.flatMap(dict =>
    field(dict, "code", int)->Result.flatMap(code =>
      field(dict, "message", string)->Result.flatMap(message =>
        optField(dict, "data", unknown)->Result.map(data => {Protocol.code, message, data})
      )
    )
  )

// The JSON-RPC envelope: exactly one of {result, error}.
type envelope =
  | Success(JSON.t)
  | RpcFailure(Protocol.jsonRpcError)

let responseEnvelope: (JSON.t, string) => result<envelope, string> = (json, path) =>
  objectOf(json, path, "JSON-RPC response")->Result.flatMap(dict =>
    switch dict->Dict.get("error") {
    | Some(JSON.Null) | None =>
      switch dict->Dict.get("result") {
      | Some(result) => Ok(Success(result))
      | None => error(path, "response has neither result nor error")
      }
    | Some(errJson) =>
      jsonRpcError(errJson, path ++ ".error")->Result.map(err => RpcFailure(err))
    }
  )

// --- list results (unwrap the arrays) ---

// Shared shape of `tools/list` and `prompts/list`: the array under `key`.
let listResult = (
  json: JSON.t,
  path: string,
  key: string,
  what: string,
  decoder: t<'a>,
): result<array<'a>, string> =>
  objectOf(json, path, what)->Result.flatMap(dict =>
    switch dict->Dict.get(key) {
    | Some(items) => array(decoder, items, path ++ "." ++ key)
    | None => Ok([])
    }
  )

let toolsResult: t<array<Protocol.tool>> = (json, path) =>
  listResult(json, path, "tools", "tools/list result", tool)

let promptsResult: t<array<Protocol.prompt>> = (json, path) =>
  listResult(json, path, "prompts", "prompts/list result", prompt)
