# 0033 Groups carry their effective settings

Status: accepted (2026-11-21)

Context: A score's options set defaults for its groups, and a group's own options override them (ADR 0031). Either the records keep the options as written, and layout looks each one up through the group, the score and the default (LilyPond's way), or the reader works out each group's settings once.

Decision: The reader fills every group in completely: each `group` record carries its effective settings, its own where it gives them, else the score's, else the default. The `score` record keeps only the options that are set on the score alone. Positions written in a score (`:from`, `:to`, `:breaks`) are stored as times.

Consequences: Layout reads plain values, with no lookups, and its tests can build groups directly. The records no longer show which settings were written and which were inherited, so a tool that rewrites scores would need the source.
