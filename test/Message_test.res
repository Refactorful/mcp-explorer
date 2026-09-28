open Vitest

let makeMessage = (
  ~method=Protocol.ToolsCall,
  ~name=Some("echo"),
  ~params,
): Message.t => {
  id: Message.uuid(),
  direction: Message.ClientToServer,
  method,
  name,
  params,
  request: JSON.Encode.object(Dict.make()),
  startedAt: Date.now(),
  durationMs: None,
  status: Message.Pending,
  response: None,
  error: None,
}

let argObject = () =>
  JSON.Encode.object(
    Dict.fromArray([
      ("arguments", JSON.Encode.object(Dict.fromArray([("a", JSON.Encode.int(1))]))),
    ]),
  )

describe("Message", () => {
  test("formatTime renders local 24-hour time", () => {
    let date = Date.makeWithYMDHMS(~year=2024, ~month=0, ~day=2, ~hours=20, ~minutes=30, ~seconds=46)
    expect(date->Date.getTime->Message.formatTime)->toBe("20:30:46")
  })

  test("pad adds leading zeros", () => {
    let date = Date.makeWithYMDHMS(~year=2024, ~month=0, ~day=2, ~hours=6, ~minutes=5, ~seconds=9)
    expect(date->Date.getTime->Message.formatTime)->toBe("06:05:09")
  })

  test("methodLabel is the uppercased wire method", () => {
    expect(makeMessage(~params=argObject())->Message.methodLabel)->toBe("TOOLS/CALL")
  })

  test("formatDuration renders milliseconds and pending", () => {
    expect(Message.formatDuration(None))->toBe("\u2026")
    expect(Message.formatDuration(Some(41.0)))->toBe("41ms")
  })

  test("isReopenable requires a named tool/prompt call", () => {
    expect(makeMessage(~params=argObject())->Message.isReopenable)->toBe(true)
    expect(makeMessage(~name=None, ~params=argObject())->Message.isReopenable)->toBe(false)
    expect(
      makeMessage(~method=Protocol.ToolsList, ~name=None, ~params=argObject())->Message.isReopenable,
    )->toBe(false)
  })

  test("toolArguments extracts tools/call arguments", () => {
    let message = makeMessage(~params=argObject())
    switch message->Message.toolArguments {
    | Some(arguments) => expect(arguments->JSON.stringify)->toBe("{\"a\":1}")
    | None => expect("missing arguments")->toBe("present")
    }
  })

  test("promptArgument extracts a named prompts/get argument", () => {
    let params =
      JSON.Encode.object(
        Dict.fromArray([
          ("arguments", JSON.Encode.object(Dict.fromArray([("city", JSON.Encode.string("Boston"))]))),
        ]),
      )
    let message = makeMessage(~method=Protocol.PromptsGet, ~name=Some("weather"), ~params)
    expect(message->Message.promptArgument("city"))->toBe(Some("Boston"))
    expect(message->Message.promptArgument("missing"))->toBe(None)
  })

  test("isReopenable accepts a named resources/read", () => {
    let params = JSON.Encode.object(
      Dict.fromArray([("uri", JSON.Encode.string("file:///a.txt"))]),
    )
    expect(
      makeMessage(~method=Protocol.ResourcesRead, ~name=Some("file:///a.txt"), ~params)
      ->Message.isReopenable,
    )->toBe(true)
    expect(
      makeMessage(~method=Protocol.ResourcesRead, ~name=None, ~params)->Message.isReopenable,
    )->toBe(false)
  })

  test("resourceUri extracts the resources/read uri", () => {
    let params = JSON.Encode.object(
      Dict.fromArray([("uri", JSON.Encode.string("file:///a.txt"))]),
    )
    let message = makeMessage(~method=Protocol.ResourcesRead, ~name=Some("file:///a.txt"), ~params)
    expect(message->Message.resourceUri)->toBe(Some("file:///a.txt"))
    expect(makeMessage(~params=argObject())->Message.resourceUri)->toBe(None)
  })

  test("uuid produces a v4 uuid", () => {
    let id = Message.uuid()
    expect(String.length(id))->toBe(36)
    expect(String.charAt(id, 14))->toBe("4")
    expect(id == Message.uuid())->toBe(false)
  })

  test("shortId truncates long ids", () => {
    expect(Message.shortId("1234567890"))->toBe("12345678")
    expect(Message.shortId("abc"))->toBe("abc")
  })
})

describe("MessageStore", () => {
  test("start prepends newest first and finish records the outcome", () => {
    MessageStore.clear()
    let first = MessageStore.start(
      ~method=Protocol.ToolsList,
      ~name=None,
      ~params=argObject(),
      ~request=argObject(),
      ~startedAt=Date.now(),
    )
    let second = MessageStore.start(
      ~method=Protocol.ToolsCall,
      ~name=Some("echo"),
      ~params=argObject(),
      ~request=argObject(),
      ~startedAt=Date.now(),
    )
    expect(MessageStore.count())->toBe(2)

    switch MessageStore.all() {
    | [newest, _] => expect(newest.Message.id)->toBe(second)
    | _ => expect("two messages")->toBe("present")
    }

    MessageStore.finish(
      first,
      ~status=Message.Succeeded,
      ~durationMs=12.0,
      ~response=Some(argObject()),
      ~error=None,
    )
    switch MessageStore.all()->Array.find(message => message.Message.id == first) {
    | Some(message) =>
      expect(message.Message.status)->toBe(Message.Succeeded)
      expect(message.Message.durationMs)->toBe(Some(12.0))
    | None => expect("message")->toBe("present")
    }
    MessageStore.clear()
    expect(MessageStore.count())->toBe(0)
  })

  test("subscribe notifies and unsubscribe stops notifications", () => {
    MessageStore.clear()
    let calls = ref(0)
    let unsubscribe = MessageStore.subscribe(() => calls := calls.contents + 1)
    let _ = MessageStore.start(
      ~method=Protocol.Discover,
      ~name=None,
      ~params=argObject(),
      ~request=argObject(),
      ~startedAt=Date.now(),
    )
    expect(calls.contents)->toBe(1)
    unsubscribe()
    let _ = MessageStore.start(
      ~method=Protocol.Discover,
      ~name=None,
      ~params=argObject(),
      ~request=argObject(),
      ~startedAt=Date.now(),
    )
    expect(calls.contents)->toBe(1)
    MessageStore.clear()
  })
})
