// Selector for JSON-Schema composition (`oneOf` / `anyOf`).
//
// Renders a `<select>` of the branches plus the chosen branch as a nested form.
// The enclosing SchemaForm supplies the branch labels, the per-branch default
// value and a render function that recurses through the same controls.

@react.component
let make = (
  ~value: option<JSON.t>,
  ~labels: array<string>,
  ~newValue: int => JSON.t,
  ~initialIndex: int,
  ~onChange: JSON.t => unit,
  ~renderBranch: (int, option<JSON.t>, JSON.t => unit) => React.element,
) => {
  let (selected, setSelected) = React.useState(() => initialIndex)

  let select = index => {
    setSelected(_ => index)
    onChange(newValue(index))
  }

  <div className="schema-variant">
    <select
      className="select-input variant-select"
      value={Int.toString(selected)}
      onChange={event => {
        switch Int.fromString(ReactEvent.Form.target(event)["value"]) {
        | Some(index) => select(index)
        | None => ()
        }
      }}>
      {labels
      ->Array.mapWithIndex((label, index) =>
        <option key={Int.toString(index)} value={Int.toString(index)}>
          {label->React.string}
        </option>
      )
      ->React.array}
    </select>
    <div className="variant-body">
      {renderBranch(selected, value, onChange)}
    </div>
  </div>
}
