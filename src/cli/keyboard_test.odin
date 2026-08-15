package main

import "core:strings"
import "core:testing"

import "../muse"

/*
The drawings PLAN.md fixes, without the line that heads them. Comparing them
verbatim is what enforces the anatomy: black keys straddling a boundary, none
between E and F or between B and C, and a press in the exposed foot of a white
key or in place of the face of a black one.
*/
KEYBOARD_C :: `_____________________________
|  |#| |#|  |  |#| |#| |#|  |
|  |#| |#|  |  |#| |#| |#|  |
|  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |
|_*_|___|_*_|___|_*_|___|___|
  C   D   E   F   G   A   B
`

KEYBOARD_C7 :: `_____________________________
|  |#| |#|  |  |#| |#| |*|  |
|  |#| |#|  |  |#| |#| |*|  |
|  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |
|_*_|___|_*_|___|_*_|___|___|
  C   D   E   F   G   A   B
`

KEYBOARD_DROP2 :: `_________________________________________________________
|  |#| |#|  |  |#| |#| |#|  |  |#| |#|  |  |#| |#| |#|  |
|  |#| |#|  |  |#| |#| |#|  |  |#| |#|  |  |#| |#| |#|  |
|  |_| |_|  |  |_| |_| |_|  |  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |   |   |   |   |   |   |   |
|___|___|___|___|_*_|___|___|_*_|___|_*_|___|___|___|_*_|
  C3  D   E   F   G   A   B   C4  D   E   F   G   A   B
`

/*
The drawing a datum makes, headed by the line it came in on.
*/
@(private = "file")
drawn :: proc(t: ^testing.T, text: string, arguments: []string, colored := false) -> string {
  options, _, options_ok := options_parse(arguments, context.temp_allocator)
  testing.expect(t, options_ok)

  written, token, error := keyboard_text([]string{ text }, options, colored, context.temp_allocator)
  testing.expectf(t, error == .None, "%s: %v", token, error)
  return written
}

/*
The pitch classes a drawing marks, read back off the characters. The header is
skipped and nothing else needs to be: no other row can carry a star.
*/
@(private = "file")
keyboard_marked :: proc(text: string) -> (marked: [12]bool) {
  classes : [KEYBOARD_OCTAVE_COLUMNS]int
  for column, pitch_class in keyboard_columns() {
    classes[column] = pitch_class
  }

  rest := text
  _, _ = strings.split_lines_iterator(&rest)

  for line in strings.split_lines_iterator(&rest) {
    for character, column in line {
      if character == '*' {
        marked[classes[column %% KEYBOARD_OCTAVE_COLUMNS]] = true
      }
    }
  }
  return marked
}

/*
The three drawings PLAN.md fixes, compared verbatim.

The header is where the spelling lives, since a drawing can only show a pitch
class. A chord's symbol is not its notes so they follow it; a voicing carries its
pitches in field one already, so nothing follows that.
*/
@(test)
test_the_keyboard_is_drawn_as_the_plan_fixes_it :: proc(t: ^testing.T) {
  testing.expect_value(t, drawn(t, "C", []string{ "keys" }), strings.concatenate(
    []string{ "C\tC E G\n", KEYBOARD_C }, context.temp_allocator,
  ))

  testing.expect_value(t, drawn(t, "C7", []string{ "keys" }), strings.concatenate(
    []string{ "C7\tC E G Bb\n", KEYBOARD_C7 }, context.temp_allocator,
  ))

  testing.expect_value(t, drawn(t, "G3 C4 E4 B4", []string{ "keys" }), strings.concatenate(
    []string{ "G3 C4 E4 B4\n", KEYBOARD_DROP2 }, context.temp_allocator,
  ))
}

