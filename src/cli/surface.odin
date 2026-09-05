package main

import "core:fmt"
import "core:os"
import "core:strings"

import "../muse"

/*
The command surface, in one table.

`muse help` prints this, `muse help <topic>` answers questions about it, and
tools/completions.sh builds the three shell completions out of those answers. A
command added here therefore reaches the usage text, the man page and every
shell at once, which is the whole reason the table exists rather than a usage
string with a dispatch switch beside it.
*/

/*
A set of words an operand or a flag value can be. A vocabulary names its words
rather than holding them, because every list is derived from the table that
already defines it: the scale names from the scale templates, the degrees from
the roman numerals, the styles, colours and sizes from the tables their parsers
read. The rest name a shape nothing can enumerate -- a number, a file -- and
have no words at all.
*/
Vocabulary :: enum {
  None,
  Commands,
  Flags,
  Topics,
  Scales,
  Degrees,
  Styles,
  Colors,
  Sizes,
  Number,
  Fraction,
  Interval,
  Symbol,
  Notes,
  File,
}

/*
What `muse help <topic>` is asked for. None is unnamed: it is the absence of a
vocabulary rather than one of them.
*/
VOCABULARY_NAMES := [Vocabulary]string {
  .None     = "",
  .Commands = "commands",
  .Flags    = "flags",
  .Topics   = "topics",
  .Scales   = "scales",
  .Degrees  = "degrees",
  .Styles   = "styles",
  .Colors   = "colors",
  .Sizes    = "sizes",
  .Number   = "number",
  .Fraction = "fraction",
  .Interval = "interval",
  .Symbol   = "symbol",
  .Notes    = "notes",
  .File     = "file",
}

/*
The token a table entry writes where its vocabulary's words belong. It expands
to the words joined by a bar inside an argument, where it stands for a choice,
and by spaces inside a summary, where it is a list a reader is reading.
*/
WORDS :: "%words"

/*
One command: the word that names it, the operand shape its usage line shows,
the vocabulary that operand is drawn from, the summary under `muse help`, and
the proc that runs it.

A summary is a slice because two lines are sometimes needed and a wrapped one
would be indented wrongly.
*/
Command :: struct {
  name     : string,
  argument : string,
  operand  : Vocabulary,
  summary  : []string,
  run      : proc(options: Options) -> int,
}

@(rodata)
COMMANDS := []Command {
  { "scale", "<root> [name]", .Scales,
    { "build a scale, defaulting to major" }, command_scale },
  { "chord", "<symbol>", .Symbol,
    { "build a chord from a symbol" }, command_chord },
  { "chords", "[degrees ...]", .Degrees,
    { "harmonize a scale, every degree or the ones named",
      "a degree is 4, IV or iv; the case is muse's to get" }, command_chords },
  { "notes", "", .None,
    { "reduce anything to its bare note list" }, command_notes },
  { "interval", "<a> <b>", .Notes,
    { "name the interval between two notes" }, command_interval },
  { "transpose", "<interval>", .Interval,
    { "transpose, preserving spelling" }, command_transpose },
  { "invert", "<n>", .Number,
    { "invert a voicing" }, command_invert },
  { "voice", "<style>", .Styles,
    { "realize as pitches: " + WORDS }, command_voice },
  { "name", "<notes ...>", .Notes,
    { "identify the chord or scale a note set forms" }, command_name },
  { "in", "<key>", .Scales,
    { "annotate input with its degrees in a key" }, command_in },
  { "midi", "", .None,
    { "write a Standard MIDI File" }, command_midi },
  { "json", "", .None,
    { "structured output for programs; unstable, see below" }, command_json },
  { "numbers", "", .None,
    { "bare MIDI note numbers, one line per item" }, command_numbers },
  { "info", "", .None,
    { "everything muse knows about the input" }, command_info },
  { "keys", "", .None,
    { "draw the input on an ASCII keyboard" }, command_keys },
  { "help", "[topic]", .Topics,
    { "print this message, or the words a topic holds" }, command_help },
  { "version", "", .None,
    { "print the version" }, command_version },
}

/*
One flag: the spellings that reach it, the value shape its usage line shows,
the vocabulary that value is drawn from, and its summary.

A flag takes a value exactly when its vocabulary is not None, so nothing has to
say so twice.
*/
Flag :: struct {
  names    : []string,
  argument : string,
  value    : Vocabulary,
  summary  : []string,
}

