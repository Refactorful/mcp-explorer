// Decorative sidebar toggle glyph (a panel + a chevron that flips when open).
// Kept as a plain helper so `make` stays the only React component in the module.
let sidebarIcon = (isOpen: bool): React.element =>
  <svg
    viewBox="0 0 24 24"
    width="18"
    height="18"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    ariaHidden=true>
    <rect x="3" y="4" width="18" height="16" rx="2" />
    <line x1="15" y1="4" x2="15" y2="20" />
    {isOpen ? <path d="M8 9l3 3-3 3" /> : <path d="M11 9l-3 3 3 3" />}
  </svg>

// Tools and prompts render through the same master list.
let toItem = (name: string, description: option<string>): ItemList.item => {name, description}

// The logged message to re-apply when `name` is reopened in a detail pane, if any.
let reopenFor = (reopen: option<Message.reopen>, method: Protocol.method, name: string) =>
  switch reopen {
  | Some(r) if r.message.method == method && r.message.name == Some(name) => Some(r)
  | _ => None
  }

// Remount key: a reopened pane gets a nonce so reopening the same item twice
// re-applies its inputs.
let detailKey = (name: string, reopen: option<Message.reopen>) =>
  switch reopen {
  | Some(r) => name ++ "#" ++ r.nonce->Int.toString
  | None => name
  }

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
  let (messages, setMessages) = React.useState(() => MessageStore.all())
  let (messagesOpen, setMessagesOpen) = React.useState(() => true)
  // Number of messages already seen while the sidebar was open; the badge shows
  // the difference when it is collapsed.
  let (lastRead, setLastRead) = React.useState(() => 0)
  // Set when a history entry is clicked: which message to replay into a detail
  // pane, plus a nonce that forces the pane to remount and re-apply the inputs.
  let (reopen, setReopen) = React.useState(() => (None: option<Message.reopen>))
  let (reopenNonce, setReopenNonce) = React.useState(() => 0)
  // Execution is fixed for the lifetime of the mount: it is either forced by the
  // host via `execEnabled`, or falls back to the build-time default. There is no
  // in-app toggle; hosts control it when they mount the viewer.
  let execEnabled = initialExecEnabled->Option.getOr(Config.execDefault)
  // Whether the endpoint field is editable in the toolbar. Hosts can lock it to
  // fix the viewer to a single server.
  let endpointEditable = initialEndpointEditable->Option.getOr(true)
  let discovery = UseDiscovery.use(endpoint, refreshKey)

  // Keep the sidebar in sync with the transport's message log.
  React.useEffect0(() => {
    let unsubscribe = MessageStore.subscribe(() => setMessages(_ => MessageStore.all()))
    Some(unsubscribe)
  })

  // Apply a view without touching history (used by popstate / push).
  let applyView = (view: History.view) => {
    setActiveTab(_ => view.tab)
    // Any normal navigation drops a pending reopen.
    setReopen(_ => None)
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

  // Reopen a logged call in the matching detail pane with the same inputs.
  let onReopen = (message: Message.t) => {
    let nonce = reopenNonce + 1
    setReopenNonce(_ => nonce)
    let tab = switch message.Message.method {
    | Protocol.ToolsCall => Some("Tools")
    | Protocol.PromptsGet => Some("Prompts")
    | _ => None
    }
    switch (tab, message.Message.name) {
    | (Some(tab), Some(name)) => navigate({tab, name: Some(name)})
    | _ => ()
    }
    setReopen(_ => Some({Message.nonce, message}))
  }

  // Send a fresh copy of a logged request; the transport logs the new attempt.
  let onReplay = (message: Message.t) => {
    let client = Mcp.make(~endpoint)
    let run = async () =>
      await Mcp.replay(
        client,
        ~method=message.Message.method,
        ~name=message.Message.name,
        ~params=message.Message.params,
      )
    run()->ignore
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

  let toggleMessages = () => {
    setLastRead(_ => messages->Array.length)
    setMessagesOpen(current => !current)
  }

  let unread = {
    let value = messagesOpen ? 0 : messages->Array.length - lastRead
    value < 0 ? 0 : value
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
      <ItemList
        items={prompts->Array.map(prompt => toItem(prompt.name, prompt.description))}
        empty="No prompts registered."
        selectedName=selectedPrompt
        onSelect={name => navigate({tab: "Prompts", name: Some(name)})}
      />
    } else {
      <ItemList
        items={tools->Array.map(tool => toItem(tool.name, tool.description))}
        empty="No tools registered."
        selectedName=selectedTool
        onSelect={name => navigate({tab: "Tools", name: Some(name)})}
      />
    }

    let detailView = if isPrompts {
      switch selectedPrompt->Option.flatMap(name =>
        prompts->Array.find(prompt => prompt.name == name)
      ) {
      | Some(prompt) =>
        let promptReopen = reopenFor(reopen, Protocol.PromptsGet, prompt.name)
        <PromptDetail
          key={detailKey(prompt.name, promptReopen)}
          prompt
          endpoint
          reopen=promptReopen
          onBack={() => History.back()}
        />
      | None => emptyDetail("prompt")
      }
    } else {
      switch selectedTool->Option.flatMap(name => tools->Array.find(tool => tool.name == name)) {
      | Some(tool) =>
        let toolReopen = reopenFor(reopen, Protocol.ToolsCall, tool.name)
        <ToolDetail
          key={detailKey(tool.name, toolReopen)}
          tool
          endpoint
          execEnabled
          reopen=toolReopen
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

  <div className={messagesOpen ? "app" : "app collapsed"}>
    <header className="app-header">
      <div className="app-header-left">
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
      </div>
      <button
        className="btn sidebar-toggle"
        ariaLabel={messagesOpen ? "Hide messages" : "Show messages"}
        ariaExpanded=messagesOpen
        title={messagesOpen ? "Hide messages" : "Show messages"}
        onClick={_ => toggleMessages()}>
        {sidebarIcon(messagesOpen)}
        {unread > 0 ? <span className="sidebar-badge" /> : React.null}
      </button>
    </header>
    <div className="app-main"> {body} </div>
    {messagesOpen
      ? <MessagesPanel
          messages
          onClear={() => MessageStore.clear()}
          onReplay
          onReopen
        />
      : React.null}
  </div>
}
