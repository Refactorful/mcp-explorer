// Free-form JSON editor used for arrays / untyped sub-schemas.
//
// Kept uncontrolled (so typing is never clobbered by a re-render) and reports
// validity upward so the surrounding form can block submission on bad JSON.

@react.component
let make = (
  ~value: option<JSON.t>,
  ~required: bool,
  ~onChange: JSON.t => unit,
  ~onValidityChange: bool => unit,
) => {
  let (error, setError) = React.useState(() => false)
  let initial = value->Option.map(json => json->JSON.stringify)->Option.getOr("")

  <div>
    <textarea
      className={error ? "json-editor invalid" : "json-editor"}
      defaultValue=initial
      rows=4
      spellCheck=false
      required
      placeholder={required ? "required" : "optional JSON"}
      onChange={event => {
        let text = ReactEvent.Form.target(event)["value"]
        switch text->String.trim {
        | "" =>
          setError(_ => false)
          onValidityChange(true)
        | text =>
          switch (
            try {
              Some(JSON.parseOrThrow(text))
            } catch {
            | JsExn(_) => None
            }
          ) {
          | Some(json) =>
            setError(_ => false)
            onValidityChange(true)
            onChange(json)
          | None =>
            setError(_ => true)
            onValidityChange(false)
          }
        }
      }}
    />
    {error ? <div className="parse-error"> {"Invalid JSON"->React.string} </div> : React.null}
  </div>
}
