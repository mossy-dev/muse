package muse

import "core:slice"
import "core:strings"
import "core:testing"

/*
The nine seven-note templates, in the order the old DIATONIC_TRIADS and
DIATONIC_SEVENTHS tables listed them.
*/
@(private)
HEPTATONIC_NAMES := []string {
  "major", "minor", "harmonic minor", "melodic minor",
  "dorian", "phrygian", "lydian", "mixolydian", "locrian",
}

/*
The classical tables the previous design hard-coded, transcribed from
0d6af1b:theory.odin as chord symbols. Harmonizing has to reproduce these
exactly; that it does is the whole argument for deleting them.
*/
@(private)
DIATONIC_TRIADS := [9][7]string {
  { "",    "m",   "m",    "",     "",    "m",   "dim" },
  { "m",   "dim", "",     "m",    "m",   "",    ""    },
  { "m",   "dim", "aug",  "m",    "",    "",    "dim" },
  { "m",   "m",   "aug",  "",     "",    "dim", "dim" },
  { "m",   "m",   "",     "",     "m",   "dim", ""    },
  { "m",   "",    "",     "m",    "dim", "",    "m"   },
  { "",    "",    "m",    "dim",  "",    "m",   "m"   },
  { "",    "m",   "dim",  "",     "m",   "m",   ""    },
  { "dim", "",    "m",    "m",    "",    "",    "m"   },
}

@(private)
DIATONIC_SEVENTHS := [9][7]string {
  { "maj7",  "m7",   "m7",     "maj7", "7",    "m7",   "m7b5" },
  { "m7",    "m7b5", "maj7",   "m7",   "m7",   "maj7", "7"    },
  { "mMaj7", "m7b5", "maj7#5", "m7",   "7",    "maj7", "dim7" },
  { "mMaj7", "m7",   "maj7#5", "7",    "7",    "m7b5", "m7b5" },
  { "m7",    "m7",   "maj7",   "7",    "m7",   "m7b5", "maj7" },
  { "m7",    "maj7", "7",      "m7",   "m7b5", "maj7", "m7"   },
  { "maj7",  "7",    "m7",     "m7b5", "maj7", "m7",   "m7"   },
  { "7",     "m7",   "m7b5",   "maj7", "m7",   "m7",   "maj7" },
  { "m7b5",  "maj7", "m7",     "m7",   "maj7", "7",    "m7"   },
}

@(private)
scale_of :: proc(t: ^testing.T, text: string) -> Scale {
  scale, ok := scale_parse(text, context.temp_allocator)
  testing.expectf(t, ok, "%s did not parse", text)
  return scale
}

@(private)
scale_notes_text :: proc(t: ^testing.T, text: string) -> string {
  notes, _, ok := scale_notes(scale_of(t, text), context.temp_allocator)
  testing.expectf(t, ok, "%s could not be spelled", text)
  return notes_text(notes)
}

@(private)
expected_chord :: proc(root: Note, symbol: string) -> string {
  return strings.concatenate(
    { note_string(root, context.temp_allocator), symbol },
    context.temp_allocator,
  )
}

@(private)
harmony_symbol :: proc(harmony: Harmony) -> string {
  chord, named := harmony.chord.?
  if !named {
    return notes_text(harmony.notes)
  }
  return chord_string(chord, context.temp_allocator)
}

@(test)
test_scale_notes_spell_the_pattern :: proc(t: ^testing.T) {
  testing.expect_value(t, scale_notes_text(t, "G major"),          "G A B C D E F#")
  testing.expect_value(t, scale_notes_text(t, "C minor"),          "C D Eb F G Ab Bb")
  testing.expect_value(t, scale_notes_text(t, "A harmonic minor"), "A B C D E F G#")
  testing.expect_value(t, scale_notes_text(t, "A melodic"),        "A B C D E F# G#")
  testing.expect_value(t, scale_notes_text(t, "D dorian"),         "D E F G A B C")
  testing.expect_value(t, scale_notes_text(t, "F lydian"),         "F G A B C D E")
  testing.expect_value(t, scale_notes_text(t, "B locrian"),        "B C D E F G A")
  testing.expect_value(t, scale_notes_text(t, "C majpent"),        "C D E G A")
  testing.expect_value(t, scale_notes_text(t, "A minpent"),        "A C D E G")
  testing.expect_value(t, scale_notes_text(t, "C blues"),          "C Eb F Gb G Bb")
  testing.expect_value(t, scale_notes_text(t, "C chromatic"),      "C C# D D# E F F# G G# A A# B")
  testing.expect_value(t, scale_notes_text(t, "Db chromatic"),     "Db D Eb E F Gb G Ab A Bb B C")
}

