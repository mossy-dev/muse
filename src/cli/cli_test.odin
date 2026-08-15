package main

import "core:slice"
import "core:strings"
import "core:testing"

import "../muse"

@(test)
test_options_take_the_first_positional_as_the_command :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "chord", "C", "E", "G" }, context.temp_allocator)

  testing.expect(t, ok)
  testing.expect_value(t, options.command, "chord")
  testing.expect_value(t, len(options.operands), 3)
  testing.expect_value(t, options.literal, false)
}

@(test)
test_options_read_flags_anywhere :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "chord", "--literal", "C13" }, context.temp_allocator)

  testing.expect(t, ok)
  testing.expect_value(t, options.command, "chord")
  testing.expect_value(t, len(options.operands), 1)
  testing.expect(t, options.literal)
}

/*
Only a double dash introduces a flag, since an interval name opens with a single
one and has to reach its command as an operand.
*/
@(test)
test_options_keep_a_single_dash_as_an_operand :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "transpose", "-m3" }, context.temp_allocator)

  testing.expect(t, ok)
  testing.expect_value(t, len(options.operands), 1)
  testing.expect_value(t, options.operands[0], "-m3")
}

@(test)
test_options_reject_an_unknown_flag_by_name :: proc(t: ^testing.T) {
  _, token, ok := options_parse([]string{ "chord", "--bogus", "C" }, context.temp_allocator)

  testing.expect(t, !ok)
  testing.expect_value(t, token, "--bogus")
}

/*
The join rule: a command reads one datum from its operands, so how the shell
split the input makes no difference to what the command receives.
*/
@(test)
test_input_joins_operands_into_one_datum :: proc(t: ^testing.T) {
  split,  _, _ := options_parse([]string{ "notes", "C", "E", "G" }, context.temp_allocator)
  quoted, _, _ := options_parse([]string{ "notes", "C E G" },       context.temp_allocator)

  from_split,  split_ok  := input_read(split,  context.temp_allocator)
  from_quoted, quoted_ok := input_read(quoted, context.temp_allocator)

  testing.expect(t, split_ok && quoted_ok)
  testing.expect_value(t, len(from_split), 1)
  testing.expect_value(t, from_split[0], "C E G")
  testing.expect_value(t, from_quoted[0], "C E G")
}

@(test)
test_a_line_ends_at_its_first_tab :: proc(t: ^testing.T) {
  testing.expect_value(t, line_datum("Cmaj7\tC E G B"),   "Cmaj7")
  testing.expect_value(t, line_datum("G major\tG A B\tI"), "G major")
  testing.expect_value(t, line_datum("C E G"),             "C E G")
}

@(test)
test_datum_reads_every_form_notation_takes :: proc(t: ^testing.T) {
  scale, scale_ok := datum_parse("G major", context.temp_allocator)
  testing.expect(t, scale_ok)
  _, is_scale := scale.(muse.Scale)
  testing.expect(t, is_scale)

  chord, chord_ok := datum_parse("Cmaj7", context.temp_allocator)
  testing.expect(t, chord_ok)
  _, is_chord := chord.(muse.Chord)
  testing.expect(t, is_chord)

  notes, notes_ok := datum_parse("C E G", context.temp_allocator)
  testing.expect(t, notes_ok)
  _, is_notes := notes.(Notes)
  testing.expect(t, is_notes)

  voicing, voicing_ok := datum_parse("C4 E4 G4", context.temp_allocator)
  testing.expect(t, voicing_ok)
  _, is_voicing := voicing.(muse.Voicing)
  testing.expect(t, is_voicing)

  _, nonsense_ok := datum_parse("H major", context.temp_allocator)
  testing.expect(t, !nonsense_ok)
}

/*
Everything reduces to the same note list, which is what `muse notes` is for.
*/
@(test)
test_every_datum_reduces_to_notes :: proc(t: ^testing.T) {
  for text in ([]string{ "C major", "C6", "C D E F G A B", "C4 E4 G4" }) {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    testing.expectf(t, datum_ok, "%s did not parse", text)

    notes, notes_ok := datum_notes(datum, false, context.temp_allocator)
    testing.expectf(t, notes_ok && len(notes) > 0, "%s reduced to nothing", text)
  }

  chord, _ := datum_parse("C6", context.temp_allocator)
  notes, _ := datum_notes(chord, false, context.temp_allocator)
  testing.expect_value(t, notes_string(notes, context.temp_allocator), "C E G A")
}

/*
The round trip the pipeline rests on, at its smallest: a printed note list reads
back as the notes it was printed from.
*/
@(test)
test_a_printed_note_list_parses_back :: proc(t: ^testing.T) {
  scale, _ := datum_parse("Eb major", context.temp_allocator)
  notes, _ := datum_notes(scale, false, context.temp_allocator)

  reread, reread_ok := datum_parse(notes_string(notes, context.temp_allocator), context.temp_allocator)
  testing.expect(t, reread_ok)

  reduced, reduced_ok := datum_notes(reread, false, context.temp_allocator)
  testing.expect(t, reduced_ok)
  testing.expect_value(t, notes_string(reduced, context.temp_allocator), "Eb F G Ab Bb C D")
}

@(test)
test_rendering_a_pipe_separates_fields_with_one_tab :: proc(t: ^testing.T) {
  rows := []Row {
    { "Cmaj7", []string{ "C E G B" } },
    { "C13",   []string{ "C E G Bb D A", "omits 11" } },
  }

  testing.expect_value(
    t,
    render_text(rows[:], false, false, context.temp_allocator),
    "Cmaj7\tC E G B\nC13\tC E G Bb D A\tomits 11\n",
  )
}

