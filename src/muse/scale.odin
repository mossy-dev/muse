package muse

import "core:fmt"
import "core:slice"
import "core:strings"

/*
A root and the intervals from it, ascending and excluding the octave. Like
Chord, a Scale stores intervals rather than notes, so its notes are spelled on
demand and a transposed scale keeps its spelling by arithmetic rather than by
preference.
*/
Scale :: struct {
  root      : Note,
  name      : string,
  intervals : []Interval,
}

/*
One named interval pattern. A scale name is a word rather than a grammar, so
unlike ChordTemplate this carries its aliases: there is nothing to derive them
from.
*/
ScaleTemplate :: struct {
  name      : string,
  aliases   : []string,
  intervals : []Interval,
}

@(rodata)
SCALE_TEMPLATES := []ScaleTemplate {
  {
    "major", { "ionian", "maj" },
    { UNISON, MAJOR_SECOND, MAJOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MAJOR_SIXTH, MAJOR_SEVENTH },
  },
  {
    "minor", { "natural minor", "aeolian", "min" },
    { UNISON, MAJOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MINOR_SIXTH, MINOR_SEVENTH },
  },
  {
    "harmonic minor", { "harmonic" },
    { UNISON, MAJOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MINOR_SIXTH, MAJOR_SEVENTH },
  },
  {
    "melodic minor", { "melodic" },
    { UNISON, MAJOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MAJOR_SIXTH, MAJOR_SEVENTH },
  },
  {
    "dorian", {},
    { UNISON, MAJOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MAJOR_SIXTH, MINOR_SEVENTH },
  },
  {
    "phrygian", {},
    { UNISON, MINOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MINOR_SIXTH, MINOR_SEVENTH },
  },
  {
    "lydian", {},
    { UNISON, MAJOR_SECOND, MAJOR_THIRD, AUGMENTED_FOURTH, PERFECT_FIFTH, MAJOR_SIXTH, MAJOR_SEVENTH },
  },
  {
    "mixolydian", {},
    { UNISON, MAJOR_SECOND, MAJOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MAJOR_SIXTH, MINOR_SEVENTH },
  },
  {
    "locrian", {},
    { UNISON, MINOR_SECOND, MINOR_THIRD, PERFECT_FOURTH, DIMINISHED_FIFTH, MINOR_SIXTH, MINOR_SEVENTH },
  },
  {
    "major pentatonic", { "majpent", "pentatonic" },
    { UNISON, MAJOR_SECOND, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SIXTH },
  },
  {
    "minor pentatonic", { "minpent" },
    { UNISON, MINOR_THIRD, PERFECT_FOURTH, PERFECT_FIFTH, MINOR_SEVENTH },
  },
  {
    "blues", {},
    { UNISON, MINOR_THIRD, PERFECT_FOURTH, DIMINISHED_FIFTH, PERFECT_FIFTH, MINOR_SEVENTH },
  },
  {
    "chromatic", {},
    {
      UNISON, AUGMENTED_UNISON, MAJOR_SECOND, AUGMENTED_SECOND, MAJOR_THIRD, PERFECT_FOURTH,
      AUGMENTED_FOURTH, PERFECT_FIFTH, AUGMENTED_FIFTH, MAJOR_SIXTH, AUGMENTED_SIXTH, MAJOR_SEVENTH,
    },
  },
}

/*
Roman numerals for scale degrees. Twelve is every degree a scale in this library
can have, since the chromatic scale is the longest one there is.
*/
@(rodata)
ROMAN_NUMERALS := [12]string {
  "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII",
}

/*
One degree of a harmonized scale: the notes the stack produced, and the chord
they name where they name one. A stack that no template matches is not a
failure -- the notes are a legitimate datum, and DESIGN.md's rule is that the
line carries them rather than going missing.
*/
Harmony :: struct {
  notes : []Note,
  chord : Maybe(Chord),
}

/*
Build a scale on a root from a template row, copying rather than borrowing.
*/
scale_make :: proc(root: Note, template: ScaleTemplate, allocator := context.allocator) -> Scale {
  return Scale {
    root      = root,
    name      = strings.clone(template.name, allocator),
    intervals = slice.clone(template.intervals, allocator),
  }
}

/*
The notes of a scale, ascending from the root.

Returns the 1-based degree that failed and false when a note needs more than a
double accidental. G## harmonic minor wants an F###, and saying which degree ran
out of accidentals is the difference between a precise no and a shrug.
*/
scale_notes :: proc(scale: Scale, allocator := context.allocator) -> (notes: []Note, degree: int, ok: bool) {
  spelled := make([dynamic]Note, 0, len(scale.intervals), allocator)

  for interval, index in scale.intervals {
    note, note_ok := note_add_interval(scale.root, interval)
    if !note_ok {
      delete(spelled)
      return nil, index + 1, false
    }
    append(&spelled, note)
  }

  return spelled[:], 0, true
}

