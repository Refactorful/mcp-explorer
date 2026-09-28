// Live log of SSE messages streamed before a request's final response
// (progress notifications, server requests, ...). Shared by the tool "Try it"
// pane and the resource reader.

@react.component
let make = (~events: array<Stream.t>) =>
  if events->Array.length == 0 {
    React.null
  } else {
    <div className="stream-log">
      <h3> {"Stream"->React.string} </h3>
      <ul className="stream-list">
        {events
        ->Array.mapWithIndex((event, index) =>
          <li
            key={Int.toString(index)}
            className={"stream-event " ++ Stream.kindClass(event.Stream.kind)}
          >
            <div className="stream-line">
              <span className="stream-time">
                {Message.formatTime(event.Stream.at)->React.string}
              </span>
              <span className="stream-kind">
                {Stream.kindLabel(event.Stream.kind)->React.string}
              </span>
              {switch event.Stream.method {
              | Some(method) => <span className="stream-method"> {method->React.string} </span>
              | None => React.null
              }}
            </div>
            <JsonBlock value={event.Stream.payload} />
          </li>
        )
        ->React.array}
      </ul>
    </div>
  }
