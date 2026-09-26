// Loads server/discover plus tools and prompts for an endpoint.
//
// Prompts are only fetched when the server advertises the capability, so the
// tab can be hidden without a second round trip.

type loaded = {
  discover: Protocol.discoverResult,
  tools: array<Protocol.tool>,
  prompts: array<Protocol.prompt>,
}

type state =
  | Loading
  | Loaded(loaded)
  | Failed(Protocol.apiError)

let use = (endpoint: string, refreshKey: int): state => {
  let (state, setState) = React.useState(() => Loading)

  React.useEffect2(
    () => {
      let cancelled = ref(false)
      setState(_ => Loading)
      let client = Mcp.make(~endpoint)
      let load = async () => {
        switch await Mcp.discover(client) {
        | Error(err) =>
          if !cancelled.contents {
            setState(_ => Failed(err))
          }
        | Ok(discover) =>
          let tools = switch await Mcp.listTools(client) {
          | Ok(tools) => tools
          | Error(_) => []
          }
          let prompts = if discover.capabilities.prompts {
            switch await Mcp.listPrompts(client) {
            | Ok(prompts) => prompts
            | Error(_) => []
            }
          } else {
            []
          }
          if !cancelled.contents {
            setState(_ => Loaded({discover, tools, prompts}))
          }
        }
      }
      load()->ignore
      Some(() => {
        cancelled := true
      })
    },
    (endpoint, refreshKey),
  )

  state
}