/*
The same scale on an enharmonic root that spells, for a root that does not.
G## harmonic minor is unspellable and A harmonic minor is the same sound, so
that is the suggestion; the caller offers it and never applies it, because
`muse scale G## harmonic` asked a precise question.

Returns false when no enharmonic root spells either.
*/
scale_respell :: proc(scale: Scale, allocator := context.allocator) -> (Scale, bool) {
  pitch_class := note_pitch_class(scale.root)

  best      : Note
  best_found := false

  for letter in Letter {
    alteration := (pitch_class - LETTER_SEMITONES[letter]) %% 12
    if alteration > 6 {
      alteration -= 12
    }
    if alteration < -MAX_ALTERATION || alteration > MAX_ALTERATION {
      continue
    }

    candidate := Note{ letter = letter, alteration = alteration }
    if candidate == scale.root {
      continue
    }
    if best_found && abs(alteration) >= abs(best.alteration) {
      continue
    }

    trial := Scale{ root = candidate, name = scale.name, intervals = scale.intervals }
    if _, _, ok := scale_notes(trial, context.temp_allocator); !ok {
      continue
    }

    best       = candidate
    best_found = true
  }

  if !best_found {
    return {}, false
  }

  return Scale {
    root      = best,
    name      = strings.clone(scale.name, allocator),
    intervals = slice.clone(scale.intervals, allocator),
  }, true
}

/*
The same scale on a root moved by an interval. The template is untouched, so the
spelling of every degree follows from the new root by the same arithmetic that
spelled the old one, and transposing back returns the scale that set out.

Returns false when the new root itself needs more than a double accidental. A
root that spells but leaves a degree that does not is scale_notes' answer to
give, since it is the one that knows which degree ran out.
*/
scale_transpose :: proc(scale: Scale, interval: Interval, allocator := context.allocator) -> (Scale, bool) {
  root, root_ok := note_add_interval(scale.root, interval)
  if !root_ok {
    return {}, false
  }

  return Scale {
    root      = root,
    name      = strings.clone(scale.name, allocator),
    intervals = slice.clone(scale.intervals, allocator),
  }, true
}

/*
Read a scale name: a root, a space, and a template name or one of its aliases.
The name is matched without regard to case, so "G Major" and "g major" differ
only in the root, which is case sensitive because note letters are.

There is no default name here. `muse scale G` means G major, but that default
belongs to the command that has an argument missing, not to a parser that would
then read a bare chord symbol as a scale.
*/
scale_parse :: proc(text: string, allocator := context.allocator) -> (Scale, bool) {
  space := strings.index_byte(text, ' ')
  if space < 0 {
    return {}, false
  }

  root, root_ok := note_parse(text[:space])
  if !root_ok {
    return {}, false
  }

  name := strings.to_lower(strings.trim_space(text[space + 1:]), context.temp_allocator)
  template, template_ok := scale_template_match(name)
  if !template_ok {
    return {}, false
  }

  return scale_make(root, template, allocator), true
}

scale_string :: proc(scale: Scale, allocator := context.allocator) -> string {
  return fmt.aprintf(
    "%s %s",
    note_string(scale.root, context.temp_allocator),
    scale.name,
    allocator = allocator,
  )
}

/*
Stack alternating scale members from a degree, size notes high, and name the
result. This is what makes a diatonic chord table unnecessary: for a seven-note
scale, alternating members are thirds, and the chord that comes out is the one
the scale already contained.

Stacking stops early rather than repeating a note, so a six-note blues scale
harmonizes into three-note chords however large a size is asked for.

degree is 1-based. Returns false for a degree outside the scale, and for a scale
whose notes cannot be spelled.
*/
scale_chord_at :: proc(scale: Scale, degree: int, size: int, allocator := context.allocator) -> (Harmony, bool) {
  members, _, members_ok := scale_notes(scale, context.temp_allocator)
  if !members_ok {
    return {}, false
  }
  if degree < 1 || degree > len(members) || size < 1 {
    return {}, false
  }

  return scale_stack(members, degree, size, allocator), true
}

/*
Harmonize every degree of a scale, one Harmony per degree in scale order.
*/
scale_harmonize :: proc(scale: Scale, size: int, allocator := context.allocator) -> ([]Harmony, bool) {
  members, _, members_ok := scale_notes(scale, context.temp_allocator)
  if !members_ok || size < 1 {
    return nil, false
  }

  harmonies := make([]Harmony, len(members), allocator)
  for degree in 1 ..= len(members) {
    harmonies[degree - 1] = scale_stack(members, degree, size, allocator)
  }

  return harmonies, true
}

