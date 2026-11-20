# 0002 Time is a grid of equal steps

Status: accepted (2026-11-19)

Context: Balinese gamelan parts, especially interlocking kotekan, are naturally written on a fixed pulse. Variable note durations would complicate the reader, layout and analysis.

Decision: Time is a grid of equal steps, like a step sequencer. Every token in a part is exactly one step. Time in the model is integer steps starting at 0.

Consequences: A note's duration comes from the hold tokens (`_`) after it, not a duration value. Layout maps steps directly to columns. Rhythms finer than one step need a smaller step size for the whole piece.
