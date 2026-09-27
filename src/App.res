@react.component
let make = (
  ~initialEndpoint: string,
  ~initialExecEnabled: option<bool>,
  ~initialEndpointEditable: option<bool>,
) => {
  let (endpoint, setEndpoint) = React.useState(() => initialEndpoint)
  let (refreshKey, setRefreshKey) = React.useState(() => 0)
  let (activeTab, setActiveTab) = React.useState(() => "Tools")
  let (selectedTool, setSelectedTool) = React.useState(() => None)
  let (selectedPrompt, setSelectedPrompt) = React.useState(() => None)
  // Execution is fixed for the lifetime of the mount: it is either forced by the
  // host via `execEnabled`, or falls back to the build-time default. There is no
  // in-app toggle; hosts control it when they mount the viewer.
  let execEnabled = initialExecEnabled->Option.getOr(Config.execDefault)
  // Whether the endpoint field is editable in the toolbar. Hosts can lock it to
  // fix the viewer to a single server.
  let endpointEditable = initialEndpointEditable->Option.getOr(true)
  let discovery = UseDiscovery.use(endpoint, refreshKey)

  // Apply a view without touching history (used by popstate / push).
  let applyView = (view: History.view) => {
    setActiveTab(_ => view.tab)
    switch view.tab {
    | "Prompts" =>
      setSelectedTool(_ => None)
      setSelectedPrompt(_ => view.name)
    | _ =>
      setSelectedPrompt(_ => None)
      setSelectedTool(_ => view.name)
    }
  }

  let navigate = (view: History.view) => {
    applyView(view)
    History.push(view)
  }

  // Seed a "home" entry so the back button has somewhere to return to, and
  // restore views on browser back/forward.
  React.useEffect0(() => {
    History.replace({tab: "Tools", name: None})
    History.onPopState(applyView)
    None
  })

  let loading = switch discovery {
  | UseDiscovery.Loading => true
  | UseDiscovery.Loaded(_) | UseDiscovery.Failed(_) => false
  }

  let onRefresh = () => {
    setSelectedTool(_ => None)
    setSelectedPrompt(_ => None)
    History.replace({tab: activeTab, name: None})
    setRefreshKey(key => key + 1)
  }

  let body = switch discovery {
  | UseDiscovery.Loading =>
    <div className="panel muted"> {"Loading MCP server…"->React.string} </div>
  | UseDiscovery.Failed(err) =>
    <div className="panel error-box">
      <h2> {"Failed to load the MCP server"->React.string} </h2>
      <p> {Protocol.apiErrorToString(err)->React.string} </p>
      <p className="muted"> {endpoint->React.string} </p>
      {Config.isDevBuild
        ? <p className="warning">
            {"Dev tip: use the relative `/mcp` endpoint — Vite proxies it to the MCP server (MCP_DEV_TARGET). Absolute cross-origin URLs are rejected by Oxygen."->React.string}
          </p>
        : React.null}
    </div>
  | UseDiscovery.Loaded({discover, tools, prompts}) =>
    let showPrompts = discover.capabilities.prompts
    let tabs = showPrompts ? ["Tools", "Prompts"] : ["Tools"]
    let version = discover.supportedVersions->Array.get(0)->Option.getOr("")
    let isPrompts = activeTab == "Prompts" && showPrompts
    let hasDetail = isPrompts ? selectedPrompt->Option.isSome : selectedTool->Option.isSome

    let emptyDetail = kind =>
      <div className="empty-detail muted">
        {("Select a " ++ kind ++ " from the list to inspect it.")->React.string}
      </div>

    let listView = if isPrompts {
      <PromptList
        prompts
        selectedName=selectedPrompt
        onSelect={name => navigate({tab: "Prompts", name: Some(name)})}
      />
    } else {
      <ToolList
        tools
        selectedName=selectedTool
        onSelect={name => navigate({tab: "Tools", name: Some(name)})}
      />
    }

    let detailView = if isPrompts {
      switch selectedPrompt->Option.flatMap(name =>
        prompts->Array.find(prompt => prompt.name == name)
      ) {
      | Some(prompt) =>
        <PromptDetail
          key={prompt.name}
          prompt
          endpoint
          onBack={() => History.back()}
        />
      | None => emptyDetail("prompt")
      }
    } else {
      switch selectedTool->Option.flatMap(name => tools->Array.find(tool => tool.name == name)) {
      | Some(tool) =>
        <ToolDetail
          key={tool.name}
          tool
          endpoint
          execEnabled
          onBack={() => History.back()}
        />
      | None => emptyDetail("tool")
      }
    }

    <div className="panel">
      <div className="panel-head">
        <Tabs
          tabs
          active=activeTab
          onSelect={value => navigate({tab: value, name: None})}
        />
        {version == ""
          ? React.null
          : <span className="pill"> {("Protocol " ++ version)->React.string} </span>}
      </div>
      <div className={hasDetail ? "split has-detail" : "split"}>
        <aside className="split-list"> {listView} </aside>
        <section className="split-detail"> {detailView} </section>
      </div>
    </div>
  }

  <div className="app">
    <header className="app-header">
      <div className="brand">
        <h1> {"MCP Explorer"->React.string} </h1>
        <span className="subtitle"> {"MCP server inspector"->React.string} </span>
      </div>
      <ConfigBar
        endpoint
        onEndpointChange={value => setEndpoint(_ => value)}
        endpointLocked={!endpointEditable}
        onRefresh
        loading
      />
    </header>
    {body}
  </div>
}