/*
The phase gate: layout is presentation, so a terminal and a pipe differ in
whitespace and agree on field one exactly.
*/
@(test)
test_field_one_survives_both_layouts :: proc(t: ^testing.T) {
  rows := []Row {
    { "Cmaj7", []string{ "C E G B" } },
    { "C13",   []string{ "C E G Bb D A", "omits 11" } },
    { "Am",    []string{ "A C E" } },
  }

  piped   := render_text(rows[:], false, false, context.temp_allocator)
  aligned := render_text(rows[:], true,  false, context.temp_allocator)

  piped_lines   := strings.split_lines(piped,   context.temp_allocator)
  aligned_lines := strings.split_lines(aligned, context.temp_allocator)
  testing.expect_value(t, len(piped_lines), len(aligned_lines))

  for row, index in rows {
    testing.expect_value(t, line_datum(piped_lines[index]), row.datum)
    testing.expect(t, strings.has_prefix(aligned_lines[index], row.datum))
  }

  testing.expect(t, strings.contains(aligned_lines[0], "Cmaj7  C E G B"))
  testing.expect(t, strings.contains(aligned_lines[2], "Am     A C E"))
}

@(test)
test_color_wraps_annotations_and_never_the_datum :: proc(t: ^testing.T) {
  rows := []Row { { "Cmaj7", []string{ "C E G B" } } }

  text := render_text(rows[:], false, true, context.temp_allocator)
  testing.expect_value(t, text, "Cmaj7\t" + DIM + "C E G B" + RESET + "\n")
}

/*
The flag overrides detection in both directions, and auto is what asks.
*/
@(test)
test_color_follows_the_flag_before_the_terminal :: proc(t: ^testing.T) {
  testing.expect(t, color_chosen(.Always, false))
  testing.expect(t, !color_chosen(.Never, true))
  testing.expect(t, color_chosen(.Auto, true))
  testing.expect(t, !color_chosen(.Auto, false))

  options, _, ok := options_parse([]string{ "scale", "--color", "never", "G" }, context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, options.color, Color.Never)
  testing.expect_value(t, len(options.operands), 1)

  _, token, bogus_ok := options_parse([]string{ "scale", "--color", "maybe" }, context.temp_allocator)
  testing.expect(t, !bogus_ok)
  testing.expect_value(t, token, "maybe")
}

/*
--plain drops the annotation columns and cannot reach field one, which is the
same guarantee the layout has and for the same reason.
*/
@(test)
test_plain_drops_the_annotations_and_keeps_the_datum :: proc(t: ^testing.T) {
  rows := []Row {
    { "Cmaj7", []string{ "C E G B" } },
    { "C13",   []string{ "C E G Bb D A", "omits 11" } },
  }

  plain := rows_plain(rows, context.temp_allocator)
  testing.expect_value(t, plain[0].datum, "Cmaj7")
  testing.expect_value(t, len(plain[0].annotations), 0)

  testing.expect_value(
    t,
    render_text(plain, false, false, context.temp_allocator),
    "Cmaj7\nC13\n",
  )
}

@(test)
test_a_bare_root_is_a_major_scale :: proc(t: ^testing.T) {
  scale, ok := scale_read("G", context.temp_allocator)

  testing.expect(t, ok)
  testing.expect_value(t, muse.scale_string(scale, context.temp_allocator), "G major")
}

@(test)
test_intervals_measure_pitches_with_their_register :: proc(t: ^testing.T) {
  within, _, within_ok := interval_read("C", "E")
  testing.expect(t, within_ok)
  testing.expect_value(t, within, muse.MAJOR_THIRD)

  compound, _, compound_ok := interval_read("C4", "E5")
  testing.expect(t, compound_ok)
  testing.expect_value(t, muse.interval_number(compound), 10)

  _, token, bad_ok := interval_read("C", "H")
  testing.expect(t, !bad_ok)
  testing.expect_value(t, token, "H")
}

/*
The size flag speaks the musician's numbers and everything downstream counts
notes, so 7 is a seventh chord and four of them.
*/
@(test)
test_size_translates_the_musicians_number :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "chords", "--size", "7" }, context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, options.size, 4)

  defaulted, _, defaulted_ok := options_parse([]string{ "chords" }, context.temp_allocator)
  testing.expect(t, defaulted_ok)
  testing.expect_value(t, defaulted.size, DEFAULT_SIZE)
  testing.expect_value(t, defaulted.octave, DEFAULT_OCTAVE)

  _, token, bad_ok := options_parse([]string{ "chords", "--size", "8" }, context.temp_allocator)
  testing.expect(t, !bad_ok)
  testing.expect_value(t, token, "8")
}

@(test)
test_octave_moves_a_realization :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "voice", "close", "--octave", "2" }, context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, options.octave, 2)
  testing.expect_value(t, len(options.operands), 1)
}

/*
A command's own argument comes off the front of its operands, and what is left
is the datum -- which, being nothing at all here, is stdin under the one input
rule.
*/
@(test)
test_a_command_takes_its_argument_before_its_datum :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "voice", "drop2", "Cmaj7" }, context.temp_allocator)

  style, rest, style_ok := operand_take(options)
  testing.expect(t, style_ok)
  testing.expect_value(t, style, "drop2")

  data, data_ok := input_read(rest, context.temp_allocator)
  testing.expect(t, data_ok)
  testing.expect_value(t, data[0], "Cmaj7")

  piped, _, _ := options_parse([]string{ "voice", "drop2" }, context.temp_allocator)
  _, from_pipe, take_ok := operand_take(piped)
  testing.expect(t, take_ok)
  testing.expect_value(t, len(from_pipe.operands), 0)

  _, _, empty_ok := operand_take(from_pipe)
  testing.expect(t, !empty_ok)
}

