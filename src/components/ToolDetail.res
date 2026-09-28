@react.component
let make = (
  ~tool: Protocol.tool,
  ~endpoint: string,
  ~execEnabled: bool,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => {
  // A reopened `tools/call` seeds the form with the same arguments it was sent
  // with; a normal selection falls back to schema defaults.
  let initialArgs = switch reopen {
  | Some({Message.message}) =>
    message->Message.toolArguments->Option.getOr(Schema.defaultsFromSchema(tool.inputSchema))
  | None => Schema.defaultsFromSchema(tool.inputSchema)
  }
  let (args, setArgs) = React.useState(() => initialArgs)
  let (argsText, setArgsText) = React.useState(() => initialArgs->Schema.pretty)
  let (mode, setMode) = React.useState(() => "form")
  let (parseError, setParseError) = React.useState(() => (None: option<string>))
  let (formValid, setFormValid) = React.useState(() => true)
  let (formKey, setFormKey) = React.useState(() => 0)
  let (state, setState) = React.useState(() => Protocol.Idle)
  // SSE messages streamed before the final response (progress notifications,
  // server requests, ...). Shown live while the call is in flight.
  let (events, setEvents) = React.useState(() => ([]: array<Stream.t>))

  let applyArgs = (next: JSON.t) => {
    setArgs(_ => next)
    setArgsText(_ => next->Schema.pretty)
  }

  let onTextChange = (text: string) => {
    setArgsText(_ => text)
    switch JsonValue.parse(text) {
    | Some(json) =>
      setParseError(_ => None)
      setArgs(_ => json)
    | None => setParseError(_ => Some("Invalid JSON"))
    }
  }

  let onReset = () => {
    let fresh = Schema.defaultsFromSchema(tool.inputSchema)
    setArgs(_ => fresh)
    setArgsText(_ => fresh->Schema.pretty)
    setParseError(_ => None)
    setFormValid(_ => true)
    setFormKey(key => key + 1)
    setState(_ => Protocol.Idle)
    setEvents(_ => [])
  }

  let client = Mcp.make(~endpoint)
  let requestBody =
    Mcp.envelope(
      ~id=1,
      ~method=Protocol.ToolsCall,
      ~params=Mcp.callParams(~name=tool.name, ~arguments=args),
      client,
    )->JSON.stringify(~space=2)
  let curl = Curl.forToolCall(~endpoint, ~name=tool.name, ~body=requestBody)

  let onRun = () => {
    setState(_ => Protocol.Loading)
    setEvents(_ => [])
    let request = async () =>
      switch await Mcp.callTool(
        client,
        ~name=tool.name,
        ~arguments=args,
        ~onEvent=event => setEvents(previous => Array.concat(previous, [event])),
      ) {
      | Ok(value) => setState(_ => Protocol.Success(value))
      | Error(err) => setState(_ => Protocol.Failure(err))
      }
    request()->ignore
  }

  let renderStream = () => <StreamLog events />

  let jsonInvalid = mode == "json" && parseError->Option.isSome
  let runDisabled = !execEnabled || jsonInvalid
  let requiredFields = Schema.requiredFields(tool.inputSchema)
  // When execution is off, disable the whole "Try it" area (fields, toggles,
  // actions) and say why.
  let disabledClass = execEnabled ? "" : " tryit-disabled"

  <div className="detail">
    <div className="detail-header">
      <button className="btn back-btn" onClick={_ => onBack()}>
        {"← Tools"->React.string}
      </button>
      <h2> {tool.name->React.string} </h2>
      {switch tool.description {
      | Some(description) => <p className="description"> {description->React.string} </p>
      | None => React.null
      }}
    </div>
    <div className="detail-grid">
      <details className="detail-col disclosure">
        <summary>
          <span className="disclosure-label"> {"Input schema"->React.string} </span>
        </summary>
        <div className="disclosure-body">
          <JsonBlock value={tool.inputSchema} />
          {requiredFields->Array.length > 0
            ? <p className="required-note">
                {"Required: "->React.string}
                {requiredFields->Array.join(", ")->React.string}
              </p>
            : React.null}
        </div>
      </details>
      <section className="detail-col">
        <div className="tryit-head">
          <h3> {"Try it"->React.string} </h3>
          <div className="mode-toggle">
            <button
              className={mode == "form" ? "subtab active" : "subtab"}
              disabled={!execEnabled}
              onClick={_ => setMode(_ => "form")}>
              {"Form"->React.string}
            </button>
            <button
              className={mode == "json" ? "subtab active" : "subtab"}
              disabled={!execEnabled}
              onClick={_ => setMode(_ => "json")}>
              {"JSON"->React.string}
            </button>
          </div>
        </div>
        {!execEnabled
          ? <p className="warning">
              {"Tool execution is disabled. Enable it from the host by mounting McpExplorer with `execEnabled: true`."->React.string}
            </p>
          : React.null}
        <form
          className={disabledClass}
          onSubmit={event => {
            ReactEvent.Form.preventDefault(event)
            if execEnabled && !jsonInvalid && (mode == "json" || formValid) {
              onRun()
            }
          }}>
          <fieldset className="tryit-fieldset" disabled={!execEnabled}>
            {mode == "form"
              ? <SchemaForm
                  key={Int.toString(formKey)}
                  schema={tool.inputSchema}
                  value=args
                  onChange=applyArgs
                  onValidityChange={valid => setFormValid(_ => valid)}
                />
              : <JsonEditor value=argsText onChange=onTextChange error=parseError />}
            <div className="actions">
              {!execEnabled
                ? <span className="warning">
                    {"Execution disabled — the host controls this setting."->React.string}
                  </span>
                : mode == "form" && !formValid
                  ? <span className="warning"> {"Fix invalid JSON fields."->React.string} </span>
                  : React.null}
              <div className="actions-buttons">
                <button type_="submit" className="btn primary" disabled=runDisabled>
                  {"Run tool"->React.string}
                </button>
                <button type_="button" className="btn" onClick={_ => onReset()}>
                  {"Reset"->React.string}
                </button>
              </div>
            </div>
          </fieldset>
        </form>
        {renderStream()}
        <ResultView state curl />
      </section>
    </div>
  </div>
}
