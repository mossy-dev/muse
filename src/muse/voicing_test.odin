package muse

import "core:strings"
import "core:testing"

@(private)
pitches_text :: proc(voicing: Voicing) -> string {
  parts := make([dynamic]string, 0, len(voicing.pitches), context.temp_allocator)
  for pitch in voicing.pitches {
    append(&parts, pitch_string(pitch, context.temp_allocator))
  }
  return strings.join(parts[:], " ", context.temp_allocator)
}

@(private)
voicing_of :: proc(t: ^testing.T, symbol: string, octave := 4) -> Voicing {
  chord, chord_ok := chord_parse(symbol, context.temp_allocator)
  testing.expectf(t, chord_ok, "%s did not parse", symbol)

  voicing, voicing_ok := voicing_close(chord, octave, false, context.temp_allocator)
  testing.expectf(t, voicing_ok, "%s could not be realized", symbol)

  return voicing
}

@(private)
voicing_ascends :: proc(voicing: Voicing) -> bool {
  for index in 1 ..< len(voicing.pitches) {
    if pitch_compare(voicing.pitches[index - 1], voicing.pitches[index]) >= 0 {
      return false
    }
  }
  return true
}

@(test)
test_voicing_close_sits_around_middle_c :: proc(t: ^testing.T) {
  triad := voicing_of(t, "C")
  testing.expect_value(t, pitches_text(triad), "C4 E4 G4")
  testing.expect_value(t, pitch_midi(triad.pitches[0]), 60)
  testing.expect_value(t, pitch_midi(triad.pitches[1]), 64)
  testing.expect_value(t, pitch_midi(triad.pitches[2]), 67)

  lower := voicing_of(t, "C", 3)
  testing.expect_value(t, pitches_text(lower), "C3 E3 G3")
  testing.expect_value(t, pitch_midi(lower.pitches[0]), 48)
}

@(test)
test_voicing_close_stacks_upward :: proc(t: ^testing.T) {
  testing.expect_value(t, pitches_text(voicing_of(t, "Cmaj7")),  "C4 E4 G4 B4")
  testing.expect_value(t, pitches_text(voicing_of(t, "C13")),    "C4 E4 G4 Bb4 D5 A5")
  testing.expect_value(t, pitches_text(voicing_of(t, "Am7")),    "A4 C5 E5 G5")
  testing.expect_value(t, pitches_text(voicing_of(t, "Bdim7")),  "B4 D5 F5 Ab5")
  testing.expect_value(t, pitches_text(voicing_of(t, "Cm7b5")),  "C4 Eb4 Gb4 Bb4")
}

@(test)
test_voicing_close_keeps_ascending_across_the_octave_boundary :: proc(t: ^testing.T) {
  testing.expect_value(t, pitches_text(voicing_of(t, "B")),     "B4 D#5 F#5")
  testing.expect_value(t, pitches_text(voicing_of(t, "B#")),    "B#4 D##5 F##5")
  testing.expect_value(t, pitches_text(voicing_of(t, "Cb")),    "Cb4 Eb4 Gb4")
  testing.expect_value(t, pitches_text(voicing_of(t, "Bmaj7")), "B4 D#5 F#5 A#5")
}

@(test)
test_voicing_close_puts_a_slash_bass_at_the_bottom :: proc(t: ^testing.T) {
  first_inversion := voicing_of(t, "C/E")
  testing.expect_value(t, pitches_text(first_inversion), "E4 G4 C5")
  testing.expect_value(t, pitch_midi(first_inversion.pitches[0]), 64)

  second_inversion := voicing_of(t, "C/G")
  testing.expect_value(t, pitches_text(second_inversion), "G4 C5 E5")

  outside := voicing_of(t, "C/D")
  testing.expect_value(t, pitches_text(outside), "D4 C5 E5 G5")

  extension := voicing_of(t, "C13/A")
  testing.expect_value(t, pitches_text(extension), "A4 C5 E5 G5 Bb5 D6")
}

@(test)
test_voicing_literal_realization_keeps_the_full_stack :: proc(t: ^testing.T) {
  chord, _ := chord_parse("C13", context.temp_allocator)

  literal, ok := voicing_close(chord, 4, true, context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, pitches_text(literal), "C4 E4 G4 Bb4 D5 F5 A5")
}