/*
A key is one token or two, so the longest prefix that reads as a scale wins and
the datum starts after it.
*/
@(test)
test_a_key_is_taken_greedily :: proc(t: ^testing.T) {
  two_words, _, _ := options_parse([]string{ "in", "G", "major", "Am" }, context.temp_allocator)
  key, rest, key_ok := key_take(two_words, context.temp_allocator)
  testing.expect(t, key_ok)
  testing.expect_value(t, key, "G major")
  testing.expect_value(t, len(rest.operands), 1)
  testing.expect_value(t, rest.operands[0], "Am")

  three_words, _, _ := options_parse([]string{ "in", "G", "harmonic", "minor" }, context.temp_allocator)
  long, long_rest, long_ok := key_take(three_words, context.temp_allocator)
  testing.expect(t, long_ok)
  testing.expect_value(t, long, "G harmonic minor")
  testing.expect_value(t, len(long_rest.operands), 0)

  bare, _, _ := options_parse([]string{ "in", "G", "Am" }, context.temp_allocator)
  root, root_rest, root_ok := key_take(bare, context.temp_allocator)
  testing.expect(t, root_ok)
  testing.expect_value(t, root, "G")
  testing.expect_value(t, root_rest.operands[0], "Am")
}

@(test)
test_a_degree_reads_as_a_number_or_a_numeral :: proc(t: ^testing.T) {
  expect_degree :: proc(t: ^testing.T, token: string, expected: int) {
    degree, ok := degree_read(token)
    testing.expectf(t, ok, "%s did not read as a degree", token)
    testing.expect_value(t, degree, expected)
  }

  expect_degree(t, "4",   4)
  expect_degree(t, "IV",  4)
  expect_degree(t, "iv",  4)
  expect_degree(t, "vii", 7)

  _, zero_ok := degree_read("0")
  testing.expect(t, !zero_ok)

  _, bogus_ok := degree_read("H")
  testing.expect(t, !bogus_ok)
}

/*
A quality letter says which interval is meant; a bare count of semitones does
not, so the two forms of the same distance are read apart. This is the whole of
`transpose 3` against `transpose M3`.
*/
@(test)
test_a_bare_number_transposes_by_semitones :: proc(t: ^testing.T) {
  expect_interval :: proc(t: ^testing.T, token: string, expected: muse.Interval) {
    interval, ok := transpose_interval(token)
    testing.expectf(t, ok, "%s did not read as an interval", token)
    testing.expect_value(t, interval, expected)
  }

  expect_interval(t, "3",   muse.MINOR_THIRD)
  expect_interval(t, "+3",  muse.MINOR_THIRD)
  expect_interval(t, "-3",  muse.interval_negate(muse.MINOR_THIRD))
  expect_interval(t, "M3",  muse.MAJOR_THIRD)
  expect_interval(t, "+m3", muse.MINOR_THIRD)
  expect_interval(t, "-P5", muse.interval_negate(muse.PERFECT_FIFTH))

  _, bogus_ok := transpose_interval("zz")
  testing.expect(t, !bogus_ok)
}

/*
Every kind of datum transposes in its own terms and prints as the same kind, so
a transposition is a step in a pipeline rather than the end of one.
*/
@(test)
test_transposing_keeps_the_kind_and_the_spelling :: proc(t: ^testing.T) {
  expect_transposed :: proc(t: ^testing.T, text: string, interval: muse.Interval, expected: string) {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    testing.expectf(t, datum_ok, "%s did not parse", text)

    moved, moved_ok := datum_transpose(datum, interval, context.temp_allocator)
    testing.expectf(t, moved_ok, "%s did not transpose", text)
    testing.expect_value(t, datum_string(moved, context.temp_allocator), expected)
  }

  expect_transposed(t, "G major", muse.PERFECT_FIFTH, "D major")
  expect_transposed(t, "Cmaj7",   muse.MINOR_THIRD,   "Ebmaj7")
  expect_transposed(t, "C E G",   muse.MAJOR_SECOND,  "D F# A")
  expect_transposed(t, "C4 E4 G4", muse.MAJOR_NINTH,  "D5 F#5 A5")
}

@(test)
test_transposing_back_returns_the_datum :: proc(t: ^testing.T) {
  for text in ([]string{ "Eb major", "C13", "C E G Bb", "G3 C4 E4 B4" }) {
    datum, _ := datum_parse(text, context.temp_allocator)

    moved, moved_ok := datum_transpose(datum, muse.MINOR_THIRD, context.temp_allocator)
    testing.expect(t, moved_ok)

    back, back_ok := datum_transpose(moved, muse.interval_negate(muse.MINOR_THIRD), context.temp_allocator)
    testing.expect(t, back_ok)
    testing.expect_value(t, datum_string(back, context.temp_allocator), text)
  }
}

/*
The harmonized line DESIGN.md prints: the chord in field one, its numeral, and
the notes it stacked.
*/
@(test)
test_a_harmonized_degree_carries_its_numeral :: proc(t: ^testing.T) {
  scale, _ := muse.scale_parse("G major", context.temp_allocator)

  harmonies, ok := muse.scale_harmonize(scale, 3, context.temp_allocator)
  testing.expect(t, ok)

  first := harmony_row(harmonies[0], 1, context.temp_allocator)
  testing.expect_value(t, first.datum, "G")
  testing.expect_value(t, first.annotations[0], "I")
  testing.expect_value(t, first.annotations[1], "G B D")

  seventh := harmony_row(harmonies[6], 7, context.temp_allocator)
  testing.expect_value(t, seventh.datum, "F#dim")
  testing.expect_value(t, seventh.annotations[0], "vii°")
}

