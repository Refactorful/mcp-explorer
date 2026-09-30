@react.component
let make = (
  ~endpoint: string="/mcp",
  ~execEnabled: option<bool>=?,
  ~endpointEditable: option<bool>=?,
  ~className: option<string>=?,
) =>
  <div ?className>
    <App
      initialEndpoint=endpoint
      initialExecEnabled=execEnabled
      initialEndpointEditable=endpointEditable
    />
  </div>
