@react.component
let make: (
  ~uri: string,
  ~name: string,
  ~description: option<string>,
  ~mimeType: option<string>,
  ~template: option<string>,
  ~endpoint: string,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => React.element
