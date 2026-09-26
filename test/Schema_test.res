open Vitest

describe("Schema", () => {
  test("generates defaults for each property (enum + default + type)", () => {
    let schema = JSON.parseOrThrow(
      `{"type":"object","required":["a"],"properties":{"a":{"type":"integer"},"b":{"type":"string","default":"hi"},"c":{"type":"boolean"},"d":{"type":"array"},"e":{"enum":[2,3],"type":"integer"}}}`,
    )
    expect(Schema.defaultsFromSchema(schema)->JSON.stringify)->toBe(
      `{"a":0,"b":"hi","c":false,"d":[],"e":2}`,
    )
  })

  test("resolves $ref into $defs recursively", () => {
    let schema = JSON.parseOrThrow(
      `{"type":"object","properties":{"place":{"$ref":"#/$defs/Place"}},"$defs":{"Place":{"type":"object","properties":{"name":{"type":"string"},"coords":{"$ref":"#/$defs/Coords"}},"required":["name"]},"Coords":{"type":"object","properties":{"lat":{"type":"number"}}}}}`,
    )
    expect(Schema.defaultsFromSchema(schema)->JSON.stringify)->toBe(
      `{"place":{"name":"","coords":{"lat":0}}}`,
    )
  })

  test("coerces a string array default into a real array", () => {
    let schema = JSON.parseOrThrow(
      `{"type":"object","properties":{"tags":{"type":"array","items":{"type":"string"},"default":"[]"}}}`,
    )
    expect(Schema.defaultsFromSchema(schema)->JSON.stringify)->toBe(`{"tags":[]}`)
  })

  test("coerces a string object default into a real object", () => {
    let schema = JSON.parseOrThrow(
      `{"type":"object","properties":{"meta":{"type":"object","default":"{}"}}}`,
    )
    expect(Schema.defaultsFromSchema(schema)->JSON.stringify)->toBe(`{"meta":{}}`)
  })

  test("coerces numeric-string defaults to numbers", () => {
    let schema = JSON.parseOrThrow(
      `{"type":"object","properties":{"n":{"type":"integer","default":"5"}}}`,
    )
    expect(Schema.defaultsFromSchema(schema)->JSON.stringify)->toBe(`{"n":5}`)
  })

  test("exotic schemas fall back to null", () => {
    expect(Schema.defaultsFromSchema(JSON.parseOrThrow(`{"type":"something"}`))->JSON.stringify)->toBe(
      "null",
    )
    expect(Schema.defaultsFromSchema(JSON.parseOrThrow(`"not-an-object"`))->JSON.stringify)->toBe(
      "null",
    )
  })

  test("requiredFields reads the required array", () => {
    expect(
      Schema.requiredFields(JSON.parseOrThrow(`{"required":["a","b"]}`))->Array.join(","),
    )->toBe("a,b")
    expect(Schema.requiredFields(JSON.parseOrThrow(`{"type":"object"}`))->Array.length)->toBe(0)
  })

  test("pretty prints with two-space indentation", () => {
    expect(JSON.parseOrThrow(`{"a":1}`)->Schema.pretty)->toBe(`{
  "a": 1
}`)
  })
})
