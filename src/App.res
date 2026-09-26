@react.component
let make = (~initialEndpoint: string) => {
  let (endpoint, setEndpoint) = React.useState(() => initialEndpoint)
  let (refreshKey, setRefreshKey) = React.useState(() => 0)
  let (activeTab, setActiveTab) = React.useState(() => "Tools")
  let (selectedTool, setSelectedTool) = React.useState(() => None)
  let (selectedPrompt, setSelectedPrompt) = React.useState(() => None)
  let (execEnabled, setExecEnabled) = React.useState(() => Config.execDefault)
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

    let content = if activeTab == "Prompts" && showPrompts {
      switch selectedPrompt {
      | Some(name) =>
        switch prompts->Array.find(prompt => prompt.name == name) {
        | Some(prompt) =>
          <PromptDetail
            key={prompt.name}
            prompt
            endpoint
            onBack={() => History.back()}
          />
        | None =>
          <PromptList
            prompts
            selectedName=selectedPrompt
            onSelect={name => navigate({tab: "Prompts", name: Some(name)})}
          />
        }
      | None =>
        <PromptList
          prompts
          selectedName=selectedPrompt
          onSelect={name => navigate({tab: "Prompts", name: Some(name)})}
        />
      }
    } else {
      switch selectedTool {
      | Some(name) =>
        switch tools->Array.find(tool => tool.name == name) {
        | Some(tool) =>
          <ToolDetail
            key={tool.name}
            tool
            endpoint
            execEnabled
            onBack={() => History.back()}
          />
        | None =>
          <ToolList
            tools
            selectedName=selectedTool
            onSelect={name => navigate({tab: "Tools", name: Some(name)})}
          />
        }
      | None =>
        <ToolList
          tools
          selectedName=selectedTool
          onSelect={name => navigate({tab: "Tools", name: Some(name)})}
        />
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
      {content}
    </div>
  }

  <div className="app">
    <header className="app-header">
      <div className="brand">
        <h1> {"MCP Viewer"->React.string} </h1>
        <span className="subtitle"> {"MCP server inspector"->React.string} </span>
      </div>
      <ConfigBar
        endpoint
        onEndpointChange={value => setEndpoint(_ => value)}
        onRefresh
        execEnabled
        onToggleExec={() => setExecEnabled(value => !value)}
        loading
      />
    </header>
    {body}
  </div>
}
