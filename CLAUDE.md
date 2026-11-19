# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GNU Guile 3.0 project for notating and visualizing Balinese gamelan music. Currently a skeleton: all modules are empty stubs.

## Commands

- Run all tests: `make check` (exits non-zero if any test file fails)
- Run one test file: `guile --fresh-auto-compile -L . tests/<name>.scm`
- Remove SRFI-64 logs: `make clean`

Always run from the repo root with `-L .` so `(gamelan ...)` modules resolve.

`--fresh-auto-compile` is deliberate: Guile caches compiled `.go` files in `~/.cache/guile/ccache` and checks freshness only by mtime. If a file is edited within the same second as the last compile, Guile loads the stale copy and tests give wrong results. `--no-auto-compile` does not fix this, because a cached `.go` that looks current is still loaded.

## Architecture

Modules live in `gamelan/` under the `(gamelan <name>)` namespace. The intended pipeline is:

`reader` (text notation → model) → `model` (core data: instruments, notes, gongan) → `layout` (visual structure) → `typst` (Typst source output), with `analysis` working on the model alongside this pipeline.

`doc/notation.md` is the place to define the input notation that `reader` parses; `examples/` is for example pieces.

## Scheme style

Write idiomatic Guile 3, not another language translated into Scheme:

- Data: immutable `define-record-type` (SRFI-9) records for domain objects; association lists or vectors only for small, simple data.
- Control flow: `match` from `(ice-9 match)` for destructuring and dispatch over cond/car/cdr chains; named `let`, `fold`, and SRFI-1 procedures over manual loops; tail recursion over mutation. Avoid `set!` unless state is truly local.
- Procedures: `define*` with `#:key` arguments for optional settings, `parameterize` for configuration passed through context (e.g. layout settings), and docstrings on exported procedures.
- Errors: Guile 3 exceptions (`raise-exception`, `make-exception` with `&error`/`&message`/`&irritants`; `guard` or `with-exception-handler` to catch them). Do not fail by returning `#f`.
- Modules: export explicitly with `#:export`, so a module's public surface is its export list.
- Macros: use one when a procedure can't do the job: a new binding form, control over evaluation (delay, short-circuit), a declarative mini-language (likely for instrument/notation definitions), or compile-time checks. Prefer `syntax-rules`; use `syntax-case` only for what it alone can do (e.g. building identifiers, checking syntax at expansion). Don't write a macro just to save a little typing or where a higher-order procedure works.

## Keeping README.md current

`tests/readme.scm` runs under `make check` and fails when README.md is out of sync with the code: a module file in `gamelan/` that README doesn't mention, a `gamelan/*.scm` path in README that doesn't exist, or a `make <target>` in README that the Makefile lacks. When you add, rename, or remove a module, Makefile target, or user-facing workflow, update README.md in the same change. If README needs a new kind of fact that could go stale (e.g. a CLI command), extend `tests/readme.scm` to check it.

## Tests

Tests use SRFI-64. Each `tests/*.scm` file is a standalone script that `make check` picks up automatically. A test file must exit non-zero on failure: save `(test-runner-current)` before `test-end`, then `(exit (zero? (+ fail-count xpass-count)))`. See `tests/smoke.scm`.
