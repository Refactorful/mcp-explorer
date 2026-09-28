open Vitest

describe("ResourceTemplate", () => {
  test("extracts simple and reserved variables", () => {
    let vars = ResourceTemplate.variables("file:///{path}/{name}.txt")
    expect(Array.length(vars))->toBe(2)
    expect(Array.getUnsafe(vars, 0).ResourceTemplate.name)->toBe("path")
    expect(Array.getUnsafe(vars, 0).ResourceTemplate.reserved)->toBe(false)
    expect(Array.getUnsafe(vars, 1).ResourceTemplate.name)->toBe("name")

    let reserved = ResourceTemplate.variables("https://example.com/{+route}")
    expect(Array.length(reserved))->toBe(1)
    expect(Array.getUnsafe(reserved, 0).ResourceTemplate.name)->toBe("route")
    expect(Array.getUnsafe(reserved, 0).ResourceTemplate.reserved)->toBe(true)
  })

  test("flags complex expressions and malformed braces", () => {
    expect(ResourceTemplate.isComplex("file:///{?a,b}"))->toBe(true)
    expect(ResourceTemplate.isComplex("file:///{/id}"))->toBe(true)
    expect(ResourceTemplate.isComplex("file:///{name:3}"))->toBe(true)
    expect(ResourceTemplate.isComplex("file:///{path"))->toBe(true)
    expect(ResourceTemplate.isComplex("file:///{{path}}"))->toBe(true)
    expect(ResourceTemplate.isComplex("file:///plain.txt"))->toBe(false)
    expect(ResourceTemplate.isComplex("file:///{path}"))->toBe(false)
  })

  test("substitutes variables with percent-encoding", () => {
    let values = Dict.fromArray([("path", "docs/hello world.md")])
    expect(ResourceTemplate.substitute("file:///{path}", values))->toEqual(
      Some("file:///docs%2Fhello%20world.md"),
    )
  })

  test("reserved expansion keeps URI separators", () => {
    let values = Dict.fromArray([("route", "a/b")])
    expect(ResourceTemplate.substitute("https://example.com/{+route}", values))->toEqual(
      Some("https://example.com/a/b"),
    )
  })

  test("substitution returns None for complex templates", () => {
    expect(ResourceTemplate.substitute("file:///{?a}", Dict.make()))->toEqual(None)
  })

  test("missing values expand to the empty string", () => {
    expect(ResourceTemplate.substitute("file:///{path}", Dict.make()))->toEqual(Some("file:///"))
  })
})
