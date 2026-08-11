package muse

import "core:testing"

@(test)
test_pitch_class_wraps_at_the_octave_boundary :: proc(t: ^testing.T) {
  testing.expect_value(t, note_pitch_class(Note{ .C,  0 }),  0)
  testing.expect_value(t, note_pitch_class(Note{ .C, -1 }), 11)
  testing.expect_value(t, note_pitch_class(Note{ .B,  1 }),  0)
  testing.expect_value(t, note_pitch_class(Note{ .F,  2 }),  7)
  testing.expect_value(t, note_pitch_class(Note{ .G, -2 }),  5)
}

@(test)
test_enharmonics_sound_alike_and_spell_apart :: proc(t: ^testing.T) {
  e_flat  := Note{ .E, -1 }
  d_sharp := Note{ .D,  1 }
  testing.expect(t, note_enharmonic(e_flat, d_sharp))
  testing.expect(t, e_flat != d_sharp)
}

@(test)
test_transposition_spells_by_interval_not_by_preference :: proc(t: ^testing.T) {
  c := Note{ .C, 0 }

  minor_third, _ := note_add_interval(c, MINOR_THIRD)
  testing.expect_value(t, minor_third, Note{ .E, -1 })

  augmented_second, _ := note_add_interval(c, AUGMENTED_SECOND)
  testing.expect_value(t, augmented_second, Note{ .D, 1 })

  testing.expect_value(t, note_pitch_class(minor_third), note_pitch_class(augmented_second))
}

@(test)
test_transposition_carries_accidentals :: proc(t: ^testing.T) {
  fifth_above_c_flat, _ := note_add_interval(Note{ .C, -1 }, PERFECT_FIFTH)
  testing.expect_value(t, fifth_above_c_flat, Note{ .G, -1 })

  third_above_b, _ := note_add_interval(Note{ .B, 0 }, MAJOR_THIRD)
  testing.expect_value(t, third_above_b, Note{ .D, 1 })

  third_below_c, _ := note_add_interval(Note{ .C, 0 }, interval_negate(MINOR_THIRD))
  testing.expect_value(t, third_below_c, Note{ .A, 0 })
}

@(test)
test_transposition_refuses_unspellable_results :: proc(t: ^testing.T) {
  _, ok := note_add_interval(Note{ .F, -2 }, DIMINISHED_SEVENTH)
  testing.expect(t, !ok)
}

@(test)
test_midi_numbers_read_the_octave_off_the_letter :: proc(t: ^testing.T) {
  testing.expect_value(t, pitch_midi(Pitch{ Note{ .C, 0 }, 4 }), 60)
  testing.expect_value(t, pitch_midi(Pitch{ Note{ .A, 0 }, 4 }), 69)
  testing.expect_value(t, pitch_midi(Pitch{ Note{ .B, 1 }, 3 }), 60)
  testing.expect_value(t, pitch_midi(Pitch{ Note{ .C, -1 }, 4 }), 59)
}

@(test)
test_pitch_transposition_crosses_octaves :: proc(t: ^testing.T) {
  g4, _ := pitch_add_interval(Pitch{ Note{ .C, 0 }, 4 }, PERFECT_FIFTH)
  testing.expect_value(t, g4, Pitch{ Note{ .G, 0 }, 4 })

  d5, _ := pitch_add_interval(Pitch{ Note{ .G, 0 }, 4 }, PERFECT_FIFTH)
  testing.expect_value(t, d5, Pitch{ Note{ .D, 0 }, 5 })

  c4, _ := pitch_add_interval(Pitch{ Note{ .B, 0 }, 3 }, MINOR_SECOND)
  testing.expect_value(t, c4, Pitch{ Note{ .C, 0 }, 4 })

  f3, _ := pitch_add_interval(Pitch{ Note{ .C, 0 }, 4 }, interval_negate(PERFECT_FIFTH))
  testing.expect_value(t, f3, Pitch{ Note{ .F, 0 }, 3 })
}

@(test)
test_pitch_transposition_distinguishes_compound_intervals :: proc(t: ^testing.T) {
  second, _ := pitch_add_interval(Pitch{ Note{ .C, 0 }, 4 }, MAJOR_SECOND)
  ninth,  _ := pitch_add_interval(Pitch{ Note{ .C, 0 }, 4 }, MAJOR_NINTH)
  testing.expect_value(t, second, Pitch{ Note{ .D, 0 }, 4 })
  testing.expect_value(t, ninth,  Pitch{ Note{ .D, 0 }, 5 })
}

@(test)
test_pitch_transposition_is_invertible :: proc(t: ^testing.T) {
  intervals := []Interval{
    MINOR_SECOND, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, OCTAVE, MAJOR_NINTH,
  }
  starts := []Pitch{
    Pitch{ Note{ .C,  0 }, 4 },
    Pitch{ Note{ .F,  1 }, 2 },
    Pitch{ Note{ .B, -1 }, 5 },
  }

  for start in starts {
    for interval in intervals {
      up,   up_ok   := pitch_add_interval(start, interval)
      back, back_ok := pitch_add_interval(up, interval_negate(interval))
      testing.expect(t, up_ok && back_ok)
      testing.expect_value(t, back, start)
    }
  }
}

@(test)
test_pitches_order_by_sound :: proc(t: ^testing.T) {
  testing.expect(t, pitch_compare(Pitch{ Note{ .C, 0 }, 4 }, Pitch{ Note{ .D, 0 }, 4 }) < 0)
  testing.expect(t, pitch_compare(Pitch{ Note{ .B, 0 }, 3 }, Pitch{ Note{ .C, 0 }, 4 }) < 0)
  testing.expect(t, pitch_compare(Pitch{ Note{ .C, 0 }, 5 }, Pitch{ Note{ .B, 0 }, 4 }) > 0)
}