@(test)
test_scale_names_round_trip :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in SCALE_TEMPLATES {
      scale := scale_make(root, template, context.temp_allocator)
      text  := scale_string(scale, context.temp_allocator)

      parsed, ok := scale_parse(text, context.temp_allocator)
      if !testing.expectf(t, ok, "%s did not parse", text) {
        continue
      }
      testing.expectf(t, scale_equal(parsed, scale), "%s did not round trip", text)
    }
  }
}

@(test)
test_scale_aliases_and_case :: proc(t: ^testing.T) {
  aliases := []struct{ input, canonical: string } {
    { "C ionian",         "C major" },
    { "C maj",            "C major" },
    { "C Major",          "C major" },
    { "C natural minor",  "C minor" },
    { "C aeolian",        "C minor" },
    { "C harmonic",       "C harmonic minor" },
    { "C melodic",        "C melodic minor" },
    { "C majpent",        "C major pentatonic" },
    { "C pentatonic",     "C major pentatonic" },
    { "C minpent",        "C minor pentatonic" },
    { "Bb HARMONIC MINOR", "Bb harmonic minor" },
  }

  for alias in aliases {
    scale, ok := scale_parse(alias.input, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not parse", alias.input) {
      continue
    }
    testing.expect_value(t, scale_string(scale, context.temp_allocator), alias.canonical)
  }
}

@(test)
test_scale_parse_rejects_malformed_input :: proc(t: ^testing.T) {
  rejected := []string{ "", "C", "G major seven", "H major", "c major", "major", "G ", "G# klezmer" }

  for text in rejected {
    _, ok := scale_parse(text, context.temp_allocator)
    testing.expectf(t, !ok, "%q parsed as a scale", text)
  }
}

@(test)
test_heptatonic_scales_spell_each_letter_once :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for name in HEPTATONIC_NAMES {
      template, _ := scale_template_match(name)
      scale       := scale_make(root, template, context.temp_allocator)
      text        := scale_string(scale, context.temp_allocator)

      notes, _, ok := scale_notes(scale, context.temp_allocator)
      if !testing.expectf(t, ok, "%s could not be spelled", text) {
        continue
      }

      seen : bit_set[Letter]
      for note in notes {
        testing.expectf(t, note.letter not_in seen, "%s repeats a letter", text)
        seen += { note.letter }
      }
      testing.expectf(t, card(seen) == 7, "%s does not use every letter", text)
    }
  }
}

@(test)
test_harmonizing_reproduces_the_classical_tables :: proc(t: ^testing.T) {
  for name, index in HEPTATONIC_NAMES {
    for root in TEST_ROOTS {
      template, _ := scale_template_match(name)
      scale       := scale_make(root, template, context.temp_allocator)
      text        := scale_string(scale, context.temp_allocator)

      triads, triads_ok := scale_harmonize(scale, 3, context.temp_allocator)
      if !testing.expectf(t, triads_ok, "%s did not harmonize", text) {
        continue
      }
      sevenths, sevenths_ok := scale_harmonize(scale, 4, context.temp_allocator)
      testing.expectf(t, sevenths_ok, "%s did not harmonize", text)

      for degree in 1 ..= 7 {
        triad := triads[degree - 1]
        testing.expect_value(
          t,
          harmony_symbol(triad),
          expected_chord(triad.notes[0], DIATONIC_TRIADS[index][degree - 1]),
        )

        seventh := sevenths[degree - 1]
        testing.expect_value(
          t,
          harmony_symbol(seventh),
          expected_chord(seventh.notes[0], DIATONIC_SEVENTHS[index][degree - 1]),
        )
      }
    }
  }
}

@(test)
test_harmonized_chords_stay_inside_the_scale :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in SCALE_TEMPLATES {
      scale := scale_make(root, template, context.temp_allocator)
      text  := scale_string(scale, context.temp_allocator)

      members, _, members_ok := scale_notes(scale, context.temp_allocator)
      if !testing.expectf(t, members_ok, "%s could not be spelled", text) {
        continue
      }

      for size in ([]int{ 3, 4, 5, 6, 7 }) {
        harmonies, ok := scale_harmonize(scale, size, context.temp_allocator)
        if !testing.expectf(t, ok, "%s did not harmonize", text) {
          continue
        }
        testing.expectf(t, len(harmonies) == len(members), "%s dropped a degree", text)

        for harmony in harmonies {
          testing.expectf(t, len(harmony.notes) > 0, "%s produced an empty line", text)
          for note in harmony.notes {
            testing.expectf(
              t,
              slice.contains(members, note),
              "%s harmonized %s outside the scale",
              text,
              note_string(note, context.temp_allocator),
            )
          }
        }
      }
    }
  }
}