/*
The five styles, and the two that need a chord to answer at all.
*/
@(test)
test_voicing_styles_realize_what_they_are_given :: proc(t: ^testing.T) {
  chord, _ := datum_parse("Cmaj7", context.temp_allocator)

  voicing, named, realized_ok := datum_realize(chord, DEFAULT_OCTAVE, false, context.temp_allocator)
  testing.expect(t, realized_ok)

  close, close_ok := voicing_style(voicing, named, "close", DEFAULT_OCTAVE, context.temp_allocator)
  testing.expect(t, close_ok)
  testing.expect_value(t, voicing_string(close, context.temp_allocator), "C4 E4 G4 B4")

  drop2, drop2_ok := voicing_style(voicing, named, "drop2", DEFAULT_OCTAVE, context.temp_allocator)
  testing.expect(t, drop2_ok)
  testing.expect_value(t, voicing_string(drop2, context.temp_allocator), "G3 C4 E4 B4")

  shell, shell_ok := voicing_style(voicing, named, "shell", DEFAULT_OCTAVE, context.temp_allocator)
  testing.expect(t, shell_ok)
  testing.expect_value(t, voicing_string(shell, context.temp_allocator), "C4 E4 B4")

  scale, _ := datum_parse("G major", context.temp_allocator)
  run, unnamed, run_ok := datum_realize(scale, DEFAULT_OCTAVE, false, context.temp_allocator)
  testing.expect(t, run_ok)

  stacked, stacked_ok := voicing_style(run, unnamed, "close", DEFAULT_OCTAVE, context.temp_allocator)
  testing.expect(t, stacked_ok)
  testing.expect_value(t, voicing_string(stacked, context.temp_allocator), "G4 A4 B4 C5 D5 E5 F#5")

  notes, _ := datum_parse("C D E", context.temp_allocator)
  bare, no_chord, bare_ok := datum_realize(notes, DEFAULT_OCTAVE, false, context.temp_allocator)
  testing.expect(t, bare_ok)

  _, shell_of_nothing := voicing_style(bare, no_chord, "shell", DEFAULT_OCTAVE, context.temp_allocator)
  testing.expect(t, !shell_of_nothing)
}

/*
A realization identifies back as the chord it was realized from, which is the
round trip printed in the annotation column.
*/
@(test)
test_a_voicing_line_names_the_chord_it_realizes :: proc(t: ^testing.T) {
  chord, _ := datum_parse("Cmaj7", context.temp_allocator)
  voicing, _, _ := datum_realize(chord, DEFAULT_OCTAVE, false, context.temp_allocator)

  row := voicing_row(voicing, context.temp_allocator)
  testing.expect_value(t, row.datum, "C4 E4 G4 B4")
  testing.expect_value(t, row.annotations[0], "Cmaj7")
}

/*
A set that spells a scale is named as one, with the other rotations beside it; a
smaller set is named as the chord it forms; a set neither table has a name for
is a well-formed request with no answer.
*/
@(test)
test_naming_prefers_a_scale_and_falls_back_to_a_chord :: proc(t: ^testing.T) {
  notes_of :: proc(text: string) -> []muse.Note {
    datum, _ := datum_parse(text, context.temp_allocator)
    notes, _ := datum_notes(datum, false, context.temp_allocator)
    return notes
  }

  chord, chord_ok := name_row(notes_of("C E G B"), context.temp_allocator)
  testing.expect(t, chord_ok)
  testing.expect_value(t, chord.datum, "Cmaj7")

  scale, scale_ok := name_row(notes_of("C D E F G A B"), context.temp_allocator)
  testing.expect(t, scale_ok)
  testing.expect_value(t, scale.datum, "C major")
  testing.expect(t, strings.has_prefix(scale.annotations[1], "also D dorian"))

  _, nameless_ok := name_row(notes_of("C Db"), context.temp_allocator)
  testing.expect(t, !nameless_ok)
}

/*
The degree a chord occupies in a key, with the accidental that carries the key's
own degree to a root outside it.
*/
@(test)
test_a_key_label_reads_inside_and_outside_the_key :: proc(t: ^testing.T) {
  expect_label :: proc(t: ^testing.T, key_text, text, expected: string) {
    key, key_ok := scale_read(key_text, context.temp_allocator)
    testing.expectf(t, key_ok, "%s is not a key", key_text)

    datum, datum_ok := datum_parse(text, context.temp_allocator)
    testing.expectf(t, datum_ok, "%s did not parse", text)

    notes, notes_ok := label_notes(datum, false, context.temp_allocator)
    testing.expect(t, notes_ok)
    testing.expect_value(t, key_label(key, notes, context.temp_allocator), expected)
  }

  expect_label(t, "G major", "G",     "I")
  expect_label(t, "G major", "Am",    "ii")
  expect_label(t, "G major", "F#dim", "vii°")
  expect_label(t, "C major", "Eb",    "bIII")
  expect_label(t, "C major", "F#dim", "#iv°")
  expect_label(t, "C major", "C/E",   "I")
}

/*
The phase gate: every transform's field one is another transform's input. The
helpers that build the lines are asked for one of each kind, and every one of
them reads back as the datum it prints.
*/
@(test)
test_every_transform_output_reparses :: proc(t: ^testing.T) {
  expect_datum :: proc(t: ^testing.T, row: Row) {
    _, ok := datum_parse(row.datum, context.temp_allocator)
    testing.expectf(t, ok, "%s did not read back as notation", row.datum)
  }

  scale, _ := datum_parse("G major", context.temp_allocator)
  scale_line, scale_ok := datum_row(scale, false, context.temp_allocator)
  testing.expect(t, scale_ok)
  expect_datum(t, scale_line)

  harmonies, _ := muse.scale_harmonize(scale.(muse.Scale), 4, context.temp_allocator)
  for harmony, index in harmonies {
    expect_datum(t, harmony_row(harmony, index + 1, context.temp_allocator))
  }

  moved, _ := datum_transpose(scale, muse.MINOR_THIRD, context.temp_allocator)
  moved_line, moved_ok := datum_row(moved, false, context.temp_allocator)
  testing.expect(t, moved_ok)
  expect_datum(t, moved_line)

  chord, _ := datum_parse("Cmaj7", context.temp_allocator)
  voicing, named, _ := datum_realize(chord, DEFAULT_OCTAVE, false, context.temp_allocator)
  for style in ([]string{ "close", "open", "drop2", "drop3", "shell" }) {
    voiced, voiced_ok := voicing_style(voicing, named, style, DEFAULT_OCTAVE, context.temp_allocator)
    testing.expectf(t, voiced_ok, "no %s voicing of Cmaj7", style)
    expect_datum(t, voicing_row(voiced, context.temp_allocator))
  }

  expect_datum(t, voicing_row(muse.voicing_invert(voicing, 1, context.temp_allocator), context.temp_allocator))

  notes, _ := datum_notes(chord, false, context.temp_allocator)
  named_line, named_line_ok := name_row(notes, context.temp_allocator)
  testing.expect(t, named_line_ok)
  expect_datum(t, named_line)
}

