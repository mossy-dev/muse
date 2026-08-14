package muse

import "core:testing"

@(test)
test_quality_reads_deviation_from_the_major_scale :: proc(t: ^testing.T) {
  expect_quality :: proc(t: ^testing.T, interval: Interval, expected: IntervalQuality) {
    quality, ok := interval_quality(interval)
    testing.expect(t, ok)
    testing.expect_value(t, quality, expected)
  }

  expect_quality(t, UNISON,             .Perfect)
  expect_quality(t, MINOR_THIRD,        .Minor)
  expect_quality(t, MAJOR_THIRD,        .Major)
  expect_quality(t, PERFECT_FIFTH,      .Perfect)
  expect_quality(t, DIMINISHED_FIFTH,   .Diminished)
  expect_quality(t, AUGMENTED_FOURTH,   .Augmented)
  expect_quality(t, DIMINISHED_SEVENTH, .Diminished)
  expect_quality(t, MAJOR_NINTH,        .Major)
  expect_quality(t, AUGMENTED_ELEVENTH, .Augmented)
}

@(test)
test_enharmonic_intervals_keep_separate_qualities :: proc(t: ^testing.T) {
  testing.expect_value(t, AUGMENTED_FOURTH.semitones, DIMINISHED_FIFTH.semitones)

  tritone_up,   _ := interval_quality(AUGMENTED_FOURTH)
  tritone_down, _ := interval_quality(DIMINISHED_FIFTH)
  testing.expect(t, tritone_up != tritone_down)
}

@(test)
test_descending_intervals_mirror_their_ascending_form :: proc(t: ^testing.T) {
  descending := interval_negate(PERFECT_FIFTH)
  testing.expect(t, interval_is_descending(descending))
  testing.expect_value(t, interval_number(descending), 5)

  quality, ok := interval_quality(descending)
  testing.expect(t, ok)
  testing.expect_value(t, quality, IntervalQuality.Perfect)
}

@(test)
test_construction_rejects_impossible_pairings :: proc(t: ^testing.T) {
  _, minor_fifth_ok := interval_make(5, .Minor)
  testing.expect(t, !minor_fifth_ok)

  _, perfect_third_ok := interval_make(3, .Perfect)
  testing.expect(t, !perfect_third_ok)

  _, major_fourth_ok := interval_make(4, .Major)
  testing.expect(t, !major_fourth_ok)
}

@(test)
test_construction_and_naming_are_inverse :: proc(t: ^testing.T) {
  for number in 1 ..= 15 {
    for quality in IntervalQuality {
      interval, made := interval_make(number, quality)
      if !made {
        continue
      }
      read_back, ok := interval_quality(interval)
      testing.expect(t, ok)
      testing.expect_value(t, read_back, quality)
      testing.expect_value(t, interval_number(interval), number)
    }
  }
}

@(test)
test_abbreviations_round_trip_through_the_parser :: proc(t: ^testing.T) {
  for number in 1 ..= 15 {
    for quality in IntervalQuality {
      interval, made := interval_make(number, quality)
      if !made {
        continue
      }
      for candidate in ([]Interval{ interval, interval_negate(interval) }) {
        text, printed := interval_abbreviation(candidate, context.temp_allocator)
        testing.expect(t, printed)
        parsed, ok := interval_parse(text)
        testing.expect(t, ok)
        testing.expect_value(t, parsed, candidate)
      }
    }
  }
}

@(test)
test_parser_accepts_the_forms_musicians_write :: proc(t: ^testing.T) {
  expect_parse :: proc(t: ^testing.T, token: string, expected: Interval) {
    parsed, ok := interval_parse(token)
    testing.expect(t, ok, token)
    testing.expect_value(t, parsed, expected)
  }

  expect_parse(t, "M3",   MAJOR_THIRD)
  expect_parse(t, "m3",   MINOR_THIRD)
  expect_parse(t, "P5",   PERFECT_FIFTH)
  expect_parse(t, "A4",   AUGMENTED_FOURTH)
  expect_parse(t, "d5",   DIMINISHED_FIFTH)
  expect_parse(t, "maj7", MAJOR_SEVENTH)
  expect_parse(t, "min7", MINOR_SEVENTH)
  expect_parse(t, "-P5",  interval_negate(PERFECT_FIFTH))
  expect_parse(t, "+M3",  MAJOR_THIRD)
  expect_parse(t, "5",    PERFECT_FIFTH)
  expect_parse(t, "3",    MAJOR_THIRD)
  expect_parse(t, "9",    MAJOR_NINTH)
}

@(test)
test_flat_shorthand_lowers_the_unaltered_interval :: proc(t: ^testing.T) {
  flat_third, _ := interval_parse("b3")
  testing.expect_value(t, flat_third, MINOR_THIRD)

  diminished_third, _ := interval_parse("d3")
  testing.expect_value(t, diminished_third, Interval{ 2, 2 })

  flat_fifth, _ := interval_parse("b5")
  testing.expect_value(t, flat_fifth, DIMINISHED_FIFTH)

  sharp_eleventh, _ := interval_parse("#11")
  testing.expect_value(t, sharp_eleventh, AUGMENTED_ELEVENTH)

  sharp_ninth, _ := interval_parse("#9")
  testing.expect_value(t, sharp_ninth, AUGMENTED_NINTH)
}

