// Right-hand "Messages" sidebar: a timeline of every client↔server call.
//
// Each row shows the local send time, direction, round-trip time and the wire
// method (e.g. `TOOLS/CALL`). Clicking a reopenable row (a tool/prompt call with
// a name) replays it into the detail pane with the same inputs; other rows
// expand to show the raw request/response. The replay button always re-sends a
// fresh copy of the request.

@react.component
let make = (
  ~messages: array<Message.t>,
  ~onClear: unit => unit,
  ~onReplay: Message.t => unit,
  ~onReopen: Message.t => unit,
) => {
  let (expanded, setExpanded) = React.useState(() => (None: option<string>))

  let toggle = (id: string) =>
    setExpanded(current => current == Some(id) ? None : Some(id))

  // Reopen when we can (tool/prompt call), otherwise fall back to showing the
  // raw request/response so a click is never a no-op.
  let onMain = (message: Message.t) =>
    if message->Message.isReopenable {
      onReopen(message)
    } else {
      toggle(message.Message.id)
    }

  let detail = (message: Message.t) =>
    <div className="message-detail">
      <div className="message-section">
        <h4> {"Request"->React.string} </h4>
        <JsonBlock value={message.request} />
      </div>
      {switch message.response {
      | Some(response) =>
        <div className="message-section">
          <h4> {"Response"->React.string} </h4>
          <JsonBlock value=response />
        </div>
      | None => React.null
      }}
      {switch message.error {
      | Some(error) => <div className="error-box"> {error->React.string} </div>
      | None => React.null
      }}
      <p className="message-uuid muted">
        {("uuid " ++ message.Message.id)->React.string}
      </p>
    </div>

  <aside className="messages-panel">
    <div className="messages-head">
      <h2> {"Messages"->React.string} </h2>
      <span className="pill"> {messages->Array.length->Int.toString->React.string} </span>
      <button
        className="btn"
        disabled={messages->Array.length == 0}
        onClick={_ => onClear()}>
        {"Clear"->React.string}
      </button>
    </div>
    {messages->Array.length == 0
      ? <p className="muted">
          {"No messages yet. Calls appear here as they happen."->React.string}
        </p>
      : <ul className="message-list">
          {messages
          ->Array.map(message =>
            <li
              key={message.Message.id}
              className={"message-item " ++ Message.statusClass(message.Message.status)}>
              <div className="message-row">
                <button className="message-main" onClick={_ => onMain(message)}>
                  <span className="message-line">
                    <span className="message-time">
                      {Message.formatTime(message.Message.startedAt)->React.string}
                    </span>
                    <span className="message-direction">
                      {Message.directionLabel(message.Message.direction)->React.string}
                    </span>
                    <span className="message-duration">
                      {Message.formatDuration(message.Message.durationMs)->React.string}
                    </span>
                  </span>
                  <span className="message-line">
                    <span className="message-method">
                      {Message.methodLabel(message)->React.string}
                    </span>
                    {switch message.Message.name {
                    | Some(name) => <span className="message-name"> {name->React.string} </span>
                    | None => React.null
                    }}
                  </span>
                </button>
                <div className="message-actions">
                  <button
                    className="icon-btn"
                    title="Replay this request"
                    onClick={_ => onReplay(message)}>
                    {"\u21bb"->React.string}
                  </button>
                  <button
                    className="icon-btn"
                    title="Show request and response"
                    onClick={_ => toggle(message.Message.id)}>
                    {expanded == Some(message.Message.id)
                      ? "\u25be"->React.string
                      : "\u25b8"->React.string}
                  </button>
                </div>
              </div>
              {expanded == Some(message.Message.id) ? detail(message) : React.null}
            </li>
          )
          ->React.array}
        </ul>}
  </aside>
}
