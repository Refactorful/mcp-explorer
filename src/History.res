// Minimal History API bindings for in-app navigation.
//
// A view is `{tab, name?}`: `name` is the selected tool/prompt, or absent for
// the list ("home") view. Pushing a view on selection lets the browser back
// button walk back to the list; `onPopState` restores a view on back/forward.

@val external pushState: ({..}, string, string) => unit = "window.history.pushState"
@val external replaceState: ({..}, string, string) => unit = "window.history.replaceState"
@val external back: unit => unit = "window.history.back"
@val external addEventListener: (string, 'event => unit) => unit = "window.addEventListener"

type popStateEvent

@get external state: popStateEvent => nullable<{..}> = "state"

type view = {tab: string, name: option<string>}

let encode = (view: view): {..} => {"tab": view.tab, "name": view.name->Option.getOr("")}

let decode = (raw: {..}): view => {
  let tab: string = raw["tab"]
  let name: string = raw["name"]
  {tab, name: name == "" ? None : Some(name)}
}

let push = (view: view) => pushState(encode(view), "", "")

let replace = (view: view) => replaceState(encode(view), "", "")

let onPopState = (handler: view => unit) =>
  addEventListener("popstate", event =>
    switch (event: popStateEvent)->state->Nullable.toOption {
    | Some(raw) => handler(decode(raw))
    | None => handler({tab: "Tools", name: None})
    }
  )