@(test)
test_options_read_the_midi_flags :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string {
    "midi", "--tempo", "90", "--meter", "3/4", "--duration", "1/8", "-k", "G major", "-o", "loop.mid",
  }, context.temp_allocator)

  testing.expect(t, ok)
  testing.expect_value(t, options.tempo, 90)
  testing.expect_value(t, options.meter, muse.Meter{ 3, 4 })
  testing.expect_value(t, options.duration.?, muse.Duration{ 1, 8 })
  testing.expect_value(t, options.key, "G major")
  testing.expect_value(t, options.output, "loop.mid")
  testing.expect_value(t, len(options.operands), 0)
}

/*
The values the flags refuse, each reported by the token that carried it: a tempo
of nothing, a meter whose lower number is not a note value, and a duration of
zero length.
*/
@(test)
test_options_reject_midi_values_by_token :: proc(t: ^testing.T) {
  cases := [][]string {
    { "midi", "--tempo", "0" },
    { "midi", "--tempo", "fast" },
    { "midi", "--meter", "4/3" },
    { "midi", "--duration", "0/4" },
    { "midi", "--duration", "1/x" },
  }

  for arguments in cases {
    _, token, ok := options_parse(arguments, context.temp_allocator)
    testing.expectf(t, !ok, "%s was accepted", arguments[2])
    testing.expect_value(t, token, arguments[2])
  }

  _, missing, missing_ok := options_parse([]string{ "midi", "-o" }, context.temp_allocator)
  testing.expect(t, !missing_ok)
  testing.expect_value(t, missing, "-o")
}

/*
A duration no flag gave is one bar, which is only as long as the meter says.
*/
@(test)
test_a_bar_is_the_duration_the_meter_gives :: proc(t: ^testing.T) {
  common,  _, _ := options_parse([]string{ "midi" },                          context.temp_allocator)
  waltz,   _, _ := options_parse([]string{ "midi", "--meter", "3/4" },        context.temp_allocator)
  quarter, _, _ := options_parse([]string{ "midi", "--duration", "1/4" },     context.temp_allocator)

  testing.expect_value(t, midi_options(common).duration,  muse.Duration{ 4, 4 })
  testing.expect_value(t, midi_options(waltz).duration,   muse.Duration{ 3, 4 })
  testing.expect_value(t, midi_options(quarter).duration, muse.Duration{ 1, 4 })
}

/*
A scale sounds as a run of single notes and everything else as one stack, which
is the difference a voice step in front of the sink makes.
*/
@(test)
test_a_scale_is_a_run_and_a_chord_is_a_stack :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "midi" }, context.temp_allocator)

  scale, _ := datum_parse("G major", context.temp_allocator)
  run, run_ok := midi_items(scale, options, context.temp_allocator)
  testing.expect(t, run_ok)
  testing.expect_value(t, len(run), 7)
  for item in run {
    testing.expect_value(t, len(item.pitches), 1)
  }

  chord, _ := datum_parse("Cmaj7", context.temp_allocator)
  stack, stack_ok := midi_items(chord, options, context.temp_allocator)
  testing.expect(t, stack_ok)
  testing.expect_value(t, len(stack), 1)
  testing.expect_value(t, len(stack[0].pitches), 4)

  voiced, _ := datum_parse("G4 A4 B4 C5 D5 E5 F#5", context.temp_allocator)
  voiced_items, voiced_ok := midi_items(voiced, options, context.temp_allocator)
  testing.expect(t, voiced_ok)
  testing.expect_value(t, len(voiced_items), 1)
}

/*
The key signature comes from the input where the input is a scale, from -k where
it is given, and from nowhere else: a run of chord symbols with no key named
writes no signature rather than guessing at one.
*/
@(test)
test_a_key_signature_is_written_only_where_a_key_is_known :: proc(t: ^testing.T) {
  key_signature :: proc(t: ^testing.T, arguments: []string, data: []string) -> ([]u8, bool) {
    options, _, options_ok := options_parse(arguments, context.temp_allocator)
    testing.expect(t, options_ok)

    bytes, token, error := midi_bytes(data, options, context.temp_allocator)
    testing.expectf(t, error == .None, "%s: %v", token, error)

    for index := 0; index + 5 <= len(bytes); index += 1 {
      if bytes[index] == 0xFF && bytes[index + 1] == 0x59 && bytes[index + 2] == 0x02 {
        return bytes[index + 3:][:2], true
      }
    }
    return nil, false
  }

  from_scale, scale_found := key_signature(t, []string{ "midi" }, []string{ "G major" })
  testing.expect(t, scale_found)
  testing.expect_value(t, from_scale[0], u8(1))
  testing.expect_value(t, from_scale[1], u8(0))

  from_flag, flag_found := key_signature(t, []string{ "midi", "-k", "F major" }, []string{ "Dm7", "G7" })
  testing.expect(t, flag_found)
  testing.expect_value(t, from_flag[0], u8(0xFF))

  _, chords_found := key_signature(t, []string{ "midi" }, []string{ "Dm7", "G7" })
  testing.expect(t, !chords_found)
}

