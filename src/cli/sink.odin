package main

import "core:fmt"
import "core:os"
import "core:strings"

import "../muse"

/*
Why these are sinks and not transforms: none of what they emit parses as
notation, so nothing can follow one in a chain. Each reads field one and derives
everything else from the parsed datum, exactly as a transform does, which is
what makes them a test of the text protocol rather than a way around it.

Every one of them builds its whole output before writing any of it, which is how
"no partial output on failure" holds for a file of symbols with a bad line at the
end of it.
*/

/*
What can stop a sink writing. The datum that caused it is reported alongside, so
the message names the line rather than the command.
*/
SinkError :: enum {
  None,
  NotNotation,
  NotAKey,
  Unspellable,
  OutOfRange,
}

/*
The exit a sink failure earns. A line that is not notation is a parse error and
a line muse cannot answer for is a well-formed request with no answer, which is
the same split every transform makes.
*/
@(private)
sink_fail :: proc(error: SinkError, token: string) -> int {
  switch error {
  case .None:
    return EXIT_SUCCESS
  case .NotNotation:
    return fail(EXIT_USAGE, "not notation", token)
  case .NotAKey:
    return fail(EXIT_USAGE, "not a key", token)
  case .Unspellable:
    return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", token)
  case .OutOfRange:
    return fail(EXIT_NO_ANSWER, "outside the range MIDI can number", token)
  }
  return EXIT_SUCCESS
}

/*
The key a sink annotates against, from -k where it is given and from nowhere
else. A sink takes the same explicit context flag a transform does; nothing is
smuggled through the stream.
*/
@(private)
sink_key :: proc(options: Options, allocator := context.allocator) -> (Maybe(muse.Scale), bool) {
  if len(options.key) == 0 {
    return nil, true
  }

  key, key_ok := scale_read(options.key, allocator)
  if !key_ok {
    return nil, false
  }
  return key, true
}

/*
The degree a datum occupies in a key, or the empty string where no key was
given. It is the label `in` prints, from the same proc, so a numeral in a JSON
object and a numeral in a pipeline cannot disagree.
*/
@(private)
sink_degree :: proc(
  datum     : Datum,
  key       : Maybe(muse.Scale),
  literal   : bool,
  allocator := context.allocator,
) -> string {
  scale, keyed := key.?
  if !keyed {
    return ""
  }

  notes, notes_ok := label_notes(datum, literal, context.temp_allocator)
  if !notes_ok {
    return ""
  }
  return key_label(scale, notes, allocator)
}

/*
Write the input as a Standard MIDI File: every item the same length, laid end to
end, at the tempo and meter the flags asked for.

Anything that is not a voicing is realized on the way through, so a scale or a
bare symbol writes a file without a voice step in front of it.
*/
command_midi :: proc(options: Options) -> int {
  if midi_refuses_terminal(options.output, output_is_terminal()) {
    return fail(
      EXIT_USAGE,
      "refusing to write a MIDI file to a terminal",
      "redirect it or pass -o FILE",
    )
  }

  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  bytes, token, error := midi_bytes(data, options)
  if error != .None {
    return sink_fail(error, token)
  }

  if len(options.output) > 0 {
    if write_error := os.write_entire_file(options.output, bytes); write_error != nil {
      return fail(EXIT_USAGE, "cannot write", options.output)
    }
    return EXIT_SUCCESS
  }

  os.write(os.stdout, bytes)
  return EXIT_SUCCESS
}

/*
Binary belongs in a file or a pipe and not on a screen. Redirection is the unix
answer and -o FILE is the other one, so a terminal with neither is a request
muse declines rather than one it garbles.

The check is a predicate over the terminal rather than a reading of it, which is
what lets the rule be tested without a terminal to test it on. It runs before
the input is read, so a refusal costs the pipeline in front of it nothing.
*/
@(private)
midi_refuses_terminal :: proc(output: string, is_terminal: bool) -> bool {
  return len(output) == 0 && is_terminal
}

