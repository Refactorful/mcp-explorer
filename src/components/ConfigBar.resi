@react.component
let make: (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~onRefresh: unit => unit,
  ~execEnabled: bool,
  ~onToggleExec: unit => unit,
  ~loading: bool,
) => React.element
