@react.component
let make: (
  ~state: Protocol.requestState<Protocol.callResult>,
  ~curl: string,
) => React.element
