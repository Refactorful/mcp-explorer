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
  | Protocol.ResourceLink(json) =>
    <details className="content-json">
      <summary> {"resource_link"->React.string} </summary>
      <pre className="code-block"> {json->Schema.pretty->React.string} </pre>
    </details>
  | Protocol.Resource(json) =>
    <details className="content-json">
      <summary> {"resource"->React.string} </summary>
      <pre className="code-block"> {json->Schema.pretty->React.string} </pre>
    </details>
  | Protocol.Unknown(json) =>
    <details className="content-json">
      <summary> {"unknown content block"->React.string} </summary>
      <pre className="code-block"> {json->Schema.pretty->React.string} </pre>
    </details>
  }
