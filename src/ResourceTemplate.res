// RFC 6570 URI templates, limited to the expressions MCP servers use in
// practice: simple string expansion (`{name}`) and reserved expansion
// (`{+name}`). Anything else (`{?a,b}`, `{/id}`, `{#frag}`, prefixes, ...) or
// malformed/mismatched braces makes the template "complex"; callers then fall
// back to a raw URI input.

type variable = {name: string, reserved: bool}

@val external encodeURI: string => string = "encodeURI"
@val external encodeURIComponent: string => string = "encodeURIComponent"

// JS-side scanner: returns each expression body (without braces) when every
// expression is simple, or `null` when the template is complex. An empty array
// means the template has no expressions at all.
let rawExpressions: string => nullable<array<string>> = %raw(`(function(template) {
  var re = /\{([^{}]*)\}/g;
  var out = [];
  var match;
  while ((match = re.exec(template)) !== null) {
    var expression = match[1];
    var body = expression.charAt(0) === "+" ? expression.slice(1) : expression;
    if (!/^[A-Za-z0-9_.%-]+$/.test(body)) return null;
    out.push(expression);
  }
  var stripped = template.replace(/\{[^{}]*\}/g, "");
  if (stripped.indexOf("{") !== -1 || stripped.indexOf("}") !== -1) return null;
  return out;
})`)

let variables = (template: string): array<variable> =>
  switch rawExpressions(template)->Nullable.toOption {
  | None => []
  | Some(expressions) =>
    expressions->Array.map(expression =>
      expression->String.startsWith("+")
        ? {
            name: expression->String.slice(~start=1),
            reserved: true,
          }
        : {name: expression, reserved: false}
    )
  }

let isComplex = (template: string): bool =>
  rawExpressions(template)->Nullable.toOption->Option.isNone

// A `$` in the replacement string would otherwise be interpreted by
// `String.replaceAll`, so double it first.
let escapeReplacement = (value: string) => value->String.replaceAll("$", "$$")

// Substitute the template's variables; `None` when the template is complex.
// Missing values expand to the empty string, as RFC 6570 defines for
// undefined variables.
let substitute = (template: string, values: dict<string>): option<string> =>
  switch rawExpressions(template)->Nullable.toOption {
  | None => None
  | Some(expressions) =>
    let result = ref(template)
    expressions->Array.forEach(expression => {
      let reserved = expression->String.startsWith("+")
      let name = reserved ? expression->String.slice(~start=1) : expression
      let value = values->Dict.get(name)->Option.getOr("")
      let encoded = reserved ? encodeURI(value) : encodeURIComponent(value)
      result :=
        result.contents->String.replaceAll("{" ++ expression ++ "}", escapeReplacement(encoded))
    })
    Some(result.contents)
  }
