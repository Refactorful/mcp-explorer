// Schema-driven form for a tool's `inputSchema`.
//
// Leaves become typed controls: enums (and `const`) -> <select>, booleans ->
// checkbox, integer/number -> validated text, strings -> text. Containers
// recurse through the same renderer:
//   - objects (`properties`) -> nested fields, plus a dynamic key/value editor
//     when `additionalProperties` / `patternProperties` are present;
//   - maps (`additionalProperties` / `patternProperties` without `properties`)
//     -> dynamic key/value editor;
//   - arrays (singular or tuple `items`) -> dynamic list with add/remove/reorder;
//   - `oneOf` / `anyOf` -> a branch selector, with optional `discriminator`.
// `allOf` and `$ref` are collapsed up front, and `type` unions (e.g.
// `["string","null"]`) resolve to their non-null member. Anything still
// unrecognised falls back to a JSON editor.

type widget =
  | Object
  | Map(JSON.t)
  | Array(JSON.t)
  | Variant(array<JSON.t>)
  | Select(array<JSON.t>)
  | Checkbox
  | Integer
  | Number
  | Text
  | Json

let effective = Schema.effective

let enumOf = (schema: JSON.t): option<array<JSON.t>> =>
  JsonValue.getField(schema, "enum")->Option.flatMap(JSON.Decode.array)

let descriptionOf = (schema: JSON.t): option<string> =>
  JsonValue.getField(schema, "description")->Option.flatMap(JSON.Decode.string)

let mapOrJson = (schema: JSON.t): widget =>
  switch Schema.additionalPropertiesOf(schema) {
  | Some(valueSchema) => Map(valueSchema)
  | None =>
    switch Schema.patternPropertiesOf(schema) {
    | Some(_) => Map(JSON.Encode.bool(true))
    | None => Json
    }
  }

