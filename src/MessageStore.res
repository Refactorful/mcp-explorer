// In-memory, React-agnostic log of every transport message.
//
// `Mcp.post` records a message before the fetch and finishes it afterwards; the
// App subscribes to re-render the Messages sidebar. This module deliberately
// avoids React so the transport layer can import it without a cycle. New
// messages are prepended, so `all()` is newest-first.

let messages: ref<array<Message.t>> = ref([])
let listeners: ref<array<unit => unit>> = ref([])

let notify = () => listeners.contents->Array.forEach(listener => listener())

// Registers a change listener and returns an unsubscribe function.
let subscribe = (listener: unit => unit) => {
  listeners := Array.concat(listeners.contents, [listener])
  () => listeners := listeners.contents->Array.filter(current => current !== listener)
}

let all = () => messages.contents

let count = () => Array.length(messages.contents)

// Records an outbound request in progress and returns its UUID.
let start = (
  ~direction=Message.ClientToServer,
  ~method: Protocol.method,
  ~name: option<string>,
  ~params: JSON.t,
  ~request: JSON.t,
  ~startedAt: float,
): string => {
  let id = Message.uuid()
  messages := [
    {
      Message.id,
      direction,
      method,
      name,
      params,
      request,
      startedAt,
      durationMs: None,
      status: Message.Pending,
      response: None,
      error: None,
    },
    ...messages.contents,
  ]
  notify()
  id
}

// Completes a previously started message with its outcome and elapsed time.
let finish = (
  id: string,
  ~status: Message.status,
  ~durationMs: float,
  ~response: option<JSON.t>,
  ~error: option<string>,
) => {
  messages := messages.contents->Array.map(message =>
    message.Message.id == id
      ? {...message, durationMs: Some(durationMs), status, response, error}
      : message
  )
  notify()
}

let clear = () => {
  messages := []
  notify()
}
