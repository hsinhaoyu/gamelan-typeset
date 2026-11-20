#set page(width: auto, height: auto, margin: 14pt, fill: white)
#set text(font: "DejaVu Sans", size: 8pt)

#let gamelan-grid(data) = {
  let n = data.steps
  let spp = data.steps_per_pulse
  let first = 2            // column 0: group label, column 1: lane name
  let cells = ()
  let row = 1              // row 0: pulse header

  for g in data.groups {
    let lanes = g.lanes
    cells.push(grid.hline(y: row, stroke: 0.8pt + luma(120)))
    cells.push(grid.cell(x: 0, y: row, rowspan: lanes.len(),
      align: horizon + left, inset: (right: 10pt))[
        #text(weight: "bold", size: 9pt, g.label) \
        #text(fill: luma(110), style: "italic", g.sub)])
    for (i, l) in lanes.enumerate() {
      cells.push(grid.cell(x: 1, y: row + i, align: horizon + right,
        inset: (right: 5pt), text(fill: luma(140), size: 7pt, l)))
    }
    for v in g.voices {
      for e in v.events {
        let lane = lanes.position(l => l == e.lane)
        cells.push(grid.cell(x: first + e.start, y: row + lane, colspan: e.dur,
          inset: 1.5pt,
          block(width: 100%, height: 100%, fill: rgb(v.color), radius: 3pt,
            align(center + horizon,
              text(fill: white, weight: "bold", e.text)))))
      }
    }
    row += lanes.len()
  }
  cells.push(grid.hline(y: row, stroke: 0.8pt + luma(120)))

  let cols = (10.5em, 3.6em) + (2.6em,) * n
  let rws = (1.6em,) + (1.5em,) * (row - 1)
  // layer 1: pulse shading and pulse lines only
  let bg = grid(columns: cols, rows: rws,
    fill: (x, y) => if x >= first and y > 0 and calc.rem(calc.quo(x - first, spp), 2) == 0 { luma(243) },
    stroke: (x, y) => if x >= first and calc.rem(x - first, spp) == 0 { (left: 0.5pt + luma(170)) },
    ..range(cols.len() * row).map(_ => []))
  // layer 2: labels, header and notes, transparent
  let fg = grid(columns: cols, rows: rws,
    ..range(n).map(i => grid.cell(x: first + i, y: 0, align: center + horizon,
      if calc.rem(i, spp) == 0 { text(weight: "bold", size: 9pt, str(calc.quo(i, spp) + 1)) }
      else { text(fill: luma(150), "·") })),
    ..cells)
  box({ place(top + left, bg); fg })
}

#figure(
  gamelan-grid(json("piece.json")),
  caption: [Reyong kotekan (polos #box(fill: rgb("#2a9d8f"), width: 6pt, height: 6pt, radius: 1pt) and sangsih #box(fill: rgb("#e76f51"), width: 6pt, height: 6pt, radius: 1pt)) with ugal, calung, kempli, gong and kendang.],
)
