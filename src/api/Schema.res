// Best-effort JSON-Schema helpers for pre-filling the "Try it" editor.
//
// Schemas are intentionally untyped (`JSON.t`), so these helpers are lenient:
// anything they don't understand yields a `null`/`{}` placeholder instead of
// throwing. `$ref`s into `$defs`/`definitions` are resolved on a best-effort
// basis, which is what Oxygen emits for nested record arguments.

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

let typeOf = (dict: dict<JSON.t>): option<string> =>
  dict->Dict.get("type")->Option.flatMap(JSON.Decode.string)

let parseStringJSON = (text: string): option<JSON.t> =>
  try {
    Some(JSON.parseOrThrow(text))
  } catch {
  | JsExn(_) => None
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
      switch JSON.Decode.string(value)->Option.flatMap(parseStringJSON) {
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
      switch JSON.Decode.string(value)->Option.flatMap(parseStringJSON) {
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

let rec defaultFor = (schema: JSON.t, root: JSON.t, depth: int): JSON.t =>
  if depth > 16 {
    JSON.Encode.null
  } else {
    switch JSON.Decode.object(schema) {
    | None => JSON.Encode.null
    | Some(dict) =>
      switch resolveRef(dict, root) {
      | Some(resolved) => defaultFor(resolved, root, depth + 1)
      | None =>
        switch dict->Dict.get("default") {
        | Some(value) => coerceToType(value, typeOf(dict))
        | None =>
          switch enumDefault(dict) {
          | Some(value) => value
          | None =>
            switch typeOf(dict) {
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
and enumDefault = (dict: dict<JSON.t>): option<JSON.t> =>
  switch dict->Dict.get("enum")->Option.flatMap(JSON.Decode.array) {
  | Some(items) if Array.length(items) > 0 => Some(Array.getUnsafe(items, 0))
  | _ => None
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
    switch dict->Dict.get(key)->Option.flatMap(JSON.Decode.array) {
    | Some(items) if Array.length(items) > 0 =>
      Some(defaultFor(Array.getUnsafe(items, 0), root, depth + 1))
    | _ => None
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

let requiredFields = (schema: JSON.t): array<string> =>
  switch JSON.Decode.object(schema) {
  | None => []
  | Some(dict) =>
    switch dict->Dict.get("required")->Option.flatMap(JSON.Decode.array) {
    | Some(items) => items->Array.filterMap(JSON.Decode.string)
    | None => []
    }
  }

let pretty = (json: JSON.t): string => JSON.stringify(json, ~space=2)
