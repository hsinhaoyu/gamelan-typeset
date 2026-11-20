# 0018 One notasi command with subcommands

Status: accepted (2026-11-20)

Context: ADR 0010 named the command-line scripts after the package: `scripts/notasi-render` (and `scripts/notasi-analyse`, dropped by ADR 0015). The design for scores in Typst documents (06) adds more commands: update a document's side file, compile it, and watch it. A separate script for each would be four similarly named programs to install and remember.

Decision: There is one command, `scripts/notasi`, with subcommands: `notasi render` for a standalone figure (05), and `notasi typst`, `notasi update` and `notasi watch` for documents (06). This replaces the script name in ADR 0010; the rest of 0010 (the package and module names) stands.

Consequences: Users install and learn one command, and its `--help` lists everything it can do. Adding a feature means adding a subcommand, not a script. The document subcommands are only planned while ADR 0016 is proposed; `notasi render` does not depend on it.

Supersedes: 0010 (only the script name)
