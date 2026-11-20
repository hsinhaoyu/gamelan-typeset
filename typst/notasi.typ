// notasi: draw a figure laid out by notasi's Guile side.
// See doc/design/05-typst-backend.md, "Typst template design".
//
//   #import "notasi.typ": score
//   #score(json("piece.json"))
//
// The template draws exactly what the figure says and makes no musical
// decisions (ADR 0005). It sets no page, font or text size, so a
// score takes on the look of the document around it.

// A length from the figure, e.g. "10.5em".
#let _len(s) = float(s.trim("em", at: end)) * 1em

// The content of one note's cell: a block filling the cell in the
// note's colour, with its name when the figure gives one (ADR 0019,
// 0020). A note with no colour is just its name.
#let _note(e) = {
  let name = if e.text != none and not e.continued {
    align(center + horizon,
      text(fill: rgb(e.text_color), weight: "bold", e.text))
  }
  if e.fill == none {
    name
  } else {
    // A thin white border keeps neighbouring notes apart, so repeated
    // strokes don't merge into what looks like one held note.
    block(width: 100%, height: 100%, fill: rgb(e.fill),
      stroke: 0.5pt + white, name)
  }
}

// One system as a grid: a background layer for the pulse lines, and a
// transparent foreground layer for labels, header and notes, drawn on
// top. A single grid can't do both: a note spanning
// several columns would cover the lines under it.
#let _system(data, sys) = {
  let spp = data.steps_per_pulse
  let sizes = data.sizes
  let first = 2                     // column 0: group label, 1: lane label
  let pulse-start(i) = calc.rem(sys.start + i, spp) == 0
  let pulse(i) = calc.quo(sys.start + i, spp)

  let cells = ()
  let row = 1                       // row 0: the header
  for g in sys.groups {
    let lanes = g.lanes
    cells.push(grid.hline(y: row, stroke: 0.8pt + luma(120)))
    if lanes.len() > 0 {
      cells.push(grid.cell(x: 0, y: row, rowspan: lanes.len(),
        align: horizon + left, inset: (right: 10pt), {
          text(weight: "bold", size: 1.1em, g.label)
          if g.subtitle != none {
            linebreak()
            text(fill: luma(110), style: "italic", g.subtitle)
          }
        }))
      for (i, l) in lanes.enumerate() {
        cells.push(grid.cell(x: 1, y: row + i, align: horizon + right,
          inset: (right: 5pt), text(fill: luma(140), size: 0.85em, l)))
      }
      for v in g.voices {
        for e in v.events {
          cells.push(grid.cell(x: first + e.start, y: row + e.lane,
            colspan: e.dur, inset: 0pt, _note(e)))
        }
      }
    }
    row += lanes.len()
  }
  cells.push(grid.hline(y: row, stroke: 0.8pt + luma(120)))

  let cols = ((_len(sizes.label_width), _len(sizes.lane_width))
    + (_len(sizes.step_width),) * sys.steps)
  let rows = (_len(sizes.row_height),) * row

  let background = grid(columns: cols, rows: rows,
    stroke: (x, y) => if x >= first and pulse-start(x - first) {
      (left: 0.5pt + luma(170))
    },
    ..range(cols.len() * row).map(_ => []))

  let foreground = grid(columns: cols, rows: rows,
    ..range(sys.steps).map(i => grid.cell(x: first + i, y: 0,
      align: center + horizon,
      if pulse-start(i) { text(weight: "bold", str(pulse(i) + 1)) }
      else { text(fill: luma(150), "·") })),
    ..cells)

  box({
    place(top + left, background)
    foreground
  })
}

/// Draw DATA, the figure laid out by notasi: its systems stacked, 1em
/// apart. Returns content; captions and numbering are the caller's.
#let score(data) = {
  data.systems.map(sys => _system(data, sys)).join(v(1em))
}
