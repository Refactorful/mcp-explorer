@react.component
let make = (~prompt: Protocol.prompt, ~endpoint: string, ~onBack: unit => unit) => {
  let (values, setValues) = React.useState(() =>
    prompt.arguments->Array.map(argument => (argument.name, ""))
  )
  let (state, setState) = React.useState(() => Protocol.Idle)

  let valueOf = name =>
    values
    ->Array.find(((key, _)) => key == name)
    ->Option.map(((_, value)) => value)
    ->Option.getOr("")

  let update = (name, value) =>
    setValues(previous =>
      previous->Array.map(((key, current)) => key == name ? (key, value) : (key, current))
    )

  let missing = prompt.arguments->Array.some(argument => argument.required && valueOf(argument.name) == "")

  let onRun = () => {
    setState(_ => Protocol.Loading)
    let client = Mcp.make(~endpoint)
    let arguments = Dict.fromArray(values)
    let request = async () =>
      switch await Mcp.getPrompt(client, ~name=prompt.name, ~arguments) {
      | Ok(value) => setState(_ => Protocol.Success(value))
      | Error(err) => setState(_ => Protocol.Failure(err))
      }
    request()->ignore
  }

  <div className="detail">
    <div className="detail-header">
      <button className="btn back-btn" onClick={_ => onBack()}>
        {"← Prompts"->React.string}
      </button>
      <h2> {prompt.name->React.string} </h2>
      {switch prompt.description {
      | Some(description) => <p className="description"> {description->React.string} </p>
      | None => React.null
      }}
    </div>
    <div className="detail-grid">
      <section className="detail-col">
        <h3> {"Arguments"->React.string} </h3>
        {prompt.arguments->Array.length == 0
          ? <p className="muted"> {"This prompt takes no arguments."->React.string} </p>
          : prompt.arguments
            ->Array.map(argument =>
              <label key={argument.name} className="field">
                <span>
                  {argument.name->React.string}
                  {argument.required ? " *"->React.string : React.null}
                </span>
                <input
                  className="text-input"
                  value={valueOf(argument.name)}
                  onChange={event =>
                    update(argument.name, ReactEvent.Form.target(event)["value"])}
                />
              </label>
            )
            ->React.array}
        <div className="actions">
          <button className="btn primary" disabled=missing onClick={_ => onRun()}>
            {"Get prompt"->React.string}
          </button>
        </div>
      </section>
      <section className="detail-col">
        <h3> {"Result"->React.string} </h3>
        {switch state {
        | Protocol.Idle => <div className="muted"> {"Not run yet."->React.string} </div>
        | Protocol.Loading => <div className="muted"> {"Loading…"->React.string} </div>
        | Protocol.Failure(err) =>
          <div className="error-box"> {Protocol.apiErrorToString(err)->React.string} </div>
        | Protocol.Success(result) =>
          <div>
            {result.messages
            ->Array.mapWithIndex((message, index) =>
              <div key={Int.toString(index)} className={"message " ++ Protocol.roleToString(message.role)}>
                <div className="message-role">
                  {Protocol.roleToString(message.role)->React.string}
                </div>
                <ContentView block={message.content} />
              </div>
            )
            ->React.array}
            <details className="content-json">
              <summary> {"Raw JSON"->React.string} </summary>
              <pre className="code-block">
                {result->Protocol.promptResultToJson->Schema.pretty->React.string}
              </pre>
            </details>
          </div>
        }}
      </section>
    </div>
  </div>
}
