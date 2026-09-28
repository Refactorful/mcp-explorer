let mimeSrc = (media: Protocol.media): string =>
  "data:" ++ media.mimeType ++ ";base64," ++ media.data

@react.component
let make = (~block: Protocol.contentBlock) =>
  switch block {
  | Protocol.Text(text) => <pre className="content-text"> {text->React.string} </pre>
  | Protocol.Image(media) =>
    <div className="content-media">
      <img src={mimeSrc(media)} alt="image content" />
    </div>
  | Protocol.Audio(media) =>
    <div className="content-media">
      <audio controls=true src={mimeSrc(media)} />
    </div>
  | Protocol.ResourceLink(json) => <JsonBlock value=json label="resource_link" />
  | Protocol.Resource(json) => <JsonBlock value=json label="resource" />
  | Protocol.Unknown(json) => <JsonBlock value=json label="unknown content block" />
  }
