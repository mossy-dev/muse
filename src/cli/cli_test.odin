package main

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
