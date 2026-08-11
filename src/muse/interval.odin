package muse

import "core:fmt"
import "core:strconv"
import "core:strings"

/*
A diatonic distance and a chromatic distance, together. Steps counts letter
names traversed, so 0 is a unison, 2 is a third and 7 is an octave; semitones
counts the sound.

Carrying both is what lets muse spell. A major third and a diminished fourth
are four semitones apart either way and differ only in steps, and every
spelling decision in the library reduces to reading those two numbers.
Negative values describe a descending interval.
*/
Interval :: struct {
  steps     : int,
  semitones : int,
}

IntervalQuality :: enum {
  DoublyDiminished,
  Diminished,
  Minor,
  Perfect,
  Major,
  Augmented,
  DoublyAugmented,
}

/*
Semitones above the tonic for each degree of the major scale. This is the
reference every interval quality is measured against.
*/
@(rodata)
MAJOR_SCALE_SEMITONES := [7]int { 0, 2, 4, 5, 7, 9, 11 }

@(rodata)
QUALITY_ABBREVIATIONS := [IntervalQuality]string {
  .DoublyDiminished = "dd",
  .Diminished       = "d",
  .Minor            = "m",
  .Perfect          = "P",
  .Major            = "M",
  .Augmented        = "A",
  .DoublyAugmented  = "AA",
}

@(rodata)
QUALITY_NAMES := [IntervalQuality]string {
  .DoublyDiminished = "doubly diminished",
  .Diminished       = "diminished",
  .Minor            = "minor",
  .Perfect          = "perfect",
  .Major            = "major",
  .Augmented        = "augmented",
  .DoublyAugmented  = "doubly augmented",
}

@(rodata)
ORDINAL_NAMES := [16]string {
  "", "unison", "second", "third", "fourth", "fifth", "sixth", "seventh",
  "octave", "ninth", "tenth", "eleventh", "twelfth", "thirteenth",
  "fourteenth", "fifteenth",
}

UNISON             :: Interval{ 0,  0 }
MINOR_SECOND       :: Interval{ 1,  1 }
MAJOR_SECOND       :: Interval{ 1,  2 }
AUGMENTED_SECOND   :: Interval{ 1,  3 }
MINOR_THIRD        :: Interval{ 2,  3 }
MAJOR_THIRD        :: Interval{ 2,  4 }
PERFECT_FOURTH     :: Interval{ 3,  5 }
AUGMENTED_FOURTH   :: Interval{ 3,  6 }
DIMINISHED_FIFTH   :: Interval{ 4,  6 }
PERFECT_FIFTH      :: Interval{ 4,  7 }
AUGMENTED_FIFTH    :: Interval{ 4,  8 }
MINOR_SIXTH        :: Interval{ 5,  8 }
MAJOR_SIXTH        :: Interval{ 5,  9 }
DIMINISHED_SEVENTH :: Interval{ 6,  9 }
MINOR_SEVENTH      :: Interval{ 6, 10 }
MAJOR_SEVENTH      :: Interval{ 6, 11 }
OCTAVE             :: Interval{ 7, 12 }
MINOR_NINTH        :: Interval{ 8, 13 }
MAJOR_NINTH        :: Interval{ 8, 14 }
AUGMENTED_NINTH    :: Interval{ 8, 15 }
PERFECT_ELEVENTH   :: Interval{10, 17 }
AUGMENTED_ELEVENTH :: Interval{10, 18 }
MINOR_THIRTEENTH   :: Interval{12, 20 }
MAJOR_THIRTEENTH   :: Interval{12, 21 }

/*
Whether a step count names one of the intervals that is perfect rather than
major or minor: unisons, fourths, fifths and their compounds.
*/
interval_is_perfect_number :: proc(steps: int) -> bool {
  switch steps %% 7 {
  case 0, 3, 4: return true
  }
  return false
}

/*
The semitone count of the unaltered interval spanning the given steps, taken
from the major scale and extended by an octave per compound.
*/
interval_reference_semitones :: proc(steps: int) -> int {
  return MAJOR_SCALE_SEMITONES[steps %% 7] + 12 * floor_div(steps, 7)
}

