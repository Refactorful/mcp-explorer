@react.component
let make = (
  ~prompts: array<Protocol.prompt>,
  ~selectedName: option<string>,
  ~onSelect: string => unit,
) =>
  if prompts->Array.length == 0 {
    <p className="muted"> {"No prompts registered."->React.string} </p>
  } else {
    <ul className="item-list">
      {prompts
      ->Array.map(prompt =>
        <li key={prompt.name}>
          <button
            className={selectedName == Some(prompt.name) ? "item selected" : "item"}
            onClick={_ => onSelect(prompt.name)}>
            <span className="item-name"> {prompt.name->React.string} </span>
            <span className="item-desc">
              {prompt.description->Option.getOr("")->React.string}
            </span>
          </button>
        </li>
      )
      ->React.array}
    </ul>
  }
