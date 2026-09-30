@react.component
let make = (
  ~endpoint: string,
  ~onEndpointChange: string => unit,
  ~endpointLocked: bool,
  ~onRefresh: unit => unit,
  ~loading: bool,
) =>
  <div className="config-bar">
    <span> {"MCP Endpoint"->React.string} </span>
    <label className="field grow">
      <input
        className="text-input"
        value=endpoint
        spellCheck=false
        disabled=endpointLocked
        title={endpointLocked ? "The endpoint is configured by the host" : ""}
        onChange={event => onEndpointChange(ReactEvent.Form.target(event)["value"])}
      />
    </label>
    <button className="btn" disabled=loading onClick={_ => onRefresh()}>
      {(loading ? "Refreshing…" : "Refresh")->React.string}
    </button>
  </div>
