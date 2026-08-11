package muse

/*
A letter name is the diatonic identity of a note, independent of any
alteration. The ordering is C-first so that a letter index doubles as a
position within an octave: octaves turn over between B and C.
*/
Letter :: enum u8 {
  C, D, E, F, G, A, B,
}

/*
Notation carries at most two accidentals in either direction. Anything beyond
that is unspellable rather than merely unusual, and the arithmetic procs
report it instead of inventing a spelling.
*/
MAX_ALTERATION :: 2

@(rodata)
LETTER_SEMITONES := [Letter]int {
  .C = 0,
  .D = 2,
  .E = 4,
  .F = 5,
  .G = 7,
  .A = 9,
  .B = 11,
}

/*
A letter name plus an alteration in semitones, flats negative. There is no
octave and no frequency here: Note is a pitch class with its spelling intact,
so that Eb and D# remain distinguishable.
*/
Note :: struct {
  letter     : Letter,
  alteration : int,
}

/*
A Note placed in an octave, numbered by scientific pitch notation where C4 is
middle C. The octave belongs to the letter rather than to the sounding pitch,
which is what makes B#3 and Cb4 land in the octaves a musician expects.
*/
Pitch :: struct {
  note   : Note,
  octave : int,
}

/*
The pitch class of a note, 0 through 11 with C as 0. Wrapping keeps Cb at 11
rather than -1.
*/
note_pitch_class :: proc(note: Note) -> int {
  return (LETTER_SEMITONES[note.letter] + note.alteration) %% 12
}

/*
Whether two notes sound alike, regardless of how they are spelled.
*/
note_enharmonic :: proc(a, b: Note) -> bool {
  return note_pitch_class(a) == note_pitch_class(b)
}

/*
Transpose a note by an interval. The interval's step count selects the letter
and its semitone count then determines the only alteration that reaches the
required sound, so the spelling is computed rather than preferred: C up a
minor third is Eb, and C up an augmented second is D#.

Returns false when the result would need more than a double accidental.
*/
note_add_interval :: proc(note: Note, interval: Interval) -> (result: Note, ok: bool) {
  letter := Letter((int(note.letter) + interval.steps) %% 7)
  target := (note_pitch_class(note) + interval.semitones) %% 12

  alteration := (target - LETTER_SEMITONES[letter]) %% 12
  if alteration > 6 {
    alteration -= 12
  }
  if alteration < -MAX_ALTERATION || alteration > MAX_ALTERATION {
    return {}, false
  }

  return Note{ letter = letter, alteration = alteration }, true
}

/*
The MIDI note number of a pitch, where C4 is 60. Reading the octave off the
letter means B#3 is 60 and Cb4 is 59 without a boundary case.
*/
pitch_midi :: proc(pitch: Pitch) -> int {
  return (pitch.octave + 1) * 12 + LETTER_SEMITONES[pitch.note.letter] + pitch.note.alteration
}

/*
Transpose a pitch by an interval, carrying the octave when the letter sequence
crosses C. Unlike note_add_interval this keeps compound intervals distinct: a
ninth moves the pitch further than a second.

Returns false when the result would need more than a double accidental.
*/
pitch_add_interval :: proc(pitch: Pitch, interval: Interval) -> (result: Pitch, ok: bool) {
  letter_index := int(pitch.note.letter) + interval.steps
  letter       := Letter(letter_index %% 7)
  octave       := pitch.octave + floor_div(letter_index, 7)

  natural    := (octave + 1) * 12 + LETTER_SEMITONES[letter]
  alteration := pitch_midi(pitch) + interval.semitones - natural
  if alteration < -MAX_ALTERATION || alteration > MAX_ALTERATION {
    return {}, false
  }

  return Pitch{ note = { letter = letter, alteration = alteration }, octave = octave }, true
}

/*
Order two pitches by sounding height, falling back to spelling so that
enharmonic pitches sort consistently. Negative when a is lower.
*/
pitch_compare :: proc(a, b: Pitch) -> int {
  if difference := pitch_midi(a) - pitch_midi(b); difference != 0 {
    return difference
  }
  return int(a.note.letter) - int(b.note.letter)
}

/*
Integer division rounding toward negative infinity, which Odin's / does not do.
Descending intervals depend on it to select the octave below.
*/
@(private)
floor_div :: proc(numerator, denominator: int) -> int {
  quotient  := numerator / denominator
  remainder := numerator % denominator
  if remainder != 0 && (remainder < 0) != (denominator < 0) {
    quotient -= 1
  }
  return quotient
}