/*
The bytes a run of input encodes to. Every line is parsed and realized before
anything is written, which is the same rule the transforms follow: a failure on
the last line leaves no half-written file.

The key signature comes from -k where it is given and from the first datum that
is a scale otherwise, so `muse scale G major | muse midi` carries its own key and
a chain that has lost its scale can be told one. A run naming no key writes no
key signature rather than guessing at C major.

Returns the offending datum with the failure, and an empty token where the
failure belongs to no single line.
*/
@(private)
midi_bytes :: proc(
  data      : []string,
  options   : Options,
  allocator := context.allocator,
) -> ([]byte, string, SinkError) {
  items     := make([dynamic]muse.Voicing, 0, len(data), allocator)
  smf       := midi_options(options)
  key_found := false

  if len(options.key) > 0 {
    key, key_ok := scale_read(options.key, allocator)
    if !key_ok {
      return nil, options.key, .NotAKey
    }
    smf.key   = key
    key_found = true
  }

  for text in data {
    datum, datum_ok := datum_parse(text, allocator)
    if !datum_ok {
      return nil, text, .NotNotation
    }

    if scale, is_scale := datum.(muse.Scale); is_scale && !key_found {
      smf.key   = scale
      key_found = true
    }

    voicings, voicings_ok := midi_items(datum, options, allocator)
    if !voicings_ok {
      return nil, text, .Unspellable
    }

    for voicing in voicings {
      if !muse.smf_in_range(voicing) {
        return nil, text, .OutOfRange
      }
      append(&items, voicing)
    }
  }

  bytes, encode_ok := muse.smf_encode(items[:], smf, allocator)
  if !encode_ok {
    return nil, "", .OutOfRange
  }

  return bytes, "", .None
}

/*
The items one datum sounds as.

A scale is a run of single notes, one to an item, because a scale is a melody
and a chord is not: DESIGN.md's own remark that a scale reads better as quarter
notes than as seven whole bars only makes sense if its notes are the items. A
`voice` step in front of the sink makes the same scale one chord, which is how
the cluster is asked for.
*/
@(private)
midi_items :: proc(
  datum     : Datum,
  options   : Options,
  allocator := context.allocator,
) -> ([]muse.Voicing, bool) {
  voicing, _, realized_ok := datum_realize(datum, options.octave, options.literal, allocator)
  if !realized_ok {
    return nil, false
  }

  if _, is_scale := datum.(muse.Scale); !is_scale {
    single := make([]muse.Voicing, 1, allocator)
    single[0] = voicing
    return single, true
  }

  run := make([]muse.Voicing, len(voicing.pitches), allocator)
  for pitch, index in voicing.pitches {
    run[index] = muse.voicing_make([]muse.Pitch{ pitch }, allocator)
  }
  return run, true
}

/*
Structured output for programs: one object per input line, inside one array, so
what comes out is a whole document rather than a stream a reader has to assemble.

The schema is parking lot item A in DESIGN.md and is explicitly unstable. It says
what muse knows about a datum, which is not the same as a promise about how that
will be spelled next month, and --help says so.
*/
command_json :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  key, key_ok := sink_key(options)
  if !key_ok {
    return sink_fail(.NotAKey, options.key)
  }

  text, token, error := json_text(data, key, options)
  if error != .None {
    return sink_fail(error, token)
  }

  os.write_string(os.stdout, text)
  return EXIT_SUCCESS
}

/*
Bare MIDI note numbers, one line per input line, for a script that wants pitches
without carrying a parser to get them.

Anything that is not already a voicing is realized on the way through, by the same
route the MIDI sink realizes it, so the numbers and the file agree on the pitches.
Where they differ is grouping: a line here is a line of input, whereas a scale
reaches the file as a run of separate items.
*/
command_numbers :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  text, token, error := numbers_text(data, options)
  if error != .None {
    return sink_fail(error, token)
  }

  os.write_string(os.stdout, text)
  return EXIT_SUCCESS
}

