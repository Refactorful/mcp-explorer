open Vitest

let headerValue = (headers: array<(string, string)>, name: string) =>
  headers
  ->Array.find(((key, _)) => key == name)
  ->Option.map(((_, value)) => value)

describe("Mcp headers and envelope", () => {
  test("every method carries the modern protocol headers", () => {
    let methods = [
      Protocol.Discover,
      Protocol.ToolsList,
      Protocol.ToolsCall,
      Protocol.PromptsList,
      Protocol.PromptsGet,
    ]
    methods->Array.forEach(method => {
      let headers = Mcp.headersFor(method)
      expect(headerValue(headers, "Mcp-Method"))->toEqual(Some(Protocol.wire(method)))
      expect(headerValue(headers, "MCP-Protocol-Version"))->toEqual(Some("2026-07-28"))
      expect(headerValue(headers, "Content-Type"))->toEqual(Some("application/json"))
      expect(headerValue(headers, "Accept"))->toEqual(
        Some("application/json, text/event-stream"),
      )
    })
  })

  test("Mcp-Name is not part of the derived headers (only added for call/get)", () => {
    expect(headerValue(Mcp.headersFor(Protocol.ToolsList), "Mcp-Name"))->toEqual(None)
    expect(headerValue(Mcp.headersFor(Protocol.ToolsCall), "Mcp-Name"))->toEqual(None)
  })

  test("envelope derives the method from the variant and injects _meta", () => {
    let client = Mcp.make(~endpoint="/mcp")
    let body = Mcp.envelope(
      ~id=7,
      ~method=Protocol.PromptsGet,
      ~params=JSON.Encode.object(Dict.make()),
      client,
    )
    let text = body->JSON.stringify
    expect(String.includes(text, `"method":"prompts/get"`))->toBeTruthy
    expect(String.includes(text, `"jsonrpc":"2.0"`))->toBeTruthy
    expect(String.includes(text, `"id":7`))->toBeTruthy
    expect(String.includes(text, "io.modelcontextprotocol/protocolVersion"))->toBeTruthy
    expect(String.includes(text, "io.modelcontextprotocol/clientInfo"))->toBeTruthy
  })

  test("request parameters survive alongside _meta", () => {
    let client = Mcp.make(~endpoint="/mcp")
    let params = Dict.make()
    params->Dict.set("name", JSON.Encode.string("greet"))
    let body = Mcp.envelope(
      ~id=1,
      ~method=Protocol.ToolsCall,
      ~params=JSON.Encode.object(params),
      client,
    )
    let text = body->JSON.stringify
    expect(String.includes(text, `"name":"greet"`))->toBeTruthy
    expect(String.includes(text, `"method":"tools/call"`))->toBeTruthy
  })
})
