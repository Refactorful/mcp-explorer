@react.component
let make: (
  ~initialEndpoint: string,
  ~initialExecEnabled: option<bool>,
  ~initialEndpointEditable: option<bool>,
) => React.element
