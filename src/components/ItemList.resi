type item = {name: string, description: option<string>}

@react.component
let make: (
  ~items: array<item>,
  ~empty: string,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) => React.element
