package muse

import "core:slice"
import "core:strings"
import "core:testing"

/*
The twelve roots the cross-product tests use: one spelling per pitch class,
chosen so that every template stays inside a double accidental.
*/
@(private)
TEST_ROOTS := [12]Note {
  { .C,  0 }, { .D, -1 }, { .D, 0 }, { .E, -1 }, { .E, 0 }, { .F, 0 },
  { .G, -1 }, { .G,  0 }, { .A, -1 }, { .A, 0 }, { .B, -1 }, { .B, 0 },
}

@(private)
notes_text :: proc(notes: []Note) -> string {
  parts := make([dynamic]string, 0, len(notes), context.temp_allocator)
  for note in notes {
    append(&parts, note_string(note, context.temp_allocator))
  }
  return strings.join(parts[:], " ", context.temp_allocator)
}

@(private)
intervals_text :: proc(intervals: []Interval) -> string {
  parts := make([dynamic]string, 0, len(intervals), context.temp_allocator)
  for interval in intervals {
    abbreviation, _ := interval_abbreviation(interval, context.temp_allocator)
    append(&parts, abbreviation)
  }
  return strings.join(parts[:], " ", context.temp_allocator)
}

@(private)
notes_of :: proc(text: string) -> []Note {
  notes := make([dynamic]Note, 0, 8, context.temp_allocator)

  start := 0
  for index in 0 ..= len(text) {
    if index < len(text) && text[index] != ' ' {
      continue
    }
    if note, ok := note_parse(text[start:index]); ok {
      append(&notes, note)
    }
    start = index + 1
  }

  return notes[:]
}

@(private)
notes_sorted_text :: proc(notes: []Note) -> string {
  sorted := slice.clone(notes, context.temp_allocator)
  slice.sort_by(sorted, proc(a, b: Note) -> bool {
    if a.letter != b.letter {
      return a.letter < b.letter
    }
    return a.alteration < b.alteration
  })
  return notes_text(sorted)
}

@(private)
reduced_intervals :: proc(intervals: []Interval, omit: bool) -> []Interval {
  omitted, has_omission := intervals_omission(intervals)

  reduced := make([dynamic]Interval, 0, len(intervals), context.temp_allocator)
  for interval in intervals {
    if omit && has_omission && interval == omitted {
      continue
    }
    append(&reduced, interval_simple(interval))
  }

  intervals_sort(reduced[:])
  return reduced[:]
}

/*
docs/CHORD-SYMBOLS.md section 8, transcribed. Each row is an accepted input, the
canonical spelling it prints as, its interval set, and the notes of its
idiomatic realization.
*/
@(private)
ChordFixture :: struct {
  input     : string,
  canonical : string,
  intervals : string,
  notes     : string,
}

