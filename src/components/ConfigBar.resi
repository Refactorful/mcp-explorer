@react.component
let make: (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~onRefresh: unit => unit,
  ~loading: bool,
) => React.element
