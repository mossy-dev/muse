package main

import "core:os"
import "core:slice"
import "core:strings"

import "../muse"

/*
A parsed command line: the command, the positional arguments after it, and the
flags that change how a result is rendered.

Only a double dash introduces a flag. A single dash opens an interval name, so
`muse transpose -m3` has to reach its command as an operand.
*/
Options :: struct {
  command  : string,
  operands : []string,
  literal  : bool,
}

/*
Split a command line into a command, its operands and its flags. The first
positional argument names the command and every later one is an operand.

Returns the offending token and false for a flag muse does not have.
*/
options_parse :: proc(
  arguments : []string,
  allocator := context.allocator,
) -> (options: Options, token: string, ok: bool) {
  operands := make([dynamic]string, 0, len(arguments), allocator)

  for argument in arguments {
    if strings.has_prefix(argument, "--") {
      switch argument {
      case "--literal":
        options.literal = true
      case:
        return options, argument, false
      }
      continue
    }

    if len(options.command) == 0 {
      options.command = argument
      continue
    }
    append(&operands, argument)
  }

  options.operands = operands[:]
  return options, "", true
}

/*
The one input rule: a command's operands are its input, and a command given none
reads stdin. It lives here once, so no command carries a fallback of its own.

From arguments the operands join with single spaces and make one datum, so
`muse chord C E G` and `muse chord "C E G"` are the same request and no command
needs to know how the shell split its input. From stdin each non-empty line is a
datum: everything before the first tab, which is where the annotation columns
begin.

Returns false when that leaves nothing to work on, so every command reports an
empty input the same way.
*/
input_read :: proc(options: Options, allocator := context.allocator) -> ([]string, bool) {
  if len(options.operands) > 0 {
    data := make([]string, 1, allocator)
    data[0] = strings.join(options.operands, " ", allocator)
    return data, true
  }

  content, error := os.read_entire_file(os.stdin, allocator)
  if error != nil {
    return nil, false
  }

  data := make([dynamic]string, 0, 8, allocator)
  text := string(content)
  for line in strings.split_lines_iterator(&text) {
    datum := strings.trim_space(line_datum(line))
    if len(datum) > 0 {
      append(&data, datum)
    }
  }

  return data[:], len(data) > 0
}

/*
Field one of an input line. A piped line always carries its tab; a line with
none is a datum entire, which is what a file of hand-written symbols looks like.
*/
line_datum :: proc(line: string) -> string {
  if tab := strings.index_byte(line, '\t'); tab >= 0 {
    return line[:tab]
  }
  return line
}

/*
A note list read as a datum. It is the reading of last resort, since a bare list
of notes is what everything else reduces to.
*/
Notes :: distinct []muse.Note

/*
Everything field one of a line can hold. Notation is the protocol, so this is
the whole of it: no command reads a format muse invented for itself.
*/
Datum :: union {
  muse.Scale,
  muse.Chord,
  Notes,
  muse.Voicing,
}

/*
Read a line of notation as whatever it turns out to be, most specific first.

A scale is tried before a chord because only a scale carries a name after a
space, and pitches before notes because a pitch is a note with a register on it.
The one overlap the order settles is a single token like `C5`, which is the
power chord rather than a one-note voicing, matching the rule that an accidental
after the root binds to the root.
*/
datum_parse :: proc(text: string, allocator := context.allocator) -> (Datum, bool) {
  if scale, scale_ok := muse.scale_parse(text, allocator); scale_ok {
    return scale, true
  }
  if chord, chord_ok := muse.chord_parse(text, allocator); chord_ok {
    return chord, true
  }

  fields := strings.fields(text, context.temp_allocator)
  if len(fields) == 0 {
    return nil, false
  }

  pitches := make([dynamic]muse.Pitch, 0, len(fields), context.temp_allocator)
  for field in fields {
    pitch, pitch_ok := muse.pitch_parse(field)
    if !pitch_ok {
      break
    }
    append(&pitches, pitch)
  }
  if len(pitches) == len(fields) {
    return muse.voicing_make(pitches[:], allocator), true
  }

  notes := make([dynamic]muse.Note, 0, len(fields), allocator)
  for field in fields {
    note, note_ok := muse.note_parse(field)
    if !note_ok {
      return nil, false
    }
    append(&notes, note)
  }

  return Notes(notes[:]), true
}

/*
The notes a datum reduces to: a scale's members, a chord's realization, the
notes a voicing sounds, or a note list as it stands.

Returns false when a note would need more than a double accidental, which only a
scale or a chord on an already doubly altered root can reach.
*/
datum_notes :: proc(
  datum     : Datum,
  literal   := false,
  allocator := context.allocator,
) -> ([]muse.Note, bool) {
  switch value in datum {
  case muse.Scale:
    notes, _, notes_ok := muse.scale_notes(value, allocator)
    return notes, notes_ok
  case muse.Chord:
    return muse.chord_notes(value, literal, allocator)
  case muse.Voicing:
    return muse.voicing_notes(value, allocator), true
  case Notes:
    return slice.clone(cast([]muse.Note)value, allocator), true
  }
  return nil, false
}

/*
A note list as muse prints it and reads it back: names separated by single
spaces, which is the datum form `muse notes` emits.
*/
notes_string :: proc(notes: []muse.Note, allocator := context.allocator) -> string {
  spellings := make([]string, len(notes), context.temp_allocator)
  for note, index in notes {
    spellings[index] = muse.note_string(note, context.temp_allocator)
  }
  return strings.join(spellings, " ", allocator)
}
