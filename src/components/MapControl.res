// Dynamic key/value editor for arbitrary maps: JSON-Schema objects that use
// `additionalProperties` / `patternProperties`, optionally alongside declared
// `properties` (the declared keys are passed in as `reserved` and left to the
// regular field renderer).
//
// The surrounding form owns the canonical JSON value; this component keeps an
// ordered list of rows with stable ids so that editing a key never remounts its
// input (which would drop focus), and re-emits a fresh object on every change.

type row = {id: int, key: string, value: JSON.t}

let isReserved = (reserved: array<string>, key: string): bool =>
  reserved->Array.some(item => item == key)

let rowsFromValue = (value: option<JSON.t>, reserved: array<string>): array<row> =>
  switch value->Option.flatMap(JSON.Decode.object) {
  | Some(dict) =>
    dict
    ->Dict.toArray
    ->Array.filter(((key, _)) => !isReserved(reserved, key))
    ->Array.mapWithIndex((entry, index) => {
      let (key, value) = entry
      {id: index, key, value}
    })
  | None => []
  }

let reservedPairs = (value: option<JSON.t>, reserved: array<string>): array<(string, JSON.t)> =>
  switch value->Option.flatMap(JSON.Decode.object) {
  | Some(dict) => dict->Dict.toArray->Array.filter(((key, _)) => isReserved(reserved, key))
  | None => []
  }

let rowsToObject = (rows: array<row>): JSON.t =>
  JSON.Encode.object(Dict.fromArray(rows->Array.map(row => (row.key, row.value))))

let uniqueKey = (rows: array<row>, base: string): string => {
  let exists = candidate => rows->Array.some(row => row.key == candidate)
  if !exists(base) {
    base
  } else {
    let rec loop = n =>
      if exists(base ++ Int.toString(n)) {
        loop(n + 1)
      } else {
        base ++ Int.toString(n)
      }
    loop(2)
  }
}

let invalidKeys = (
  rows: array<row>,
  minProperties: int,
  maxProperties: option<int>,
  patterns: array<string>,
  allowAdditional: bool,
): bool =>
  Array.length(rows) < minProperties ||
  maxProperties->Option.map(max => Array.length(rows) > max)->Option.getOr(false) ||
  rows->Array.some(row => {
    let empty = row.key == ""
    let unmatched =
      Array.length(patterns) > 0 &&
      !(patterns->Array.some(pattern => Schema.matchesPattern(pattern, row.key))) &&
      !allowAdditional
    let duplicate =
      rows->Array.filter(other => other.key == row.key)->Array.length > 1
    empty || unmatched || duplicate
  })

@react.component
let make = (
  ~value: option<JSON.t>,
  ~newValue: JSON.t,
  ~reserved: array<string>,
  ~keyPatterns: array<string>,
  ~allowAdditional: bool,
  ~minProperties: int,
  ~maxProperties: option<int>,
  ~onChange: JSON.t => unit,
  ~onValidityChange: bool => unit,
  ~renderValue: (string, option<JSON.t>, JSON.t => unit) => React.element,
) => {
  let (rows, setRows) = UseSyncedRows.use(
    ~value,
    ~fromJson=value => rowsFromValue(value, reserved),
    ~toJson=rowsToObject,
  )

  let invalid = invalidKeys(rows, minProperties, maxProperties, keyPatterns, allowAdditional)
  let atMax = maxProperties->Option.map(max => Array.length(rows) >= max)->Option.getOr(false)

  React.useEffect1(
    () => {
      onValidityChange(!invalid)
      None
    },
    [invalid],
  )

  let commit = (next: array<row>) => {
    setRows(_ => next)
    onChange(
      JSON.Encode.object(
        Dict.fromArray(
          Array.concat(reservedPairs(value, reserved), next->Array.map(row => (row.key, row.value))),
        ),
      ),
    )
  }

  let add = () =>
    commit(
      Array.concat(
        rows,
        [
          {
            id: UseSyncedRows.nextId(rows, row => row.id),
            key: uniqueKey(rows, "key"),
            value: newValue,
          },
        ],
      ),
    )

  let updateKey = (id: int, key: string) =>
    commit(rows->Array.map(row => row.id == id ? {...row, key} : row))

  let updateValue = (id: int, value: JSON.t) =>
    commit(rows->Array.map(row => row.id == id ? {...row, value} : row))

  let remove = (id: int) => commit(rows->Array.filter(row => row.id != id))

  <div className="schema-map">
    {rows
    ->Array.map(row =>
      <div className="map-row" key={Int.toString(row.id)}>
        <input
          className="text-input map-key"
          value={row.key}
          placeholder="key"
          spellCheck=false
          onChange={event => updateKey(row.id, ReactEvent.Form.target(event)["value"])}
        />
        <div className="map-value">
          {renderValue(row.key, Some(row.value), newValue => updateValue(row.id, newValue))}
        </div>
        <button type_="button" className="btn map-remove" onClick={_ => remove(row.id)}>
          {"✕"->React.string}
        </button>
      </div>
    )
    ->React.array}
    <button type_="button" className="btn map-add" disabled={atMax} onClick={_ => add()}>
      {"+ Add entry"->React.string}
    </button>
    {invalid
      ? <div className="parse-error">
          {Array.length(rows) < minProperties
            ? ("At least " ++ Int.toString(minProperties) ++ " entr(ies) required.")->React.string
            : maxProperties->Option.map(max => Array.length(rows) > max)->Option.getOr(false)
              ? "Too many entries."->React.string
              : Array.length(keyPatterns) > 0 && !allowAdditional
                ? "Keys must match the allowed pattern(s) and be unique."->React.string
                : "Keys must be unique and non-empty."->React.string}
        </div>
      : React.null}
  </div>
}
