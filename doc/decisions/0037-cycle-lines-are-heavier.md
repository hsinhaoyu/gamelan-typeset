# 0037 Cycle lines are heavier than pulse lines

Status: accepted (2026-11-21)

Context: ADR 0020 keeps a plain white grid in which only the pulse lines remain. With colotomies, the most important boundary in a gamelan score is the end of the gong cycle, and a reader should see where each cycle begins without counting pulses.

Decision: The grid has two kinds of line, both decided by layout (the figure's `lines`, ADR 0036) and drawn by the template down the left edge of a column: a thin pulse line, as now, and a heavier cycle line where a cycle starts, just after the gong. The background stays white, with no shading. Where ADR 0020 says only the pulse lines remain, read pulse and cycle lines.

Consequences: Cycles are visible at a glance, in the coloured grid and in Tenzer's layout alike. Pieces without a colotomy have pulse lines only, as in v1.
