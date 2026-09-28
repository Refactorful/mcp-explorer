// Shared master list for tools and prompts: one selectable row per item.

type item = {name: string, description: option<string>}

@react.component
let make = (
  ~items: array<item>,
  ~empty: string,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) =>
  if items->Array.length == 0 {
    <p className="muted"> {empty->React.string} </p>
  } else {
    <ul className="item-list">
      {items
      ->Array.map(item =>
        <li key={item.name}>
          <button
            className={selectedName == Some(item.name) ? "item selected" : "item"}
            onClick={_ => onSelect(item.name)}>
            <span className="item-name"> {item.name->React.string} </span>
            <span className="item-desc"> {item.description->Option.getOr("")->React.string} </span>
          </button>
        </li>
      )
      ->React.array}
    </ul>
  }