@(test)
test_voicing_operations_ascend :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord := chord_make(root, template, context.temp_allocator)
      text  := chord_string(chord, context.temp_allocator)

      close, close_ok := voicing_close(chord, 4, false, context.temp_allocator)
      if !testing.expectf(t, close_ok, "%s could not be realized", text) {
        continue
      }
      testing.expectf(t, voicing_ascends(close), "%s close does not ascend", text)

      shell, shell_ok := voicing_shell(chord, 4, context.temp_allocator)
      testing.expectf(t, shell_ok, "%s shell could not be realized", text)
      testing.expectf(t, voicing_ascends(shell), "%s shell does not ascend", text)

      testing.expectf(
        t,
        voicing_ascends(voicing_open(close, context.temp_allocator)),
        "%s open does not ascend",
        text,
      )

      for n in -3 ..= 8 {
        inverted := voicing_invert(close, n, context.temp_allocator)
        testing.expectf(t, voicing_ascends(inverted), "%s inverted by %d does not ascend", text, n)
      }

      for n in 2 ..= len(close.pitches) {
        dropped, dropped_ok := voicing_drop(close, n, context.temp_allocator)
        testing.expectf(t, dropped_ok, "%s has no voice %d from the top", text, n)
        testing.expectf(t, voicing_ascends(dropped), "%s drop %d does not ascend", text, n)
      }
    }
  }
}

@(test)
test_voicing_invert_preserves_the_pitch_classes :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord      := chord_make(root, template, context.temp_allocator)
      close, _   := voicing_close(chord, 4, false, context.temp_allocator)
      expected   := pitch_classes(close)

      for n in -3 ..= 8 {
        inverted := voicing_invert(close, n, context.temp_allocator)
        testing.expectf(
          t,
          expected == pitch_classes(inverted),
          "%s inverted by %d changed its pitch classes",
          chord_string(chord, context.temp_allocator),
          n,
        )
      }
    }
  }
}

@(private)
pitch_classes :: proc(voicing: Voicing) -> (classes: bit_set[0 ..< 12]) {
  for pitch in voicing.pitches {
    classes += { note_pitch_class(pitch.note) }
  }
  return
}

@(test)
test_voicing_invert_moves_the_bottom_voice_up :: proc(t: ^testing.T) {
  close := voicing_of(t, "C")

  testing.expect_value(t, pitches_text(voicing_invert(close, 1, context.temp_allocator)), "E4 G4 C5")
  testing.expect_value(t, pitches_text(voicing_invert(close, 2, context.temp_allocator)), "G4 C5 E5")
  testing.expect_value(t, pitches_text(voicing_invert(close, 3, context.temp_allocator)), "C5 E5 G5")
  testing.expect_value(t, pitches_text(voicing_invert(close, 4, context.temp_allocator)), "E5 G5 C6")
  testing.expect_value(t, pitches_text(voicing_invert(close, -1, context.temp_allocator)), "G3 C4 E4")
  testing.expect_value(t, pitches_text(voicing_invert(close, 0, context.temp_allocator)), "C4 E4 G4")
}

@(test)
test_voicing_drop_moves_one_inner_voice :: proc(t: ^testing.T) {
  close := voicing_of(t, "Cmaj7")
  testing.expect_value(t, pitches_text(close), "C4 E4 G4 B4")

  drop_two, drop_two_ok := voicing_drop(close, 2, context.temp_allocator)
  testing.expect(t, drop_two_ok)
  testing.expect_value(t, pitches_text(drop_two), "G3 C4 E4 B4")

  drop_three, drop_three_ok := voicing_drop(close, 3, context.temp_allocator)
  testing.expect(t, drop_three_ok)
  testing.expect_value(t, pitches_text(drop_three), "E3 C4 G4 B4")

  _, too_high := voicing_drop(close, 5, context.temp_allocator)
  testing.expect(t, !too_high)

  _, too_low := voicing_drop(close, 1, context.temp_allocator)
  testing.expect(t, !too_low)
}

@(test)
test_voicing_open_lifts_alternate_voices :: proc(t: ^testing.T) {
  triad := voicing_of(t, "C")
  testing.expect_value(t, pitches_text(voicing_open(triad, context.temp_allocator)), "C4 G4 E5")

  seventh := voicing_of(t, "Cmaj7")
  testing.expect_value(t, pitches_text(voicing_open(seventh, context.temp_allocator)), "C4 G4 E5 B5")
}

