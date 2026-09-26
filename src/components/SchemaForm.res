// Schema-driven form for a tool's `inputSchema`.
//
// Leaves become typed controls: enums -> <select>, booleans -> checkbox,
// integer/number -> <input type="number">, strings -> text, nested objects are
// rendered recursively. Arrays and anything unrecognised fall back to a JSON
// editor. Native `<form>` validation enforces `required` and numeric types.

type widget =
  | Object
  | Select(array<JSON.t>)
  | Checkbox
  | Integer
  | Number
  | Text
  | Json

let resolve = (schema: JSON.t, root: JSON.t): JSON.t =>
  switch JSON.Decode.object(schema) {
  | Some(dict) =>
    switch Schema.resolveRef(dict, root) {
    | Some(resolved) => resolved
    | None => schema
    }
  | None => schema
  }

let propertiesOf = (schema: JSON.t): option<dict<JSON.t>> =>
  switch JSON.Decode.object(schema) {
  | Some(dict) => dict->Dict.get("properties")->Option.flatMap(JSON.Decode.object)
  | None => None
  }

let enumOf = (schema: JSON.t): option<array<JSON.t>> =>
  switch JSON.Decode.object(schema) {
  | Some(dict) => dict->Dict.get("enum")->Option.flatMap(JSON.Decode.array)
  | None => None
  }

let typeOf = (schema: JSON.t): option<string> =>
  switch JSON.Decode.object(schema) {
  | Some(dict) => dict->Dict.get("type")->Option.flatMap(JSON.Decode.string)
  | None => None
  }

let descriptionOf = (schema: JSON.t): option<string> =>
  switch JSON.Decode.object(schema) {
  | Some(dict) => dict->Dict.get("description")->Option.flatMap(JSON.Decode.string)
  | None => None
  }

let classify = (schema: JSON.t): widget =>
  switch enumOf(schema) {
  | Some(values) if Array.length(values) > 0 => Select(values)
  | _ =>
    switch typeOf(schema) {
    | Some("object") =>
      switch propertiesOf(schema) {
      | Some(_) => Object
      | None => Json
      }
    | Some("boolean") => Checkbox
    | Some("integer") => Integer
    | Some("number") => Number
    | Some("string") => Text
    | Some("array") => Json
    | Some(_) | None =>
      switch propertiesOf(schema) {
      | Some(_) => Object
      | None => Json
      }
    }
  }

let fieldLabel = (name, required, description) =>
  <div className="schema-label">
    <span className="schema-name">
      {name->React.string}
      {required ? <span className="required-mark"> {"*"->React.string} </span> : React.null}
    </span>
    {switch description {
    | Some(description) => <span className="schema-desc"> {description->React.string} </span>
    | None => React.null
    }}
  </div>

let renderText = (~current: option<JSON.t>, ~required: bool, ~onChange: string => unit) => {
  let initial = switch current {
  | Some(JSON.String(value)) => value
  | _ => ""
  }
  <input
    className="text-input"
    defaultValue=initial
    required
    spellCheck=false
    onChange={event => onChange(ReactEvent.Form.target(event)["value"])}
  />
}

let renderNumber = (
  ~current: option<JSON.t>,
  ~integer: bool,
  ~required: bool,
  ~onChange: option<float> => unit,
) => {
  let initial = switch current {
  | Some(JSON.Number(value)) =>
    if integer {
      value->Int.fromFloat->Int.toString
    } else {
      value->Float.toString
    }
  | _ => ""
  }
  <input
    className="text-input"
    type_="text"
    inputMode={integer ? "numeric" : "decimal"}
    pattern={integer ? "-?[0-9]+" : "-?[0-9]+(\\.[0-9]+)?"}
    defaultValue=initial
    required
    spellCheck=false
    onChange={event => {
      let text = ReactEvent.Form.target(event)["value"]
      switch text {
      | "" => onChange(None)
      | _ =>
        switch Float.fromString(text) {
        | Some(value) => onChange(Some(value))
        | None => ()
        }
      }
    }}
  />
}

let renderCheckbox = (~current: option<JSON.t>, ~onChange: bool => unit) => {
  let checked = switch current {
  | Some(JSON.Boolean(value)) => value
  | _ => false
  }
  <input
    className="checkbox-input"
    type_="checkbox"
    checked
    onChange={event => onChange(ReactEvent.Form.target(event)["checked"])}
  />
}

