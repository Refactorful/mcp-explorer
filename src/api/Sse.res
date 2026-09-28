// Incremental reader for `text/event-stream` (SSE) responses.
//
// MCP "Streamable HTTP" may answer a POST with a stream of JSON-RPC messages
// instead of a single JSON body: zero or more notifications / server requests
// followed by the response for our request id. We decode each SSE `data:` frame
// and hand it to `onMessage` as soon as it parses, so the UI can render partial
// updates live.
//
// `isFinal` lets the caller stop as soon as the message it is waiting for
// arrives, even if the server keeps the connection open. The promise resolves
// with every message seen so far.
//
// `Fetch.Response.t` is the native `Response` at runtime, so the raw body
// stream (`response.body.getReader()`) is reachable here even though the typed
// binding does not expose it.

let read: (Fetch.Response.t, JSON.t => unit, JSON.t => bool) => promise<array<JSON.t>> =
  %raw(`(function(response, onMessage, isFinal) {
  return new Promise(function(resolve, reject) {
    if (!response || !response.body || typeof response.body.getReader !== "function") {
      reject(new Error("response has no readable stream body"));
      return;
    }

    var reader = response.body.getReader();
    var decoder = new TextDecoder("utf-8");
    var messages = [];
    var buffer = "";
    var settled = false;

    function settle() {
      if (settled) {
        return;
      }
      settled = true;
      resolve(messages);
    }

    function fail(error) {
      if (settled) {
        return;
      }
      settled = true;
      reject(error);
    }

    function dispatch(data) {
      var text = data.join("\n");
      if (text === "") {
        return;
      }
      var parsed;
      try {
        parsed = JSON.parse(text);
      } catch (error) {
        return;
      }
      messages.push(parsed);
      onMessage(parsed);
      if (isFinal(parsed)) {
        try {
          reader.cancel();
        } catch (error) { /* already closed */ }
        settle();
      }
    }

    function handleEvent(rawEvent) {
      var lines = rawEvent.split("\n");
      var data = [];
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "" || line.charAt(0) === ":") {
          continue;
        }
        var colon = line.indexOf(":");
        var field = colon === -1 ? line : line.slice(0, colon);
        var value = colon === -1 ? "" : line.slice(colon + 1);
        if (value.charAt(0) === " ") {
          value = value.slice(1);
        }
        if (field === "data") {
          data.push(value);
        }
      }
      dispatch(data);
    }

    function drain() {
      var boundary;
      while ((boundary = buffer.indexOf("\n\n")) !== -1) {
        var rawEvent = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        handleEvent(rawEvent);
      }
    }

    function pump() {
      reader.read().then(function(result) {
        if (result.done) {
          drain();
          settle();
          return;
        }
        buffer += decoder.decode(result.value, { stream: true });
        buffer = buffer.replace(/\r\n/g, "\n");
        drain();
        pump();
      }).catch(fail);
    }

    pump();
  });
})`)
