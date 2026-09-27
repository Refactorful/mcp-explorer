@react.component
let make: (
  ~prompt: Protocol.prompt,
  ~endpoint: string,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => React.element
