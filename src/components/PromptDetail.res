@react.component
let make = (
  ~prompt: Protocol.prompt,
  ~endpoint: string,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => {
  // A reopened `prompts/get` seeds the inputs with the same argument values.
  let initialValues = prompt.arguments->Array.map(argument => {
    let value = switch reopen {
    | Some({Message.message}) =>
      message->Message.promptArgument(argument.name)->Option.getOr("")
    | None => ""
    }
    (argument.name, value)
  })
  let (values, setValues) = React.useState(() => initialValues)
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

  let isBlank = (value: string) => value->String.trim == ""

  let missing = prompt.arguments->Array.some(argument => argument.required && isBlank(valueOf(argument.name)))

  let onRun = () => {
    setState(_ => Protocol.Loading)
    let client = Mcp.make(~endpoint)
    // Blank optional arguments are left out of the request entirely: servers
    // reject empty strings for arguments the caller is not providing.
    let arguments = values->Array.filter(((_, value)) => !isBlank(value))->Dict.fromArray
    let request = async () =>
      switch await Mcp.getPrompt(client, ~name=prompt.name, ~arguments) {
      | Ok(value) => setState(_ => Protocol.Success(value))
      | Error(err) => setState(_ => Protocol.Failure(err))
      }
    request()->ignore
  }

  let renderResult = (result: Protocol.promptResult) =>
    <div>
      {result.messages
      ->Array.mapWithIndex((message, index) =>
        <div
          key={Int.toString(index)}
          className={"message " ++ Protocol.roleToString(message.role)}>
          <div className="message-role"> {Protocol.roleToString(message.role)->React.string} </div>
          <ContentView block={message.content} />
        </div>
      )
      ->React.array}
      <JsonBlock value={result->Protocol.promptResultToJson} label="Raw JSON" />
    </div>

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
        {RequestState.render(~state, ~loading="Loading…", ~success=renderResult)}
      </section>
    </div>
  </div>
}
