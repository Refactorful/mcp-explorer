// Pretty-printed JSON code block. With `label` it renders as a collapsed
// `<details>` disclosure, matching the "raw payload" sections across the UI.

@react.component
let make = (~value: JSON.t, ~label: option<string>=?) =>
  switch label {
  | Some(label) =>
    <details className="content-json">
      <summary> {label->React.string} </summary>
      <pre className="code-block"> {value->Schema.pretty->React.string} </pre>
    </details>
  | None => <pre className="code-block"> {value->Schema.pretty->React.string} </pre>
  }
