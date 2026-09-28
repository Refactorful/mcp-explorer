// Best-effort JSON-Schema helpers for pre-filling the "Try it" editor.
//
// Schemas are intentionally untyped (`JSON.t`), so these helpers are lenient:
// anything they don't understand yields a `null`/`{}` placeholder instead of
// throwing. `$ref`s into `$defs`/`definitions` are resolved on a best-effort
// basis, which is a common way to emit nested record arguments.

let rec walkFrom = (node: JSON.t, segments: array<string>, i: int): option<JSON.t> =>
  if i >= Array.length(segments) {
    Some(node)
  } else {
    let key = Array.getUnsafe(segments, i)
    let next = switch JSON.Decode.object(node) {
    | Some(dict) => dict->Dict.get(key)
    | None =>
      switch JSON.Decode.array(node) {
      | Some(items) =>
        switch Int.fromString(key) {
        | Some(index) if index >= 0 && index < Array.length(items) =>
          Some(Array.getUnsafe(items, index))
        | _ => None
        }
      | None => None
      }
    }
    switch next {
    | Some(value) => walkFrom(value, segments, i + 1)
    | None => None
    }
  }

let resolveRef = (dict: dict<JSON.t>, root: JSON.t): option<JSON.t> =>
  switch dict->Dict.get("$ref")->Option.flatMap(JSON.Decode.string) {
  | Some(ref) =>
    walkFrom(root, ref->String.split("/")->Array.filter(segment => segment != "" && segment != "#"), 0)
  | None => None
  }

// Schemas occasionally declare a `default` whose JSON type disagrees with the
// declared `type` (e.g. `"default": "[]"` for a `type: "array"` field). Sending
// that verbatim causes a server-side conversion error, so coerce the default to
// the declared type, parsing a JSON-looking string when needed.
let coerceToType = (value: JSON.t, type_: option<string>): JSON.t =>
  switch type_ {
  | Some("array") =>
    switch JSON.Decode.array(value) {
    | Some(_) => value
    | None =>
      switch JSON.Decode.string(value)->Option.flatMap(JsonValue.parse) {
      | Some(parsed) =>
        switch JSON.Decode.array(parsed) {
        | Some(_) => parsed
        | None => JSON.Encode.array([])
        }
      | None => JSON.Encode.array([])
      }
    }
  | Some("object") =>
    switch JSON.Decode.object(value) {
    | Some(_) => value
    | None =>
      switch JSON.Decode.string(value)->Option.flatMap(JsonValue.parse) {
      | Some(parsed) =>
        switch JSON.Decode.object(parsed) {
        | Some(_) => parsed
        | None => JSON.Encode.object(Dict.make())
        }
      | None => JSON.Encode.object(Dict.make())
      }
    }
  | Some("string") =>
    switch JSON.Decode.string(value) {
    | Some(_) => value
    | None => JSON.Encode.string("")
    }
  | Some("integer") | Some("number") =>
    switch JSON.Decode.float(value) {
    | Some(_) => value
    | None =>
      switch JSON.Decode.string(value)->Option.flatMap(Float.fromString) {
      | Some(number) => JSON.Encode.float(number)
      | None => JSON.Encode.float(0.0)
      }
    }
  | Some("boolean") =>
    switch JSON.Decode.bool(value) {
    | Some(_) => value
    | None => JSON.Encode.bool(false)
    }
  | Some(_) | None => value
  }

// --- Composition, type unions and array/map helpers -------------------------

type regexp
@new external makeRegExp: (string, string) => regexp = "RegExp"
@send external testRegExp: (regexp, string) => bool = "test"

let matchesPattern = (pattern: string, text: string): bool =>
  try {
    testRegExp(makeRegExp(pattern, ""), text)
  } catch {
  | JsExn(_) => true
  }

// Resolve a top-level `$ref` against `root`, falling back to the schema itself.
let deref = (schema: JSON.t, root: JSON.t): JSON.t =>
  switch JSON.Decode.object(schema) {
  | Some(dict) =>
    switch resolveRef(dict, root) {
    | Some(resolved) => resolved
    | None => schema
    }
  | None => schema
  }

let typesOf = (schema: JSON.t): array<string> =>
  switch JsonValue.getField(schema, "type") {
  | Some(JSON.String(type_)) => [type_]
  | Some(json) => JSON.Decode.array(json)->Option.getOr([])->Array.filterMap(JSON.Decode.string)
  | None => []
  }

let primaryType = (schema: JSON.t): option<string> =>
  typesOf(schema)->Array.find(item => item != "null")

let isNullable = (schema: JSON.t): bool =>
  typesOf(schema)->Array.some(item => item == "null")

