@react.component
let make: (
  ~value: option<JSON.t>,
  ~labels: array<string>,
  ~newValue: int => JSON.t,
  ~initialIndex: int,
  ~onChange: JSON.t => unit,
  ~renderBranch: (int, option<JSON.t>, JSON.t => unit) => React.element,
) => React.element
