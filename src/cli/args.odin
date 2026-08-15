package main

import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

import "../muse"

/*
A parsed command line: the command, the positional arguments after it, and the
flags that change how a result is rendered.

Only a double dash introduces a flag, with -o and -k the exceptions: a single
dash opens an interval name, so `muse transpose -m3` has to reach its command as
an operand, and no interval is named o or k.

key is the context a name cannot carry, passed explicitly rather than smuggled:
a MIDI file's key signature is a property of the music around the notes and not
of the notes themselves.

size is a note count and not the number a musician says: --size 7 is a seventh
chord and four notes. The spelling is translated here so that no command has to
know both.

duration is absent rather than defaulted, because the default is one bar and a
bar is only as long as the meter says. The sink resolves it once both are read.
*/
Options :: struct {
  command  : string,
  operands : []string,
  size     : int,
  octave   : int,
  tempo    : int,
  meter    : muse.Meter,
  duration : Maybe(muse.Duration),
  output   : string,
  key      : string,
  color    : Color,
  literal  : bool,
  plain    : bool,
  help     : bool,
  version  : bool,
}

/*
Whether to style output, asked of the terminal or answered outright. Auto is the
zero value because detection is what happens when nobody says otherwise.
*/
Color :: enum {
  Auto,
  Always,
  Never,
}

DEFAULT_SIZE   :: 3
DEFAULT_OCTAVE :: 4

