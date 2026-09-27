@react.component
let make = (~endpoint: string, ~onEndpointChange: string => unit, ~onRefresh: unit => unit, ~loading: bool) =>
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
  </div>
