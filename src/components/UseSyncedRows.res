// Stable-id row state shared by the dynamic array/map editors.
//
// The parent owns the canonical JSON value; the editor keeps rows locally so
// editing a row never remounts its inputs (which would drop focus). When the
// value changes from the outside (JSON mode, Reset) the rows are rebuilt; our
// own edits round-trip through the parent, so the serialized comparison matches
// and focus is preserved.

let use = (
  ~value: option<JSON.t>,
  ~fromJson: option<JSON.t> => array<'row>,
  ~toJson: array<'row> => JSON.t,
): (array<'row>, (array<'row> => array<'row>) => unit) => {
  let (rows, setRows) = React.useState(() => fromJson(value))

  React.useEffect1(
    () => {
      if toJson(fromJson(value))->JSON.stringify != toJson(rows)->JSON.stringify {
        setRows(_ => fromJson(value))
      }
      None
    },
    [value],
  )

  (rows, setRows)
}

// Next stable id for a row list: one past the current maximum.
let nextId = (rows: array<'row>, idOf: 'row => int): int =>
  rows->Array.reduce(0, (max, row) => idOf(row) >= max ? idOf(row) + 1 : max)
