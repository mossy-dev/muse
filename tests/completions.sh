#!/bin/sh
#
# Generate the three shell completions and check them against the binary they
# were generated from.
#
# The claim under test is that the completions cannot drift: every command, flag
# and scale name muse has reaches all three shells without a file being edited by
# hand. So nothing here holds a list of its own -- each expectation is asked of
# the binary, and a command added to the table fails this test in every shell
# that did not receive it.
#
# bash and zsh are driven for real where they are installed: the completion is
# sourced and asked what it would offer. fish has no way to answer that without
# a terminal, so it is parsed where fish is installed and read structurally
# where it is not. A shell that is missing is reported rather than passed over.

set -eu

directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary="$directory/build"

if [ ! -x "$binary" ]; then
  echo "completions: no binary at $binary; run just build" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
skipped=""

fail() {
  echo "completions: $1"
  failures=$((failures + 1))
}

# Every word of a list is in a file, whatever else that file holds.
expect_words() {
  file=$1
  label=$2
  while IFS= read -r word; do
    if ! grep -qF -- "$word" "$file"; then
      fail "$label does not carry '$word'"
    fi
  done
}

# Two newline-separated lists hold the same words, in any order.
expect_same() {
  label=$1
  sort "$2" > "$work/left"
  sort "$3" > "$work/right"
  if ! diff -u "$work/left" "$work/right" > "$work/difference"; then
    fail "$label offers the wrong words"
    sed 's/^/  /' "$work/difference"
  fi
}

# A candidate as the file holds it. fish carries its list escaped, so that the
# space in a multi-word name survives being tokenized; bash and zsh hold the
# words as muse prints them and escape when they offer them.
spell_words() {
  case "$1" in
    fish) sed 's/ /\\ /g' ;;
    *) cat ;;
  esac
}

# A flag as the file spells it. fish takes a long name after -l and a short one
# after -s rather than the dashes themselves. The second expression cannot fire
# on what the first rewrote, since only a short flag is a dash and one letter.
spell_flags() {
  case "$1" in
    fish) sed -e 's/^--/-l /' -e 's/^-\(.\)$/-s \1/' ;;
    *) cat ;;
  esac
}

for shell in bash zsh fish; do
  "$directory/tools/completions.sh" "$binary" "$shell" > "$work/$shell"
done

# The structural gate, which is the one the phase promises: every command, every
# flag and every scale name appears in all three files.
"$binary" help commands | cut -f1 > "$work/commands"
"$binary" help flags | cut -f1 > "$work/flags"
"$binary" help scales > "$work/scales"

for shell in bash zsh fish; do
  spell_flags "$shell" < "$work/flags" > "$work/spelled-flags"
  spell_words "$shell" < "$work/scales" > "$work/spelled-scales"

  expect_words "$work/$shell" "$shell" < "$work/commands"
  expect_words "$work/$shell" "$shell" < "$work/spelled-flags"
  expect_words "$work/$shell" "$shell" < "$work/spelled-scales"
done

if command -v bash > /dev/null; then
  bash -n "$work/bash" || fail "the bash completion does not parse"

  cat > "$work/drive.bash" <<'DRIVE'
source "$1"
shift
COMP_WORDS=( "$@" )
COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
_muse
printf '%s\n' "${COMPREPLY[@]}"
DRIVE

  offer() {
    bash "$work/drive.bash" "$work/bash" "$@" > "$work/offered"
  }

  # A bare `muse` offers every command and every flag, which is the gate a
  # command added in a later phase has to pass.
  offer muse ""
  cat "$work/commands" "$work/flags" > "$work/expected"
  expect_same "bash on a bare muse" "$work/expected" "$work/offered"

  # A scale name completes to what `muse scale` accepts, spaces and all, with
  # the flags still on offer beside it.
  offer muse scale G ""
  sed 's/ /\\ /g' "$work/scales" > "$work/expected"
  cat "$work/flags" >> "$work/expected"
  expect_same "bash after muse scale G" "$work/expected" "$work/offered"

  # A flag's value comes from the flag rather than from the command.
  offer muse chords --color ""
  "$binary" help colors > "$work/expected"
  expect_same "bash after --color" "$work/expected" "$work/offered"

  offer muse chords --size ""
  "$binary" help sizes > "$work/expected"
  expect_same "bash after --size" "$work/expected" "$work/offered"

  offer muse midi -k "harm"
  printf 'harmonic\\ minor\nharmonic\n' > "$work/expected"
  expect_same "bash after -k harm" "$work/expected" "$work/offered"

  # A command with no vocabulary of its own offers the flags and nothing else,
  # an empty candidate included.
  offer muse notes ""
  cat "$work/flags" > "$work/expected"
  expect_same "bash after muse notes" "$work/expected" "$work/offered"

  # An operand vocabulary is offered alongside the flags, never instead of them.
  offer muse voice ""
  cat "$work/flags" > "$work/expected"
  "$binary" help styles >> "$work/expected"
  expect_same "bash after muse voice" "$work/expected" "$work/offered"
else
  skipped="$skipped bash"
fi

if command -v zsh > /dev/null; then
  zsh -n "$work/zsh" || fail "the zsh completion does not parse"

  # The completion system is not available outside a terminal, so the three
  # procs it calls to offer a candidate are stubbed and asked what they were
  # handed. Nothing else about the file is changed.
  cat > "$work/drive.zsh" <<'DRIVE'
compadd() { if [[ $1 == -a ]]; then print -rl -- ${(P)2}; else print -rl -- "$@"; fi }
_describe() { local name=${@[-1]}; local -a entries; entries=( ${(P)name} ); print -rl -- ${entries%%:*} }
_files() { print -r -- '<files>' }
typeset -ga words
words=( "${(@)argv[2,-1]}" )
CURRENT=$#words
source "$1"
DRIVE

  zsh -f "$work/drive.zsh" "$work/zsh" muse "" > "$work/offered"
  cat "$work/commands" "$work/flags" > "$work/expected"
  expect_same "zsh on a bare muse" "$work/expected" "$work/offered"

  zsh -f "$work/drive.zsh" "$work/zsh" muse scale G "" > "$work/offered"
  cat "$work/scales" "$work/flags" > "$work/expected"
  expect_same "zsh after muse scale G" "$work/expected" "$work/offered"

  zsh -f "$work/drive.zsh" "$work/zsh" muse chords --color "" > "$work/offered"
  "$binary" help colors > "$work/expected"
  expect_same "zsh after --color" "$work/expected" "$work/offered"
else
  skipped="$skipped zsh"
fi

if command -v fish > /dev/null; then
  fish --no-execute "$work/fish" || fail "the fish completion does not parse"
else
  skipped="$skipped fish"
fi

if [ "$failures" -gt 0 ]; then
  echo "completions: $failures check(s) failed" >&2
  exit 1
fi

if [ -n "$skipped" ]; then
  echo "completions: every check passes; not installed here:$skipped"
else
  echo "completions: every check passes"
fi
