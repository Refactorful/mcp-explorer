@react.component
let make: (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~onRefresh: unit => unit,
  ~execEnabled: bool,
  ~execLocked: bool,
  ~onToggleExec: unit => unit,
  ~loading: bool,
) => React.element
