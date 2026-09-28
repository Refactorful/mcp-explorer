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

  let renderResult = (result: Protocol.callResult) =>
    switch view {
    | "raw" => <JsonBlock value={result->Protocol.callResultToJson} />
    | "curl" => <pre className="code-block"> {curl->React.string} </pre>
    | _ =>
      <div className={result.isError ? "result-body error" : "result-body"}>
        {result.content
        ->Array.mapWithIndex((block, index) => <ContentView key={Int.toString(index)} block />)
        ->React.array}
        {switch result.structuredContent {
        | Some(value) =>
          <div>
            <h4> {"structuredContent"->React.string} </h4>
            <JsonBlock value />
          </div>
        | None => React.null
        }}
      </div>
    }

  <div className="result-view">
    <div className="subtabs">
      {subtab("Result", "result")}
      {subtab("Raw", "raw")}
      {subtab("cURL", "curl")}
    </div>
    {RequestState.render(~state, ~success=renderResult)}
  </div>
}
