@react.component
let make: (
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
) => React.element
