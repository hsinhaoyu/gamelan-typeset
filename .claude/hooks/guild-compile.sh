#!/usr/bin/env bash
# PostToolUse hook: compile an edited .scm file with guild and report
# read errors (e.g. unbalanced parens) and compiler warnings (e.g. unbound
# variables). Exit 2 sends the report back to Claude; exit 0 means clean.
set -u

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
case "$f" in *.scm) ;; *) exit 0 ;; esac
[ -f "$f" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 0
out_dir=$(mktemp -d)
trap 'rm -rf "$out_dir"' EXIT

output=$(guild compile -L . -o "$out_dir/out.go" "$f" 2>&1)
status=$?

# Keep only the useful lines: drop backtraces and the "wrote ..." note.
report=$(printf '%s\n' "$output" \
  | grep -E 'warning:|error|ERROR|unexpected|In procedure' \
  | grep -v "^wrote ")

if [ $status -ne 0 ] || printf '%s\n' "$output" | grep -q 'warning:'; then
  {
    echo "guild compile failed for $f:"
    printf '%s\n' "${report:-$output}"
  } >&2
  exit 2
fi
exit 0