@(private)
CHORD_FIXTURES := []ChordFixture {
  { "C",          "C",         "P1 M3 P5",       "C E G" },
  { "Cmaj",       "C",         "P1 M3 P5",       "C E G" },
  { "CM",         "C",         "P1 M3 P5",       "C E G" },
  { "Cm",         "Cm",        "P1 m3 P5",       "C Eb G" },
  { "Cmin",       "Cm",        "P1 m3 P5",       "C Eb G" },
  { "C-",         "Cm",        "P1 m3 P5",       "C Eb G" },
  { "Cdim",       "Cdim",      "P1 m3 d5",       "C Eb Gb" },
  { "C°",         "Cdim",      "P1 m3 d5",       "C Eb Gb" },
  { "Caug",       "Caug",      "P1 M3 A5",       "C E G#" },
  { "C+",         "Caug",      "P1 M3 A5",       "C E G#" },
  { "C(#5)",      "Caug",      "P1 M3 A5",       "C E G#" },
  { "C(b5)",      "C(b5)",     "P1 M3 d5",       "C E Gb" },
  { "Csus4",      "Csus4",     "P1 P4 P5",       "C F G" },
  { "Csus",       "Csus4",     "P1 P4 P5",       "C F G" },
  { "Csus2",      "Csus2",     "P1 M2 P5",       "C D G" },
  { "C5",         "C5",        "P1 P5",          "C G" },
  { "Cno3",       "C5",        "P1 P5",          "C G" },
  { "Comit3",     "C5",        "P1 P5",          "C G" },

  { "C6",         "C6",        "P1 M3 P5 M6",    "C E G A" },
  { "Cm6",        "Cm6",       "P1 m3 P5 M6",    "C Eb G A" },
  { "C-6",        "Cm6",       "P1 m3 P5 M6",    "C Eb G A" },
  { "C69",        "C69",       "P1 M3 P5 M6 M9", "C E G A D" },
  { "C6/9",       "C69",       "P1 M3 P5 M6 M9", "C E G A D" },
  { "Cm69",       "Cm69",      "P1 m3 P5 M6 M9", "C Eb G A D" },

  { "C7",         "C7",        "P1 M3 P5 m7",    "C E G Bb" },
  { "Cmaj7",      "Cmaj7",     "P1 M3 P5 M7",    "C E G B" },
  { "CM7",        "Cmaj7",     "P1 M3 P5 M7",    "C E G B" },
  { "CΔ7",        "Cmaj7",     "P1 M3 P5 M7",    "C E G B" },
  { "CΔ",         "Cmaj7",     "P1 M3 P5 M7",    "C E G B" },
  { "Cm7",        "Cm7",       "P1 m3 P5 m7",    "C Eb G Bb" },
  { "Cmin7",      "Cm7",       "P1 m3 P5 m7",    "C Eb G Bb" },
  { "C-7",        "Cm7",       "P1 m3 P5 m7",    "C Eb G Bb" },
  { "CmMaj7",     "CmMaj7",    "P1 m3 P5 M7",    "C Eb G B" },
  { "Cmmaj7",     "CmMaj7",    "P1 m3 P5 M7",    "C Eb G B" },
  { "CminMaj7",   "CmMaj7",    "P1 m3 P5 M7",    "C Eb G B" },
  { "CmΔ7",       "CmMaj7",    "P1 m3 P5 M7",    "C Eb G B" },
  { "Cm(maj7)",   "CmMaj7",    "P1 m3 P5 M7",    "C Eb G B" },
  { "Cdim7",      "Cdim7",     "P1 m3 d5 d7",    "C Eb Gb Bbb" },
  { "C°7",        "Cdim7",     "P1 m3 d5 d7",    "C Eb Gb Bbb" },
  { "Cm7b5",      "Cm7b5",     "P1 m3 d5 m7",    "C Eb Gb Bb" },
  { "Cø",         "Cm7b5",     "P1 m3 d5 m7",    "C Eb Gb Bb" },
  { "Cø7",        "Cm7b5",     "P1 m3 d5 m7",    "C Eb Gb Bb" },
  { "C-7b5",      "Cm7b5",     "P1 m3 d5 m7",    "C Eb Gb Bb" },
  { "Caug7",      "Caug7",     "P1 M3 A5 m7",    "C E G# Bb" },
  { "C+7",        "Caug7",     "P1 M3 A5 m7",    "C E G# Bb" },
  { "C7#5",       "Caug7",     "P1 M3 A5 m7",    "C E G# Bb" },
  { "C7b5",       "C7b5",      "P1 M3 d5 m7",    "C E Gb Bb" },
  { "Cmaj7#5",    "Cmaj7#5",   "P1 M3 A5 M7",    "C E G# B" },
  { "C7sus4",     "C7sus4",    "P1 P4 P5 m7",    "C F G Bb" },
  { "C7sus",      "C7sus4",    "P1 P4 P5 m7",    "C F G Bb" },
  { "Cmaj7sus4",  "Cmaj7sus4", "P1 P4 P5 M7",    "C F G B" },

  { "C9",         "C9",        "P1 M3 P5 m7 M9",     "C E G Bb D" },
  { "Cmaj9",      "Cmaj9",     "P1 M3 P5 M7 M9",     "C E G B D" },
  { "CM9",        "Cmaj9",     "P1 M3 P5 M7 M9",     "C E G B D" },
  { "CΔ9",        "Cmaj9",     "P1 M3 P5 M7 M9",     "C E G B D" },
  { "Cm9",        "Cm9",       "P1 m3 P5 m7 M9",     "C Eb G Bb D" },
  { "C-9",        "Cm9",       "P1 m3 P5 m7 M9",     "C Eb G Bb D" },
  { "CmMaj9",     "CmMaj9",    "P1 m3 P5 M7 M9",     "C Eb G B D" },
  { "Cm9b5",      "Cm9b5",     "P1 m3 d5 m7 M9",     "C Eb Gb Bb D" },
  { "Cø9",        "Cm9b5",     "P1 m3 d5 m7 M9",     "C Eb Gb Bb D" },
  { "Cdim9",      "Cdim9",     "P1 m3 d5 d7 M9",     "C Eb Gb Bbb D" },
  { "C9sus4",     "C9sus4",    "P1 P4 P5 m7 M9",     "C F G Bb D" },
  { "C7b9",       "C7b9",      "P1 M3 P5 m7 m9",     "C E G Bb Db" },
  { "C7#9",       "C7#9",      "P1 M3 P5 m7 A9",     "C E G Bb D#" },
  { "C7b9#11",    "C7b9#11",   "P1 M3 P5 m7 m9 A11", "C E G Bb Db F#" },
  { "C7(b9,#11)", "C7b9#11",   "P1 M3 P5 m7 m9 A11", "C E G Bb Db F#" },
  { "Cadd9",      "Cadd9",     "P1 M3 P5 M9",        "C E G D" },
  { "Cmadd9",     "Cmadd9",    "P1 m3 P5 M9",        "C Eb G D" },
  { "Cm(add9)",   "Cmadd9",    "P1 m3 P5 M9",        "C Eb G D" },
  { "Cadd2",      "Cadd2",     "P1 M2 M3 P5",        "C D E G" },

  { "C11",        "C11",       "P1 M3 P5 m7 M9 P11", "C G Bb D F" },
  { "Cm11",       "Cm11",      "P1 m3 P5 m7 M9 P11", "C Eb G Bb D F" },
  { "Cmaj11",     "Cmaj11",    "P1 M3 P5 M7 M9 P11", "C G B D F" },
  { "Cm11b5",     "Cm11b5",    "P1 m3 d5 m7 M9 P11", "C Eb Gb Bb D F" },
  { "C7#11",      "C7#11",     "P1 M3 P5 m7 A11",    "C E G Bb F#" },
  { "C9#11",      "C9#11",     "P1 M3 P5 m7 M9 A11", "C E G Bb D F#" },
  { "Cmaj9#11",   "Cmaj9#11",  "P1 M3 P5 M7 M9 A11", "C E G B D F#" },
  { "C(#11)",     "C(#11)",    "P1 M3 P5 A11",       "C E G F#" },
  { "Cadd11",     "Cadd11",    "P1 M3 P5 P11",       "C E G F" },
  { "C11no9",     "C11no9",    "P1 M3 P5 m7 P11",    "C G Bb F" },

  { "C13",        "C13",       "P1 M3 P5 m7 M9 P11 M13", "C E G Bb D A" },
  { "Cm13",       "Cm13",      "P1 m3 P5 m7 M9 P11 M13", "C Eb G Bb D F A" },
  { "Cmaj13",     "Cmaj13",    "P1 M3 P5 M7 M9 P11 M13", "C E G B D A" },
  { "C13b9",      "C13b9",     "P1 M3 P5 m7 m9 P11 M13", "C E G Bb Db A" },
  { "C13#11",     "C13#11",    "P1 M3 P5 m7 M9 A11 M13", "C E G Bb D F# A" },
  { "C13no11",    "C13no11",   "P1 M3 P5 m7 M9 M13",     "C E G Bb D A" },
  { "C13sus4",    "C13sus4",   "P1 P5 m7 M9 P11 M13",    "C G Bb D F A" },
  { "C7b13",      "C7b13",     "P1 M3 P5 m7 m13",        "C E G Bb Ab" },

  { "F#m7b5",     "F#m7b5",    "P1 m3 d5 m7",            "F# A C E" },
  { "Ebmaj7",     "Ebmaj7",    "P1 M3 P5 M7",            "Eb G Bb D" },
  { "Db9",        "Db9",       "P1 M3 P5 m7 M9",         "Db F Ab Cb Eb" },
  { "Bb13",       "Bb13",      "P1 M3 P5 m7 M9 P11 M13", "Bb D F Ab C G" },
  { "Gbdim7",     "Gbdim7",    "P1 m3 d5 d7",            "Gb Bbb Dbb Fbb" },
  { "G##dim7",    "G##dim7",   "P1 m3 d5 d7",            "G## B# D# F#" },
  { "A♯m7",       "A#m7",      "P1 m3 P5 m7",            "A# C# E# G#" },
  { "E♭maj7",     "Ebmaj7",    "P1 M3 P5 M7",            "Eb G Bb D" },
  { "C𝄪",         "C##",       "P1 M3 P5",               "C## E## G##" },
  { "Cx7",        "C##7",      "P1 M3 P5 m7",            "C## E## G## B#" },
}