@(test)
test_parser_rejects_malformed_tokens :: proc(t: ^testing.T) {
  for token in ([]string{ "", "M", "3M", "Q5", "P", "-", "M3x", "P0", "m-3" }) {
    _, ok := interval_parse(token)
    testing.expect(t, !ok, token)
  }
}

@(test)
test_interval_between_notes_uses_spelling :: proc(t: ^testing.T) {
  testing.expect_value(t, interval_between(Note{ .C, 0 }, Note{ .E,  0 }), MAJOR_THIRD)
  testing.expect_value(t, interval_between(Note{ .C, 0 }, Note{ .E, -1 }), MINOR_THIRD)
  testing.expect_value(t, interval_between(Note{ .E, 0 }, Note{ .C,  0 }), MINOR_SIXTH)
  testing.expect_value(t, interval_between(Note{ .C, 0 }, Note{ .B,  1 }), Interval{ 6, 12 })
  testing.expect_value(t, interval_between(Note{ .C, -1 }, Note{ .G, 0 }), AUGMENTED_FIFTH)
}

@(test)
test_interval_between_pitches_is_signed_and_compound :: proc(t: ^testing.T) {
  c4 := Pitch{ Note{ .C, 0 }, 4 }
  d5 := Pitch{ Note{ .D, 0 }, 5 }
  g3 := Pitch{ Note{ .G, 0 }, 3 }

  testing.expect_value(t, pitch_interval_between(c4, d5), MAJOR_NINTH)
  testing.expect_value(t, pitch_interval_between(c4, g3), interval_negate(PERFECT_FOURTH))
  testing.expect_value(t, pitch_interval_between(c4, c4), UNISON)
}

@(test)
test_compound_intervals_reduce_to_simple_ones :: proc(t: ^testing.T) {
  testing.expect_value(t, interval_simple(MAJOR_NINTH),        MAJOR_SECOND)
  testing.expect_value(t, interval_simple(AUGMENTED_ELEVENTH), AUGMENTED_FOURTH)
  testing.expect_value(t, interval_simple(MAJOR_THIRTEENTH),   MAJOR_SIXTH)
  testing.expect_value(t, interval_simple(OCTAVE),             UNISON)
  testing.expect_value(t, interval_simple(MAJOR_THIRD),        MAJOR_THIRD)
}

@(test)
test_spoken_names :: proc(t: ^testing.T) {
  expect_name :: proc(t: ^testing.T, interval: Interval, expected: string) {
    name, ok := interval_name(interval, context.temp_allocator)
    testing.expect(t, ok)
    testing.expect_value(t, name, expected)
  }

  expect_name(t, MINOR_THIRD,        "minor third")
  expect_name(t, PERFECT_FIFTH,      "perfect fifth")
  expect_name(t, AUGMENTED_FOURTH,   "augmented fourth")
  expect_name(t, OCTAVE,             "perfect octave")
  expect_name(t, UNISON,             "unison")
  expect_name(t, MAJOR_THIRTEENTH,   "major thirteenth")
  expect_name(t, interval_negate(PERFECT_FIFTH), "descending perfect fifth")
}

/*
A semitone count carries no spelling, so the one it is given is the one a
musician writes: the major, minor or perfect interval of that distance, and the
augmented fourth for the tritone, which is the one distance none of those spans.
*/
@(test)
test_semitone_counts_spell_as_the_plain_intervals :: proc(t: ^testing.T) {
  testing.expect_value(t, interval_from_semitones(0),  UNISON)
  testing.expect_value(t, interval_from_semitones(1),  MINOR_SECOND)
  testing.expect_value(t, interval_from_semitones(3),  MINOR_THIRD)
  testing.expect_value(t, interval_from_semitones(4),  MAJOR_THIRD)
  testing.expect_value(t, interval_from_semitones(5),  PERFECT_FOURTH)
  testing.expect_value(t, interval_from_semitones(6),  AUGMENTED_FOURTH)
  testing.expect_value(t, interval_from_semitones(7),  PERFECT_FIFTH)
  testing.expect_value(t, interval_from_semitones(10), MINOR_SEVENTH)
  testing.expect_value(t, interval_from_semitones(12), OCTAVE)
  testing.expect_value(t, interval_from_semitones(14), MAJOR_NINTH)
  testing.expect_value(t, interval_from_semitones(-3), interval_negate(MINOR_THIRD))
}

/*
Every semitone count reaches a nameable interval, which is what makes a bare
number safe to hand to transposition.
*/
@(test)
test_every_semitone_count_names_an_interval :: proc(t: ^testing.T) {
  for semitones in -24 ..= 24 {
    interval := interval_from_semitones(semitones)
    testing.expect_value(t, interval.semitones, semitones)

    _, ok := interval_quality(interval)
    testing.expectf(t, ok, "%d semitones spelled as an unnameable interval", semitones)
  }
}
