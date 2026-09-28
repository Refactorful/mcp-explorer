@react.component
let make = (
  ~uri: string,
  ~name: string,
  ~description: option<string>,
  ~mimeType: option<string>,
  ~template: option<string>,
  ~endpoint: string,
  ~onBack: unit => unit,
  ~reopen: option<Message.reopen>,
) => {
  // A reopened `resources/read` carries the concrete URI it was sent with;
  // templates cannot be reverse-mapped, so they reopen with a raw URI input.
  let reopenUri = switch reopen {
  | Some({Message.message: message}) => message->Message.resourceUri
  | None => None
  }
  let isTemplate = template->Option.isSome
  let templateValue = template->Option.getOr("")
  let variables =
    templateValue == "" || ResourceTemplate.isComplex(templateValue)
      ? []
      : ResourceTemplate.variables(templateValue)
  // Simple templates build the URI from one input per `{variable}`; complex
  // templates and reopened reads use a single raw URI input; plain resources
  // keep their fixed URI.
  let usingVariables = isTemplate && variables->Array.length > 0 && reopenUri->Option.isNone
  let (rawUri, setRawUri) = React.useState(() =>
    reopenUri->Option.getOr(isTemplate ? templateValue : uri)
  )
  let (values, setValues) = React.useState(() =>
    variables->Array.map(variable => (variable.ResourceTemplate.name, ""))
  )
  let (state, setState) = React.useState(() => Protocol.Idle)
  let (events, setEvents) = React.useState((): array<Stream.t> => [])

  let valueOf = variable =>
    values
    ->Array.find(((key, _)) => key == variable)
    ->Option.map(((_, value)) => value)
    ->Option.getOr("")

  let update = (variable, value) =>
    setValues(previous =>
      previous->Array.map(((key, current)) => key == variable ? (key, value) : (key, current))
    )

  let target = if usingVariables {
    ResourceTemplate.substitute(templateValue, values->Dict.fromArray)->Option.getOr(templateValue)
  } else {
    rawUri
  }

  let isBlank = (value: string) => value->String.trim == ""

  let missing = if usingVariables {
    variables->Array.some(variable => isBlank(valueOf(variable.ResourceTemplate.name)))
  } else {
    isBlank(target)
  }

  let onRun = () => {
    setState(_ => Protocol.Loading)
    setEvents(_ => [])
    let client = Mcp.make(~endpoint)
    let request = async () =>
      switch await Mcp.readResource(client, ~uri=target, ~onEvent=event =>
        setEvents(previous => Array.concat(previous, [event]))
      ) {
      | Ok(value) => setState(_ => Protocol.Success(value))
      | Error(err) => setState(_ => Protocol.Failure(err))
      }
    request()->ignore
  }

  let renderContents = (contents: Protocol.resourceContents, index: int) => {
    let mime = contents.mimeType->Option.getOr("application/octet-stream")
    let dataSrc = "data:" ++ mime ++ ";base64," ++ contents.blob->Option.getOr("")
    <div key={Int.toString(index)} className="resource-content">
      <div className="resource-content-head">
        <span className="item-name"> {contents.uri->React.string} </span>
        <span className="muted"> {mime->React.string} </span>
      </div>
      {switch (contents.text, contents.blob) {
      | (Some(text), _) => <pre className="content-text"> {text->React.string} </pre>
      | (None, Some(blob)) =>
        if mime->String.startsWith("image/") {
          <ImagePreview src=dataSrc alt="resource content" />
        } else if mime->String.startsWith("audio/") {
          <div className="content-media">
            <audio controls=true src=dataSrc />
          </div>
        } else {
          <div>
            <p className="muted">
              {("Binary content (" ++ blob->String.length->Int.toString ++ " base64 characters).")
                ->React.string}
            </p>
            <a className="btn" href=dataSrc download={contents.uri}> {"Download"->React.string} </a>
          </div>
        }
      | (None, None) =>
        <p className="muted"> {"This content entry has neither text nor blob."->React.string} </p>
      }}
    </div>
  }

  let renderResult = (result: Protocol.readResult) =>
    <div>
      {result.contents->Array.length == 0
        ? <p className="muted"> {"The server returned no content."->React.string} </p>
        : result.contents
          ->Array.mapWithIndex((contents, index) => renderContents(contents, index))
          ->React.array}
      <JsonBlock value={result->Protocol.resourceResultToJson} label="Raw JSON" />
    </div>

  <div className="detail">
    <div className="detail-header">
      <button className="btn back-btn" onClick={_ => onBack()}>
        {"← Resources"->React.string}
      </button>
      <h2> {name->React.string} </h2>
      {switch description {
      | Some(description) => <p className="description"> {description->React.string} </p>
      | None => React.null
      }}
    </div>
    <div className="detail-grid">
      <section className="detail-col">
        <h3> {"Resource"->React.string} </h3>
        {if usingVariables {
          variables
          ->Array.map(variable =>
            <label key={variable.ResourceTemplate.name} className="field">
              <span>
                {variable.ResourceTemplate.name->React.string}
                {" *"->React.string}
              </span>
              <input
                className="text-input"
                value={valueOf(variable.ResourceTemplate.name)}
                onChange={event =>
                  update(variable.ResourceTemplate.name, ReactEvent.Form.target(event)["value"])}
              />
            </label>
          )
          ->React.array
        } else {
          <label className="field">
            <span> {"URI"->React.string} </span>
            <input
              className="text-input"
              value=target
              readOnly={!isTemplate}
              onChange={event => setRawUri(_ => ReactEvent.Form.target(event)["value"])}
            />
          </label>
        }}
        {switch mimeType {
        | Some(mimeType) => <p className="muted"> {("MIME type: " ++ mimeType)->React.string} </p>
        | None => React.null
        }}
        <div className="actions">
          <div className="actions-buttons">
            <button className="btn primary" disabled=missing onClick={_ => onRun()}>
              {"Read resource"->React.string}
            </button>
          </div>
        </div>
      </section>
      <section className="detail-col">
        <h3> {"Result"->React.string} </h3>
        <StreamLog events />
        {RequestState.render(~state, ~loading="Reading…", ~success=renderResult)}
      </section>
    </div>
  </div>
}
