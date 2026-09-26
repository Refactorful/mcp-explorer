@react.component
let make = (~tool: Protocol.tool, ~endpoint: string, ~execEnabled: bool, ~onBack: unit => unit) => {
  let (args, setArgs) = React.useState(() => Schema.defaultsFromSchema(tool.inputSchema))
  let (argsText, setArgsText) = React.useState(() =>
    Schema.defaultsFromSchema(tool.inputSchema)->Schema.pretty
  )
  let (mode, setMode) = React.useState(() => "form")
  let (parseError, setParseError) = React.useState(() => (None: option<string>))
  let (formValid, setFormValid) = React.useState(() => true)
  let (formKey, setFormKey) = React.useState(() => 0)
  let (state, setState) = React.useState(() => Protocol.Idle)

  let applyArgs = (next: JSON.t) => {
    setArgs(_ => next)
    setArgsText(_ => next->Schema.pretty)
  }

  let onTextChange = (text: string) => {
    setArgsText(_ => text)
    switch (
      try {
        Some(JSON.parseOrThrow(text))
      } catch {
      | JsExn(_) => None
      }
    ) {
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
  }

  let client = Mcp.make(~endpoint)
  let params = Dict.make()
  params->Dict.set("name", JSON.Encode.string(tool.name))
  params->Dict.set("arguments", args)
  let requestBody =
    Mcp.envelope(~id=1, ~method=Protocol.ToolsCall, ~params=JSON.Encode.object(params), client)
    ->JSON.stringify(~space=2)
  let curl = Curl.forToolCall(~endpoint, ~name=tool.name, ~body=requestBody)

  let onRun = () => {
    setState(_ => Protocol.Loading)
    let request = async () =>
      switch await Mcp.callTool(client, ~name=tool.name, ~arguments=args) {
      | Ok(value) => setState(_ => Protocol.Success(value))
      | Error(err) => setState(_ => Protocol.Failure(err))
      }
    request()->ignore
  }

  let jsonInvalid = mode == "json" && parseError->Option.isSome
  let runDisabled = !execEnabled || jsonInvalid
  let requiredFields = Schema.requiredFields(tool.inputSchema)

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
          <SchemaView schema={tool.inputSchema} />
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
              onClick={_ => setMode(_ => "form")}>
              {"Form"->React.string}
            </button>
            <button
              className={mode == "json" ? "subtab active" : "subtab"}
              onClick={_ => setMode(_ => "json")}>
              {"JSON"->React.string}
            </button>
          </div>
        </div>
        <form
          onSubmit={event => {
            ReactEvent.Form.preventDefault(event)
            if execEnabled && !jsonInvalid && (mode == "json" || formValid) {
              onRun()
            }
          }}>
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
            <button type_="submit" className="btn primary" disabled=runDisabled>
              {"Run tool"->React.string}
            </button>
            <button type_="button" className="btn" onClick={_ => onReset()}>
              {"Reset"->React.string}
            </button>
            {!execEnabled
              ? <span className="warning">
                  {"Execution disabled — enable it in the toolbar."->React.string}
                </span>
              : mode == "form" && !formValid
                ? <span className="warning"> {"Fix invalid JSON fields."->React.string} </span>
                : React.null}
          </div>
        </form>
        <ResultView state curl />
      </section>
    </div>
  </div>
}
