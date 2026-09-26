@react.component
let make = (~tabs: array<string>, ~active: string, ~onSelect: string => unit) =>
  <nav className="tabs">
    {tabs
    ->Array.map(tab =>
      <button
        key=tab
        className={active == tab ? "tab active" : "tab"}
        onClick={_ => onSelect(tab)}>
        {tab->React.string}
      </button>
    )
    ->React.array}
  </nav>
