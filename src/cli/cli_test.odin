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
