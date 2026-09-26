@react.component
let make = (~value: string, ~onChange: string => unit, ~error: option<string>) =>
  <div className="editor">
    <textarea
      className={error->Option.isSome ? "json-editor invalid" : "json-editor"}
      value
      rows=8
      spellCheck=false
      onChange={event => onChange(ReactEvent.Form.target(event)["value"])}
    />
    {switch error {
    | Some(message) => <div className="parse-error"> {message->React.string} </div>
    | None => React.null
    }}
  </div>
