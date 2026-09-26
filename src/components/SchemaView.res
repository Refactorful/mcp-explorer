@react.component
let make = (~schema: JSON.t) => <pre className="code-block"> {schema->Schema.pretty->React.string} </pre>
