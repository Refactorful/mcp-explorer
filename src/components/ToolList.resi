@react.component
let make: (
  ~tools: array<Protocol.tool>,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) => React.element