@(rodata)
FLAGS := []Flag {
  { { "--size" }, WORDS, .Sizes,
    { "how far to stack a harmonization, default 3" } },
  { { "--octave" }, "<n>", .Number,
    { "where a realization sounds, default 4" } },
  { { "--literal" }, "", .None,
    { "keep the degree a chord's realization drops" } },
  { { "--color" }, "<when>", .Colors,
    { WORDS + "; default auto" } },
  { { "--plain" }, "", .None,
    { "drop the annotation columns and print field one" } },
  { { "--tempo" }, "<bpm>", .Number,
    { "beats per minute of a MIDI file, default 120" } },
  { { "--meter" }, "<n/d>", .Fraction,
    { "time signature of a MIDI file, default 4/4" } },
  { { "--duration" }, "<n/d>", .Fraction,
    { "how long each item sounds, default one bar" } },
  { { "-k", "--key" }, "<scale>", .Scales,
    { "the key degrees and signatures are named in" } },
  { { "-o" }, "<file>", .File,
    { "write a MIDI file here instead of to stdout" } },
  { { "--help" }, "", .None,
    { "print the command surface" } },
  { { "--version" }, "", .None,
    { "print the version" } },
}

USAGE_HEADER :: "usage: muse <command> [operand ...]\n"

USAGE_FOOTER ::
`Every command reads its operand from its arguments, and from stdin when it has
none, so any line muse prints can be piped into the next command or typed back
in by hand.

The json schema is unstable and may change without notice. It says what muse
knows about a datum rather than promising how that is spelled; it settles when
something depends on it.
`

/*
The usage text, built from the tables above. Summaries line up in a column as
wide as the widest invocation, so a longer command shifts the column rather
than running into it.
*/
usage_text :: proc(allocator := context.allocator) -> string {
  invocations := make([dynamic]string, 0, len(COMMANDS) + len(FLAGS), context.temp_allocator)
  for command in COMMANDS {
    append(&invocations, command_invocation(command, context.temp_allocator))
  }
  for flag in FLAGS {
    append(&invocations, flag_invocation(flag, context.temp_allocator))
  }

  width := 0
  for invocation in invocations {
    width = max(width, len(invocation))
  }

  builder := strings.builder_make(context.temp_allocator)
  strings.write_string(&builder, USAGE_HEADER)
  strings.write_string(&builder, "\n")

  for command, index in COMMANDS {
    write_entry(&builder, invocations[index], width, command.summary, command.operand)
  }
  strings.write_string(&builder, "\n")

  for flag, index in FLAGS {
    write_entry(&builder, invocations[len(COMMANDS) + index], width, flag.summary, flag.value)
  }
  strings.write_string(&builder, "\n")

  strings.write_string(&builder, USAGE_FOOTER)
  return strings.clone(strings.to_string(builder), allocator)
}

/*
One usage entry: the invocation indented by two, then its summary lines in a
column, each with its words substituted in.
*/
@(private)
write_entry :: proc(
  builder    : ^strings.Builder,
  invocation : string,
  width      : int,
  summary    : []string,
  vocabulary : Vocabulary,
) {
  for line, index in summary {
    heading := index == 0 ? invocation : ""
    strings.write_string(builder, "  ")
    strings.write_string(builder, heading)
    for _ in len(heading) ..< width + 2 {
      strings.write_byte(builder, ' ')
    }
    strings.write_string(builder, expand_words(line, vocabulary, " ", context.temp_allocator))
    strings.write_byte(builder, '\n')
  }
}

/*
A command's usage invocation: its name and the operand shape after it.
*/
@(private)
command_invocation :: proc(command: Command, allocator := context.allocator) -> string {
  argument := expand_words(command.argument, command.operand, "|", context.temp_allocator)
  if len(argument) == 0 {
    return strings.clone(command.name, allocator)
  }
  return fmt.aprintf("%s %s", command.name, argument, allocator = allocator)
}

/*
A flag's usage invocation: its spellings, and the value shape after them.
*/
@(private)
flag_invocation :: proc(flag: Flag, allocator := context.allocator) -> string {
  names    := strings.join(flag.names, ", ", context.temp_allocator)
  argument := expand_words(flag.argument, flag.value, "|", context.temp_allocator)
  if len(argument) == 0 {
    return strings.clone(names, allocator)
  }
  return fmt.aprintf("%s %s", names, argument, allocator = allocator)
}

