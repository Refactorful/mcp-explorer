@react.component
let make = (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~onRefresh: unit => unit,
  ~execEnabled: bool,
  ~onToggleExec: unit => unit,
  ~loading: bool,
) =>
  <div className="config-bar">
    <label className="field grow">
      <span> {"MCP endpoint"->React.string} </span>
      <input
        className="text-input"
        value=endpoint
        spellCheck=false
        onChange={event => onEndpointChange(ReactEvent.Form.target(event)["value"])}
      />
    </label>
    <button className="btn" disabled=loading onClick={_ => onRefresh()}>
      {(loading ? "Refreshing…" : "Refresh")->React.string}
    </button>
    <label className="toggle">
      <input type_="checkbox" checked=execEnabled onChange={_ => onToggleExec()} />
      <span> {"Enable execution"->React.string} </span>
    </label>
  </div>