let classify = (schema: JSON.t): widget =>
  switch enumOf(schema) {
  | Some(values) if Array.length(values) > 0 => Select(values)
  | _ =>
    switch Schema.constOf(schema) {
    | Some(value) => Select([value])
    | None =>
      switch Schema.variantsOf(schema) {
      | Some(branches) => Variant(branches)
      | None =>
        switch Schema.primaryType(schema) {
        | Some("object") =>
          switch Schema.propertiesOf(schema) {
          | Some(_) => Object
          | None => mapOrJson(schema)
          }
        | Some("array") =>
          Array(Schema.itemSchemaOf(schema)->Option.getOr(JSON.Encode.bool(true)))
        | Some("boolean") => Checkbox
        | Some("integer") => Integer
        | Some("number") => Number
        | Some("string") => Text
        | Some(_) | None =>
          switch Schema.propertiesOf(schema) {
          | Some(_) => Object
          | None => mapOrJson(schema)
          }
        }
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

// --- map / pattern helpers --------------------------------------------------

let extraValueSchema = (extra: option<JSON.t>, patterns: array<(string, JSON.t)>): JSON.t =>
  switch extra {
  | Some(schema) => schema
  | None =>
    switch Array.length(patterns) {
    | 0 => JSON.Encode.bool(true)
    | _ =>
      let (_, schema) = Array.getUnsafe(patterns, 0)
      schema
    }
  }

let valueSchemaForKey = (
  key: string,
  extra: option<JSON.t>,
  patterns: array<(string, JSON.t)>,
): JSON.t =>
  switch patterns->Array.find(((pattern, _)) => Schema.matchesPattern(pattern, key)) {
  | Some((_, schema)) => schema
  | None => extraValueSchema(extra, patterns)
  }

// --- composition helpers ----------------------------------------------------

let stringifyValue = (value: JSON.t): string =>
  switch JSON.Decode.string(value) {
  | Some(text) => text
  | None => value->JSON.stringify
  }

let variantLabel = (discriminator: option<string>, branch: JSON.t, index: int): string =>
  switch Schema.titleOf(branch) {
  | Some(title) => title
  | None =>
    switch discriminator->Option.flatMap(property =>
      Schema.propertiesOf(branch)
      ->Option.flatMap(properties => properties->Dict.get(property))
      ->Option.flatMap(Schema.constOf)
    ) {
    | Some(value) => stringifyValue(value)
    | None =>
      switch Schema.constOf(branch) {
      | Some(value) => stringifyValue(value)
      | None =>
        switch Schema.primaryType(branch) {
        | Some(type_) => type_
        | None => "Option " ++ Int.toString(index + 1)
        }
      }
    }
  }

let matchesBranch = (value: JSON.t, branch: JSON.t, root: JSON.t): bool => {
  let schema = effective(branch, root, 0)
  let typeOk = switch Schema.primaryType(schema) {
  | Some("object") => JSON.Decode.object(value)->Option.isSome
  | Some("array") => JSON.Decode.array(value)->Option.isSome
  | Some("string") => JSON.Decode.string(value)->Option.isSome
  | Some("integer") | Some("number") => JSON.Decode.float(value)->Option.isSome
  | Some("boolean") => JSON.Decode.bool(value)->Option.isSome
  | _ => true
  }
  let requiredOk = Schema.requiredFields(schema)->Array.reduce(true, (acc, name) =>
    acc && JsonValue.getField(value, name)->Option.isSome
  )
  typeOk && requiredOk
}

let initialVariant = (
  ~current: option<JSON.t>,
  ~branches: array<JSON.t>,
  ~root: JSON.t,
  ~discriminator: option<string>,
): int =>
  switch current {
  | None => 0
  | Some(value) =>
    let byDiscriminator = switch discriminator {
    | None => -1
    | Some(property) =>
      let actual = JsonValue.getField(value, property)
      let rec find = index =>
        if index >= Array.length(branches) {
          -1
        } else {
          let expected =
            Schema.propertiesOf(effective(Array.getUnsafe(branches, index), root, 0))
            ->Option.flatMap(properties => properties->Dict.get(property))
            ->Option.flatMap(Schema.constOf)
          if actual->Option.isSome && actual == expected {
            index
          } else {
            find(index + 1)
          }
        }
      find(0)
    }
    let byMatch = {
      let rec find = index =>
        if index >= Array.length(branches) {
          -1
        } else if matchesBranch(value, Array.getUnsafe(branches, index), root) {
          index
        } else {
          find(index + 1)
        }
      find(0)
    }
    byDiscriminator >= 0 ? byDiscriminator : byMatch >= 0 ? byMatch : 0
  }

// --- recursive renderer -----------------------------------------------------

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
    let properties = Schema.propertiesOf(schema)->Option.getOr(Dict.make())
    properties
    ->Dict.toArray
    ->Array.map(((name, propSchema)) =>
      renderField(
        ~name,
        ~propSchema,
        ~required=Schema.requiredFields(schema)->Array.some(required => required == name),
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
  let resolved = effective(propSchema, root, 0)
  let description = switch descriptionOf(propSchema) {
  | Some(description) => Some(description)
  | None => descriptionOf(resolved)
  }
  let current = JsonValue.getField(parentValue, name)
  let setValue = (value: JSON.t) => onChange(JsonValue.setField(parentValue, name, value))
  let clearValue = () => onChange(JsonValue.removeField(parentValue, name))
  let className = switch classify(resolved) {
  | Object | Map(_) | Array(_) | Variant(_) => "schema-field object"
  | Json => "schema-field json"
  | Select(_) | Checkbox | Integer | Number | Text => "schema-field"
  }

  <div className={className} key={name}>
    {fieldLabel(name, required, description)}
    {renderControl(
      ~resolved,
      ~current,
      ~required,
      ~root,
      ~onValue=setValue,
      ~onClear=clearValue,
      ~reportError,
      ~path,
      ~depth,
    )}
  </div>
}
and renderControl = (
  ~resolved: JSON.t,
  ~current: option<JSON.t>,
  ~required: bool,
  ~root: JSON.t,
  ~onValue: JSON.t => unit,
  ~onClear: unit => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): React.element => {
  let onNumberChange = (value: option<float>) =>
    switch value {
    | Some(number) => onValue(JSON.Encode.float(number))
    | None => onClear()
    }

  switch classify(resolved) {
  | Object =>
    let nestedValue = current->Option.getOr(JSON.Encode.object(Dict.make()))
    let extra = Schema.additionalPropertiesOf(resolved)
    let patterns = Schema.patternPropertiesOf(resolved)->Option.getOr([])
    let hasExtras = extra->Option.isSome || Array.length(patterns) > 0
    <div className="schema-nested">
      {renderFields(
        ~schema=resolved,
        ~root,
        ~value=nestedValue,
        ~onChange=onValue,
        ~reportError,
        ~path,
        ~depth=depth + 1,
      )->React.array}
      {hasExtras
        ? renderExtraMap(~resolved, ~current, ~required, ~root, ~onValue, ~reportError, ~path, ~depth)
        : React.null}
    </div>
  | Map(_) =>
    renderExtraMap(~resolved, ~current, ~required, ~root, ~onValue, ~reportError, ~path, ~depth)
  | Array(itemSchema) =>
    renderArray(~resolved, ~itemSchema, ~current, ~root, ~onValue, ~reportError, ~path, ~depth)
  | Variant(branches) =>
    renderVariant(~resolved, ~branches, ~current, ~required, ~root, ~onValue, ~reportError, ~path, ~depth)
  | Select(values) => renderSelect(~values, ~current, ~required, ~onChange=onValue)
  | Checkbox => renderCheckbox(~current, ~onChange=value => onValue(JSON.Encode.bool(value)))
  | Integer => renderNumber(~current, ~integer=true, ~required, ~onChange=onNumberChange)
  | Number => renderNumber(~current, ~integer=false, ~required, ~onChange=onNumberChange)
  | Text =>
    renderText(~current, ~required, ~onChange=text =>
      switch text {
      | "" => onClear()
      | text => onValue(JSON.Encode.string(text))
      }
    )
  | Json =>
    <JsonControl
      value=current
      required
      onChange=onValue
      onValidityChange={valid => reportError(path, valid)}
    />
  }
}
and renderChild = (
  ~schema: JSON.t,
  ~current: option<JSON.t>,
  ~root: JSON.t,
  ~set: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
  ~required: bool=false,
): React.element =>
  renderControl(
    ~resolved=effective(schema, root, 0),
    ~current,
    ~required,
    ~root,
    ~onValue=set,
    ~onClear=() => set(JSON.Encode.null),
    ~reportError,
    ~path,
    ~depth=depth + 1,
  )
and renderExtraMap = (
  ~resolved: JSON.t,
  ~current: option<JSON.t>,
  ~required: bool,
  ~root: JSON.t,
  ~onValue: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): React.element => {
  let extra = Schema.additionalPropertiesOf(resolved)
  let patterns = Schema.patternPropertiesOf(resolved)->Option.getOr([])
  let reserved = Schema.propertyNames(resolved)
  let valueSchema = extraValueSchema(extra, patterns)
  let validityPath = path == "" ? "*" : path ++ ".*"
  let min = Schema.minPropertiesOf(resolved)
  let minProperties = required && min == 0 ? 1 : min
  // Container values render a full-width nested control, so the map row gives
  // them their own line instead of a tall empty key column.
  let valueIsContainer = (key: string): bool =>
    switch classify(effective(valueSchemaForKey(key, extra, patterns), root, 0)) {
    | Object | Map(_) | Array(_) | Variant(_) | Json => true
    | Select(_) | Checkbox | Integer | Number | Text => false
    }

  <MapControl
    value=current
    newValue={Schema.defaultsWithRoot(valueSchema, root)}
    reserved
    keyPatterns={patterns->Array.map(((pattern, _)) => pattern)}
    allowAdditional={extra->Option.isSome || Array.length(patterns) == 0}
    minProperties
    maxProperties={Schema.maxPropertiesOf(resolved)}
    onChange=onValue
    onValidityChange={valid => reportError(validityPath, valid)}
    valueIsContainer
    renderValue={(key, entryValue, setEntryValue) =>
      renderChild(
        ~schema=valueSchemaForKey(key, extra, patterns),
        ~current=entryValue,
        ~root,
        ~set=setEntryValue,
        ~reportError,
        ~path=path == "" ? key : path ++ "." ++ key,
        ~depth,
      )
    }
  />
}
and renderArray = (
  ~resolved: JSON.t,
  ~itemSchema: JSON.t,
  ~current: option<JSON.t>,
  ~root: JSON.t,
  ~onValue: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): React.element => {
  let tuple = Schema.tupleItemsOf(resolved)

  <ArrayControl
    value=current
    newValue={index =>
      switch tuple {
      | Some(items) if index < Array.length(items) =>
        Schema.defaultsWithRoot(Array.getUnsafe(items, index), root)
      | _ => Schema.defaultsWithRoot(itemSchema, root)
      }
    }
    minItems={Schema.minItemsOf(resolved)}
    maxItems={Schema.maxItemsOf(resolved)}
    onChange=onValue
    onValidityChange={valid => reportError(path, valid)}
    renderItem={(index, itemValue, setItemValue) => {
      let schema = switch tuple {
      | Some(items) if index < Array.length(items) => Array.getUnsafe(items, index)
      | _ => itemSchema
      }
      renderChild(
        ~schema,
        ~current=itemValue,
        ~root,
        ~set=setItemValue,
        ~reportError,
        ~path=path ++ "[" ++ Int.toString(index) ++ "]",
        ~depth,
      )
    }}
  />
}
and renderVariant = (
  ~resolved: JSON.t,
  ~branches: array<JSON.t>,
  ~current: option<JSON.t>,
  ~required: bool,
  ~root: JSON.t,
  ~onValue: JSON.t => unit,
  ~reportError: (string, bool) => unit,
  ~path: string,
  ~depth: int,
): React.element => {
  let discriminator = Schema.discriminatorOf(resolved)
  let effectiveBranches = branches->Array.map(branch => effective(branch, root, 0))
  let labels = effectiveBranches->Array.mapWithIndex((branch, index) =>
    variantLabel(discriminator, branch, index)
  )
  let initial = initialVariant(~current, ~branches=effectiveBranches, ~root, ~discriminator)

  <VariantControl
    value=current
    labels
    newValue={index => Schema.defaultsWithRoot(Array.getUnsafe(effectiveBranches, index), root)}
    initialIndex=initial
    onChange=onValue
    renderBranch={(index, branchValue, setBranchValue) =>
      renderChild(
        ~schema=Array.getUnsafe(effectiveBranches, index),
        ~current=branchValue,
        ~required,
        ~root,
        ~set=setBranchValue,
        ~reportError,
        ~path,
        ~depth,
      )
    }
  />
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

  let effectiveSchema = effective(schema, schema, 0)

  // The root is normally a plain object; render its fields flat. Anything else
  // (a map, array, composition or scalar root, or an object that also carries
  // `additionalProperties`/`patternProperties`) goes through the control path.
  let body = switch classify(effectiveSchema) {
  | Object
    if (
      Schema.additionalPropertiesOf(effectiveSchema)->Option.isNone &&
      Schema.patternPropertiesOf(effectiveSchema)->Option.isNone
    ) =>
    renderFields(
      ~schema=effectiveSchema,
      ~root=schema,
      ~value,
      ~onChange,
      ~reportError,
      ~path="",
      ~depth=0,
    )->React.array
  | _ =>
    [
      renderControl(
        ~resolved=effectiveSchema,
        ~current=Some(value),
        ~required=false,
        ~root=schema,
        ~onValue=onChange,
        ~onClear=() => onChange(JSON.Encode.null),
        ~reportError,
        ~path="",
        ~depth=0,
      ),
    ]->React.array
  }

  <div className="schema-form"> {body} </div>
}