@(test)
test_harmonizing_g_major_matches_the_design_example :: proc(t: ^testing.T) {
  harmonies, ok := scale_harmonize(scale_of(t, "G major"), 3, context.temp_allocator)
  testing.expect(t, ok)

  expected := []struct{ symbol, numeral, notes: string } {
    { "G",     "I",    "G B D" },
    { "Am",    "ii",   "A C E" },
    { "Bm",    "iii",  "B D F#" },
    { "C",     "IV",   "C E G" },
    { "D",     "V",    "D F# A" },
    { "Em",    "vi",   "E G B" },
    { "F#dim", "vii°", "F# A C" },
  }

  for row, index in expected {
    harmony := harmonies[index]
    testing.expect_value(t, harmony_symbol(harmony), row.symbol)
    testing.expect_value(t, notes_text(harmony.notes), row.notes)
    testing.expect_value(
      t,
      scale_degree_label(index + 1, harmony.notes, context.temp_allocator),
      row.numeral,
    )
  }
}

@(test)
test_degree_labels_take_their_suffix_from_the_stack :: proc(t: ^testing.T) {
  labels := []struct{ scale: string, size: int, expected: []string } {
    { "C major",          3, { "I", "ii", "iii", "IV", "V", "vi", "vii°" } },
    { "C major",          4, { "Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7" } },
    { "C harmonic minor", 3, { "i", "ii°", "III+", "iv", "V", "VI", "vii°" } },
    { "C harmonic minor", 4, { "imaj7", "iiø7", "III+maj7", "iv7", "V7", "VImaj7", "vii°7" } },
  }

  for row in labels {
    harmonies, ok := scale_harmonize(scale_of(t, row.scale), row.size, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not harmonize", row.scale) {
      continue
    }

    for expected, index in row.expected {
      testing.expect_value(
        t,
        scale_degree_label(index + 1, harmonies[index].notes, context.temp_allocator),
        expected,
      )
    }
  }
}

@(test)
test_scale_chord_at_stacks_higher_extensions :: proc(t: ^testing.T) {
  major := scale_of(t, "C major")

  sizes := []struct{ size: int, symbol, notes: string } {
    { 3, "C",      "C E G" },
    { 4, "Cmaj7",  "C E G B" },
    { 5, "Cmaj9",  "C E G B D" },
    { 6, "Cmaj11", "C E G B D F" },
    { 7, "Cmaj13", "C E G B D F A" },
  }

  for row in sizes {
    harmony, ok := scale_chord_at(major, 1, row.size, context.temp_allocator)
    if !testing.expectf(t, ok, "C major degree 1 size %d failed", row.size) {
      continue
    }
    testing.expect_value(t, harmony_symbol(harmony), row.symbol)
    testing.expect_value(t, notes_text(harmony.notes), row.notes)
  }

  _, beyond := scale_chord_at(major, 8, 3, context.temp_allocator)
  testing.expect(t, !beyond)

  _, below := scale_chord_at(major, 0, 3, context.temp_allocator)
  testing.expect(t, !below)
}

@(test)
test_non_heptatonic_scales_harmonize :: proc(t: ^testing.T) {
  pentatonic, pentatonic_ok := scale_harmonize(scale_of(t, "C majpent"), 3, context.temp_allocator)
  testing.expect(t, pentatonic_ok)
  testing.expect_value(t, len(pentatonic), 5)

  expected := []string{ "Am/C", "Gsus4/D", "Asus4/E", "C/G", "Dsus4/A" }
  for symbol, index in expected {
    testing.expect_value(t, harmony_symbol(pentatonic[index]), symbol)
  }

  // A six-note scale stacks in thirds only three deep before it comes back
  // round to its own root, so a seventh chord is not available and the line
  // carries the three notes that were.
  blues, blues_ok := scale_harmonize(scale_of(t, "C blues"), 4, context.temp_allocator)
  testing.expect(t, blues_ok)
  testing.expect_value(t, len(blues), 6)
  testing.expect_value(t, len(blues[0].notes), 3)
  testing.expect_value(t, harmony_symbol(blues[0]), "Csus4")

  // The chromatic scale is where a stack stops having a name, and the note
  // list is the datum instead.
  chromatic, chromatic_ok := scale_harmonize(scale_of(t, "C chromatic"), 3, context.temp_allocator)
  testing.expect(t, chromatic_ok)
  testing.expect_value(t, len(chromatic), 12)

  _, named := chromatic[0].chord.?
  testing.expect(t, !named)
  testing.expect_value(t, harmony_symbol(chromatic[0]), "C D E")
}