let nonEmptyArray = (json: JSON.t): option<array<JSON.t>> =>
  switch JSON.Decode.array(json) {
  | Some(items) if Array.length(items) > 0 => Some(items)
  | _ => None
  }

let constOf = (schema: JSON.t): option<JSON.t> => JsonValue.getField(schema, "const")

let titleOf = (schema: JSON.t): option<string> =>
  JsonValue.getField(schema, "title")->Option.flatMap(JSON.Decode.string)

let variantsOf = (schema: JSON.t): option<array<JSON.t>> =>
  switch JsonValue.getField(schema, "oneOf")->Option.flatMap(nonEmptyArray) {
  | Some(items) => Some(items)
  | None => JsonValue.getField(schema, "anyOf")->Option.flatMap(nonEmptyArray)
  }

let discriminatorOf = (schema: JSON.t): option<string> =>
  JsonValue.getField(schema, "discriminator")
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(dict => dict->Dict.get("propertyName"))
  ->Option.flatMap(JSON.Decode.string)

// `additionalProperties` describes an arbitrary map: the value schema (or `true`
// for untyped values). `false` means no extra keys, so there is nothing to edit.
let additionalPropertiesOf = (schema: JSON.t): option<JSON.t> =>
  switch JsonValue.getField(schema, "additionalProperties") {
  | Some(JSON.Boolean(false)) => None
  | Some(value) => Some(value)
  | None => None
  }

let patternPropertiesOf = (schema: JSON.t): option<array<(string, JSON.t)>> =>
  switch JsonValue.getField(schema, "patternProperties")->Option.flatMap(JSON.Decode.object) {
  | Some(patterns) =>
    switch patterns->Dict.toArray {
    | [] => None
    | entries => Some(entries)
    }
  | None => None
  }

let propertiesOf = (schema: JSON.t): option<dict<JSON.t>> =>
  JsonValue.getField(schema, "properties")->Option.flatMap(JSON.Decode.object)

let propertyNames = (schema: JSON.t): array<string> =>
  propertiesOf(schema)->Option.getOr(Dict.make())->Dict.keysToArray

let requiredOf = (schema: JSON.t): array<string> =>
  JsonValue.getField(schema, "required")
  ->Option.flatMap(JSON.Decode.array)
  ->Option.getOr([])
  ->Array.filterMap(JSON.Decode.string)

// 2020-12 `prefixItems` (or draft-07 `items` as an array) describes a tuple.
let tupleItemsOf = (schema: JSON.t): option<array<JSON.t>> =>
  switch JsonValue.getField(schema, "prefixItems")->Option.flatMap(nonEmptyArray) {
  | Some(items) => Some(items)
  | None => JsonValue.getField(schema, "items")->Option.flatMap(JSON.Decode.array)
  }

// Singular `items` schema (objects only; an array `items` is a tuple).
let itemSchemaOf = (schema: JSON.t): option<JSON.t> =>
  switch JsonValue.getField(schema, "items") {
  | Some(json) =>
    switch JSON.Decode.object(json) {
    | Some(_) => Some(json)
    | None => None
    }
  | None => None
  }

let intField = (schema: JSON.t, name: string): option<int> =>
  JsonValue.getField(schema, name)->Option.flatMap(JSON.Decode.float)->Option.map(Float.toInt)

let minItemsOf = (schema: JSON.t): int => intField(schema, "minItems")->Option.getOr(0)
let maxItemsOf = (schema: JSON.t): option<int> => intField(schema, "maxItems")
let minPropertiesOf = (schema: JSON.t): int => intField(schema, "minProperties")->Option.getOr(0)
let maxPropertiesOf = (schema: JSON.t): option<int> => intField(schema, "maxProperties")

let mergeStringList = (a: array<string>, b: array<string>): array<string> =>
  b->Array.reduce(a, (acc, item) =>
    acc->Array.some(existing => existing == item) ? acc : Array.concat(acc, [item])
  )

// Shallow schema merge used to collapse `allOf`. `properties` are unioned and
// merged recursively; `required` arrays are unioned; later values win for
// everything else. `allOf` itself is dropped from the result.
let rec mergeSchemas = (a: JSON.t, b: JSON.t): JSON.t =>
  switch (JSON.Decode.object(a), JSON.Decode.object(b)) {
  | (Some(da), Some(db)) =>
    let out = Dict.make()
    da->Dict.toArray->Array.forEach(((key, value)) =>
      if key != "allOf" {
        out->Dict.set(key, value)
      }
    )
    db->Dict.toArray->Array.forEach(((key, value)) =>
      if key != "allOf" {
        switch key {
        | "properties" =>
          switch (propertiesOf(a), propertiesOf(b)) {
          | (Some(pa), Some(pb)) =>
            let merged = Dict.make()
            pa->Dict.toArray->Array.forEach(((name, schema)) => merged->Dict.set(name, schema))
            pb->Dict.toArray->Array.forEach(((name, schema)) =>
              merged->Dict.set(
                name,
                switch merged->Dict.get(name) {
                | Some(existing) => mergeSchemas(existing, schema)
                | None => schema
                },
              )
            )
            out->Dict.set("properties", JSON.Encode.object(merged))
          | _ => out->Dict.set(key, value)
          }
        | "required" =>
          out->Dict.set(
            "required",
            mergeStringList(requiredOf(a), requiredOf(b))
            ->Array.map(JSON.Encode.string)
            ->JSON.Encode.array,
          )
        | _ => out->Dict.set(key, value)
        }
      }
    )
    JSON.Encode.object(out)
  | (Some(_), None) => a
  | (None, Some(_)) => b
  | (None, None) => a
  }

