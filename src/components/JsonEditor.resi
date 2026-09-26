@react.component
let make: (~value: string, ~onChange: string => unit, ~error: option<string>) => React.element
