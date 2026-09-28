// Click-to-zoom image preview. The thumbnail sits in a checkerboard box (so
// transparent pixels stay visible) and clicking it opens a full-screen modal;
// the X button, Escape, or a backdrop click closes it.

// Attach an Escape-key listener; returns the cleanup React runs on unmount.
let withEscapeKey: (unit => unit) => unit => unit = %raw(`(function(onEscape) {
  function onKeyDown(event) {
    if (event.key === "Escape") onEscape();
  }
  document.addEventListener("keydown", onKeyDown);
  return function() {
    document.removeEventListener("keydown", onKeyDown);
  };
})`)

@react.component
let make = (~src: string, ~alt: string) => {
  let (isOpen, setOpen) = React.useState(() => false)
  let close = () => setOpen(_ => false)

  React.useEffect1(
    () => {
      if isOpen {
        Some(withEscapeKey(close))
      } else {
        None
      }
    },
    [isOpen],
  )

  let modal = isOpen
    ? <div className="image-modal" onClick={_ => close()}>
        <div
          className="image-modal-body"
          role="dialog"
          ariaModal=true
          ariaLabel=alt
          onClick={event => ReactEvent.Mouse.stopPropagation(event)}>
          <button
            className="image-modal-close"
            type_="button"
            ariaLabel="Close"
            onClick={_ => close()}>
            {"×"->React.string}
          </button>
          <img className="image-modal-img" src alt />
        </div>
      </div>
    : React.null

  React.array([
    <button
      className="image-preview"
      type_="button"
      title="Click to enlarge"
      onClick={_ => setOpen(_ => true)}>
      <img src alt />
    </button>,
    modal,
  ])
}