/*
A drawing marks the keys the datum sounds and no others, over every template on
all twelve roots. A keyboard that marks a key the chord does not hold is the one
failure nobody would notice by looking.

Both realizations are drawn, so --literal reaches this sink as it reaches the
others: the eleventh C13 drops is unmarked without the flag and marked with it.
*/
@(test)
test_a_keyboard_marks_the_keys_its_datum_sounds :: proc(t: ^testing.T) {
  roots := []string{ "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

  for spelling in roots {
    root, root_ok := muse.note_parse(spelling)
    testing.expectf(t, root_ok, "%s did not parse", spelling)

    for template in muse.CHORD_TEMPLATES {
      chord  := muse.chord_make(root, template, context.temp_allocator)
      symbol := muse.chord_string(chord, context.temp_allocator)

      for literal in ([2]bool{ false, true }) {
        arguments := literal ? []string{ "keys", "--literal" } : []string{ "keys" }

        notes, notes_ok := muse.chord_notes(chord, literal, context.temp_allocator)
        if !testing.expectf(t, notes_ok, "%s could not be spelled", symbol) {
          continue
        }

        expected : [12]bool
        for note in notes {
          expected[muse.note_pitch_class(note)] = true
        }

        testing.expectf(
          t,
          keyboard_marked(drawn(t, symbol, arguments)) == expected,
          "%s marks keys it does not sound", symbol,
        )
      }
    }
  }
}

/*
A keyboard of two octaves is the one-octave drawing twice, less the edge they
share. The label row is the exception, since it is trimmed on the right and an
octave in the middle of a run has nothing to trim.
*/
@(test)
test_an_octave_is_the_same_drawing_repeated :: proc(t: ^testing.T) {
  draw :: proc(octaves: int) -> []string {
    builder := strings.builder_make(context.temp_allocator)
    keyboard_draw(&builder, make([]bool, keyboard_width(octaves), context.temp_allocator), nil)
    return strings.split_lines(strings.to_string(builder), context.temp_allocator)
  }

  one := draw(1)
  two := draw(2)
  testing.expect_value(t, len(one), len(two))

  for line, index in one[:len(one) - 2] {
    testing.expect_value(t, len(line), keyboard_width(1))
    testing.expect_value(t, two[index], strings.concatenate(
      []string{ line, line[1:] }, context.temp_allocator,
    ))
  }
}

/*
The drawing has a fixed width and never reflows, so a pipe and a terminal differ
in color and in nothing else. Color reaches the header alone, which is the same
guarantee every other command's field one already has.
*/
@(test)
test_a_keyboard_does_not_reflow :: proc(t: ^testing.T) {
  plain   := drawn(t, "C", []string{ "keys" })
  colored := drawn(t, "C", []string{ "keys" }, true)

  testing.expect(t, strings.contains(colored, DIM))

  stripped, _ := strings.remove_all(colored, DIM, context.temp_allocator)
  stripped, _  = strings.remove_all(stripped, RESET, context.temp_allocator)
  testing.expect_value(t, stripped, plain)

  drawing := colored[strings.index_byte(colored, '\n') + 1:]
  testing.expect(t, !strings.contains(drawing, "\e"))

  bare := drawn(t, "C", []string{ "keys", "--plain" })
  testing.expect(t, strings.has_prefix(bare, "C\n"))
}

/*
No line of a drawing ends in whitespace, at either width.
*/
@(test)
test_a_keyboard_carries_no_trailing_whitespace :: proc(t: ^testing.T) {
  for text in ([]string{ "C", "G3 C4 E4 B4" }) {
    written := drawn(t, text, []string{ "keys" })

    rest := written
    for line in strings.split_lines_iterator(&rest) {
      testing.expectf(t, line == strings.trim_right_space(line), "%q ends in whitespace", line)
    }
  }
}

/*
A keyboard to a datum, separated by a blank line, and nothing written at all when
a line in the middle of the input fails -- the rule every sink follows.
*/
@(test)
test_keys_writes_nothing_when_a_line_fails :: proc(t: ^testing.T) {
  options, _, _ := options_parse([]string{ "keys" }, context.temp_allocator)

  pair, _, error := keyboard_text([]string{ "C", "Am" }, options, false, context.temp_allocator)
  testing.expect_value(t, error, SinkError.None)
  testing.expect(t, strings.contains(pair, "\n\nAm\tA C E\n"))

  written, token, failure := keyboard_text(
    []string{ "C", "Hmm" }, options, false, context.temp_allocator,
  )
  testing.expect_value(t, failure, SinkError.NotNotation)
  testing.expect_value(t, token, "Hmm")
  testing.expect_value(t, len(written), 0)
}