/*
Every failure a file can have, reported against the line that caused it.
*/
@(test)
test_midi_reports_the_line_that_failed :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "midi" }, context.temp_allocator)

  _, nonsense, nonsense_error := midi_bytes([]string{ "Cmaj7", "Hmm" }, options, context.temp_allocator)
  testing.expect_value(t, nonsense_error, SinkError.NotNotation)
  testing.expect_value(t, nonsense, "Hmm")

  high, _, _ := options_parse([]string{ "midi", "--octave", "10" }, context.temp_allocator)
  _, token, range_error := midi_bytes([]string{ "Cmaj7" }, high, context.temp_allocator)
  testing.expect_value(t, range_error, SinkError.OutOfRange)
  testing.expect_value(t, token, "Cmaj7")

  keyed, _, _ := options_parse([]string{ "midi", "-k", "H major" }, context.temp_allocator)
  _, key_token, key_error := midi_bytes([]string{ "Cmaj7" }, keyed, context.temp_allocator)
  testing.expect_value(t, key_error, SinkError.NotAKey)
  testing.expect_value(t, key_token, "H major")
}

/*
Binary goes to a file or a pipe and never to a screen. TTY detection is a
parameter here for the same reason it is one in the renderer: the rule can be
tested without a terminal to test it on.
*/
@(test)
test_midi_refuses_a_terminal_and_nothing_else :: proc(t: ^testing.T) {
  testing.expect(t, midi_refuses_terminal("", true))
  testing.expect(t, !midi_refuses_terminal("", false))
  testing.expect(t, !midi_refuses_terminal("loop.mid", true))
}

/*
The sink reads field one and derives the rest, exactly as a transform does, so
what `muse chords` prints is what `muse midi` encodes.
*/
@(test)
test_the_sink_reads_the_lines_a_transform_prints :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "midi" }, context.temp_allocator)

  scale, _ := datum_parse("G major", context.temp_allocator)
  harmonies, _ := muse.scale_harmonize(scale.(muse.Scale), 4, context.temp_allocator)

  lines := make([dynamic]string, 0, len(harmonies), context.temp_allocator)
  for harmony, index in harmonies {
    append(&lines, harmony_row(harmony, index + 1, context.temp_allocator).datum)
  }

  bytes, token, error := midi_bytes(lines[:], options, context.temp_allocator)
  testing.expectf(t, error == .None, "%s: %v", token, error)
  testing.expect_value(t, string(bytes[:4]), "MThd")
}

/*
The longest prefix of operands that reads as a degree is the sequence, and what
is left is the datum. Nothing a scale is written with reads as a degree, so the
two halves need no marker between them.
*/
@(test)
test_degrees_come_off_the_front_of_the_operands :: proc(t: ^testing.T) {
  expect_split :: proc(t: ^testing.T, arguments: []string, degrees: []int, datum: string) {
    options, _, _ := options_parse(arguments, context.temp_allocator)

    taken, rest := degrees_take(options, context.temp_allocator)
    testing.expectf(t, slice.equal(taken, degrees), "%v took %v", arguments, taken)
    testing.expect_value(t, strings.join(rest.operands, " ", context.temp_allocator), datum)
  }

  expect_split(t, []string{ "chords", "I", "V", "vi", "IV" },   []int{ 1, 5, 6, 4 }, "")
  expect_split(t, []string{ "chords", "I", "V", "C", "major" }, []int{ 1, 5 },       "C major")
  expect_split(t, []string{ "chords", "1", "4", "5" },          []int{ 1, 4, 5 },    "")
  expect_split(t, []string{ "chords", "C", "major" },           []int{},             "C major")
  expect_split(t, []string{ "chords" },                         []int{},             "")
}

/*
A named sequence harmonizes in the order it was named, repeats included; naming
none harmonizes every degree in scale order.
*/
@(test)
test_a_progression_follows_the_order_it_was_asked_for :: proc(t: ^testing.T) {
  scale, scale_ok := scale_read("C major", context.temp_allocator)
  testing.expect(t, scale_ok)

  expect_sequence :: proc(t: ^testing.T, rows: []Row, datums: []string, numerals: []string) {
    testing.expect_value(t, len(rows), len(datums))
    for row, index in rows {
      testing.expect_value(t, row.datum, datums[index])
      testing.expect_value(t, row.annotations[0], numerals[index])
    }
  }

  progression, _, progression_ok := harmony_rows(
    scale, []int{ 1, 5, 6, 4, 1 }, 3, context.temp_allocator,
  )
  testing.expect(t, progression_ok)
  expect_sequence(t,
    progression,
    []string{ "C", "G", "Am", "F", "C" },
    []string{ "I", "V", "vi", "IV", "I" },
  )

  every, _, every_ok := harmony_rows(scale, nil, 3, context.temp_allocator)
  testing.expect(t, every_ok)
  expect_sequence(t,
    every,
    []string{ "C", "Dm", "Em", "F", "G", "Am", "Bdim" },
    []string{ "I", "ii", "iii", "IV", "V", "vi", "vii°" },
  )
}

/*
A degree the scale does not have is a well-formed request with no answer, and
the position it came at is what lets the command echo the numeral that was
typed rather than the number it read.
*/
@(test)
test_a_degree_outside_the_scale_names_its_position :: proc(t: ^testing.T) {
  scale, _ := scale_read("C major", context.temp_allocator)

  _, failed, ok := harmony_rows(scale, []int{ 1, 5, 8 }, 3, context.temp_allocator)
  testing.expect(t, !ok)
  testing.expect_value(t, failed, 2)

  pentatonic, _ := scale_read("C major pentatonic", context.temp_allocator)
  _, sixth, pentatonic_ok := harmony_rows(pentatonic, []int{ 6 }, 3, context.temp_allocator)
  testing.expect(t, !pentatonic_ok)
  testing.expect_value(t, sixth, 0)
}

