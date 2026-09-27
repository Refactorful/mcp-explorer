// Dynamic array editor for JSON-Schema `type: "array"` fields.
//
// The surrounding form owns the canonical JSON value; this component keeps an
// ordered list of items with stable ids so that adding/removing/reordering rows
// never remounts the remaining controls (which would drop focus).
//
// Tuples are handled by the caller: `renderItem` and `newValue` receive the item
// index, so per-index schemas (`prefixItems` / draft-07 `items` arrays) can be
// rendered field-by-field, with `items` supplying any extra elements.

type item = {id: int, value: JSON.t}

let itemsFromValue = (value: option<JSON.t>): array<item> =>
  switch value->Option.flatMap(JSON.Decode.array) {
  | Some(items) => items->Array.mapWithIndex((value, index) => {id: index, value})
  | None => []
  }

let toArray = (items: array<item>): JSON.t =>
  JSON.Encode.array(items->Array.map(item => item.value))

let nextId = (items: array<item>): int =>
  items->Array.reduce(0, (max, item) => item.id >= max ? item.id + 1 : max)

let indexOf = (items: array<item>, id: int): int => {
  let rec loop = index =>
    if index >= Array.length(items) {
      -1
    } else if (Array.getUnsafe(items, index).id == id) {
      index
    } else {
      loop(index + 1)
    }
  loop(0)
}

@react.component
let make = (
  ~value: option<JSON.t>,
  ~newValue: int => JSON.t,
  ~minItems: int,
  ~maxItems: option<int>,
  ~onChange: JSON.t => unit,
  ~onValidityChange: bool => unit,
  ~renderItem: (int, option<JSON.t>, JSON.t => unit) => React.element,
) => {
  let (items, setItems) = React.useState(() => itemsFromValue(value))

  React.useEffect1(
    () => {
      if toArray(itemsFromValue(value))->JSON.stringify != toArray(items)->JSON.stringify {
        setItems(_ => itemsFromValue(value))
      }
      None
    },
    [value],
  )

  let length = Array.length(items)
  let overMax = maxItems->Option.map(max => length > max)->Option.getOr(false)
  let invalid = length < minItems || overMax
  let atMax = maxItems->Option.map(max => length >= max)->Option.getOr(false)

  React.useEffect1(
    () => {
      onValidityChange(!invalid)
      None
    },
    [invalid],
  )

  let commit = (next: array<item>) => {
    setItems(_ => next)
    onChange(toArray(next))
  }

  let add = () => commit(Array.concat(items, [{id: nextId(items), value: newValue(length)}]))

  let update = (id: int, value: JSON.t) =>
    commit(items->Array.map(item => item.id == id ? {...item, value} : item))

  let remove = (id: int) => commit(items->Array.filter(item => item.id != id))

  let swap = (a: int, b: int) =>
    if a >= 0 && b >= 0 && a < length && b < length {
      let itemA = Array.getUnsafe(items, a)
      let itemB = Array.getUnsafe(items, b)
      commit(
        items->Array.mapWithIndex((item, index) =>
          if index == a {
            itemB
          } else if index == b {
            itemA
          } else {
            item
          }
        ),
      )
    }

  let move = (id: int, delta: int) => {
    let index = indexOf(items, id)
    swap(index, index + delta)
  }

  <div className="schema-array">
    {items
    ->Array.mapWithIndex((item, index) =>
      <div className="array-row" key={Int.toString(item.id)}>
        <span className="array-index"> {(index + 1)->Int.toString->React.string} </span>
        <div className="array-value">
          {renderItem(index, Some(item.value), next => update(item.id, next))}
        </div>
        <div className="array-actions">
          <button
            type_="button"
            className="btn array-action"
            disabled={index == 0}
            title="Move up"
            onClick={_ => move(item.id, -1)}>
            {"↑"->React.string}
          </button>
          <button
            type_="button"
            className="btn array-action"
            disabled={index == length - 1}
            title="Move down"
            onClick={_ => move(item.id, 1)}>
            {"↓"->React.string}
          </button>
          <button
            type_="button"
            className="btn map-remove"
            disabled={length <= minItems}
            title="Remove"
            onClick={_ => remove(item.id)}>
            {"✕"->React.string}
          </button>
        </div>
      </div>
    )
    ->React.array}
    <button type_="button" className="btn map-add" disabled={atMax} onClick={_ => add()}>
      {"+ Add item"->React.string}
    </button>
    {invalid
      ? <div className="parse-error">
          {overMax
            ? "Too many items."->React.string
            : ("At least " ++ Int.toString(minItems) ++ " item(s) required.")->React.string}
        </div>
      : React.null}
  </div>
}
