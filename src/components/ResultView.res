@react.component
let make = (~state: Protocol.requestState<Protocol.callResult>, ~curl: string) => {
  let (view, setView) = React.useState(() => "result")

  let subtab = (label, key) =>
    <button
      key
      className={view == key ? "subtab active" : "subtab"}
      onClick={_ => setView(_ => key)}>
      {label->React.string}
    </button>

  <div className="result-view">
    <div className="subtabs">
      {subtab("Result", "result")}
      {subtab("Raw", "raw")}
      {subtab("cURL", "curl")}
    </div>
    {switch (view, state) {
    | (_, Protocol.Idle) => <div className="muted"> {"Not run yet."->React.string} </div>
    | (_, Protocol.Loading) => <div className="muted"> {"Running…"->React.string} </div>
    | (_, Protocol.Failure(err)) =>
      <div className="error-box"> {Protocol.apiErrorToString(err)->React.string} </div>
    | ("raw", Protocol.Success(result)) =>
      <pre className="code-block">
        {result->Protocol.callResultToJson->Schema.pretty->React.string}
      </pre>
    | ("curl", Protocol.Success(_)) => <pre className="code-block"> {curl->React.string} </pre>
    | (_, Protocol.Success(result)) =>
      <div className={result.isError ? "result-body error" : "result-body"}>
        {result.content
        ->Array.mapWithIndex((block, index) =>
          <ContentView key={Int.toString(index)} block />
        )
        ->React.array}
        {switch result.structuredContent {
        | Some(value) =>
          <div>
            <h4> {"structuredContent"->React.string} </h4>
            <pre className="code-block"> {value->Schema.pretty->React.string} </pre>
          </div>
        | None => React.null
        }}
      </div>
    }}
  </div>
}