/*
The roman numeral for a degree, cased and suffixed by what the notes stacked on
it turned out to be: lower case for a minor third, ° and ø and + for the fifths
that name themselves, and the seventh spelled out where there is one.

Read from the notes rather than from a chord symbol, so a stack no template
names still gets its numeral.
*/
scale_degree_label :: proc(degree: int, notes: []Note, allocator := context.allocator) -> string {
  numeral := ROMAN_NUMERALS[degree - 1]
  if len(notes) == 0 {
    return strings.clone(numeral, allocator)
  }

  third,   has_third   := notes_interval_at_steps(notes, 2)
  fifth,   has_fifth   := notes_interval_at_steps(notes, 4)
  seventh, has_seventh := notes_interval_at_steps(notes, 6)

  if has_third && third == MINOR_THIRD {
    numeral = strings.to_lower(numeral, context.temp_allocator)
  }

  seventh_suffix := ""
  if has_seventh && seventh == MAJOR_SEVENTH {
    seventh_suffix = "maj7"
  } else if has_seventh && seventh == MINOR_SEVENTH {
    seventh_suffix = "7"
  }

  fifth_suffix := ""
  if has_fifth && fifth == DIMINISHED_FIFTH {
    fifth_suffix   = has_seventh && seventh == MINOR_SEVENTH ? "ø" : "°"
    seventh_suffix = has_seventh ? "7" : ""
  } else if has_fifth && fifth == AUGMENTED_FIFTH {
    fifth_suffix = "+"
  }

  return fmt.aprintf("%s%s%s", numeral, fifth_suffix, seventh_suffix, allocator = allocator)
}

/*
Name the scale a set of notes forms, rooted at the first note supplied. Input
order carries the tonic, so C D E F G A B is C major and never A minor.
*/
scale_identify :: proc(notes: []Note, allocator := context.allocator) -> (Scale, bool) {
  readings := scale_readings(notes, allocator)
  if len(readings) == 0 {
    return {}, false
  }
  return readings[0], true
}

/*
Every scale the same notes spell, rooted on each note in turn and in the order
they were supplied. The first is the answer and the rest are the modal readings
that DESIGN.md keeps as annotation: real, and not what was asked.
*/
scale_readings :: proc(notes: []Note, allocator := context.allocator) -> []Scale {
  readings := make([dynamic]Scale, 0, len(notes), allocator)

  for root in notes {
    template, found := scale_match_at_root(root, notes)
    if !found {
      continue
    }
    append(&readings, scale_make(root, template, allocator))
  }

  return readings[:]
}

scale_equal :: proc(a, b: Scale) -> bool {
  return a.root == b.root && a.name == b.name && intervals_equal(a.intervals, b.intervals)
}

/*
Alternating members from a degree, wrapping around the scale, stopping at size
notes or at the first note that would repeat one already stacked.
*/
@(private)
scale_stack :: proc(members: []Note, degree: int, size: int, allocator := context.allocator) -> Harmony {
  notes := make([dynamic]Note, 0, size, allocator)

  for index in 0 ..< size {
    note := members[(degree - 1 + 2 * index) %% len(members)]
    if slice.contains(notes[:], note) {
      break
    }
    append(&notes, note)
  }

  harmony := Harmony{ notes = notes[:] }
  if chord, ok := chord_identify(notes[:], allocator); ok {
    harmony.chord = chord
  }
  return harmony
}

@(private)
scale_template_match :: proc(name: string) -> (ScaleTemplate, bool) {
  for template in SCALE_TEMPLATES {
    if template.name == name {
      return template, true
    }
    for alias in template.aliases {
      if alias == name {
        return template, true
      }
    }
  }
  return {}, false
}

@(private)
scale_match_at_root :: proc(root: Note, notes: []Note) -> (ScaleTemplate, bool) {
  observed := make([dynamic]Interval, 0, len(notes), context.temp_allocator)
  for note in notes {
    interval := interval_between(root, note)
    if !slice.contains(observed[:], interval) {
      append(&observed, interval)
    }
  }
  intervals_sort(observed[:])

  for template in SCALE_TEMPLATES {
    if intervals_equal(observed[:], template.intervals) {
      return template, true
    }
  }
  return {}, false
}

/*
The interval spanning the given letter steps between the first note of a set and
some later one, which is how a stack of notes is read for its third, fifth and
seventh without being a chord yet.
*/
@(private)
notes_interval_at_steps :: proc(notes: []Note, steps: int) -> (Interval, bool) {
  for note in notes[1:] {
    if interval := interval_between(notes[0], note); interval.steps == steps {
      return interval, true
    }
  }
  return {}, false
}
