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
  ~valueIsContainer: string => bool,
  ~renderValue: (string, option<JSON.t>, JSON.t => unit) => React.element,
) => React.element
