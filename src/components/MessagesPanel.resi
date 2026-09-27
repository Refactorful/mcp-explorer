@react.component
let make: (
  ~messages: array<Message.t>,
  ~onClear: unit => unit,
  ~onReplay: Message.t => unit,
  ~onReopen: Message.t => unit,
) => React.element
