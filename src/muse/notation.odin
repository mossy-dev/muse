package muse

import "core:fmt"
import "core:strconv"
import "core:unicode/utf8"

@(rodata)
LETTER_CHARACTERS := [Letter]rune {
  .C = 'C',
  .D = 'D',
  .E = 'E',
  .F = 'F',
  .G = 'G',
  .A = 'A',
  .B = 'B',
}

/*
The printed form of an alteration, indexed by the alteration offset by
MAX_ALTERATION. Unicode accidentals are read but never written: one ASCII
spelling per sound keeps output comparable and keeps a terminal that cannot
render 𝄪 out of the picture.
*/
@(rodata)
ALTERATION_SPELLINGS := [2 * MAX_ALTERATION + 1]string { "bb", "b", "", "#", "##" }

/*
Read a note name: C, F#, Bb, Gbb, Cx. Accidentals may be given as ASCII or as
their Unicode signs, and x is accepted for a double sharp.

Returns false for anything the letter and accidental grammar does not cover,
which includes mixed accidentals such as C#b and any trailing text.
*/
note_parse :: proc(token: string) -> (Note, bool) {
  note, remainder, ok := note_prefix_parse(token)
  if !ok || len(remainder) != 0 {
    return {}, false
  }
  return note, true
}

/*
Read a pitch name: C4, F#-1, Bb10. The octave is a signed decimal integer and
is required, so pitch_parse never succeeds on a bare note name.
*/
pitch_parse :: proc(token: string) -> (Pitch, bool) {
  note, remainder, note_ok := note_prefix_parse(token)
  if !note_ok {
    return {}, false
  }

  digits := remainder
  if len(digits) > 0 && digits[0] == '-' {
    digits = digits[1:]
  }
  if len(digits) == 0 {
    return {}, false
  }
  for index in 0 ..< len(digits) {
    if !is_digit(digits[index]) {
      return {}, false
    }
  }

  octave, octave_ok := strconv.parse_int(remainder, 10)
  if !octave_ok {
    return {}, false
  }
  return Pitch{ note = note, octave = octave }, true
}

note_string :: proc(note: Note, allocator := context.allocator) -> string {
  return fmt.aprintf(
    "%r%s",
    LETTER_CHARACTERS[note.letter],
    ALTERATION_SPELLINGS[note.alteration + MAX_ALTERATION],
    allocator = allocator,
  )
}

pitch_string :: proc(pitch: Pitch, allocator := context.allocator) -> string {
  return fmt.aprintf(
    "%r%s%d",
    LETTER_CHARACTERS[pitch.note.letter],
    ALTERATION_SPELLINGS[pitch.note.alteration + MAX_ALTERATION],
    pitch.octave,
    allocator = allocator,
  )
}

/*
Read a letter and its accidentals off the front of a token and return whatever
follows them. Chord and pitch notation both begin this way, and both need to
know where the note ended rather than only whether the whole token was one.

Accidentals must agree in direction and must not exceed a double, so C#b and
Cbbb are rejected here rather than by the caller.
*/
@(private)
note_prefix_parse :: proc(token: string) -> (note: Note, remainder: string, ok: bool) {
  if len(token) == 0 {
    return {}, "", false
  }

  letter, letter_ok := letter_parse(token[0])
  if !letter_ok {
    return {}, "", false
  }

  alteration := 0
  index      := 1
  for index < len(token) {
    character, width := utf8.decode_rune_in_string(token[index:])
    value, is_accidental := accidental_value(character)
    if !is_accidental {
      break
    }
    if alteration != 0 && (value < 0) != (alteration < 0) {
      return {}, "", false
    }
    alteration += value
    index      += width
  }
  if alteration < -MAX_ALTERATION || alteration > MAX_ALTERATION {
    return {}, "", false
  }

  return Note{ letter = letter, alteration = alteration }, token[index:], true
}

@(private)
letter_parse :: proc(character: u8) -> (Letter, bool) {
  switch character {
  case 'A': return .A, true
  case 'B': return .B, true
  case 'C': return .C, true
  case 'D': return .D, true
  case 'E': return .E, true
  case 'F': return .F, true
  case 'G': return .G, true
  }
  return {}, false
}

@(private)
accidental_value :: proc(character: rune) -> (int, bool) {
  switch character {
  case '#', '♯':  return  1, true
  case 'b', '♭':  return -1, true
  case 'x', '𝄪':  return  2, true
  case '𝄫':       return -2, true
  }
  return 0, false
}
