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
      Protocol.ResourcesList,
      Protocol.ResourcesTemplatesList,
      Protocol.ResourcesRead,
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

  test("Mcp-Name is not part of the derived headers (only added for call/get/read)", () => {
    expect(headerValue(Mcp.headersFor(Protocol.ToolsList), "Mcp-Name"))->toEqual(None)
    expect(headerValue(Mcp.headersFor(Protocol.ToolsCall), "Mcp-Name"))->toEqual(None)
    expect(headerValue(Mcp.headersFor(Protocol.ResourcesList), "Mcp-Name"))->toEqual(None)
    expect(headerValue(Mcp.headersFor(Protocol.ResourcesRead), "Mcp-Name"))->toEqual(None)
  })

  test("header values pass through when they are plain ASCII", () => {
    expect(Mcp.encodeHeaderValue("file:///notes/today.md"))->toBe("file:///notes/today.md")
    expect(Mcp.encodeHeaderValue("get_weather"))->toBe("get_weather")
    expect(Mcp.encodeHeaderValue("a b"))->toBe("a b")
  })

  test("header values use the base64 sentinel when they are not ASCII-safe", () => {
    expect(Mcp.encodeHeaderValue("café.txt"))->toBe("=?base64?Y2Fmw6kudHh0?=")
    expect(Mcp.encodeHeaderValue(" spaced "))->toBe("=?base64?IHNwYWNlZCA=?=")
    expect(Mcp.encodeHeaderValue("line1\nline2"))->toBe("=?base64?bGluZTEKbGluZTI=?=")
    // A plain value that looks like the sentinel must be encoded to stay unambiguous.
    expect(Mcp.encodeHeaderValue("=?base64?literal?="))->toBe(
      "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=",
    )
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

  test("request parameters survive alongside _meta", () => {    let client = Mcp.make(~endpoint="/mcp")
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

  test("envelope carries a progress token tied to the request id", () => {
    let client = Mcp.make(~endpoint="/mcp")
    let body = Mcp.envelope(
      ~id=42,
      ~method=Protocol.ToolsCall,
      ~params=JSON.Encode.object(Dict.make()),
      client,
    )
    let text = body->JSON.stringify
    expect(String.includes(text, `"progressToken":42`))->toBeTruthy
  })
})