/*
Everything muse knows about the input, a block to a line: what the datum is, what
it is made of, and what it sounds as. It is the sink for a reader rather than for
a program, which is why it is prose-shaped where json is not.
*/
command_info :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  key, key_ok := sink_key(options)
  if !key_ok {
    return sink_fail(.NotAKey, options.key)
  }

  text, token, error := info_text(data, key, options)
  if error != .None {
    return sink_fail(error, token)
  }

  os.write_string(os.stdout, text)
  return EXIT_SUCCESS
}

/*
The whole array, built before a byte of it is written.

Returns the offending datum with the failure, so a bad line in the middle of a
file is named rather than being counted.
*/
@(private)
json_text :: proc(
  data      : []string,
  key       : Maybe(muse.Scale),
  options   : Options,
  allocator := context.allocator,
) -> (string, string, SinkError) {
  builder := strings.builder_make(allocator)
  strings.write_string(&builder, "[\n")

  for text, index in data {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    if !datum_ok {
      return "", text, .NotNotation
    }

    object, object_ok := json_object(datum, key, options, context.temp_allocator)
    if !object_ok {
      return "", text, .Unspellable
    }

    strings.write_string(&builder, object)
    strings.write_string(&builder, index == len(data) - 1 ? "\n" : ",\n")
  }

  strings.write_string(&builder, "]\n")
  return strings.to_string(builder), "", .None
}

/*
One datum as an object. Every kind carries its own fields and every one of them
is derived from field one alone, which is the property the sink exists to test:
if a chord object is complete, the text protocol carried the whole chord.

The omitted list is empty under --literal, since the object describes the
realization it just printed and that realization dropped nothing.
*/
@(private)
json_object :: proc(
  datum     : Datum,
  key       : Maybe(muse.Scale),
  options   : Options,
  allocator := context.allocator,
) -> (string, bool) {
  notes, notes_ok := datum_notes(datum, options.literal, context.temp_allocator)
  if !notes_ok {
    return "", false
  }

  fields := make([dynamic]string, 0, 8, context.temp_allocator)

  switch value in datum {
  case muse.Scale:
    append(&fields, json_text_pair("type", "scale"))
    append(&fields, json_text_pair("name", muse.scale_string(value, context.temp_allocator)))
    append(&fields, json_text_pair("root", muse.note_string(value.root, context.temp_allocator)))
    append(&fields, json_note_pair("notes", notes))
    append(&fields, json_interval_pair("intervals", value.intervals))

  case muse.Chord:
    append(&fields, json_text_pair("type", "chord"))
    append(&fields, json_text_pair("symbol", muse.chord_string(value, context.temp_allocator)))
    append(&fields, json_text_pair("root", muse.note_string(value.root, context.temp_allocator)))
    if bass, has_bass := value.bass.?; has_bass {
      append(&fields, json_text_pair("bass", muse.note_string(bass, context.temp_allocator)))
    } else {
      append(&fields, json_null_pair("bass"))
    }
    append(&fields, json_note_pair("notes", notes))
    append(&fields, json_interval_pair("intervals", value.intervals))
    omitted := options.literal ? nil : muse.chord_omissions(value, context.temp_allocator)
    append(&fields, json_interval_pair("omitted", omitted))

  case muse.Voicing:
    append(&fields, json_text_pair("type", "voicing"))
    append(&fields, json_pitch_pair("pitches", value.pitches))
    append(&fields, json_number_pair("midi", pitch_numbers(value, context.temp_allocator)))
    append(&fields, json_note_pair("notes", notes))
    append(&fields, json_name_pair("chord", notes))

  case Notes:
    append(&fields, json_text_pair("type", "notes"))
    append(&fields, json_note_pair("notes", notes))
    append(&fields, json_interval_pair("intervals", notes_intervals(notes, context.temp_allocator)))
    append(&fields, json_name_pair("chord", notes))
  }

  if degree := sink_degree(datum, key, options.literal, context.temp_allocator); len(degree) > 0 {
    append(&fields, json_text_pair("degree", degree))
  }

  return strings.concatenate([]string {
    "  {\n    ",
    strings.join(fields[:], ",\n    ", context.temp_allocator),
    "\n  }",
  }, allocator), true
}

