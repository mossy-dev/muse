package muse

import "core:testing"

@(test)
test_note_names_round_trip :: proc(t: ^testing.T) {
  for letter in Letter {
    for alteration in -MAX_ALTERATION ..= MAX_ALTERATION {
      note := Note{ letter = letter, alteration = alteration }
      text := note_string(note, context.temp_allocator)

      parsed, ok := note_parse(text)
      testing.expectf(t, ok, "%s did not parse", text)
      testing.expect_value(t, parsed, note)
    }
  }
}

@(test)
test_note_printing_is_ascii :: proc(t: ^testing.T) {
  testing.expect_value(t, note_string(Note{ .C,  0 }, context.temp_allocator), "C")
  testing.expect_value(t, note_string(Note{ .F,  1 }, context.temp_allocator), "F#")
  testing.expect_value(t, note_string(Note{ .B, -1 }, context.temp_allocator), "Bb")
  testing.expect_value(t, note_string(Note{ .G, -2 }, context.temp_allocator), "Gbb")
  testing.expect_value(t, note_string(Note{ .C,  2 }, context.temp_allocator), "C##")
}

@(test)
test_note_parsing_accepts_unicode_and_x :: proc(t: ^testing.T) {
  spellings := []struct{ text: string, note: Note } {
    { "F♯",  Note{ .F,  1 } },
    { "B♭",  Note{ .B, -1 } },
    { "G𝄫",  Note{ .G, -2 } },
    { "C𝄪",  Note{ .C,  2 } },
    { "Cx",  Note{ .C,  2 } },
    { "C♯♯", Note{ .C,  2 } },
    { "B♭♭", Note{ .B, -2 } },
  }

  for spelling in spellings {
    parsed, ok := note_parse(spelling.text)
    testing.expectf(t, ok, "%s did not parse", spelling.text)
    testing.expect_value(t, parsed, spelling.note)
  }
}

@(test)
test_note_parsing_rejects_malformed_input :: proc(t: ^testing.T) {
  rejected := []string{ "H", "C#b", "", "Cb#", "4C", "c", "Cbbb", "C###", "Cx#", "C4", "C 4", "#C" }

  for text in rejected {
    _, ok := note_parse(text)
    testing.expectf(t, !ok, "%q parsed as a note", text)
  }
}

@(test)
test_pitch_names_round_trip :: proc(t: ^testing.T) {
  for letter in Letter {
    for alteration in -MAX_ALTERATION ..= MAX_ALTERATION {
      for octave in -1 ..= 10 {
        pitch := Pitch{ note = { letter = letter, alteration = alteration }, octave = octave }
        text  := pitch_string(pitch, context.temp_allocator)

        parsed, ok := pitch_parse(text)
        testing.expectf(t, ok, "%s did not parse", text)
        testing.expect_value(t, parsed, pitch)
      }
    }
  }
}

@(test)
test_pitch_printing_spells_the_octave_it_is_given :: proc(t: ^testing.T) {
  testing.expect_value(t, pitch_string(Pitch{ Note{ .C, 0 }, 4 },  context.temp_allocator), "C4")
  testing.expect_value(t, pitch_string(Pitch{ Note{ .F, 1 }, -1 }, context.temp_allocator), "F#-1")
  testing.expect_value(t, pitch_string(Pitch{ Note{ .B, -1 }, 10 }, context.temp_allocator), "Bb10")
}

@(test)
test_pitch_parsing_keeps_the_octave_on_the_letter :: proc(t: ^testing.T) {
  b_sharp, b_sharp_ok := pitch_parse("B#3")
  testing.expect(t, b_sharp_ok)
  testing.expect_value(t, pitch_midi(b_sharp), 60)

  c_flat, c_flat_ok := pitch_parse("Cb4")
  testing.expect(t, c_flat_ok)
  testing.expect_value(t, pitch_midi(c_flat), 59)
}

@(test)
test_pitch_parsing_rejects_malformed_input :: proc(t: ^testing.T) {
  rejected := []string{ "C", "H4", "", "C#b4", "4C", "C4.5", "C-", "C+4", "Cb#4", "C4b" }

  for text in rejected {
    _, ok := pitch_parse(text)
    testing.expectf(t, !ok, "%q parsed as a pitch", text)
  }
}