/*
Substitute a vocabulary's words for the WORDS token, so the usage text spells
out a short closed list rather than restating one the tables already hold.
*/
@(private)
expand_words :: proc(
  text       : string,
  vocabulary : Vocabulary,
  separator  : string,
  allocator  := context.allocator,
) -> string {
  if !strings.contains(text, WORDS) {
    return strings.clone(text, allocator)
  }

  words := strings.join(
    vocabulary_words(vocabulary, context.temp_allocator),
    separator,
    context.temp_allocator,
  )
  replaced, _ := strings.replace_all(text, WORDS, words, allocator)
  return replaced
}

/*
The words a vocabulary holds, each read off the table that defines it. A
vocabulary that names a shape rather than a list -- a number, a file -- holds
none, and completion offers nothing for it.
*/
vocabulary_words :: proc(vocabulary: Vocabulary, allocator := context.allocator) -> []string {
  words := make([dynamic]string, 0, 32, allocator)

  switch vocabulary {
  case .Commands:
    for command in COMMANDS {
      append(&words, command.name)
    }
  case .Flags:
    for flag in FLAGS {
      append(&words, ..flag.names)
    }
  case .Topics:
    for name in VOCABULARY_NAMES {
      if len(name) > 0 {
        append(&words, name)
      }
    }
  case .Scales:
    append(&words, ..muse.scale_names(context.temp_allocator))
  case .Degrees:
    for numeral in muse.ROMAN_NUMERALS {
      append(&words, numeral)
      append(&words, strings.to_lower(numeral, allocator))
    }
  case .Styles:
    append(&words, ..VOICING_STYLES)
  case .Colors:
    for color in COLORS {
      append(&words, color.token)
    }
  case .Sizes:
    for size in SIZES {
      append(&words, size.token)
    }
  case .None, .Number, .Fraction, .Interval, .Symbol, .Notes, .File:
  }

  return words[:]
}

/*
The vocabulary a topic names.
*/
vocabulary_parse :: proc(topic: string) -> (Vocabulary, bool) {
  for name, vocabulary in VOCABULARY_NAMES {
    if len(name) > 0 && name == topic {
      return vocabulary, true
    }
  }
  return .None, false
}

/*
What `muse help <topic>` prints: one word to a line.

The two topics that describe the surface itself carry more than a word, so they
print three tab-separated fields -- the word, the vocabulary that follows it,
and its first summary line. That is what a completion generator needs to know
which words take a value and what to offer after one.
*/
vocabulary_text :: proc(vocabulary: Vocabulary, allocator := context.allocator) -> string {
  builder := strings.builder_make(context.temp_allocator)

  switch vocabulary {
  case .Commands:
    for command in COMMANDS {
      write_surface_line(&builder, command.name, command.operand, command.summary)
    }
  case .Flags:
    for flag in FLAGS {
      for name in flag.names {
        write_surface_line(&builder, name, flag.value, flag.summary)
      }
    }
  case .None, .Topics, .Scales, .Degrees, .Styles, .Colors, .Sizes,
       .Number, .Fraction, .Interval, .Symbol, .Notes, .File:
    for word in vocabulary_words(vocabulary, context.temp_allocator) {
      strings.write_string(&builder, word)
      strings.write_byte(&builder, '\n')
    }
  }

  return strings.clone(strings.to_string(builder), allocator)
}

@(private)
write_surface_line :: proc(
  builder    : ^strings.Builder,
  word       : string,
  vocabulary : Vocabulary,
  summary    : []string,
) {
  strings.write_string(builder, word)
  strings.write_byte(builder, '\t')
  strings.write_string(builder, VOCABULARY_NAMES[vocabulary])
  strings.write_byte(builder, '\t')
  strings.write_string(builder, expand_words(summary[0], vocabulary, " ", context.temp_allocator))
  strings.write_byte(builder, '\n')
}

/*
Print the usage text, or the words of the topic named after it.
*/
command_help :: proc(options: Options) -> int {
  topic, _, named := operand_take(options)
  if !named {
    os.write_string(os.stdout, usage_text(context.temp_allocator))
    return EXIT_SUCCESS
  }

  vocabulary, vocabulary_ok := vocabulary_parse(topic)
  if !vocabulary_ok {
    return fail(EXIT_USAGE, "no such topic", topic)
  }

  os.write_string(os.stdout, vocabulary_text(vocabulary, context.temp_allocator))
  return EXIT_SUCCESS
}