/*
The number lines, built before any of them is written.

A pitch outside the 128 MIDI can number is refused rather than wrapped, since a
number nothing can play is worse than a message saying so.
*/
@(private)
numbers_text :: proc(
  data      : []string,
  options   : Options,
  allocator := context.allocator,
) -> (string, string, SinkError) {
  builder := strings.builder_make(allocator)

  for text in data {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    if !datum_ok {
      return "", text, .NotNotation
    }

    voicing, _, realized_ok := datum_realize(datum, options.octave, options.literal, context.temp_allocator)
    if !realized_ok {
      return "", text, .Unspellable
    }
    if !muse.smf_in_range(voicing) {
      return "", text, .OutOfRange
    }

    strings.write_string(&builder, numbers_string(voicing, context.temp_allocator))
    strings.write_byte(&builder, '\n')
  }

  return strings.to_string(builder), "", .None
}

/*
The blocks, one to a datum, separated by a blank line.
*/
@(private)
info_text :: proc(
  data      : []string,
  key       : Maybe(muse.Scale),
  options   : Options,
  allocator := context.allocator,
) -> (string, string, SinkError) {
  builder := strings.builder_make(allocator)

  for text, index in data {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    if !datum_ok {
      return "", text, .NotNotation
    }

    if index > 0 {
      strings.write_byte(&builder, '\n')
    }
    if error := info_block(&builder, datum, key, options); error != .None {
      return "", text, error
    }
  }

  return strings.to_string(builder), "", .None
}

/*
One datum's block: the canonical spelling as a heading, then the fields that kind
has. A scale carries its harmonization, because what a scale is for is the chords
in it and a reader asking for everything is asking for those.

The MIDI row is omitted rather than wrapped where a realization falls outside the
128 notes MIDI numbers, which is what --octave 10 reaches.
*/
@(private)
info_block :: proc(
  builder : ^strings.Builder,
  datum   : Datum,
  key     : Maybe(muse.Scale),
  options : Options,
) -> SinkError {
  notes, notes_ok := datum_notes(datum, options.literal, context.temp_allocator)
  if !notes_ok {
    return .Unspellable
  }

  voicing, _, realized_ok := datum_realize(datum, options.octave, options.literal, context.temp_allocator)
  if !realized_ok {
    return .Unspellable
  }

  strings.write_string(builder, datum_string(datum, context.temp_allocator))
  strings.write_byte(builder, '\n')

  switch value in datum {
  case muse.Scale:
    info_field(builder, "type", "scale")
    info_field(builder, "root", muse.note_string(value.root, context.temp_allocator))
    info_field(builder, "notes", notes_string(notes, context.temp_allocator))
    info_field(builder, "intervals", info_intervals(value.intervals))

  case muse.Chord:
    info_field(builder, "type", "chord")
    info_field(builder, "root", muse.note_string(value.root, context.temp_allocator))
    if bass, has_bass := value.bass.?; has_bass {
      info_field(builder, "bass", muse.note_string(bass, context.temp_allocator))
    }
    info_field(builder, "notes", notes_string(notes, context.temp_allocator))
    info_field(builder, "intervals", info_intervals(value.intervals))
    if omissions := muse.chord_omissions(value, context.temp_allocator); len(omissions) > 0 && !options.literal {
      info_field(builder, "omits", info_intervals(omissions))
    }

  case muse.Voicing:
    info_field(builder, "type", "voicing")
    info_field(builder, "notes", notes_string(notes, context.temp_allocator))
    info_field(builder, "chord", info_name(notes))

  case Notes:
    info_field(builder, "type", "notes")
    info_field(builder, "notes", notes_string(notes, context.temp_allocator))
    info_field(builder, "intervals", info_intervals(notes_intervals(notes, context.temp_allocator)))
    info_field(builder, "chord", info_name(notes))
  }

  if muse.smf_in_range(voicing) {
    info_field(builder, "midi", numbers_string(voicing, context.temp_allocator))
  }
  info_field(builder, "degree", sink_degree(datum, key, options.literal, context.temp_allocator))

  if scale, is_scale := datum.(muse.Scale); is_scale {
    info_field(builder, "triads", info_harmony(scale, 3))
    info_field(builder, "sevenths", info_harmony(scale, 4))
  }

  return .None
}