/*
The pipeline the sequence exists for: a progression's lines are notation, so the
sink reads them back and writes the four chords in the order they were asked
for.
*/
@(test)
test_a_progression_reaches_the_midi_sink :: proc(t: ^testing.T) {
  scale, _ := scale_read("C major", context.temp_allocator)
  rows, _, rows_ok := harmony_rows(scale, []int{ 1, 5, 6, 4 }, 3, context.temp_allocator)
  testing.expect(t, rows_ok)

  lines := make([dynamic]string, 0, len(rows), context.temp_allocator)
  for row in rows {
    append(&lines, row.datum)
  }

  options, _, _ := options_parse([]string{ "midi", "--duration", "1/4" }, context.temp_allocator)
  bytes, token, error := midi_bytes(lines[:], options, context.temp_allocator)
  testing.expectf(t, error == .None, "%s: %v", token, error)

  ons := 0
  for index := 0; index + 3 <= len(bytes); index += 1 {
    if bytes[index] == 0x90 && bytes[index + 2] == muse.SMF_DEFAULT_VELOCITY {
      ons += 1
    }
  }
  testing.expect_value(t, ons, 12)
}

/*
The phase gate: `muse chords G major | muse json` produces complete chord
objects. Field one is all the sink is handed, so an object carrying the symbol,
the root, the notes and the intervals is the proof that the text protocol
carried the whole model rather than a label for it.
*/
@(test)
test_json_rebuilds_the_whole_chord_from_field_one :: proc(t: ^testing.T) {
  scale, _ := scale_read("G major", context.temp_allocator)
  rows, _, rows_ok := harmony_rows(scale, nil, 4, context.temp_allocator)
  testing.expect(t, rows_ok)

  lines := make([dynamic]string, 0, len(rows), context.temp_allocator)
  for row in rows {
    append(&lines, row.datum)
  }

  options, _, _ := options_parse([]string{ "json" }, context.temp_allocator)
  text, token, error := json_text(lines[:], nil, options, context.temp_allocator)
  testing.expectf(t, error == .None, "%s: %v", token, error)

  testing.expect_value(t, strings.count(text, "\"type\": \"chord\""), 7)
  for expected in ([]string {
    "\"symbol\": \"Gmaj7\"",
    "\"root\": \"G\"",
    "\"notes\": [\"G\", \"B\", \"D\", \"F#\"]",
    "\"intervals\": [\"P1\", \"M3\", \"P5\", \"M7\"]",
    "\"omitted\": []",
    "\"symbol\": \"F#m7b5\"",
    "\"notes\": [\"F#\", \"A\", \"C\", \"E\"]",
  }) {
    testing.expectf(t, strings.contains(text, expected), "no %s in the objects", expected)
  }
}

/*
Every kind of datum has its own object, and each one is derived from field one
alone. A register exists only where the datum had one, which is why a voicing
carries MIDI numbers and a chord does not.
*/
@(test)
test_json_gives_every_datum_its_own_object :: proc(t: ^testing.T) {
  object :: proc(t: ^testing.T, text: string) -> string {
    options, _, _ := options_parse([]string{ "json" }, context.temp_allocator)

    written, token, error := json_text([]string{ text }, nil, options, context.temp_allocator)
    testing.expectf(t, error == .None, "%s: %v", token, error)
    return written
  }

  scale := object(t, "G major")
  testing.expect(t, strings.contains(scale, "\"type\": \"scale\""))
  testing.expect(t, strings.contains(scale, "\"name\": \"G major\""))
  testing.expect(t, !strings.contains(scale, "\"midi\""))

  slash := object(t, "Cmaj7/E")
  testing.expect(t, strings.contains(slash, "\"bass\": \"E\""))

  notes := object(t, "C E G")
  testing.expect(t, strings.contains(notes, "\"type\": \"notes\""))
  testing.expect(t, strings.contains(notes, "\"chord\": \"C\""))

  voicing := object(t, "G3 C4 E4 B4")
  testing.expect(t, strings.contains(voicing, "\"type\": \"voicing\""))
  testing.expect(t, strings.contains(voicing, "\"pitches\": [\"G3\", \"C4\", \"E4\", \"B4\"]"))
  testing.expect(t, strings.contains(voicing, "\"midi\": [55, 60, 64, 71]"))

  nameless := object(t, "C Db")
  testing.expect(t, strings.contains(nameless, "\"chord\": null"))
}

/*
--literal is a rendering flag in the sink exactly as it is in the transforms: the
same chord printed two ways, and the object describes the realization it printed.
*/
@(test)
test_json_reports_the_omission_it_rendered :: proc(t: ^testing.T) {
  idiomatic, _, _ := options_parse([]string{ "json" },             context.temp_allocator)
  literal,   _, _ := options_parse([]string{ "json", "--literal" }, context.temp_allocator)

  omitted, _, omitted_error := json_text([]string{ "C13" }, nil, idiomatic, context.temp_allocator)
  testing.expect_value(t, omitted_error, SinkError.None)
  testing.expect(t, strings.contains(omitted, "\"omitted\": [\"P11\"]"))
  testing.expect(t, strings.contains(omitted, "\"notes\": [\"C\", \"E\", \"G\", \"Bb\", \"D\", \"A\"]"))

  whole, _, whole_error := json_text([]string{ "C13" }, nil, literal, context.temp_allocator)
  testing.expect_value(t, whole_error, SinkError.None)
  testing.expect(t, strings.contains(whole, "\"omitted\": []"))
  testing.expect(t, strings.contains(whole, "\"notes\": [\"C\", \"E\", \"G\", \"Bb\", \"D\", \"F\", \"A\"]"))
}