// Collapse `allOf` (resolving `$ref`s) into a single effective schema. Nested
// sub-schemas are normalised lazily as the form descends into them.
let rec effective = (schema: JSON.t, root: JSON.t, depth: int): JSON.t =>
  if depth > 16 {
    schema
  } else {
    let resolved = deref(schema, root)
    switch JSON.Decode.object(resolved) {
    | Some(dict) =>
      switch dict->Dict.get("allOf")->Option.flatMap(JSON.Decode.array) {
      | Some(branches) if Array.length(branches) > 0 =>
        branches->Array.reduce(resolved, (acc, branch) =>
          mergeSchemas(acc, effective(branch, root, depth + 1))
        )
      | _ => resolved
      }
    | None => resolved
    }
  }

let rec defaultFor = (schema: JSON.t, root: JSON.t, depth: int): JSON.t =>
  if depth > 16 {
    JSON.Encode.null
  } else {
    let schema = effective(schema, root, 0)
    switch JSON.Decode.object(schema) {
    | None => JSON.Encode.null
    | Some(dict) =>
      switch resolveRef(dict, root) {
      | Some(resolved) => defaultFor(resolved, root, depth + 1)
      | None =>
        switch dict->Dict.get("default") {
        | Some(value) => coerceToType(value, primaryType(schema))
        | None =>
          switch constOf(schema) {
          | Some(value) => value
          | None =>
          switch enumDefault(dict) {
          | Some(value) => value
          | None =>
            switch primaryType(schema) {
            | Some("object") => objectDefault(dict, root, depth)
            | Some("array") => JSON.Encode.array([])
            | Some("string") => JSON.Encode.string("")
            | Some("integer") => JSON.Encode.int(0)
            | Some("number") => JSON.Encode.float(0.0)
            | Some("boolean") => JSON.Encode.bool(false)
            | Some("null") => JSON.Encode.null
            | Some(_) | None =>
              switch compositionDefault(dict, root, depth) {
              | Some(value) => value
              | None => JSON.Encode.null
              }
            }
          }
        }
      }
    }
  }
  }
and enumDefault = (dict: dict<JSON.t>): option<JSON.t> =>
  switch dict->Dict.get("enum")->Option.flatMap(nonEmptyArray) {
  | Some(items) => Some(Array.getUnsafe(items, 0))
  | None => None
  }
and objectDefault = (dict: dict<JSON.t>, root: JSON.t, depth: int): JSON.t => {
  let out = Dict.make()
  switch dict->Dict.get("properties")->Option.flatMap(JSON.Decode.object) {
  | Some(properties) =>
    properties->Dict.toArray->Array.forEach(((key, value)) =>
      out->Dict.set(key, defaultFor(value, root, depth + 1))
    )
  | None => ()
  }
  JSON.Encode.object(out)
}
and compositionDefault = (dict: dict<JSON.t>, root: JSON.t, depth: int): option<JSON.t> => {
  let pick = key =>
    switch dict->Dict.get(key)->Option.flatMap(nonEmptyArray) {
    | Some(items) => Some(defaultFor(Array.getUnsafe(items, 0), root, depth + 1))
    | None => None
    }
  switch pick("allOf") {
  | Some(value) => Some(value)
  | None =>
    switch pick("anyOf") {
    | Some(value) => Some(value)
    | None => pick("oneOf")
    }
  }
}

let defaultsFromSchema = (schema: JSON.t): JSON.t => defaultFor(schema, schema, 0)

// Like `defaultsFromSchema`, but resolves `$ref`s against an explicit root
// (needed for sub-schemas such as `additionalProperties` values that reference
// the enclosing document's `$defs`).
let defaultsWithRoot = (schema: JSON.t, root: JSON.t): JSON.t => defaultFor(schema, root, 0)

// Alias kept for the UI-facing name.
let requiredFields = requiredOf

let pretty = (json: JSON.t): string => JSON.stringify(json, ~space=2)