@(test)
test_chord_symbols_parse_print_and_realize :: proc(t: ^testing.T) {
  for fixture in CHORD_FIXTURES {
    chord, ok := chord_parse(fixture.input, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not parse", fixture.input) {
      continue
    }

    testing.expect_value(t, chord_string(chord, context.temp_allocator), fixture.canonical)
    testing.expect_value(t, intervals_text(chord.intervals), fixture.intervals)

    notes, notes_ok := chord_notes(chord, false, context.temp_allocator)
    if !testing.expectf(t, notes_ok, "%s could not be spelled", fixture.input) {
      continue
    }
    testing.expect_value(t, notes_text(notes), fixture.notes)
  }
}

@(test)
test_chord_symbols_round_trip :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord := chord_make(root, template, context.temp_allocator)
      text  := chord_string(chord, context.temp_allocator)

      parsed, ok := chord_parse(text, context.temp_allocator)
      if !testing.expectf(t, ok, "%s did not parse", text) {
        continue
      }
      testing.expectf(t, chord_equal(parsed, chord), "%s did not round trip", text)
    }
  }
}

@(test)
test_chord_identify_recovers_every_template :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord := chord_make(root, template, context.temp_allocator)
      text  := chord_string(chord, context.temp_allocator)

      for literal in ([2]bool{ false, true }) {
        notes, notes_ok := chord_notes(chord, literal, context.temp_allocator)
        if !testing.expectf(t, notes_ok, "%s could not be spelled", text) {
          continue
        }

        identified, identified_ok := chord_identify(notes, context.temp_allocator)
        if !testing.expectf(t, identified_ok, "%s was not identified from %s", text, notes_text(notes)) {
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

/*
The ranking in DESIGN.md only has to separate readings on different roots
because no two templates realize alike. That is a property of the table rather
than a guarantee of the model, so it is asserted here: break it and
chord_identify starts answering with whichever row it met first.
*/
@(test)
test_chord_template_realizations_are_distinct :: proc(t: ^testing.T) {
  for template, index in CHORD_TEMPLATES {
    for other in CHORD_TEMPLATES[index + 1:] {
      for template_omit in ([2]bool{ false, true }) {
        for other_omit in ([2]bool{ false, true }) {
          testing.expectf(
            t,
            !intervals_equal(
              reduced_intervals(template.intervals, template_omit),
              reduced_intervals(other.intervals,    other_omit),
            ),
            "%q and %q realize alike",
            template.symbol,
            other.symbol,
          )
        }
      }
    }
  }
}

@(test)
test_chord_identify_roots_on_the_first_note :: proc(t: ^testing.T) {
  minor_seventh, minor_seventh_ok := chord_identify(
    []Note{ { .A, 0 }, { .C, 0 }, { .E, 0 }, { .G, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, minor_seventh_ok)
  testing.expect_value(t, chord_string(minor_seventh, context.temp_allocator), "Am7")

  sixth, sixth_ok := chord_identify(
    []Note{ { .C, 0 }, { .E, 0 }, { .G, 0 }, { .A, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, sixth_ok)
  testing.expect_value(t, chord_string(sixth, context.temp_allocator), "C6")
}

@(test)
test_chord_identify_reads_a_slash_bass :: proc(t: ^testing.T) {
  inverted, inverted_ok := chord_identify(
    []Note{ { .E, 0 }, { .G, 0 }, { .C, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, inverted_ok)
  testing.expect_value(t, chord_string(inverted, context.temp_allocator), "C/E")

  // F# C E G is C with a raised eleventh under its own sharp, and only a chord
  // no reading accounts for leaves its first note outside: C# against C is a
  // degree twice over, so the bass is dropped and the triad keeps its name.
  raised, raised_ok := chord_identify(
    []Note{ { .F, 1 }, { .C, 0 }, { .E, 0 }, { .G, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, raised_ok)
  testing.expect_value(t, chord_string(raised, context.temp_allocator), "C(#11)/F#")

  outside, outside_ok := chord_identify(
    []Note{ { .C, 1 }, { .C, 0 }, { .E, 0 }, { .G, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, outside_ok)
  testing.expect_value(t, chord_string(outside, context.temp_allocator), "C/C#")

  // D C E G is C/D and is equally Cadd9/D. The notes do not choose, and a
  // reading that accounts for every note beats one that sets a note aside.
  ninth, ninth_ok := chord_identify(
    []Note{ { .D, 0 }, { .C, 0 }, { .E, 0 }, { .G, 0 } },
    context.temp_allocator,
  )
  testing.expect(t, ninth_ok)
  testing.expect_value(t, chord_string(ninth, context.temp_allocator), "Cadd9/D")
}

/*
The note sets docs/CHORD-SYMBOLS.md spells two ways, with the reading the
ranking picks and the symbol that loses to it. Neither name is wrong: the notes
do not choose, so the ranking does, and this table is what it chose.
*/
@(private)
ChordCollision :: struct {
  notes   : string,
  reading : string,
  other   : string,
}

@(private)
CHORD_COLLISIONS := []ChordCollision {
  { "C D E G",         "Cadd9",      "Cadd2" },
  { "C F G Bb D",      "C11",        "C9sus4" },
  { "C G Bb F",        "C7sus4",     "C11no9" },
  { "C E G Bb F",      "Fmaj11/C",   "C11no9" },
  { "C E G Bb Db F#",  "Edim9b13/C", "C7b9#11" },
  { "C E G Bb D A",    "C13",        "C13no11" },
  { "C E G Bb D F# A", "GmMaj13/C",  "C13#11" },
  { "C G Bb D F A",    "Gm11/C",     "C13sus4" },
  { "Eb G Bb C",       "Eb6",        "Cm7/Eb" },
  { "D C E G",         "Cadd9/D",    "C/D" },
  { "Bb C E G",        "C7/Bb",      "C/Bb" },
  { "E G A D C",       "D11/E",      "C69/E" },
}

@(private)
chord_collision_reading :: proc(notes: string) -> (string, bool) {
  for collision in CHORD_COLLISIONS {
    if collision.notes == notes {
      return collision.reading, true
    }
  }
  return "", false
}

/*
The phase gate: every symbol the specification admits is read back from its own
notes, in both realizations, and the exceptions are the note sets two symbols
share.

Identification searches bases rather than templates, so a symbol built by
alteration is named by the alterations that built it -- C E G Bb Db comes back
as C7b9 and not as a note list. Where two symbols spell one set the ranking
picks one of them, and CHORD_COLLISIONS says which.
*/
@(test)
test_chord_identification_reads_every_symbol_back :: proc(t: ^testing.T) {
  for fixture in CHORD_FIXTURES {
    chord, ok := chord_parse(fixture.input, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not parse", fixture.input) {
      continue
    }

    for literal in ([2]bool{ false, true }) {
      notes, notes_ok := chord_notes(chord, literal, context.temp_allocator)
      if !testing.expectf(t, notes_ok, "%s could not be spelled", fixture.input) {
        continue
      }

      expected := fixture.canonical
      if reading, shared := chord_collision_reading(notes_text(notes)); shared {
        expected = reading
      }

      identified, identified_ok := chord_identify(notes, context.temp_allocator)
      if !testing.expectf(t, identified_ok, "%s was not identified from %s", fixture.input, notes_text(notes)) {
        continue
      }
      testing.expectf(
        t,
        chord_string(identified, context.temp_allocator) == expected,
        "%s realizes as %s, which was identified as %s rather than %s",
        fixture.input,
        notes_text(notes),
        chord_string(identified, context.temp_allocator),
        expected,
      )
    }
  }
}

/*
The property that holds without exception: whatever identification answers with
spells the notes it was asked about. A collision is two names for one set of
notes, not a name for a different set, and this is what says so.
*/
@(test)
test_chord_collisions_carry_two_names :: proc(t: ^testing.T) {
  for collision in CHORD_COLLISIONS {
    for symbol in ([2]string{ collision.reading, collision.other }) {
      chord, ok := chord_parse(symbol, context.temp_allocator)
      if !testing.expectf(t, ok, "%s did not parse", symbol) {
        continue
      }

      spelled := false
      for literal in ([2]bool{ false, true }) {
        notes, notes_ok := chord_notes(chord, literal, context.temp_allocator)
        if notes_ok && notes_sorted_text(notes) == notes_sorted_text(notes_of(collision.notes)) {
          spelled = true
        }
      }
      testing.expectf(t, spelled, "%s does not spell %s", symbol, collision.notes)
    }
  }
}

/*
Every base identification searches, asked to name itself. The bases are the
product of the quality and extension tables the parser reads. This test reads
those tables and not the list identification derives from them, so a quality
identification stops searching fails here, and a quality added for the parser is
covered without this test being edited.

No base shares its notes with another reading, in either realization, so every
one of them comes back as itself. That is a property of the two tables rather
than a guarantee of the model, and this is where it is asserted.
*/
@(test)
test_chord_identification_covers_every_base :: proc(t: ^testing.T) {
  for quality_index in -1 ..< len(CHORD_QUALITY_TOKENS) {
    quality     : ChordQualityToken
    has_quality := quality_index >= 0
    if has_quality {
      quality = CHORD_QUALITY_TOKENS[quality_index]
    }

    for extension_index in -1 ..< len(CHORD_EXTENSION_TOKENS) {
      extension     : ChordExtensionToken
      has_extension := extension_index >= 0
      if has_extension {
        extension = CHORD_EXTENSION_TOKENS[extension_index]
      }

      if has_extension && extension.kind == .Power && has_quality {
        continue
      }
      if quality.requires_seventh && !(has_extension && extension.kind == .Stack) {
        continue
      }

      intervals, symbol := chord_build(
        quality, has_quality, extension, has_extension, nil, context.temp_allocator,
      )
      chord := Chord{ root = { .C, 0 }, symbol = symbol, intervals = intervals }
      text  := chord_string(chord, context.temp_allocator)

      for literal in ([2]bool{ false, true }) {
        notes, notes_ok := chord_notes(chord, literal, context.temp_allocator)
        if !testing.expectf(t, notes_ok, "%s could not be spelled", text) {
          continue
        }

        identified, identified_ok := chord_identify(notes, context.temp_allocator)
        if !testing.expectf(t, identified_ok, "%s was not identified from %s", text, notes_text(notes)) {
          continue
        }

        testing.expectf(
          t,
          chord_string(identified, context.temp_allocator) == text,
          "%s realizes as %s, which was identified as %s",
          text,
          notes_text(notes),
          chord_string(identified, context.temp_allocator),
        )
      }
    }
  }
}

/*
The chords the template table has no row for, named by the alterations that
build them. Each of these was a note list before identification searched bases.
*/
@(test)
test_chord_identify_names_an_altered_chord :: proc(t: ^testing.T) {
  expect_name :: proc(t: ^testing.T, notes, expected: string) {
    identified, ok := chord_identify(notes_of(notes), context.temp_allocator)
    if !testing.expectf(t, ok, "%s was not identified", notes) {
      return
    }
    testing.expect_value(t, chord_string(identified, context.temp_allocator), expected)
  }

  expect_name(t, "C E Gb",          "C(b5)")
  expect_name(t, "C E G F#",        "C(#11)")
  expect_name(t, "C E G F",         "Cadd11")
  expect_name(t, "C E G Bb Db",     "C7b9")
  expect_name(t, "C E G Bb D#",     "C7#9")
  expect_name(t, "C E G Bb F#",     "C7#11")
  expect_name(t, "C E G Bb Ab",     "C7b13")
  expect_name(t, "C F G B",         "Cmaj7sus4")
  expect_name(t, "C Eb Gb Bbb D",   "Cdim9")
  expect_name(t, "C E G Bb D F#",   "C9#11")
  expect_name(t, "C E G B D F#",    "Cmaj9#11")
  expect_name(t, "C E G Bb Db A",   "C13b9")
}

/*
The two limits on how far a name will reach, each shown at the point it stops.

Three alterations is one more than any symbol the specification admits, and a
name that long has stopped being shorter than the notes: C E G Ab Db F# is
C(b9#11b13) if the limit is three and is nothing at two.

The other limit is which degrees a reading may drop. Only the stacked ones --
the seventh, ninth, eleventh and thirteenth -- may go, so C D E is not a C with
its fifth omitted and a ninth added. It is three notes with no name.
*/
@(test)
test_chord_identify_stops_where_a_name_stops_helping :: proc(t: ^testing.T) {
  altered, altered_ok := chord_identify(notes_of("C E G Ab Db"), context.temp_allocator)
  testing.expect(t, altered_ok)
  testing.expect_value(t, chord_string(altered, context.temp_allocator), "C(b9b13)")

  _, past_limit := chord_identify(notes_of("C E G Ab Db F#"), context.temp_allocator)
  testing.expect(t, !past_limit)

  _, cluster := chord_identify(notes_of("C D E"), context.temp_allocator)
  testing.expect(t, !cluster)
}

@(test)
test_chord_slash_symbols_round_trip :: proc(t: ^testing.T) {
  symbols := []string{ "C/E", "C/G", "Cmaj7/B", "Cm7/Eb", "C/D", "C/Bb", "Ebmaj7/G" }

  for symbol in symbols {
    chord, ok := chord_parse(symbol, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not parse", symbol) {
      continue
    }
    testing.expect_value(t, chord_string(chord, context.temp_allocator), symbol)

    reparsed, reparsed_ok := chord_parse(chord_string(chord, context.temp_allocator), context.temp_allocator)
    testing.expect(t, reparsed_ok)
    testing.expectf(t, chord_equal(reparsed, chord), "%s did not round trip", symbol)
  }

  six_nine, six_nine_ok := chord_parse("C6/9/E", context.temp_allocator)
  testing.expect(t, six_nine_ok)
  testing.expect_value(t, chord_string(six_nine, context.temp_allocator), "C69/E")

  bass, bass_ok := six_nine.bass.?
  testing.expect(t, bass_ok)
  testing.expect_value(t, bass, Note{ .E, 0 })
}

@(test)
test_chord_slash_bass_sounds_below_the_chord :: proc(t: ^testing.T) {
  chord_tone, _ := chord_parse("C/E", context.temp_allocator)
  notes, ok := chord_notes(chord_tone, false, context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, notes_text(notes), "E G C")

  outside, _ := chord_parse("C/D", context.temp_allocator)
  outside_notes, outside_ok := chord_notes(outside, false, context.temp_allocator)
  testing.expect(t, outside_ok)
  testing.expect_value(t, notes_text(outside_notes), "D C E G")
}

@(test)
test_chord_omissions_follow_the_third_and_eleventh_rule :: proc(t: ^testing.T) {
  expected := []struct{ symbol: string, omitted: []Interval } {
    { "C11",     { MAJOR_THIRD } },
    { "Cmaj11",  { MAJOR_THIRD } },
    { "C11no9",  { MAJOR_THIRD } },
    { "C13",     { PERFECT_ELEVENTH } },
    { "Cmaj13",  { PERFECT_ELEVENTH } },
    { "C13b9",   { PERFECT_ELEVENTH } },
    { "Cm11",    {} },
    { "Cm13",    {} },
    { "C13#11",  {} },
    { "Cadd11",  {} },
    { "C13sus4", {} },
    { "C7",      {} },
  }

  for row in expected {
    chord, ok := chord_parse(row.symbol, context.temp_allocator)
    if !testing.expectf(t, ok, "%s did not parse", row.symbol) {
      continue
    }

    omissions := chord_omissions(chord, context.temp_allocator)
    testing.expectf(
      t,
      intervals_equal(omissions, row.omitted),
      "%s omitted %s",
      row.symbol,
      intervals_text(omissions),
    )
  }
}

@(test)
test_chord_literal_realization_keeps_the_full_stack :: proc(t: ^testing.T) {
  thirteenth, _ := chord_parse("C13", context.temp_allocator)

  idiomatic, idiomatic_ok := chord_notes(thirteenth, false, context.temp_allocator)
  testing.expect(t, idiomatic_ok)
  testing.expect_value(t, notes_text(idiomatic), "C E G Bb D A")

  literal, literal_ok := chord_notes(thirteenth, true, context.temp_allocator)
  testing.expect(t, literal_ok)
  testing.expect_value(t, notes_text(literal), "C E G Bb D F A")
}

@(test)
test_chord_parse_rejects_malformed_symbols :: proc(t: ^testing.T) {
  rejected := []string {
    "", "H7", "cmaj7", "C#b7", "Cbbb", "4C", "C10", "Cm5", "C7b7", "C#4",
    "C7b11", "Cadd", "Cadd3", "Cno", "C7alt", "CaugMaj7", "Cmaj79", "C7(b9",
    "C/", "C/H", "Cmaj7xyz", "C7b", "CmMaj", "CmMaj6",
  }

  for symbol in rejected {
    _, ok := chord_parse(symbol, context.temp_allocator)
    testing.expectf(t, !ok, "%q parsed as a chord", symbol)
  }
}

@(test)
test_chord_ambiguous_root_accidentals :: proc(t: ^testing.T) {
  ambiguous := []struct{ input, spelling: string } {
    { "Cb5",   "C(b5)" },
    { "C#5",   "C(#5)" },
    { "Cb9",   "C(b9)" },
    { "C#9",   "C(#9)" },
    { "C#11",  "C(#11)" },
    { "Cb13",  "C(b13)" },
    { "C#9b13", "C(#9)b13" },
  }

  for row in ambiguous {
    spelling, warned := chord_ambiguity(row.input, context.temp_allocator)
    testing.expectf(t, warned, "%s was read without a warning", row.input)
    testing.expect_value(t, spelling, row.spelling)
  }

  settled := []string{ "C7#11", "Cm#5", "C#7", "Cb6", "Cbb5", "Cb", "C13", "C(#11)" }
  for symbol in settled {
    _, warned := chord_ambiguity(symbol, context.temp_allocator)
    testing.expectf(t, !warned, "%s was reported ambiguous", symbol)
  }
}

@(test)
test_chord_ambiguous_root_binds_greedily :: proc(t: ^testing.T) {
  chord, ok := chord_parse("C#11", context.temp_allocator)
  testing.expect(t, ok)
  testing.expect_value(t, chord.root, Note{ .C, 1 })

  notes, notes_ok := chord_notes(chord, false, context.temp_allocator)
  testing.expect(t, notes_ok)
  testing.expect_value(t, notes_text(notes), "C# G# B D# F#")
}

@(test)
test_chord_add_interval_names_the_result :: proc(t: ^testing.T) {
  triad, _ := chord_parse("C", context.temp_allocator)

  seventh, seventh_ok := chord_add_interval(triad, MINOR_SEVENTH, context.temp_allocator)
  testing.expect(t, seventh_ok)
  testing.expect_value(t, chord_string(seventh, context.temp_allocator), "C7")

  ninth, ninth_ok := chord_add_interval(seventh, MAJOR_NINTH, context.temp_allocator)
  testing.expect(t, ninth_ok)
  testing.expect_value(t, chord_string(ninth, context.temp_allocator), "C9")

  altered, altered_ok := chord_add_interval(seventh, AUGMENTED_NINTH, context.temp_allocator)
  testing.expect(t, altered_ok)
  testing.expect_value(t, chord_string(altered, context.temp_allocator), "C7#9")
  testing.expect_value(t, intervals_text(altered.intervals), "P1 M3 P5 m7 A9")

  major_seventh, major_seventh_ok := chord_add_interval(seventh, MAJOR_SEVENTH, context.temp_allocator)
  testing.expect(t, major_seventh_ok)
  testing.expect_value(t, chord_string(major_seventh, context.temp_allocator), "Cmaj7")
}

@(test)
test_chord_notes_refuses_an_unspellable_chord :: proc(t: ^testing.T) {
  chord, ok := chord_parse("Cbbdim7", context.temp_allocator)
  testing.expect(t, ok)

  _, notes_ok := chord_notes(chord, false, context.temp_allocator)
  testing.expect(t, !notes_ok)
}

/*
Transposing a chord moves its root and leaves its identity alone, so the symbol
that named it before names it after.
*/
@(test)
test_chord_transposition_moves_the_root_and_the_bass :: proc(t: ^testing.T) {
  expect_transposed :: proc(t: ^testing.T, symbol: string, interval: Interval, expected: string) {
    chord, chord_ok := chord_parse(symbol, context.temp_allocator)
    testing.expectf(t, chord_ok, "%s did not parse", symbol)

    moved, moved_ok := chord_transpose(chord, interval, context.temp_allocator)
    testing.expectf(t, moved_ok, "%s did not transpose", symbol)
    testing.expect_value(t, chord_string(moved, context.temp_allocator), expected)
  }

  expect_transposed(t, "Cmaj7", MINOR_THIRD,     "Ebmaj7")
  expect_transposed(t, "Cmaj7", AUGMENTED_SECOND, "D#maj7")
  expect_transposed(t, "C/E",   MAJOR_SECOND,    "D/F#")
  expect_transposed(t, "Am7",   interval_negate(PERFECT_FIFTH), "Dm7")
}

/*
The property DESIGN.md names: transposing and transposing back returns the chord
that set out, spelling and all. The old model could not pass this, since a
semitone count cannot say which third it meant.
*/
@(test)
test_chord_transposition_is_invertible :: proc(t: ^testing.T) {
  for root in TEST_ROOTS {
    for template in CHORD_TEMPLATES {
      chord := chord_make(root, template, context.temp_allocator)

      for interval in ([]Interval{ MINOR_SECOND, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH }) {
        moved, moved_ok := chord_transpose(chord, interval, context.temp_allocator)
        if !moved_ok {
          continue
        }

        back, back_ok := chord_transpose(moved, interval_negate(interval), context.temp_allocator)
        testing.expect(t, back_ok)
        testing.expectf(
          t,
          chord_equal(back, chord),
          "%s did not survive a round trip through %s",
          chord_string(chord, context.temp_allocator),
          chord_string(moved, context.temp_allocator),
        )
      }
    }
  }
}
