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
      `{"supportedVersions":["2026-07-28"],"capabilities":{"tools":{},"prompts":{}}}`,
    )
    switch Codec.discoverResult(json, "$") {
    | Ok(result) =>
      expect(result.Protocol.capabilities.tools)->toBeTruthy
      expect(result.Protocol.capabilities.prompts)->toBeTruthy
    | Error(_) => expect(false)->toBeTruthy
    }
  })
})
