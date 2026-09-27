@react.component
let make: (
  ~value: option<JSON.t>,
  ~newValue: int => JSON.t,
  ~minItems: int,
  ~maxItems: option<int>,
  ~onChange: JSON.t => unit,
  ~onValidityChange: bool => unit,
  ~renderItem: (int, option<JSON.t>, JSON.t => unit) => React.element,
) => React.element
