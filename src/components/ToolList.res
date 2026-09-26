@react.component
let make = (
  ~tools: array<Protocol.tool>,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) =>
  if tools->Array.length == 0 {
    <p className="muted"> {"No tools registered."->React.string} </p>
  } else {
    <ul className="item-list">
      {tools
      ->Array.map(tool =>
        <li key={tool.name}>
          <button
            className={selectedName == Some(tool.name) ? "item selected" : "item"}
            onClick={_ => onSelect(tool.name)}>
            <span className="item-name"> {tool.name->React.string} </span>
            <span className="item-desc">
              {tool.description->Option.getOr("")->React.string}
            </span>
          </button>
        </li>
      )
      ->React.array}
    </ul>
  }
