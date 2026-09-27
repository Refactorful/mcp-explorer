@react.component
let make = (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~onRefresh: unit => unit,
  ~execEnabled: bool,
  ~execLocked: bool,
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
    <label
      className="toggle"
      title={execLocked ? "Execution is configured by the host" : ""}>
      <input
        type_="checkbox"
        checked=execEnabled
        disabled=execLocked
        onChange={_ => onToggleExec()}
      />
      <span> {"Enable execution"->React.string} </span>
    </label>
  </div>