/*
A sink takes its key by the same explicit flag a transform does, and the numeral
it prints is the one `in` prints, since both read the same proc.
*/
@(test)
test_a_sink_names_degrees_against_the_key_it_was_given :: proc(t: ^testing.T) {
  options, _, ok := options_parse([]string{ "json", "-k", "G major" }, context.temp_allocator)
  testing.expect(t, ok)

  key, key_ok := sink_key(options, context.temp_allocator)
  testing.expect(t, key_ok)

  chord, _ := datum_parse("Am7", context.temp_allocator)
  testing.expect_value(t, sink_degree(chord, key, false, context.temp_allocator), "ii7")

  text, _, error := json_text([]string{ "Am7" }, key, options, context.temp_allocator)
  testing.expect_value(t, error, SinkError.None)
  testing.expect(t, strings.contains(text, "\"degree\": \"ii7\""))

  keyless, _, keyless_error := json_text([]string{ "Am7" }, nil, options, context.temp_allocator)
  testing.expect_value(t, keyless_error, SinkError.None)
  testing.expect(t, !strings.contains(keyless, "\"degree\""))

  bogus, _, _ := options_parse([]string{ "json", "-k", "H major" }, context.temp_allocator)
  _, bogus_ok := sink_key(bogus, context.temp_allocator)
  testing.expect(t, !bogus_ok)
}

/*
The numbers a script reads are the pitches the MIDI sink writes, which is what
makes them worth having: the two realize by the same route.
*/
@(test)
test_numbers_are_the_pitches_the_file_would_carry :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "numbers" }, context.temp_allocator)

  text, token, error := numbers_text(
    []string{ "Cmaj7", "G major", "G3 C4 E4 B4" }, options, context.temp_allocator,
  )
  testing.expectf(t, error == .None, "%s: %v", token, error)
  testing.expect_value(t, text, "60 64 67 71\n67 69 71 72 74 76 78\n55 60 64 71\n")

  _, nonsense, nonsense_error := numbers_text([]string{ "Cmaj7", "Hmm" }, options, context.temp_allocator)
  testing.expect_value(t, nonsense_error, SinkError.NotNotation)
  testing.expect_value(t, nonsense, "Hmm")

  high, _, _ := options_parse([]string{ "numbers", "--octave", "10" }, context.temp_allocator)
  _, range_token, range_error := numbers_text([]string{ "Cmaj7" }, high, context.temp_allocator)
  testing.expect_value(t, range_error, SinkError.OutOfRange)
  testing.expect_value(t, range_token, "Cmaj7")
}

/*
A block says what the datum is and what muse derived from it, and a scale's block
carries the chords in it, since that is what a scale is for.
*/
@(test)
test_info_says_what_it_knows_and_leaves_out_what_it_does_not :: proc(t: ^testing.T) {
  block :: proc(t: ^testing.T, arguments: []string, text: string) -> string {
    options, _, _ := options_parse(arguments, context.temp_allocator)

    key, key_ok := sink_key(options, context.temp_allocator)
    testing.expect(t, key_ok)

    written, token, error := info_text([]string{ text }, key, options, context.temp_allocator)
    testing.expectf(t, error == .None, "%s: %v", token, error)
    return written
  }

  scale := block(t, []string{ "info" }, "G major")
  testing.expect(t, strings.has_prefix(scale, "G major\n"))
  testing.expect(t, strings.contains(scale, "  triads    G Am Bm C D Em F#dim\n"))
  testing.expect(t, strings.contains(scale, "  sevenths  Gmaj7 Am7 Bm7 Cmaj7 D7 Em7 F#m7b5\n"))
  testing.expect(t, strings.contains(scale, "  midi      67 69 71 72 74 76 78\n"))
  testing.expect(t, !strings.contains(scale, "  degree"))

  chord := block(t, []string{ "info", "-k", "F major" }, "C13")
  testing.expect(t, strings.contains(chord, "  type      chord\n"))
  testing.expect(t, strings.contains(chord, "  omits     P11\n"))
  testing.expect(t, strings.contains(chord, "  degree    V7\n"))

  high := block(t, []string{ "info", "--octave", "10" }, "Cmaj7")
  testing.expect(t, !strings.contains(high, "  midi"))

  pair := block(t, []string{ "info" }, "C4 E4 G4")
  testing.expect(t, strings.contains(pair, "  chord     C\n"))
}

/*
A block per datum, separated by a blank line, and nothing written at all when a
line in the middle of the input fails.
*/
@(test)
test_a_sink_writes_nothing_when_a_line_fails :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "info" }, context.temp_allocator)

  text, _, error := info_text([]string{ "C", "Am" }, nil, options, context.temp_allocator)
  testing.expect_value(t, error, SinkError.None)
  testing.expect(t, strings.contains(text, "\n\nAm\n"))

  for arguments in ([][]string{ { "json" }, { "numbers" }, { "info" } }) {
    failing, _, _ := options_parse(arguments, context.temp_allocator)

    written := ""
    token   := ""
    error   := SinkError.None

    switch arguments[0] {
    case "json":
      written, token, error = json_text([]string{ "C", "Hmm" }, nil, failing, context.temp_allocator)
    case "numbers":
      written, token, error = numbers_text([]string{ "C", "Hmm" }, failing, context.temp_allocator)
    case "info":
      written, token, error = info_text([]string{ "C", "Hmm" }, nil, failing, context.temp_allocator)
    }

    testing.expectf(t, error == .NotNotation, "%s accepted Hmm", arguments[0])
    testing.expect_value(t, token, "Hmm")
    testing.expect_value(t, len(written), 0)
  }
}