let renderSelect = (
  ~values: array<JSON.t>,
  ~current: option<JSON.t>,
  ~required: bool,
  ~onChange: JSON.t => unit,
) => {
  let toKey = (value: JSON.t) => value->JSON.stringify
  let currentKey = current->Option.map(toKey)->Option.getOr("")

  <select
    className="select-input"
    value=currentKey
    required
    onChange={event => {
      let key = ReactEvent.Form.target(event)["value"]
      switch values->Array.find(value => toKey(value) == key) {
      | Some(value) => onChange(value)
      | None => ()
      }
    }}>
    {required ? React.null : <option value=""> {"(unset)"->React.string} </option>}
    {values
    ->Array.map(value =>
      <option key={toKey(value)} value={toKey(value)}>
        {switch JSON.Decode.string(value) {
        | Some(text) => text->React.string
        | None => toKey(value)->React.string
        }}
      </option>
    )
    ->React.array}
  </select>
}

let isRequired = (schema: JSON.t, name: string): bool =>
  Schema.requiredFields(schema)->Array.some(required => required == name)

let rec renderFields = (
  ~schema: JSON.t,
  ~root: JSON.t,
  ~value: JSON.t,
  ~onChange: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): array<React.element> =>
  if depth > 12 {
    []
  } else {
    let properties = propertiesOf(schema)->Option.getOr(Dict.make())
    properties
    ->Dict.toArray
    ->Array.map(((name, propSchema)) =>
      renderField(
        ~name,
        ~propSchema,
        ~required=isRequired(schema, name),
        ~parentValue=value,
        ~root,
        ~onChange,
        ~reportError,
        ~path=path == "" ? name : path ++ "." ++ name,
        ~depth,
      )
    )
  }
and renderField = (
  ~name: string,
  ~propSchema: JSON.t,
  ~required: bool,
  ~parentValue: JSON.t,
  ~root: JSON.t,
  ~onChange: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): React.element => {
  let resolved = resolve(propSchema, root)
  let description = switch descriptionOf(propSchema) {
  | Some(description) => Some(description)
  | None => descriptionOf(resolved)
  }
  let current = JsonValue.getField(parentValue, name)
  let setValue = (value: JSON.t) => onChange(JsonValue.setField(parentValue, name, value))
  let clearValue = () => onChange(JsonValue.removeField(parentValue, name))
  let widget = classify(resolved)

  let control = switch widget {
  | Object =>
    let nestedValue = current->Option.getOr(JSON.Encode.object(Dict.make()))
    <div className="schema-nested">
      {renderFields(
        ~schema=resolved,
        ~root,
        ~value=nestedValue,
        ~onChange=setValue,
        ~reportError,
        ~path,
        ~depth=depth + 1,
      )->React.array}
    </div>
  | Select(values) => renderSelect(~values, ~current, ~required, ~onChange=setValue)
  | Checkbox => renderCheckbox(~current, ~onChange=value => setValue(JSON.Encode.bool(value)))
  | Integer =>
    renderNumber(~current, ~integer=true, ~required, ~onChange=value =>
      switch value {
      | Some(number) => setValue(JSON.Encode.float(number))
      | None => clearValue()
      }
    )
  | Number =>
    renderNumber(~current, ~integer=false, ~required, ~onChange=value =>
      switch value {
      | Some(number) => setValue(JSON.Encode.float(number))
      | None => clearValue()
      }
    )
  | Text =>
    renderText(~current, ~required, ~onChange=text =>
      switch text {
      | "" => clearValue()
      | text => setValue(JSON.Encode.string(text))
      }
    )
  | Json =>
    <JsonControl
      value=current
      required
      onChange=setValue
      onValidityChange={valid => reportError(path, valid)}
    />
  }

  <div className={widget == Object ? "schema-field object" : "schema-field"} key={name}>
    {fieldLabel(name, required, description)}
    {control}
  </div>
}

@react.component
let make = (
  ~schema: JSON.t,
  ~value: JSON.t,
  ~onChange: JSON.t => unit,
  ~onValidityChange: bool => unit,
) => {
  let errors = React.useRef(Dict.make())
  let (hasError, setHasError) = React.useState(() => false)

  let reportError = (path, valid) => {
    errors.current->Dict.set(path, valid)
    setHasError(_ => errors.current->Dict.toArray->Array.some(((_, valid)) => !valid))
  }

  React.useEffect1(
    () => {
      onValidityChange(!hasError)
      None
    },
    [hasError],
  )

  <div className="schema-form">
    {renderFields(~schema, ~root=schema, ~value, ~onChange, ~reportError, ~path="", ~depth=0)->React.array}
  </div>
}
