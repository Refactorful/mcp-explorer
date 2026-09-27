@react.component
let make: (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~endpointLocked: bool,
  ~onRefresh: unit => unit,
  ~loading: bool,
) => React.element
