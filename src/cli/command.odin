package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "../muse"

/*
Build a scale and print its notes.

The name defaults to major here rather than in the parser: a bare `G` is a scale
only because this command has an argument missing, and a parser that read one as
a scale would make every chord symbol ambiguous.
*/
command_scale :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    scale, scale_ok := scale_read(text)
    if !scale_ok {
      return fail(EXIT_USAGE, "not a scale", text)
    }

    notes, degree, notes_ok := muse.scale_notes(scale)
    if !notes_ok {
      return report_unspellable(scale, degree)
    }

    annotations := make([]string, 1)
    annotations[0] = notes_string(notes)

    append(&rows, Row{ datum = muse.scale_string(scale), annotations = annotations })
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Build a chord from its symbol and print its notes, naming the degree the
realization drops. --literal keeps the full stack instead, which is the same
chord printed two ways.

A symbol whose root swallowed an accidental is read greedily and the other
reading is named afterwards, so that on a terminal the answer comes before the
remark about it.
*/
command_chord :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows     := make([dynamic]Row, 0, len(data))
  readings := make([dynamic]string, 0, len(data))

  for text in data {
    chord, chord_ok := muse.chord_parse(text)
    if !chord_ok {
      return fail(EXIT_USAGE, "not a chord", text)
    }

    row, row_ok := datum_row(chord, options.literal)
    if !row_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }
    append(&rows, row)

    if spelling, ambiguous := muse.chord_ambiguity(text); ambiguous {
      append(&readings, fmt.aprintf(
        "read as root %s; write %s for the other reading",
        muse.note_string(chord.root, context.temp_allocator),
        spelling,
      ))
    }
  }

  render(rows[:])
  for reading in readings {
    warn(reading)
  }
  return EXIT_SUCCESS
}

