// Shared chrome for `Protocol.requestState`: idle/loading text and the error
// box, with the success case delegated to the caller.

let render = (
  ~state: Protocol.requestState<'a>,
  ~success: 'a => React.element,
  ~idle: string="Not run yet.",
  ~loading: string="Running…",
): React.element =>
  switch state {
  | Protocol.Idle => <div className="muted"> {idle->React.string} </div>
  | Protocol.Loading => <div className="muted"> {loading->React.string} </div>
  | Protocol.Failure(err) =>
    <div className="error-box"> {Protocol.apiErrorToString(err)->React.string} </div>
  | Protocol.Success(value) => success(value)
  }
