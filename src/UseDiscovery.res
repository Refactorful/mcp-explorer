// Loads server/discover plus tools, prompts and resources for an endpoint.
//
// Prompts and resources are only fetched when the server advertises the
// capability, so their tabs can be hidden without a second round trip.

type loaded = {
  discover: Protocol.discoverResult,
  tools: array<Protocol.tool>,
  prompts: array<Protocol.prompt>,
  resources: array<Protocol.resource>,
  resourceTemplates: array<Protocol.resourceTemplate>,
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
          let resources = if discover.capabilities.resources {
            switch await Mcp.listResources(client) {
            | Ok(resources) => resources
            | Error(_) => []
            }
          } else {
            []
          }
          let resourceTemplates = if discover.capabilities.resources {
            switch await Mcp.listResourceTemplates(client) {
            | Ok(templates) => templates
            | Error(_) => []
            }
          } else {
            []
          }
          if !cancelled.contents {
            setState(_ => Loaded({discover, tools, prompts, resources, resourceTemplates}))
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