@(test)
test_scale_identify_roots_on_the_first_note :: proc(t: ^testing.T) {
  major, major_ok := scale_identify(
    []Note{ { .C, 0 }, { .D, 0 }, { .E, 0 }, { .F, 0 }, { .G, 0 }, { .A, 0 }, { .B, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, major_ok)
  testing.expect_value(t, scale_string(major, context.temp_allocator), "C major")

  minor, minor_ok := scale_identify(
    []Note{ { .A, 0 }, { .B, 0 }, { .C, 0 }, { .D, 0 }, { .E, 0 }, { .F, 0 }, { .G, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, minor_ok)
  testing.expect_value(t, scale_string(minor, context.temp_allocator), "A minor")

  _, unknown := scale_identify([]Note{ { .C, 0 }, { .D, 0 }, { .E, 0 } }, context.temp_allocator)
  testing.expect(t, !unknown)
}

@(test)
test_scale_readings_list_the_modes :: proc(t: ^testing.T) {
  readings := scale_readings(
    []Note{ { .C, 0 }, { .D, 0 }, { .E, 0 }, { .F, 0 }, { .G, 0 }, { .A, 0 }, { .B, 0 } },
    context.temp_allocator,
  )
  testing.expect_value(t, len(readings), 7)

  expected := []string {
    "C major", "D dorian", "E phrygian", "F lydian",
    "G mixolydian", "A minor", "B locrian",
  }
  for name, index in expected {
    testing.expect_value(t, scale_string(readings[index], context.temp_allocator), name)
  }
}

@(test)
test_scale_identifies_what_it_spelled :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in SCALE_TEMPLATES {
      scale := scale_make(root, template, context.temp_allocator)
      text  := scale_string(scale, context.temp_allocator)

      notes, _, notes_ok := scale_notes(scale, context.temp_allocator)
      if !testing.expectf(t, notes_ok, "%s could not be spelled", text) {
        continue
      }

      identified, identified_ok := scale_identify(notes, context.temp_allocator)
      if !testing.expectf(t, identified_ok, "%s was not identified", text) {
        continue
      }
      testing.expectf(
        t,
        scale_equal(identified, scale),
        "%s identified as %s",
        text,
        scale_string(identified, context.temp_allocator),
      )
    }
  }
}

@(test)
test_unspellable_scale_names_the_degree_and_suggests_a_root :: proc(t: ^testing.T) {
  scale := scale_of(t, "G## harmonic")

  _, degree, ok := scale_notes(scale, context.temp_allocator)
  testing.expect(t, !ok)
  testing.expect_value(t, degree, 7)

  respelled, respelled_ok := scale_respell(scale, context.temp_allocator)
  testing.expect(t, respelled_ok)
  testing.expect_value(t, scale_string(respelled, context.temp_allocator), "A harmonic minor")

  _, _, respelled_notes_ok := scale_notes(respelled, context.temp_allocator)
  testing.expect(t, respelled_notes_ok)
}

@(test)
test_scale_respell_prefers_the_plainest_root :: proc(t: ^testing.T) {
  spellings := []struct{ input, suggestion: string } {
    { "G## harmonic minor", "A harmonic minor" },
    { "Fb major",           "E major" },
    { "B# major",           "C major" },
  }

  for spelling in spellings {
    scale := scale_of(t, spelling.input)

    respelled, ok := scale_respell(scale, context.temp_allocator)
    if !testing.expectf(t, ok, "%s has no enharmonic root", spelling.input) {
      continue
    }
    testing.expect_value(t, scale_string(respelled, context.temp_allocator), spelling.suggestion)
  }
}

/*
A transposed scale keeps its template, so every degree is spelled by the same
arithmetic on the new root, and transposing back returns the scale that set out.
*/
@(test)
test_scale_transposition_is_invertible :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in SCALE_TEMPLATES {
      scale := scale_make(root, template, context.temp_allocator)

      for interval in ([]Interval{ MINOR_SECOND, MAJOR_THIRD, PERFECT_FIFTH }) {
        moved, moved_ok := scale_transpose(scale, interval, context.temp_allocator)
        if !moved_ok {
          continue
        }

        back, back_ok := scale_transpose(moved, interval_negate(interval), context.temp_allocator)
        testing.expect(t, back_ok)
        testing.expect(t, scale_equal(back, scale))
      }
    }
  }
}

@(test)
test_scale_transposition_spells_by_the_interval :: proc(t: ^testing.T) {
  major, _ := scale_parse("G major", context.temp_allocator)

  up_a_fifth, up_ok := scale_transpose(major, PERFECT_FIFTH, context.temp_allocator)
  testing.expect(t, up_ok)
  testing.expect_value(t, scale_string(up_a_fifth, context.temp_allocator), "D major")

  notes, _, notes_ok := scale_notes(up_a_fifth, context.temp_allocator)
  testing.expect(t, notes_ok)
  testing.expect_value(t, notes_text(notes), "D E F# G A B C#")
}
