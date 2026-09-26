// Helpers for reading and updating JSON objects by key.
//
// `setField`/`removeField` return a fresh `JSON.Object` so React state changes
// are always detected (mutating the underlying dict would not re-render).

let getField = (json: JSON.t, name: string): option<JSON.t> =>
  switch JSON.Decode.object(json) {
  | Some(dict) => dict->Dict.get(name)
  | None => None
  }

let entries = (json: JSON.t): array<(string, JSON.t)> =>
  switch JSON.Decode.object(json) {
  | Some(dict) => dict->Dict.toArray
  | None => []
  }

let setField = (json: JSON.t, name: string, value: JSON.t): JSON.t => {
  let found = ref(false)
  let next = entries(json)->Array.map(((key, current)) =>
    if key == name {
      found := true
      (key, value)
    } else {
      (key, current)
    }
  )
  let next = found.contents ? next : Array.concat(next, [(name, value)])
  JSON.Encode.object(Dict.fromArray(next))
}

let removeField = (json: JSON.t, name: string): JSON.t =>
  JSON.Encode.object(
    entries(json)->Array.filter(((key, _)) => key != name)->Dict.fromArray,
  )
