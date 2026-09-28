open Vitest

describe("Codec", () => {
  test("decodes a tools/list result", () => {
    let json = JSON.parseOrThrow(
      `{"tools":[{"name":"add","description":"Add two","inputSchema":{"type":"object"}}]}`,
    )
    switch Codec.toolsResult(json, "$") {
    | Ok(tools) =>
      expect(Array.length(tools))->toBe(1)
      let tool = Array.getUnsafe(tools, 0)
      expect(tool.Protocol.name)->toBe("add")
      expect(tool.Protocol.description)->toEqual(Some("Add two"))
      expect(tool.Protocol.inputSchema->JSON.stringify)->toBe(`{"type":"object"}`)
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("unknown content block kinds are preserved, not fatal", () => {
    switch Codec.contentBlock(JSON.parseOrThrow(`{"type":"widget","x":1}`), "$") {
    | Ok(Protocol.Unknown(_)) => expect(true)->toBeTruthy
    | Ok(_) => expect(false)->toBeTruthy
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("a missing required field is a decode error with a path", () => {
    switch Codec.tool(JSON.parseOrThrow(`{"description":"x"}`), "$") {
    | Error(message) => expect(String.includes(message, "name"))->toBeTruthy
    | Ok(_) => expect(false)->toBeTruthy
    }
  })

  test("the envelope distinguishes result from error", () => {
    switch Codec.responseEnvelope(JSON.parseOrThrow(`{"result":{"ok":true}}`), "$") {
    | Ok(Codec.Success(_)) => expect(true)->toBeTruthy
    | _ => expect(false)->toBeTruthy
    }

    switch Codec.responseEnvelope(
      JSON.parseOrThrow(`{"error":{"code":-32602,"message":"bad"}}`),
      "$",
    ) {
    | Ok(Codec.RpcFailure(err)) => expect(err.Protocol.code)->toBe(-32602)
    | _ => expect(false)->toBeTruthy
    }
  })

  test("prompts/get decodes messages", () => {
    let json = JSON.parseOrThrow(
      `{"messages":[{"role":"assistant","content":{"type":"text","text":"hi"}}],"description":"d"}`,
    )
    switch Codec.promptResult(json, "$") {
    | Ok(result) =>
      expect(Array.length(result.Protocol.messages))->toBe(1)
      expect(result.Protocol.description)->toEqual(Some("d"))
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("discover capabilities are read from object presence", () => {
    let json = JSON.parseOrThrow(
      `{"supportedVersions":["2026-07-28"],"capabilities":{"tools":{},"prompts":{},"resources":{}}}`,
    )
    switch Codec.discoverResult(json, "$") {
    | Ok(result) =>
      expect(result.Protocol.capabilities.tools)->toBeTruthy
      expect(result.Protocol.capabilities.prompts)->toBeTruthy
      expect(result.Protocol.capabilities.resources)->toBeTruthy
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("resources/list decodes resources and ignores pagination metadata", () => {
    let json = JSON.parseOrThrow(
      `{"resources":[{"uri":"file:///a.txt","name":"a.txt","title":"A","description":"d","mimeType":"text/plain","size":12}],"nextCursor":"n","ttlMs":300000,"cacheScope":"public"}`,
    )
    switch Codec.resourcesResult(json, "$") {
    | Ok(resources) =>
      expect(Array.length(resources))->toBe(1)
      let resource = Array.getUnsafe(resources, 0)
      expect(resource.Protocol.uri)->toBe("file:///a.txt")
      expect(resource.Protocol.title)->toEqual(Some("A"))
      expect(resource.Protocol.size)->toEqual(Some(12.0))
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("a resource without a uri is a decode error with a path", () => {
    switch Codec.resource(JSON.parseOrThrow(`{"name":"x"}`), "$") {
    | Error(message) => expect(String.includes(message, "uri"))->toBeTruthy
    | Ok(_) => expect(false)->toBeTruthy
    }
  })

  test("resources/templates/list decodes uriTemplate", () => {
    let json = JSON.parseOrThrow(
      `{"resourceTemplates":[{"uriTemplate":"file:///{path}","name":"Files"}]}`,
    )
    switch Codec.resourceTemplatesResult(json, "$") {
    | Ok(templates) =>
      expect(Array.length(templates))->toBe(1)
      expect(Array.getUnsafe(templates, 0).Protocol.uriTemplate)->toBe("file:///{path}")
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("resources/read decodes text and blob contents", () => {
    let json = JSON.parseOrThrow(
      `{"contents":[{"uri":"file:///a.txt","mimeType":"text/plain","text":"hi"},{"uri":"file:///b.png","mimeType":"image/png","blob":"aGk="}]}`,
    )
    switch Codec.readResult(json, "$") {
    | Ok(result) =>
      expect(Array.length(result.Protocol.contents))->toBe(2)
      expect(Array.getUnsafe(result.Protocol.contents, 0).Protocol.text)->toEqual(Some("hi"))
      expect(Array.getUnsafe(result.Protocol.contents, 1).Protocol.blob)->toEqual(Some("aGk="))
    | Error(_) => expect(false)->toBeTruthy
    }
  })

  test("resources/read without a contents array degrades to empty", () => {
    switch Codec.readResult(JSON.parseOrThrow(`{}`), "$") {
    | Ok(result) => expect(Array.length(result.Protocol.contents))->toBe(0)
    | Error(_) => expect(false)->toBeTruthy
    }
  })
})