/*
Harmonize a scale: every degree in scale order, or the degrees named in front of
it and in the order they were named. `muse chords I V vi IV` is a progression,
and a degree may repeat because a progression may return to it.

A stack no template names is not a failure: the notes are the datum for that
line and the intervals from its bass are the annotation, which is what makes a
pentatonic scale harmonize into something rather than into nothing.
*/
command_chords :: proc(options: Options) -> int {
  degrees, rest := degrees_take(options)
  tokens        := options.operands[:len(degrees)]

  data, data_ok := input_read(rest)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data) * max(len(degrees), 7))
  for text in data {
    scale, scale_ok := scale_read(text)
    if !scale_ok {
      return fail(EXIT_USAGE, "not a scale", text)
    }

    if _, unspelled, spells := muse.scale_notes(scale, context.temp_allocator); !spells {
      return report_unspellable(scale, unspelled)
    }

    lines, failed, lines_ok := harmony_rows(scale, degrees, options.size)
    if !lines_ok {
      return fail(EXIT_NO_ANSWER, "no such degree", tokens[failed])
    }

    append(&rows, ..lines)
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Transpose anything by an interval, preserving spelling.

An interval name says which third it means, so `transpose m3` and `transpose A2`
move by the same sound and spell differently. A bare number of semitones cannot
say, so it is spelled as the major, minor or perfect interval of that distance,
and that is the difference between `transpose 3` and `transpose M3`.
*/
command_transpose :: proc(options: Options) -> int {
  token, rest, token_ok := operand_take(options)
  if !token_ok {
    return fail(EXIT_USAGE, "transpose takes an interval", options.command)
  }

  interval, interval_ok := transpose_interval(token)
  if !interval_ok {
    return fail(EXIT_USAGE, "not an interval", token)
  }

  data, data_ok := input_read(rest)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    moved, moved_ok := datum_transpose(datum, interval)
    if !moved_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    row, row_ok := datum_row(moved, options.literal)
    if !row_ok {
      if scale, is_scale := moved.(muse.Scale); is_scale {
        _, degree, _ := muse.scale_notes(scale, context.temp_allocator)
        return report_unspellable(scale, degree)
      }
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    append(&rows, row)
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Realize the input as pitches in one of the five styles.

Anything that is not a chord is realized on the way through, so a scale or a
note list voices as readily as a symbol does. Only shell needs a chord, and a
note set that names none is a well-formed request with no answer.
*/
command_voice :: proc(options: Options) -> int {
  style, rest, style_ok := operand_take(options)
  if !style_ok {
    return fail(EXIT_USAGE, "voice takes a style", options.command)
  }
  switch style {
  case "close", "open", "drop2", "drop3", "shell":
  case:
    return fail(EXIT_USAGE, "not a voicing style", style)
  }

  data, data_ok := input_read(rest)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    voicing, chord, realized_ok := datum_realize(datum, options.octave, options.literal)
    if !realized_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    voiced, voiced_ok := voicing_style(voicing, chord, style, options.octave)
    if !voiced_ok {
      return fail(EXIT_NO_ANSWER, fmt.tprintf("no %s voicing", style), text)
    }

    append(&rows, voicing_row(voiced))
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Invert a voicing, moving its bottom pitch up an octave n times over. Anything
that is not already a voicing is realized first, so a chord symbol inverts
without a voice step in front of it.
*/
command_invert :: proc(options: Options) -> int {
  token, rest, token_ok := operand_take(options)
  if !token_ok {
    return fail(EXIT_USAGE, "invert takes a number", options.command)
  }

  n, n_ok := strconv.parse_int(token, 10)
  if !n_ok {
    return fail(EXIT_USAGE, "not a number", token)
  }

  data, data_ok := input_read(rest)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    voicing, _, realized_ok := datum_realize(datum, options.octave, options.literal)
    if !realized_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }
    if len(voicing.pitches) < 2 {
      return fail(EXIT_NO_ANSWER, "nothing to invert", text)
    }

    append(&rows, voicing_row(muse.voicing_invert(voicing, n)))
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Name the scale or the chord a note set forms, with the modal readings of a scale
following it as annotation.

A set no template names is a well-formed request with no answer, which is
parking lot item F in DESIGN.md and not a parse failure.
*/
command_name :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    notes, notes_ok := datum_notes(datum, options.literal)
    if !notes_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    row, row_ok := name_row(notes)
    if !row_ok {
      return fail(EXIT_NO_ANSWER, "no name for these notes", text)
    }

    append(&rows, row)
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Annotate every line with the degree it occupies in a key, and change field one
in no way at all. A commentary command that rewrote its input would make every
later command's answer depend on whether it had been asked for a numeral.
*/
command_in :: proc(options: Options) -> int {
  key_text, rest, key_ok := key_take(options)
  if !key_ok {
    return fail(EXIT_USAGE, "in takes a key", options.command)
  }

  key, key_read_ok := scale_read(key_text)
  if !key_read_ok {
    return fail(EXIT_USAGE, "not a key", key_text)
  }

  if _, degree, key_spells := muse.scale_notes(key, context.temp_allocator); !key_spells {
    return report_unspellable(key, degree)
  }

  data, data_ok := input_read(rest)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    notes, notes_ok := label_notes(datum, options.literal)
    if !notes_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    annotations := make([]string, 1)
    annotations[0] = key_label(key, notes)

    append(&rows, Row{ datum = text, annotations = annotations })
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Print the command surface. It goes to stdout and exits clean, unlike the same
text printed for a command line with nothing on it.
*/
command_help :: proc() -> int {
  os.write_string(os.stdout, USAGE)
  return EXIT_SUCCESS
}

/*
Reduce anything to its bare note list. This is the command that proves the
protocol: whatever built the line, what comes out is the note list and nothing
else, and it parses back as one.
*/
command_notes :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    datum, datum_ok := datum_parse(text)
    if !datum_ok {
      return fail(EXIT_USAGE, "not notation", text)
    }

    notes, notes_ok := datum_notes(datum, options.literal)
    if !notes_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    append(&rows, Row{ datum = notes_string(notes) })
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Name the interval between two notes. Two pitches are measured with their
registers, so C4 to E5 is a tenth, while two notes without registers are
measured within an octave.
*/
command_interval :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  rows := make([dynamic]Row, 0, len(data))
  for text in data {
    fields := strings.fields(text, context.temp_allocator)
    if len(fields) != 2 {
      return fail(EXIT_USAGE, "interval takes two notes", text)
    }

    interval, token, interval_ok := interval_read(fields[0], fields[1])
    if !interval_ok {
      return fail(EXIT_USAGE, "not a note", token)
    }

    abbreviation, abbreviation_ok := muse.interval_abbreviation(interval)
    if !abbreviation_ok {
      return fail(EXIT_NO_ANSWER, "no name for this interval", text)
    }
    name, _ := muse.interval_name(interval)

    annotations := make([]string, 2)
    annotations[0] = name
    annotations[1] = semitones_string(interval.semitones)

    append(&rows, Row{ datum = abbreviation, annotations = annotations })
  }

  render(rows[:])
  return EXIT_SUCCESS
}

/*
Read a scale, from its name, from a bare root taken as major, or from the note
list a scale reduces to. The last of those is what lets a harmonization follow a
`muse notes` step, since a scale identified from its members is the same scale
its name built.
*/
@(private)
scale_read :: proc(text: string, allocator := context.allocator) -> (muse.Scale, bool) {
  if scale, scale_ok := muse.scale_parse(text, allocator); scale_ok {
    return scale, true
  }
  if _, root_ok := muse.note_parse(text); root_ok {
    return muse.scale_parse(fmt.tprintf("%s major", text), allocator)
  }

  datum, datum_ok := datum_parse(text, context.temp_allocator)
  if !datum_ok {
    return {}, false
  }
  notes, notes_ok := datum_notes(datum, false, context.temp_allocator)
  if !notes_ok {
    return {}, false
  }

  return muse.scale_identify(notes, allocator)
}

/*
The interval between two operands, measured with register when both carry one.
Returns the offending token and false when either is not a note.
*/
@(private)
interval_read :: proc(from_text, to_text: string) -> (muse.Interval, string, bool) {
  from_pitch, from_is_pitch := muse.pitch_parse(from_text)
  to_pitch,   to_is_pitch   := muse.pitch_parse(to_text)
  if from_is_pitch && to_is_pitch {
    return muse.pitch_interval_between(from_pitch, to_pitch), "", true
  }

  from_note, from_is_note := muse.note_parse(from_text)
  if !from_is_note {
    return {}, from_text, false
  }
  to_note, to_is_note := muse.note_parse(to_text)
  if !to_is_note {
    return {}, to_text, false
  }

  return muse.interval_between(from_note, to_note), "", true
}

/*
A scale whose spelling runs past a double accidental gets a precise no: which
degree ran out, and the enharmonic root that spells where one does. The
suggestion is offered and never applied, since `muse scale G## harmonic` asked a
precise question.
*/
@(private)
report_unspellable :: proc(scale: muse.Scale, degree: int) -> int {
  code := fail(
    EXIT_NO_ANSWER,
    fmt.tprintf("degree %d needs more than a double accidental", degree),
    muse.scale_string(scale, context.temp_allocator),
  )

  if respelled, respell_ok := muse.scale_respell(scale, context.temp_allocator); respell_ok {
    warn(fmt.tprintf("%s spells", muse.scale_string(respelled, context.temp_allocator)))
  }

  return code
}

/*
A datum as a line: its canonical spelling in field one and the notes it sounds
beside it, with the degree a chord's realization drops named after them.

A note list and a voicing carry their notes in field one already, so neither
repeats them in a column.
*/
@(private)
datum_row :: proc(datum: Datum, literal := false, allocator := context.allocator) -> (Row, bool) {
  switch value in datum {
  case muse.Scale:
    notes, _, notes_ok := muse.scale_notes(value, context.temp_allocator)
    if !notes_ok {
      return {}, false
    }

    annotations := make([]string, 1, allocator)
    annotations[0] = notes_string(notes, allocator)
    return Row{ datum = muse.scale_string(value, allocator), annotations = annotations }, true

  case muse.Chord:
    notes, notes_ok := muse.chord_notes(value, literal, context.temp_allocator)
    if !notes_ok {
      return {}, false
    }

    annotations := make([dynamic]string, 0, 2, allocator)
    append(&annotations, notes_string(notes, allocator))
    if omissions := muse.chord_omissions(value, context.temp_allocator); len(omissions) > 0 && !literal {
      append(&annotations, omissions_string(omissions, allocator))
    }
    return Row{ datum = muse.chord_string(value, allocator), annotations = annotations[:] }, true

  case muse.Voicing:
    return voicing_row(value, allocator), true

  case Notes:
    return Row{ datum = notes_string(cast([]muse.Note)value, allocator) }, true
  }

  return {}, false
}

/*
The lines a scale harmonizes into: the degrees asked for in the order they were
asked for, or every degree in scale order when none were.

An empty request becomes the sequence 1 to the length of the scale rather than a
second code path, so a progression and a full harmonization are the same loop
and a degree that repeats needs no thought.

Returns the position in the sequence of the first degree the scale has no answer
for, so the caller can echo the numeral a reader typed rather than the number
muse read it as.
*/
@(private)
harmony_rows :: proc(
  scale     : muse.Scale,
  degrees   : []int,
  size      : int,
  allocator := context.allocator,
) -> (rows: []Row, failed: int, ok: bool) {
  sequence := degrees
  if len(sequence) == 0 {
    every := make([]int, len(scale.intervals), context.temp_allocator)
    for index in 0 ..< len(every) {
      every[index] = index + 1
    }
    sequence = every
  }

  lines := make([]Row, len(sequence), allocator)
  for degree, index in sequence {
    harmony, harmony_ok := muse.scale_chord_at(scale, degree, size, allocator)
    if !harmony_ok {
      return nil, index, false
    }
    lines[index] = harmony_row(harmony, degree, allocator)
  }

  return lines, 0, true
}

/*
Take a sequence of degrees off the front of a command's operands: the longest
prefix that reads as one, which is the same shape of rule key_take follows.

Nothing a scale is written with reads as a degree -- muse's numerals stop at
XII, so C and D and M are note letters here and not hundreds -- so the split
between `muse chords I V C major` and `muse chords C major` needs no marker
between the two halves.
*/
@(private)
degrees_take :: proc(options: Options, allocator := context.allocator) -> ([]int, Options) {
  degrees := make([dynamic]int, 0, len(options.operands), allocator)

  for operand in options.operands {
    degree, degree_ok := degree_read(operand)
    if !degree_ok {
      break
    }
    append(&degrees, degree)
  }

  rest := options
  rest.operands = options.operands[len(degrees):]
  return degrees[:], rest
}

/*
One degree of a harmonized scale as a line: the chord where the notes name one,
and the notes themselves where they name none, with the roman numeral between
field one and the derivation.
*/
@(private)
harmony_row :: proc(harmony: muse.Harmony, degree: int, allocator := context.allocator) -> Row {
  annotations := make([dynamic]string, 0, 2, allocator)
  append(&annotations, muse.scale_degree_label(degree, harmony.notes, allocator))

  if chord, named := harmony.chord.?; named {
    append(&annotations, notes_string(harmony.notes, allocator))
    return Row{ datum = muse.chord_string(chord, allocator), annotations = annotations[:] }
  }

  if intervals, intervals_ok := intervals_string(harmony.notes, allocator); intervals_ok {
    append(&annotations, intervals)
  }
  return Row{ datum = notes_string(harmony.notes, allocator), annotations = annotations[:] }
}

/*
A voicing as a line: its pitches in field one, and the chord its pitch classes
name where they name one. That column is the round trip in plain sight -- a
realization identifies back as the chord it was realized from.
*/
@(private)
voicing_row :: proc(voicing: muse.Voicing, allocator := context.allocator) -> Row {
  annotations := make([dynamic]string, 0, 1, allocator)

  notes := muse.voicing_notes(voicing, context.temp_allocator)
  if chord, named := muse.chord_identify(notes, context.temp_allocator); named {
    append(&annotations, muse.chord_string(chord, allocator))
  }

  return Row{ datum = voicing_string(voicing, allocator), annotations = annotations[:] }
}

/*
The name a note set forms: the scale it spells where it spells one, with the
other rotations named after it, and otherwise the chord it forms.

A scale is tried first because the sets that answer to both are the large ones,
and a musician handed seven notes is asking about a key. C D E F G A B is C
major, though the same notes are also a Cmaj13, and the chord reading is a
question `muse chord` answers on request rather than one to guess at here.

Returns false when neither table has a name for it, which is parking lot item F
in DESIGN.md and not a parse failure.
*/
@(private)
name_row :: proc(notes: []muse.Note, allocator := context.allocator) -> (Row, bool) {
  readings := muse.scale_readings(notes, context.temp_allocator)
  if len(readings) > 0 {
    annotations := make([dynamic]string, 0, 2, allocator)
    append(&annotations, notes_string(notes, allocator))

    if len(readings) > 1 {
      others := make([]string, len(readings) - 1, context.temp_allocator)
      for reading, index in readings[1:] {
        others[index] = muse.scale_string(reading, context.temp_allocator)
      }
      append(&annotations, fmt.aprintf(
        "also %s",
        strings.join(others, ", ", context.temp_allocator),
        allocator = allocator,
      ))
    }

    return Row{ datum = muse.scale_string(readings[0], allocator), annotations = annotations[:] }, true
  }

  chord, named := muse.chord_identify(notes, context.temp_allocator)
  if !named {
    return {}, false
  }

  annotations := make([]string, 1, allocator)
  annotations[0] = notes_string(notes, allocator)
  return Row{ datum = muse.chord_string(chord, allocator), annotations = annotations }, true
}

/*
Apply a voicing style. close is the realization as it arrives, since realizing
is what close position means; shell needs the chord, because which degrees carry
a chord's quality is not a question a bare voicing can answer.

Returns false for a style the input has no answer for: a shell of a note set
naming no chord, or a drop of a voicing with too few voices to drop from.
*/
@(private)
voicing_style :: proc(
  voicing   : muse.Voicing,
  chord     : Maybe(muse.Chord),
  style     : string,
  octave    : int,
  allocator := context.allocator,
) -> (muse.Voicing, bool) {
  switch style {
  case "close":
    return voicing, true
  case "open":
    return muse.voicing_open(voicing, allocator), true
  case "drop2":
    return muse.voicing_drop(voicing, 2, allocator)
  case "drop3":
    return muse.voicing_drop(voicing, 3, allocator)
  case "shell":
    named, is_named := chord.?
    if !is_named {
      return {}, false
    }
    return muse.voicing_shell(named, octave, allocator)
  }

  return {}, false
}

/*
The degree a note set occupies in a key, as the roman numeral of the interval
from the tonic to its root, cased and suffixed by what is stacked on it.

A root outside the key takes the accidental that carries the key's own degree to
it, which is how bIII and #IV are written and why nothing here needs a table of
chromatic degrees.
*/
@(private)
key_label :: proc(key: muse.Scale, notes: []muse.Note, allocator := context.allocator) -> string {
  if len(notes) == 0 {
    return ""
  }

  interval := muse.interval_between(key.root, notes[0])
  label    := muse.scale_degree_label(interval.steps + 1, notes, allocator)

  diatonic, is_diatonic := interval_at_steps(key.intervals, interval.steps)
  if !is_diatonic {
    return label
  }

  deviation := interval.semitones - diatonic.semitones
  if deviation == 0 {
    return label
  }

  accidental := strings.repeat(deviation < 0 ? "b" : "#", abs(deviation), context.temp_allocator)
  return fmt.aprintf("%s%s", accidental, label, allocator = allocator)
}

/*
The notes a degree label reads. A slash chord realizes from its bass, which is
the right order to sound it in and the wrong one to read a numeral off: C/E in C
major is the tonic over its own third and not a third degree. Setting the bass
aside leaves the stack the label is about.
*/
@(private)
label_notes :: proc(datum: Datum, literal: bool, allocator := context.allocator) -> ([]muse.Note, bool) {
  if chord, is_chord := datum.(muse.Chord); is_chord {
    stack := chord
    stack.bass = nil
    return muse.chord_notes(stack, literal, allocator)
  }
  return datum_notes(datum, literal, allocator)
}

/*
Take a key off the front of a command's operands. A key is one token or two --
`G`, `G major`, `G harmonic minor` -- so the longest prefix that reads as a scale
wins, and a bare root falls through to the reading `scale` gives it.
*/
@(private)
key_take :: proc(options: Options, allocator := context.allocator) -> (string, Options, bool) {
  if len(options.operands) == 0 {
    return "", options, false
  }

  for count := min(len(options.operands), 3); count >= 2; count -= 1 {
    candidate := strings.join(options.operands[:count], " ", allocator)
    if _, scale_ok := muse.scale_parse(candidate, context.temp_allocator); !scale_ok {
      continue
    }

    rest := options
    rest.operands = options.operands[count:]
    return candidate, rest, true
  }

  return operand_take(options)
}

/*
A degree, from the number a musician says or the numeral they write it as.
*/
@(private)
degree_read :: proc(token: string) -> (int, bool) {
  if degree, degree_ok := strconv.parse_int(token, 10); degree_ok {
    return degree, degree >= 1
  }

  upper := strings.to_upper(token, context.temp_allocator)
  for numeral, index in muse.ROMAN_NUMERALS {
    if numeral == upper {
      return index + 1, true
    }
  }

  return 0, false
}

/*
The interval a transpose argument names. A quality letter says which interval is
meant and settles the spelling; a bare count of semitones does not, so it is
spelled as the interval a musician would write for that distance.
*/
@(private)
transpose_interval :: proc(token: string) -> (muse.Interval, bool) {
  digits := token
  if strings.has_prefix(digits, "+") || strings.has_prefix(digits, "-") {
    digits = digits[1:]
  }

  if len(digits) > 0 && is_all_digits(digits) {
    semitones, semitones_ok := strconv.parse_int(token, 10)
    if !semitones_ok {
      return {}, false
    }
    return muse.interval_from_semitones(semitones), true
  }

  return muse.interval_parse(token)
}

/*
The intervals a stack of notes spans, measured from its lowest note. This is the
derivation column for a stack no template names, so it is only offered when
every interval in it has a name.
*/
@(private)
intervals_string :: proc(notes: []muse.Note, allocator := context.allocator) -> (string, bool) {
  if len(notes) == 0 {
    return "", false
  }

  abbreviations := make([]string, len(notes), context.temp_allocator)
  for note, index in notes {
    interval := muse.interval_between(notes[0], note)

    abbreviation, abbreviation_ok := muse.interval_abbreviation(interval, context.temp_allocator)
    if !abbreviation_ok {
      return "", false
    }
    abbreviations[index] = abbreviation
  }

  return strings.join(abbreviations, " ", allocator), true
}

@(private)
interval_at_steps :: proc(intervals: []muse.Interval, steps: int) -> (muse.Interval, bool) {
  for interval in intervals {
    if interval.steps == steps {
      return interval, true
    }
  }
  return {}, false
}

@(private)
is_all_digits :: proc(text: string) -> bool {
  for index in 0 ..< len(text) {
    if text[index] < '0' || text[index] > '9' {
      return false
    }
  }
  return true
}

@(private)
omissions_string :: proc(omissions: []muse.Interval, allocator := context.allocator) -> string {
  builder := strings.builder_make(allocator)
  strings.write_string(&builder, "omits")

  for omission in omissions {
    strings.write_byte(&builder, ' ')
    strings.write_int(&builder, muse.interval_number(omission))
  }

  return strings.to_string(builder)
}

@(private)
semitones_string :: proc(semitones: int, allocator := context.allocator) -> string {
  if semitones == 1 || semitones == -1 {
    return fmt.aprintf("%d semitone", semitones, allocator = allocator)
  }
  return fmt.aprintf("%d semitones", semitones, allocator = allocator)
}