@(test)
test_voicing_shell_keeps_the_degrees_that_name_the_chord :: proc(t: ^testing.T) {
  shells := []struct{ symbol, pitches: string } {
    { "Cmaj7",  "C4 E4 B4" },
    { "C7",     "C4 E4 Bb4" },
    { "Cm7",    "C4 Eb4 Bb4" },
    { "C13",    "C4 E4 Bb4" },
    { "C6",     "C4 E4 A4" },
    { "C69",    "C4 E4 A4" },
    { "C7sus4", "C4 F4 Bb4" },
    { "Csus2",  "C4 D4" },
    { "C",      "C4 E4" },
    { "C5",     "C4" },
    { "Cdim7",  "C4 Eb4 Bbb4" },
  }

  for shell in shells {
    chord, chord_ok := chord_parse(shell.symbol, context.temp_allocator)
    if !testing.expectf(t, chord_ok, "%s did not parse", shell.symbol) {
      continue
    }

    voicing, voicing_ok := voicing_shell(chord, 4, context.temp_allocator)
    if !testing.expectf(t, voicing_ok, "%s could not be realized", shell.symbol) {
      continue
    }
    testing.expect_value(t, pitches_text(voicing), shell.pitches)
  }
}

@(test)
test_voicing_identifies_as_the_chord_it_came_from :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord := chord_make(root, template, context.temp_allocator)
      text  := chord_string(chord, context.temp_allocator)

      for literal in ([2]bool{ false, true }) {
        voicing, voicing_ok := voicing_close(chord, 4, literal, context.temp_allocator)
        if !testing.expectf(t, voicing_ok, "%s could not be realized", text) {
          continue
        }

        identified, identified_ok := chord_identify(
          voicing_notes(voicing, context.temp_allocator),
          context.temp_allocator,
        )
        if !testing.expectf(t, identified_ok, "%s was not identified", text) {
          continue
        }
        testing.expectf(
          t,
          chord_equal(identified, chord),
          "%s identified as %s",
          text,
          chord_string(identified, context.temp_allocator),
        )
      }
    }
  }
}

@(test)
test_voicing_of_a_slash_chord_identifies_as_that_chord :: proc(t: ^testing.T) {
  chord, _ := chord_parse("C/E", context.temp_allocator)

  voicing, voicing_ok := voicing_close(chord, 4, false, context.temp_allocator)
  testing.expect(t, voicing_ok)

  identified, identified_ok := chord_identify(
    voicing_notes(voicing, context.temp_allocator),
    context.temp_allocator,
  )
  testing.expect(t, identified_ok)
  testing.expect_value(t, chord_string(identified, context.temp_allocator), "C/E")
}

@(test)
test_voicing_close_refuses_an_unspellable_chord :: proc(t: ^testing.T) {
  chord, _ := chord_parse("Cbbdim7", context.temp_allocator)

  _, ok := voicing_close(chord, 4, false, context.temp_allocator)
  testing.expect(t, !ok)
}

/*
A voicing transposes in register: a compound interval moves it further than its
simple form, which is the whole reason a pitch carries an octave.
*/
@(test)
test_voicing_transposition_carries_the_register :: proc(t: ^testing.T) {
  close := voicing_of(t, "C")

  up_a_second, second_ok := voicing_transpose(close, MAJOR_SECOND, context.temp_allocator)
  testing.expect(t, second_ok)
  testing.expect_value(t, pitches_text(up_a_second), "D4 F#4 A4")

  up_a_ninth, ninth_ok := voicing_transpose(close, MAJOR_NINTH, context.temp_allocator)
  testing.expect(t, ninth_ok)
  testing.expect_value(t, pitches_text(up_a_ninth), "D5 F#5 A5")

  back, back_ok := voicing_transpose(up_a_ninth, interval_negate(MAJOR_NINTH), context.temp_allocator)
  testing.expect(t, back_ok)
  testing.expect_value(t, pitches_text(back), pitches_text(close))
}

/*
Stacking is what realizes anything that is not a chord: notes in the order they
arrive, each in the lowest octave that clears the one below.
*/
@(test)
test_voicing_from_notes_stacks_in_order :: proc(t: ^testing.T) {
  scale, scale_ok := scale_parse("G major", context.temp_allocator)
  testing.expect(t, scale_ok)

  notes, _, notes_ok := scale_notes(scale, context.temp_allocator)
  testing.expect(t, notes_ok)

  testing.expect_value(
    t,
    pitches_text(voicing_from_notes(notes, 4, context.temp_allocator)),
    "G4 A4 B4 C5 D5 E5 F#5",
  )
}