/*
One labelled row of a block, or nothing at all where the value is empty: a field
muse has no answer for is left out rather than printed blank.
*/
@(private)
info_field :: proc(builder: ^strings.Builder, label, value: string) {
  if len(value) == 0 {
    return
  }

  strings.write_string(builder, "  ")
  strings.write_string(builder, label)
  for _ in len(label) ..< INFO_LABEL_WIDTH {
    strings.write_byte(builder, ' ')
  }
  strings.write_string(builder, value)
  strings.write_byte(builder, '\n')
}

/*
Wide enough for the longest label a block uses, and narrow enough that a block
still reads as a list rather than as a table.
*/
INFO_LABEL_WIDTH :: 10

/*
A scale's harmonization at one size, named where a stack names a chord and given
as its notes where none does -- the same answer `muse chords` prints, since it is
the same question.
*/
@(private)
info_harmony :: proc(scale: muse.Scale, size: int, allocator := context.temp_allocator) -> string {
  harmonies, harmonies_ok := muse.scale_harmonize(scale, size, context.temp_allocator)
  if !harmonies_ok {
    return ""
  }

  names := make([]string, len(harmonies), context.temp_allocator)
  for harmony, index in harmonies {
    if chord, named := harmony.chord.?; named {
      names[index] = muse.chord_string(chord, context.temp_allocator)
    } else {
      names[index] = notes_string(harmony.notes, context.temp_allocator)
    }
  }

  return strings.join(names, " ", allocator)
}

/*
The chord a note set names, or nothing where no template does. Parking lot item F
in DESIGN.md is the reason that is an absence rather than a failure.
*/
@(private)
info_name :: proc(notes: []muse.Note, allocator := context.temp_allocator) -> string {
  chord, named := muse.chord_identify(notes, context.temp_allocator)
  if !named {
    return ""
  }
  return muse.chord_string(chord, allocator)
}

/*
An interval list as a reader writes it, or nothing where notation has no word for
one of them.
*/
@(private)
info_intervals :: proc(intervals: []muse.Interval, allocator := context.temp_allocator) -> string {
  abbreviations, ok := interval_abbreviations(intervals, context.temp_allocator)
  if !ok {
    return ""
  }
  return strings.join(abbreviations, " ", allocator)
}

/*
The MIDI numbers a voicing sounds, separated by single spaces.
*/
@(private)
numbers_string :: proc(voicing: muse.Voicing, allocator := context.allocator) -> string {
  builder := strings.builder_make(allocator)
  for pitch, index in voicing.pitches {
    if index > 0 {
      strings.write_byte(&builder, ' ')
    }
    strings.write_int(&builder, muse.pitch_midi(pitch))
  }
  return strings.to_string(builder)
}

@(private)
pitch_numbers :: proc(voicing: muse.Voicing, allocator := context.allocator) -> []int {
  numbers := make([]int, len(voicing.pitches), allocator)
  for pitch, index in voicing.pitches {
    numbers[index] = muse.pitch_midi(pitch)
  }
  return numbers
}

/*
The intervals a note list spans, measured from its lowest note, which is the only
thing a bare set of notes can be measured from.
*/
@(private)
notes_intervals :: proc(notes: []muse.Note, allocator := context.allocator) -> []muse.Interval {
  intervals := make([]muse.Interval, len(notes), allocator)
  for note, index in notes {
    intervals[index] = muse.interval_between(notes[0], note)
  }
  return intervals
}

