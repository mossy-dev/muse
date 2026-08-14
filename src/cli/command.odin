package main

import "core:fmt"
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

    notes, notes_ok := muse.chord_notes(chord, options.literal)
    if !notes_ok {
      return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", text)
    }

    annotations := make([dynamic]string, 0, 2)
    append(&annotations, notes_string(notes))

    if omissions := muse.chord_omissions(chord); len(omissions) > 0 && !options.literal {
      append(&annotations, omissions_string(omissions))
    }

    append(&rows, Row{ datum = muse.chord_string(chord), annotations = annotations[:] })

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
Read a scale name, defaulting a bare root to major.
*/
@(private)
scale_read :: proc(text: string, allocator := context.allocator) -> (muse.Scale, bool) {
  if scale, scale_ok := muse.scale_parse(text, allocator); scale_ok {
    return scale, true
  }
  if _, root_ok := muse.note_parse(text); root_ok {
    return muse.scale_parse(fmt.tprintf("%s major", text), allocator)
  }
  return {}, false
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
