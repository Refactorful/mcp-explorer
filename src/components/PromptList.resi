@react.component
let make: (
  ~prompts: array<Protocol.prompt>,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) => React.element
