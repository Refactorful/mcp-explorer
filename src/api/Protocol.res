// Typed MCP wire protocol (modern 2026-07-28 era).
//
// This module owns the vocabulary: method names, content-block variants,
// result shapes and the typed error surface. Nothing here touches the network.

type method =
  | Discover
  | ToolsList
  | ToolsCall
  | PromptsList
  | PromptsGet
  | ResourcesList
  | ResourcesTemplatesList
  | ResourcesRead

let wire = method =>
  switch method {
  | Discover => "server/discover"
  | ToolsList => "tools/list"
  | ToolsCall => "tools/call"
  | PromptsList => "prompts/list"
  | PromptsGet => "prompts/get"
  | ResourcesList => "resources/list"
  | ResourcesTemplatesList => "resources/templates/list"
  | ResourcesRead => "resources/read"
  }

// --- content blocks (mirror MCP_CONTENT_TYPES in serialization.jl) ---
type media = {data: string, mimeType: string}

type contentBlock =
  | Text(string)
  | Image(media)
  | Audio(media)
  | ResourceLink(JSON.t) // pass-through: {uri, name?, mimeType?, ...}
  | Resource(JSON.t) // {uri, mimeType?, blob?}
  | Unknown(JSON.t)

// --- discovery ---
// Capabilities are presence-based on the wire (`{"tools":{}}`); each flag here
// means the server advertised that feature.
type capabilities = {tools: bool, prompts: bool, resources: bool}

type discoverResult = {
  supportedVersions: array<string>,
  capabilities: capabilities,
  instructions: option<string>,
}

// --- tools (tools/list) ---
type tool = {
  name: string,
  description: option<string>,
  inputSchema: JSON.t, // intentionally untyped
}

// --- prompts (prompts/list, prompts/get) ---
type promptArgument = {name: string, required: bool}

type prompt = {
  name: string,
  description: option<string>,
  arguments: array<promptArgument>,
}

type role = User | Assistant

let roleToString = role =>
  switch role {
  | User => "user"
  | Assistant => "assistant"
  }

type promptMessage = {role: role, content: contentBlock}

type promptResult = {messages: array<promptMessage>, description: option<string>}

// --- resources (resources/list, resources/read) ---
type resource = {
  uri: string,
  name: string,
  title: option<string>,
  description: option<string>,
  mimeType: option<string>,
  size: option<float>,
}

type resourceTemplate = {
  uriTemplate: string,
  name: string,
  title: option<string>,
  description: option<string>,
  mimeType: option<string>,
}

// One entry of a `resources/read` result: either inline `text` or base64 `blob`.
type resourceContents = {
  uri: string,
  mimeType: option<string>,
  text: option<string>,
  blob: option<string>,
}

type readResult = {contents: array<resourceContents>}

// --- tool calls (tools/call) ---
type callResult = {
  content: array<contentBlock>,
  structuredContent: option<JSON.t>,
  isError: bool,
}

// --- errors ---
type jsonRpcError = {code: int, message: string, data: option<JSON.t>}

type apiError =
  | Transport(string) // fetch/network failure
  | Http(int, string) // non-2xx
  | ProtocolMismatch(string) // malformed JSON-RPC envelope
  | JsonRpc(jsonRpcError) // {error: ...}
  | Decode(string) // typed decode failure (path + reason)

let apiErrorToString = err =>
  switch err {
  | Transport(msg) => "Transport error: " ++ msg
  | Http(code, body) => "HTTP " ++ code->Int.toString ++ ": " ++ body
  | ProtocolMismatch(msg) => "Protocol mismatch: " ++ msg
  | JsonRpc(e) => "JSON-RPC error " ++ e.code->Int.toString ++ ": " ++ e.message
  | Decode(msg) => "Decode error: " ++ msg
  }

// Async request state used by the UI.
type requestState<'a> =
  | Idle
  | Loading
  | Success('a)
  | Failure(apiError)

// --- display encoders (typed values back to JSON for the "Raw" view) ---

let mediaToJson = (type_: string, media: media): JSON.t =>
  JSON.Encode.object(
    Dict.fromArray([
      ("type", JSON.Encode.string(type_)),
      ("data", JSON.Encode.string(media.data)),
      ("mimeType", JSON.Encode.string(media.mimeType)),
    ]),
  )

let contentBlockToJson = (block: contentBlock): JSON.t =>
  switch block {
  | Text(text) =>
    JSON.Encode.object(
      Dict.fromArray([
        ("type", JSON.Encode.string("text")),
        ("text", JSON.Encode.string(text)),
      ]),
    )
  | Image(media) => mediaToJson("image", media)
  | Audio(media) => mediaToJson("audio", media)
  | ResourceLink(json) | Resource(json) | Unknown(json) => json
  }

let callResultToJson = (result: callResult): JSON.t => {
  let dict = Dict.make()
  dict->Dict.set("content", JSON.Encode.array(result.content->Array.map(contentBlockToJson)))
  dict->Dict.set("isError", JSON.Encode.bool(result.isError))
  switch result.structuredContent {
  | Some(value) => dict->Dict.set("structuredContent", value)
  | None => ()
  }
  JSON.Encode.object(dict)
}

let promptResultToJson = (result: promptResult): JSON.t => {
  let messages = result.messages->Array.map(message => {
    let dict = Dict.make()
    dict->Dict.set("role", JSON.Encode.string(roleToString(message.role)))
    dict->Dict.set("content", contentBlockToJson(message.content))
    JSON.Encode.object(dict)
  })
  let dict = Dict.make()
  dict->Dict.set("messages", JSON.Encode.array(messages))
  switch result.description {
  | Some(description) => dict->Dict.set("description", JSON.Encode.string(description))
  | None => ()
  }
  JSON.Encode.object(dict)
}

let resourceResultToJson = (result: readResult): JSON.t => {
  let contents = result.contents->Array.map(contents => {
    let dict = Dict.make()
    dict->Dict.set("uri", JSON.Encode.string(contents.uri))
    switch contents.mimeType {
    | Some(mimeType) => dict->Dict.set("mimeType", JSON.Encode.string(mimeType))
    | None => ()
    }
    switch contents.text {
    | Some(text) => dict->Dict.set("text", JSON.Encode.string(text))
    | None => ()
    }
    switch contents.blob {
    | Some(blob) => dict->Dict.set("blob", JSON.Encode.string(blob))
    | None => ()
    }
    JSON.Encode.object(dict)
  })
  JSON.Encode.object(Dict.fromArray([("contents", JSON.Encode.array(contents))]))
}

