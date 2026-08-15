#!/bin/sh
#
# Re-run every pipeline in transcript.txt and compare its output verbatim.
#
# The transcript is the claim DESIGN.md makes about muse -- that the output of
# one command is the input of the next -- written out as pipelines and their
# answers. Running it is what turns that claim into a test: a change that alters
# a single column of a single line has to say so here.
#
# A line beginning with `$ ` is a pipeline and every line up to the next blank
# one is what it prints. A line beginning with `#` is a comment; nothing muse
# prints begins with one, since every datum opens with a letter, a bracket or a
# space.

set -eu

directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
transcript="$directory/tests/transcript.txt"

if [ ! -x "$directory/build" ]; then
  echo "transcript: no binary at $directory/build; run just build" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ln -s "$directory/build" "$work/muse"
PATH="$work:$PATH"
export PATH

expected="$work/expected"
actual="$work/actual"
difference="$work/difference"
failures=0
pipeline=""

check() {
  [ -n "$pipeline" ] || return 0

  if sh -c "$pipeline" > "$actual" 2>/dev/null; then
    if ! diff -u "$expected" "$actual" > "$difference"; then
      echo "transcript: $pipeline"
      sed 's/^/  /' "$difference"
      failures=$((failures + 1))
    fi
  else
    echo "transcript: $pipeline exited non-zero"
    failures=$((failures + 1))
  fi

  pipeline=""
}

: > "$expected"
while IFS= read -r line; do
  case "$line" in
    '$ '*)
      check
      pipeline=${line#'$ '}
      : > "$expected"
      ;;
    '')
      check
      ;;
    '#'*)
      ;;
    *)
      printf '%s\n' "$line" >> "$expected"
      ;;
  esac
done < "$transcript"
check

if [ "$failures" -gt 0 ]; then
  echo "transcript: $failures pipeline(s) differ from the transcript" >&2
  exit 1
fi

echo "transcript: every pipeline matches"
