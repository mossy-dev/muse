#!/bin/sh
#
# Write a shell completion for muse to stdout.
#
# Nothing about the command surface is written here. The commands, the flags and
# the words each one takes are read from `muse help`, the same table the usage
# text and the man page come from, so a command added to the binary completes in
# every shell without a file here being touched.
#
# Usage: tools/completions.sh [path-to-muse] bash|zsh|fish > completion

set -eu

binary=${1:-./build}
shell=${2:-}

# A bare name is a path here, not something to look up on PATH.
case "$binary" in
  */*) ;;
  *) binary="./$binary" ;;
esac

if [ ! -x "$binary" ]; then
  echo "completions: no binary at $binary; run just build" >&2
  exit 1
fi

case "$shell" in
  bash|zsh|fish) ;;
  *)
    echo "completions: usage: $0 [path-to-muse] bash|zsh|fish" >&2
    exit 1
    ;;
esac

version=$("$binary" --version | cut -d' ' -f2)

# The words a topic holds. The two topics that describe the surface itself carry
# three fields to a line, and the word is the first of them.
words() {
  case "$1" in
    commands|flags) "$binary" help "$1" | cut -f1 ;;
    *) "$binary" help "$1" ;;
  esac
}

# Every topic that holds words, so a placeholder like <file> is left to the
# shell rather than embedded as an empty list.
stocked_topics() {
  "$binary" help topics | while read -r topic; do
    if [ -n "$(words "$topic")" ]; then
      printf '%s\n' "$topic"
    fi
  done
}

# name<TAB>vocabulary for the commands and flags that take one, which is what
# tells a completion what to offer after a word and, for a flag, that the word
# after it is a value rather than an operand.
takers() {
  "$binary" help "$1" | awk -F '\t' '$2 != "" { print $1 "\t" $2 }'
}

# name<TAB>summary, for the shells that show a description beside a candidate.
descriptions() {
  "$binary" help "$1" | awk -F '\t' '{ print $1 "\t" $3 }'
}

# Quote a string for a single-quoted shell literal.
quote() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

emit_bash() {
  cat <<HEADER
# muse $version completion for bash.
#
# Generated from \`muse help\` by tools/completions.sh. Do not edit: run
# \`just completions\` instead.

_muse_words() {
  case "\$1" in
HEADER

  stocked_topics | while read -r topic; do
    printf '    %s)\n      cat <<%s\n' "$topic" "'MUSE_WORDS'"
    words "$topic"
    printf 'MUSE_WORDS\n      ;;\n'
  done

  cat <<'BODY'
  esac
}

_muse_operand_vocabulary() {
  case "$1" in
BODY

  takers commands | while IFS='	' read -r name vocabulary; do
    printf '    %s) printf %s ;;\n' "$name" "'$vocabulary\\n'"
  done

  cat <<'BODY'
  esac
}

_muse_flag_vocabulary() {
  case "$1" in
BODY

  takers flags | while IFS='	' read -r name vocabulary; do
    printf '    %s) printf %s ;;\n' "$name" "'$vocabulary\\n'"
  done

  cat <<'BODY'
  esac
}

# Offer a newline-separated list, escaping the space in a multi-word candidate
# so that it reaches muse as one argument. The escaping is a loop because bash
# 3.2, which is what macOS ships, collapses "${array[@]//pattern/text}" into a
# single element.
_muse_offer() {
  local IFS index
  IFS=$'\n'

  COMPREPLY=( $(compgen -W "$1" -- "$2") )

  index=0
  while [ "$index" -lt "${#COMPREPLY[@]}" ]; do
    COMPREPLY[$index]=${COMPREPLY[$index]// /\\ }
    index=$((index + 1))
  done
}

_muse() {
  local current previous vocabulary command word index

  current=${COMP_WORDS[COMP_CWORD]}
  previous=${COMP_WORDS[COMP_CWORD-1]}

  # A flag's value comes from the flag, whatever command it was written after.
  vocabulary=$(_muse_flag_vocabulary "$previous")
  if [ -n "$vocabulary" ]; then
    if [ "$vocabulary" = file ]; then
      COMPREPLY=( $(compgen -f -- "$current") )
      return
    fi
    _muse_offer "$(_muse_words "$vocabulary")" "$current"
    return
  fi

  # The command is the first word that is neither a flag nor a flag's value.
  command=""
  index=1
  while [ "$index" -lt "$COMP_CWORD" ]; do
    word=${COMP_WORDS[index]}
    case "$word" in
      -*)
        if [ -n "$(_muse_flag_vocabulary "$word")" ]; then
          index=$((index + 1))
        fi
        ;;
      *)
        if [ -z "$command" ]; then
          command=$word
        fi
        ;;
    esac
    index=$((index + 1))
  done

  if [ -z "$command" ]; then
    _muse_offer "$(_muse_words commands)
$(_muse_words flags)" "$current"
    return
  fi

  _muse_offer "$(_muse_words "$(_muse_operand_vocabulary "$command")")
$(_muse_words flags)" "$current"
}

complete -F _muse muse
BODY
}

emit_zsh() {
  cat <<HEADER
#compdef muse
#
# muse $version completion for zsh.
#
# Generated from \`muse help\` by tools/completions.sh. Do not edit: run
# \`just completions\` instead.

_muse_vocabulary_words() {
  case "\$1" in
HEADER

  stocked_topics | while read -r topic; do
    printf '    %s)\n      reply=(\n' "$topic"
    words "$topic" | while IFS= read -r word; do
      printf "        '%s'\n" "$(quote "$word")"
    done
    printf '      )\n      ;;\n'
  done

  cat <<'BODY'
    *) reply=() ;;
  esac
}

_muse_operand_vocabulary() {
  case "$1" in
BODY

  takers commands | while IFS='	' read -r name vocabulary; do
    printf '    %s) REPLY=%s ;;\n' "$name" "$vocabulary"
  done

  cat <<'BODY'
    *) REPLY= ;;
  esac
}

_muse_flag_vocabulary() {
  case "$1" in
BODY

  takers flags | while IFS='	' read -r name vocabulary; do
    printf '    %s) REPLY=%s ;;\n' "$name" "$vocabulary"
  done

  cat <<'BODY'
    *) REPLY= ;;
  esac
}

_muse() {
  local previous command word vocabulary index
  local -a reply muse_commands muse_flags

  muse_commands=(
BODY

  descriptions commands | while IFS='	' read -r name summary; do
    printf "    '%s:%s'\n" "$(quote "$name")" "$(quote "$summary" | sed 's/:/\\:/g')"
  done

  cat <<'BODY'
  )

  muse_flags=(
BODY

  descriptions flags | while IFS='	' read -r name summary; do
    printf "    '%s:%s'\n" "$(quote "$name")" "$(quote "$summary" | sed 's/:/\\:/g')"
  done

  cat <<'BODY'
  )

  previous=${words[CURRENT-1]}
  _muse_flag_vocabulary "$previous"
  if [[ -n $REPLY ]]; then
    if [[ $REPLY == file ]]; then
      _files
      return
    fi
    _muse_vocabulary_words "$REPLY"
    compadd -a reply
    return
  fi

  command=
  for (( index = 2; index < CURRENT; index++ )); do
    word=${words[index]}
    case $word in
      -*)
        _muse_flag_vocabulary "$word"
        [[ -n $REPLY ]] && (( index++ ))
        ;;
      *)
        [[ -z $command ]] && command=$word
        ;;
    esac
  done

  if [[ -z $command ]]; then
    _describe -t commands 'muse command' muse_commands
    _describe -t flags 'muse flag' muse_flags
    return
  fi

  _muse_operand_vocabulary "$command"
  _muse_vocabulary_words "$REPLY"
  compadd -a reply
  _describe -t flags 'muse flag' muse_flags
}

_muse "$@"
BODY
}

# Every flag as three space-separated fields: its name, the vocabulary of its
# value or a dash where it takes none, and its summary. An empty field cannot
# survive a tab-delimited read, since a shell collapses a run of them.
flag_fields() {
  "$binary" help flags | awk -F '\t' '{ printf "%s %s %s\n", $1, ($2 == "" ? "-" : $2), $3 }'
}

# Quote a string for a single-quoted fish literal, where a backslash escapes and
# there is no way out of the quotes to get one in.
fish_quote() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"
}

# A candidate for fish's -a list, which is tokenized as a command line, so the
# space in a name like `harmonic minor` is escaped to keep it one candidate.
fish_candidate() {
  fish_quote "$1" | sed 's/ /\\ /g'
}

# The flag as fish spells it: a long name after -l, a short one after -s.
fish_spelling() {
  case "$1" in
    --*) printf -- '-l %s' "${1#--}" ;;
    *) printf -- '-s %s' "${1#-}" ;;
  esac
}

emit_fish() {
  cat <<HEADER
# muse $version completion for fish.
#
# Generated from \`muse help\` by tools/completions.sh. Do not edit: run
# \`just completions\` instead.

complete -c muse -f
HEADER

  printf '\n'
  descriptions commands | while IFS='	' read -r name summary; do
    printf "complete -c muse -n __fish_use_subcommand -a '%s' -d '%s'\n" \
      "$(fish_candidate "$name")" "$(fish_quote "$summary")"
  done

  # A command's operand words, one completion to a word so that a name with a
  # space in it stays one candidate.
  stocked_topics | while read -r topic; do
    taking=$(takers commands | awk -F '\t' -v topic="$topic" '$2 == topic { print $1 }' | tr '\n' ' ' | sed 's/ *$//')
    [ -n "$taking" ] || continue
    printf '\n'
    words "$topic" | while IFS= read -r word; do
      printf "complete -c muse -n '__fish_seen_subcommand_from %s' -a '%s' -d '%s'\n" \
        "$taking" "$(fish_candidate "$word")" "$topic"
    done
  done

  printf '\n'
  flag_fields | while read -r name vocabulary summary; do
    spelling=$(fish_spelling "$name")
    case "$vocabulary" in
      -)
        printf "complete -c muse %s -d '%s'\n" "$spelling" "$(fish_quote "$summary")"
        ;;
      file)
        printf "complete -c muse %s -r -F -d '%s'\n" "$spelling" "$(fish_quote "$summary")"
        ;;
      *)
        if [ -n "$(words "$vocabulary")" ]; then
          words "$vocabulary" | while IFS= read -r word; do
            printf "complete -c muse %s -x -a '%s' -d '%s'\n" \
              "$spelling" "$(fish_candidate "$word")" "$(fish_quote "$summary")"
          done
        else
          printf "complete -c muse %s -x -d '%s'\n" "$spelling" "$(fish_quote "$summary")"
        fi
        ;;
    esac
  done
}

case "$shell" in
  bash) emit_bash ;;
  zsh)  emit_zsh ;;
  fish) emit_fish ;;
esac