interval_is_descending :: proc(interval: Interval) -> bool {
  if interval.steps != 0 {
    return interval.steps < 0
  }
  return interval.semitones < 0
}

interval_negate :: proc(interval: Interval) -> Interval {
  return Interval{ -interval.steps, -interval.semitones }
}

/*
The ordinal an interval is spoken by: 1 for a unison, 5 for a fifth, 13 for a
thirteenth. Descending intervals report the ordinal of their ascending mirror.
*/
interval_number :: proc(interval: Interval) -> int {
  steps := interval.steps
  if steps < 0 {
    steps = -steps
  }
  return steps + 1
}

/*
Reduce a compound interval to within a single octave, preserving quality. A
major ninth becomes a major second; an octave becomes a unison. Descending
intervals are mirrored first.
*/
interval_simple :: proc(interval: Interval) -> Interval {
  ascending := interval
  if interval_is_descending(interval) {
    ascending = interval_negate(interval)
  }
  octaves := ascending.steps / 7
  return Interval{ ascending.steps - 7 * octaves, ascending.semitones - 12 * octaves }
}

/*
Name an interval's quality by how far its semitone count strays from the
unaltered interval of the same step count. Perfect numbers admit no major or
minor, so they take a shorter ladder.

Returns false past a double alteration, which double accidentals can reach but
notation has no word for.
*/
interval_quality :: proc(interval: Interval) -> (IntervalQuality, bool) {
  ascending := interval
  if interval_is_descending(interval) {
    ascending = interval_negate(interval)
  }

  deviation := ascending.semitones - interval_reference_semitones(ascending.steps)

  if interval_is_perfect_number(ascending.steps) {
    switch deviation {
    case -2: return .DoublyDiminished, true
    case -1: return .Diminished,       true
    case  0: return .Perfect,          true
    case  1: return .Augmented,        true
    case  2: return .DoublyAugmented,  true
    }
    return {}, false
  }

  switch deviation {
  case -3: return .DoublyDiminished, true
  case -2: return .Diminished,       true
  case -1: return .Minor,            true
  case  0: return .Major,            true
  case  1: return .Augmented,        true
  case  2: return .DoublyAugmented,  true
  }
  return {}, false
}

/*
Build an ascending interval from the ordinal a musician says and the quality
they say with it. Returns false for the pairings notation does not have, such
as a minor fifth or a perfect third.

A unison is also refused any quality below perfect. Narrowing a unison does
not produce a smaller ascending interval, it produces a descending one, and
naming that a diminished unison would make it indistinguishable from an
ascending augmented unison.
*/
interval_make :: proc(number: int, quality: IntervalQuality) -> (Interval, bool) {
  if number < 1 {
    return {}, false
  }
  if number == 1 && (quality == .Diminished || quality == .DoublyDiminished) {
    return {}, false
  }

  steps      := number - 1
  is_perfect := interval_is_perfect_number(steps)

  deviation: int
  switch quality {
  case .DoublyDiminished:
    deviation = is_perfect ? -2 : -3
  case .Diminished:
    deviation = is_perfect ? -1 : -2
  case .Minor:
    if is_perfect {
      return {}, false
    }
    deviation = -1
  case .Perfect:
    if !is_perfect {
      return {}, false
    }
  case .Major:
    if is_perfect {
      return {}, false
    }
  case .Augmented:
    deviation = 1
  case .DoublyAugmented:
    deviation = 2
  }

  return Interval{ steps, interval_reference_semitones(steps) + deviation }, true
}

/*
The interval from one note to another, taken upward. With no octave to work
from the step count wraps within one, but the semitone count is derived from
the letters and their alterations rather than from pitch classes, so C to B#
is the augmented seventh it is spelled as and not a unison.
*/
interval_between :: proc(from, to: Note) -> Interval {
  steps   := (int(to.letter) - int(from.letter)) %% 7
  natural := (LETTER_SEMITONES[to.letter] - LETTER_SEMITONES[from.letter]) %% 12
  return Interval{ steps, natural + to.alteration - from.alteration }
}

