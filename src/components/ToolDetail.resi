@react.component
let make: (
  ~tool: Protocol.tool,
  ~endpoint: string,
  ~execEnabled: bool,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => React.element