/*
Interval abbreviations, or false where one of them has no nameable quality. A set
built from a template always names; a pair of doubly altered notes need not, and
notation having no word for it is worth reporting rather than inventing one.
*/
@(private)
interval_abbreviations :: proc(
  intervals : []muse.Interval,
  allocator := context.allocator,
) -> ([]string, bool) {
  abbreviations := make([]string, len(intervals), allocator)
  for interval, index in intervals {
    abbreviation, ok := muse.interval_abbreviation(interval, allocator)
    if !ok {
      return nil, false
    }
    abbreviations[index] = abbreviation
  }
  return abbreviations, true
}

/*
The JSON pieces. Nothing muse prints carries a quote or a backslash -- the values
are note names, template symbols and roman numerals -- so a value is quoted and
written as it stands.
*/
@(private)
json_text_pair :: proc(name, value: string, allocator := context.temp_allocator) -> string {
  return fmt.aprintf("\"%s\": \"%s\"", name, value, allocator = allocator)
}

@(private)
json_null_pair :: proc(name: string, allocator := context.temp_allocator) -> string {
  return fmt.aprintf("\"%s\": null", name, allocator = allocator)
}

@(private)
json_list_pair :: proc(name: string, values: []string, allocator := context.temp_allocator) -> string {
  quoted := make([]string, len(values), context.temp_allocator)
  for value, index in values {
    quoted[index] = fmt.tprintf("\"%s\"", value)
  }
  return fmt.aprintf(
    "\"%s\": [%s]",
    name,
    strings.join(quoted, ", ", context.temp_allocator),
    allocator = allocator,
  )
}

@(private)
json_number_pair :: proc(name: string, values: []int, allocator := context.temp_allocator) -> string {
  written := make([]string, len(values), context.temp_allocator)
  for value, index in values {
    written[index] = fmt.tprintf("%d", value)
  }
  return fmt.aprintf(
    "\"%s\": [%s]",
    name,
    strings.join(written, ", ", context.temp_allocator),
    allocator = allocator,
  )
}

@(private)
json_note_pair :: proc(name: string, notes: []muse.Note, allocator := context.temp_allocator) -> string {
  spellings := make([]string, len(notes), context.temp_allocator)
  for note, index in notes {
    spellings[index] = muse.note_string(note, context.temp_allocator)
  }
  return json_list_pair(name, spellings, allocator)
}

@(private)
json_pitch_pair :: proc(name: string, pitches: []muse.Pitch, allocator := context.temp_allocator) -> string {
  spellings := make([]string, len(pitches), context.temp_allocator)
  for pitch, index in pitches {
    spellings[index] = muse.pitch_string(pitch, context.temp_allocator)
  }
  return json_list_pair(name, spellings, allocator)
}

/*
An interval list, or null where notation has no word for one of them. A missing
name is reported as an absence rather than as a spelling that does not exist.
*/
@(private)
json_interval_pair :: proc(
  name      : string,
  intervals : []muse.Interval,
  allocator := context.temp_allocator,
) -> string {
  abbreviations, ok := interval_abbreviations(intervals, context.temp_allocator)
  if !ok {
    return json_null_pair(name, allocator)
  }
  return json_list_pair(name, abbreviations, allocator)
}

/*
The chord a note set names, or null where no template does.
*/
@(private)
json_name_pair :: proc(name: string, notes: []muse.Note, allocator := context.temp_allocator) -> string {
  chord, named := muse.chord_identify(notes, context.temp_allocator)
  if !named {
    return json_null_pair(name, allocator)
  }
  return json_text_pair(name, muse.chord_string(chord, context.temp_allocator), allocator)
}

/*
The encoder's options from the command line's. The duration a flag did not give
is one bar, which is a length only the meter knows, so it is resolved here where
both have been read.
*/
@(private)
midi_options :: proc(options: Options) -> muse.SmfOptions {
  smf := muse.smf_default_options()

  smf.tempo    = options.tempo
  smf.meter    = options.meter
  smf.duration = options.duration.? or_else muse.meter_bar(options.meter)

  return smf
}