/*
The exact interval between two pitches, signed and compound. Descending when
the second pitch is the lower.
*/
pitch_interval_between :: proc(from, to: Pitch) -> Interval {
  from_steps := int(from.note.letter) + 7 * from.octave
  to_steps   := int(to.note.letter)   + 7 * to.octave
  return Interval{ to_steps - from_steps, pitch_midi(to) - pitch_midi(from) }
}

/*
The short form of an interval: M3, P5, m9, and a leading minus when
descending. Returns false for intervals with no nameable quality.
*/
interval_abbreviation :: proc(interval: Interval, allocator := context.allocator) -> (string, bool) {
  quality, ok := interval_quality(interval)
  if !ok {
    return "", false
  }

  sign := interval_is_descending(interval) ? "-" : ""
  return fmt.aprintf(
    "%s%s%d",
    sign,
    QUALITY_ABBREVIATIONS[quality],
    interval_number(interval),
    allocator = allocator,
  ), true
}

/*
The spoken form of an interval, such as "minor third" or "descending perfect
fifth". Returns false for intervals with no nameable quality.
*/
interval_name :: proc(interval: Interval, allocator := context.allocator) -> (string, bool) {
  quality, ok := interval_quality(interval)
  if !ok {
    return "", false
  }

  number  := interval_number(interval)
  ordinal := number < len(ORDINAL_NAMES) \
    ? ORDINAL_NAMES[number] \
    : fmt.tprintf("%d%s", number, ordinal_suffix(number))

  prefix := interval_is_descending(interval) ? "descending " : ""

  if number == 1 && quality == .Perfect {
    return fmt.aprintf("%s%s", prefix, ordinal, allocator = allocator), true
  }
  return fmt.aprintf("%s%s %s", prefix, QUALITY_NAMES[quality], ordinal, allocator = allocator), true
}

/*
Read an interval from the forms a musician writes it in: M3, m7, P5, A4, d5,
dd7, AA4, the word forms maj/min/perf/aug/dim, a bare number for the
unaltered interval, and the chord-symbol shorthand b5 and #11.

The shorthand and the quality letters are not the same thing. b lowers the
unaltered interval by a semitone, so b3 is a minor third, while d names a true
diminished interval, so d3 is two semitones. A leading minus reads descending.
*/
interval_parse :: proc(token: string) -> (Interval, bool) {
  text       := token
  descending := false

  if strings.has_prefix(text, "-") {
    descending = true
    text       = text[1:]
  } else if strings.has_prefix(text, "+") {
    text = text[1:]
  }

  digits_at := 0
  for digits_at < len(text) && !is_digit(text[digits_at]) {
    digits_at += 1
  }
  if digits_at == len(text) {
    return {}, false
  }
  for index in digits_at ..< len(text) {
    if !is_digit(text[index]) {
      return {}, false
    }
  }

  number, number_ok := strconv.parse_int(text[digits_at:], 10)
  if !number_ok || number < 1 {
    return {}, false
  }

  is_perfect := interval_is_perfect_number(number - 1)

  quality: IntervalQuality
  switch text[:digits_at] {
  case "":                   quality = is_perfect ? .Perfect : .Major
  case "P", "p", "perf":     quality = .Perfect
  case "M", "maj":           quality = .Major
  case "m", "min":           quality = .Minor
  case "A", "a", "aug":      quality = .Augmented
  case "d", "dim":           quality = .Diminished
  case "AA", "aa":           quality = .DoublyAugmented
  case "dd":                 quality = .DoublyDiminished
  case "#":                  quality = .Augmented
  case "##", "x":            quality = .DoublyAugmented
  case "b":                  quality = is_perfect ? .Diminished       : .Minor
  case "bb":                 quality = is_perfect ? .DoublyDiminished : .Diminished
  case:                      return {}, false
  }

  interval, ok := interval_make(number, quality)
  if !ok {
    return {}, false
  }
  if descending {
    interval = interval_negate(interval)
  }
  return interval, true
}

@(private)
is_digit :: proc(character: u8) -> bool {
  return character >= '0' && character <= '9'
}

@(private)
ordinal_suffix :: proc(number: int) -> string {
  if number %% 100 < 11 || number %% 100 > 13 {
    switch number %% 10 {
    case 1: return "st"
    case 2: return "nd"
    case 3: return "rd"
    }
  }
  return "th"
}