/*
Split a command line into a command, its operands and its flags. The first
positional argument names the command and every later one is an operand.

Returns the offending token and false for a flag muse does not have, and for a
flag whose value it cannot use.
*/
options_parse :: proc(
  arguments : []string,
  allocator := context.allocator,
) -> (options: Options, token: string, ok: bool) {
  operands := make([dynamic]string, 0, len(arguments), allocator)

  defaults := muse.smf_default_options()
  options.size   = DEFAULT_SIZE
  options.octave = DEFAULT_OCTAVE
  options.tempo  = defaults.tempo
  options.meter  = defaults.meter

  for index := 0; index < len(arguments); index += 1 {
    argument := arguments[index]

    if argument == "-o" || argument == "-k" {
      index += 1
      if index == len(arguments) {
        return options, argument, false
      }
      if argument == "-o" {
        options.output = arguments[index]
      } else {
        options.key = arguments[index]
      }
      continue
    }

    if strings.has_prefix(argument, "--") {
      switch argument {
      case "--literal":
        options.literal = true
      case "--plain":
        options.plain = true
      case "--help":
        options.help = true
      case "--version":
        options.version = true
      case "--color":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        color, color_ok := color_parse(arguments[index])
        if !color_ok {
          return options, arguments[index], false
        }
        options.color = color
      case "--size":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        size, size_ok := size_notes(arguments[index])
        if !size_ok {
          return options, arguments[index], false
        }
        options.size = size
      case "--octave":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        octave, octave_ok := strconv.parse_int(arguments[index], 10)
        if !octave_ok {
          return options, arguments[index], false
        }
        options.octave = octave
      case "--key":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        options.key = arguments[index]
      case "--tempo":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        tempo, tempo_ok := strconv.parse_int(arguments[index], 10)
        if !tempo_ok || tempo <= 0 {
          return options, arguments[index], false
        }
        options.tempo = tempo
      case "--meter":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        meter, meter_ok := meter_parse(arguments[index])
        if !meter_ok {
          return options, arguments[index], false
        }
        options.meter = meter
      case "--duration":
        index += 1
        if index == len(arguments) {
          return options, argument, false
        }
        numerator, denominator, duration_ok := fraction_parse(arguments[index])
        if !duration_ok {
          return options, arguments[index], false
        }
        options.duration = muse.Duration{ numerator, denominator }
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
The note count a chord size names. The flag speaks the musician's numbers, where
a 7 is a seventh chord and a 13 reaches every odd degree below it, and everything
downstream counts notes.
*/
size_notes :: proc(token: string) -> (int, bool) {
  switch token {
  case "3":  return 3, true
  case "7":  return 4, true
  case "9":  return 5, true
  case "11": return 6, true
  case "13": return 7, true
  }
  return 0, false
}

/*
The three answers to whether output is colored. There is no fourth, and a token
that is none of them is a usage error rather than a silent fall back to auto.
*/
color_parse :: proc(token: string) -> (Color, bool) {
  switch token {
  case "auto":   return .Auto,   true
  case "always": return .Always, true
  case "never":  return .Never,  true
  }
  return .Auto, false
}

/*
A note value written as a fraction of a whole note: `1/4` is a quarter and `1`
is a whole one. Both halves are positive, since a duration of nothing is not a
duration.
*/
fraction_parse :: proc(token: string) -> (numerator, denominator: int, ok: bool) {
  numerator_text  := token
  denominator_text := "1"

  if slash := strings.index_byte(token, '/'); slash >= 0 {
    numerator_text   = token[:slash]
    denominator_text = token[slash + 1:]
  }

  numerator, ok = strconv.parse_int(numerator_text, 10)
  if !ok || numerator <= 0 {
    return 0, 0, false
  }

  denominator, ok = strconv.parse_int(denominator_text, 10)
  if !ok || denominator <= 0 {
    return 0, 0, false
  }

  return numerator, denominator, true
}

/*
A time signature, written the way it is on a stave. The lower number is a note
value rather than a count, so it is a power of two and 4/3 is not a meter.
*/
meter_parse :: proc(token: string) -> (muse.Meter, bool) {
  beats, unit, ok := fraction_parse(token)
  if !ok || unit & (unit - 1) != 0 {
    return {}, false
  }
  return muse.Meter{ beats = beats, unit = unit }, true
}

/*
Take a command's own argument off the front of its operands: the style `voice`
realizes in, the interval `transpose` moves by, the degree `degree` harmonizes.
What is left is the datum, and a command left with none reads stdin under the
one input rule exactly as it would have anyway.

Returns false when there is no argument to take, which is a usage error rather
than an empty input: `muse voice` alone has not said what to do.
*/
operand_take :: proc(options: Options) -> (string, Options, bool) {
  if len(options.operands) == 0 {
    return "", options, false
  }

  rest := options
  rest.operands = options.operands[1:]
  return options.operands[0], rest, true
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
The canonical spelling of a datum, which is what field one carries. Reading this
back returns the datum it was printed from, and that round trip is the whole of
the pipeline protocol.
*/
datum_string :: proc(datum: Datum, allocator := context.allocator) -> string {
  switch value in datum {
  case muse.Scale:
    return muse.scale_string(value, allocator)
  case muse.Chord:
    return muse.chord_string(value, allocator)
  case muse.Voicing:
    return voicing_string(value, allocator)
  case Notes:
    return notes_string(cast([]muse.Note)value, allocator)
  }
  return ""
}

/*
Move a datum by an interval, each kind in its own terms: a scale and a chord
move their root and keep their template, a voicing moves every pitch with its
register, and a note list moves note by note.

Returns false when a note of the result would need more than a double
accidental.
*/
datum_transpose :: proc(
  datum     : Datum,
  interval  : muse.Interval,
  allocator := context.allocator,
) -> (Datum, bool) {
  switch value in datum {
  case muse.Scale:
    scale, scale_ok := muse.scale_transpose(value, interval, allocator)
    if !scale_ok {
      return nil, false
    }
    return scale, true
  case muse.Chord:
    chord, chord_ok := muse.chord_transpose(value, interval, allocator)
    if !chord_ok {
      return nil, false
    }
    return chord, true
  case muse.Voicing:
    voicing, voicing_ok := muse.voicing_transpose(value, interval, allocator)
    if !voicing_ok {
      return nil, false
    }
    return voicing, true
  case Notes:
    notes := make([]muse.Note, len(value), allocator)
    for note, index in value {
      moved, moved_ok := muse.note_add_interval(note, interval)
      if !moved_ok {
        delete(notes, allocator)
        return nil, false
      }
      notes[index] = moved
    }
    return Notes(notes), true
  }
  return nil, false
}

/*
Realize a datum as pitches, and name the chord it forms where it names one. A
chord realizes in close position; anything else is stacked as it stands, which
puts a scale in one ascending run and leaves a voicing exactly where it already
sounds.

The chord comes back alongside because two voicing styles need one: a shell has
to know which degree is the third and which is the seventh, and a voicing alone
does not carry that.
*/
datum_realize :: proc(
  datum     : Datum,
  octave    := DEFAULT_OCTAVE,
  literal   := false,
  allocator := context.allocator,
) -> (voicing: muse.Voicing, chord: Maybe(muse.Chord), ok: bool) {
  if value, is_chord := datum.(muse.Chord); is_chord {
    realized, realized_ok := muse.voicing_close(value, octave, literal, allocator)
    return realized, value, realized_ok
  }

  if value, is_voicing := datum.(muse.Voicing); is_voicing {
    voicing = value
  } else {
    notes, notes_ok := datum_notes(datum, literal, context.temp_allocator)
    if !notes_ok {
      return {}, nil, false
    }
    voicing = muse.voicing_from_notes(notes, octave, allocator)
  }

  if named, named_ok := muse.chord_identify(muse.voicing_notes(voicing, context.temp_allocator), allocator); named_ok {
    chord = named
  }
  return voicing, chord, true
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

/*
A voicing as muse prints it: pitches low to high, each with its register, which
is the datum form every realization emits.
*/
voicing_string :: proc(voicing: muse.Voicing, allocator := context.allocator) -> string {
  spellings := make([]string, len(voicing.pitches), context.temp_allocator)
  for pitch, index in voicing.pitches {
    spellings[index] = muse.pitch_string(pitch, context.temp_allocator)
  }
  return strings.join(spellings, " ", allocator)
}
