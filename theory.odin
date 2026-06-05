package muse

import "core:strings"
import "core:fmt"

PitchClass :: enum u8 {
  C, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B
}

Accidental :: enum {
  Natural,
  Sharp,
  Flat,
  DoubleSharp,
  DoubleFlat,
}

ScaleQuality :: enum {
  Major,
  NaturalMinor,
  HarmonicMinor,
  MelodicMinor,
  Dorian,
  Phrygian,
  Lydian,
  Mixolydian,
  Locrian,
  MajorPentatonic,
  MinorPentatonic,
  Blues,
  Chromatic,
}

ChordQuality :: enum {
  Major,
  Minor,
  Diminished,
  Augmented,
  Sus2,
  Sus4,
  MajorSeventh,
  DominantSeventh,
  MinorSeventh,
  MinorMajorSeventh,
  HalfDiminished,
  FullyDiminished,
  AugmentedMajorSev
}

ChordExtension :: enum {
  Triad,
  Seventh,
  Ninth,
  Eleventh,
  Thirteenth,
  Add9,
  Add11,
  PowerChord,
}

ScaleDegree :: enum u8 {
  I   = 1,
  II  = 2,
  III = 3,
  IV  = 4,
  V   = 5,
  VI  = 6,
  VII = 7,
}

Inversion :: enum {
  Root,
  First,
  Second,
  Third,
  Fourth,
  Fifth,
  Sixth,
}

TransposeDirection :: enum { Up, Down }

Note :: struct {
  pitch      : PitchClass,
  accidental : Accidental,
  letter     : u8,
}

Scale :: struct {
  root    : Note,
  quality : ScaleQuality,
  notes   : [12]Note,
  len     : int,
}

Chord :: struct {
  root      : Note,
  bass      : Note,
  quality   : ChordQuality,
  extension : ChordExtension,
  inversion : Inversion,
  notes     : [7]Note,
  len       : int,
  degree    : ScaleDegree,
}

TransposeRequest :: struct {
  degree    : ScaleDegree,
  semitones : int,
}

@(rodata)
SCALE_LENGTHS := [ScaleQuality]int {
  .Major           = 7,
  .NaturalMinor    = 7,
  .HarmonicMinor   = 7,
  .MelodicMinor    = 7,
  .Dorian          = 7,
  .Phrygian        = 7,
  .Lydian          = 7,
  .Mixolydian      = 7,
  .Locrian         = 7,
  .MajorPentatonic = 5,
  .MinorPentatonic = 5,
  .Blues           = 6,
  .Chromatic       = 12,
}

@(rodata)
SCALE_INTERVALS := [ScaleQuality][12]int {
  .Major           = { 0,  2,  4,  5,  7,  9, 11,  0,  0,  0,  0,  0 },
  .NaturalMinor    = { 0,  2,  3,  5,  7,  8, 10,  0,  0,  0,  0,  0 },
  .HarmonicMinor   = { 0,  2,  3,  5,  7,  8, 11,  0,  0,  0,  0,  0 },
  .MelodicMinor    = { 0,  2,  3,  5,  7,  9, 11,  0,  0,  0,  0,  0 },
  .Dorian          = { 0,  2,  3,  5,  7,  9, 10,  0,  0,  0,  0,  0 },
  .Phrygian        = { 0,  1,  3,  5,  7,  8, 10,  0,  0,  0,  0,  0 },
  .Lydian          = { 0,  2,  4,  6,  7,  9, 11,  0,  0,  0,  0,  0 },
  .Mixolydian      = { 0,  2,  4,  5,  7,  9, 10,  0,  0,  0,  0,  0 },
  .Locrian         = { 0,  1,  3,  5,  6,  8, 10,  0,  0,  0,  0,  0 },
  .MajorPentatonic = { 0,  2,  4,  7,  9,  0,  0,  0,  0,  0,  0,  0 },
  .MinorPentatonic = { 0,  3,  5,  7, 10,  0,  0,  0,  0,  0,  0,  0 },
  .Blues           = { 0,  3,  5,  6,  7, 10,  0,  0,  0,  0,  0,  0 },
  .Chromatic       = { 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11 },
}

@(rodata)
CHORD_INTERVALS := [ChordQuality][4]int {
  .Major             = { 0,  4,  7,  0 },
  .Minor             = { 0,  3,  7,  0 },
  .Diminished        = { 0,  3,  6,  0 },
  .Augmented         = { 0,  4,  8,  0 },
  .Sus2              = { 0,  2,  7,  0 },
  .Sus4              = { 0,  5,  7,  0 },
  .MajorSeventh      = { 0,  4,  7,  0 },
  .DominantSeventh   = { 0,  4,  7, 11 },
  .MinorSeventh      = { 0,  3,  7, 10 },
  .MinorMajorSeventh = { 0,  3,  7, 10 },
  .HalfDiminished    = { 0,  3,  6, 11 },
  .FullyDiminished   = { 0,  3,  6,  9 },
  .AugmentedMajorSev = { 0,  4,  8, 11 },
}

@(rodata)
DIATONIC_TRIADS := [ScaleQuality][7]ChordQuality {
  .Major           = { .Major,      .Minor,      .Minor,      .Major,      .Major,      .Minor,      .Diminished },
  .NaturalMinor    = { .Minor,      .Diminished, .Major,      .Minor,      .Minor,      .Major,      .Major      },
  .HarmonicMinor   = { .Minor,      .Diminished, .Augmented,  .Minor,      .Major,      .Major,      .Diminished },
  .MelodicMinor    = { .Minor,      .Minor,      .Augmented,  .Major,      .Major,      .Diminished, .Diminished },
  .Dorian          = { .Minor,      .Minor,      .Major,      .Major,      .Minor,      .Diminished, .Major      },
  .Phrygian        = { .Minor,      .Major,      .Major,      .Minor,      .Diminished, .Major,      .Minor      },
  .Lydian          = { .Major,      .Major,      .Minor,      .Diminished, .Major,      .Minor,      .Minor      },
  .Mixolydian      = { .Major,      .Minor,      .Diminished, .Major,      .Minor,      .Minor,      .Major      },
  .Locrian         = { .Diminished, .Major,      .Minor,      .Minor,      .Major,      .Major,      .Minor      },
  .MajorPentatonic = {},
  .MinorPentatonic = {},
  .Blues           = {},
  .Chromatic       = {},
}

@(rodata)
DIATONIC_SEVENTHS := [ScaleQuality][7]ChordQuality {
  .Major           = { .MajorSeventh,      .MinorSeventh,    .MinorSeventh,      .MajorSeventh,    .DominantSeventh, .MinorSeventh,    .HalfDiminished  },
  .NaturalMinor    = { .MinorSeventh,      .HalfDiminished,  .MajorSeventh,      .MinorSeventh,    .MinorSeventh,    .MajorSeventh,    .DominantSeventh },
  .HarmonicMinor   = { .MinorMajorSeventh, .HalfDiminished,  .AugmentedMajorSev, .MinorSeventh,    .DominantSeventh, .MajorSeventh,    .FullyDiminished },
  .MelodicMinor    = { .MinorMajorSeventh, .MinorSeventh,    .AugmentedMajorSev, .DominantSeventh, .DominantSeventh, .HalfDiminished,  .HalfDiminished  },
  .Dorian          = { .MinorSeventh,      .MinorSeventh,    .MajorSeventh,      .DominantSeventh, .MinorSeventh,    .HalfDiminished,  .MajorSeventh    },
  .Phrygian        = { .MinorSeventh,      .MajorSeventh,    .DominantSeventh,   .MinorSeventh,    .HalfDiminished,  .MajorSeventh,    .MinorSeventh    },
  .Lydian          = { .MajorSeventh,      .DominantSeventh, .MinorSeventh,      .HalfDiminished,  .MajorSeventh,    .MinorSeventh,    .MinorSeventh    },
  .Mixolydian      = { .DominantSeventh,   .MinorSeventh,    .HalfDiminished,    .MajorSeventh,    .MinorSeventh,    .MinorSeventh,    .MajorSeventh    },
  .Locrian         = { .HalfDiminished,    .MajorSeventh,    .MinorSeventh,      .MinorSeventh,    .MajorSeventh,    .DominantSeventh, .MinorSeventh    },
  .MajorPentatonic = {},
  .MinorPentatonic = {},
  .Blues           = {},
  .Chromatic       = {},
}

@(rodata)
EXTENSIONS_LENGTHS := [ChordExtension]int {
  .Triad      = 3,
  .Seventh    = 4,
  .Ninth      = 5,
  .Eleventh   = 6,
  .Thirteenth = 7,
  .Add9       = 4,
  .Add11      = 4,
  .PowerChord = 2,
}

@(rodata)
EXTENSION_DERGEE_INDICES := [ChordExtension][7]int {
  .Triad      = {  0,  2,  4, -1, -1, -1, -1 },
  .Seventh    = {  0,  2,  4,  6, -1, -1, -1 },
  .Ninth      = {  0,  2,  4,  6,  1, -1, -1 },
  .Eleventh   = {  0,  2,  4,  6,  1,  3, -1 },
  .Thirteenth = {  0,  2,  4,  6,  1,  3,  5 },
  .Add9       = {  0,  2,  4,  1, -1, -1, -1 },
  .Add11      = {  0,  2,  4,  3, -1, -1, -1 },
  .PowerChord = {  0,  4, -1, -1, -1, -1, -1 },
}

@(rodata)
MAX_INVERSION := [ChordExtension]Inversion {
  .Triad      = .Second,
  .Seventh    = .Third,
  .Ninth      = .Fourth,
  .Eleventh   = .Fifth,
  .Thirteenth = .Sixth,
  .Add9       = .Third,
  .Add11      = .Third,
  .PowerChord = .First,
}

@(rodata)
KEY_ACCIDENTAL_PREFERENCE := [12]Accidental {
  .Natural,
  .Sharp,
  .Sharp,
  .Flat,
  .Sharp,
  .Flat,
  .Sharp,
  .Sharp,
  .Flat,
  .Sharp,
  .Flat,
  .Sharp,
}

@(rodata)
ROMAN_UPPER := [8]string { "", "I", "II", "III", "IV", "V", "VI", "VII" }
@(rodata)
ROMAN_LOWER := [8]string { "", "i", "ii", "iii", "iv", "v", "vi", "vii" }

@(rodata)
CHORD_QUALITY_NAMES := [ChordQuality]string {
  .Major             = "",
  .Minor             = "m",
  .Diminished        = "dim",
  .Augmented         = "aug",
  .Sus2              = "sus2",
  .Sus4              = "sus4",
  .MajorSeventh      = "maj7",
  .DominantSeventh   = "7",
  .MinorSeventh      = "m7",
  .MinorMajorSeventh = "mMaj7",
  .HalfDiminished    = "m7b5",
  .FullyDiminished   = "dim7",
  .AugmentedMajorSev = "augMaj7",
}

@(rodata)
EXTENSION_QUALITY_SUFFIX := [ChordQuality][ChordExtension]string {
  .Major = {
    .Triad      = "",
    .Seventh    = "maj7",
    .Ninth      = "maj9",
    .Eleventh   = "maj11",
    .Thirteenth = "maj13",
    .Add9       = "add9",
    .Add11      = "add11",
    .PowerChord = "5",
  },
  .Minor = {
    .Triad      = "m",
    .Seventh    = "m7",
    .Ninth      = "m9",
    .Eleventh   = "m11",
    .Thirteenth = "m13",
    .Add9       = "madd9",
    .Add11      = "madd11",
    .PowerChord = "5",
  },
  .Diminished = {
    .Triad      = "dim",
    .Seventh    = "dim7",
    .Ninth      = "dim9",
    .Eleventh   = "dim11",
    .Thirteenth = "dim13",
    .Add9       = "dimadd9",
    .Add11      = "dimadd11",
    .PowerChord = "5",
  },
  .Augmented = {
    .Triad      = "aug",
    .Seventh    = "augMaj7",
    .Ninth      = "augMaj9",
    .Eleventh   = "augMaj11",
    .Thirteenth = "augMaj13",
    .Add9       = "augadd9",
    .Add11      = "augadd11",
    .PowerChord = "5",
  },
  .DominantSeventh = {
    .Triad      = "",
    .Seventh    = "7",
    .Ninth      = "9",
    .Eleventh   = "11",
    .Thirteenth = "13",
    .Add9       = "add9",
    .Add11      = "add11",
    .PowerChord = "5",
  },
  .HalfDiminished = {
    .Triad      = "m7b5",
    .Seventh    = "m7b5",
    .Ninth      = "m9b5",
    .Eleventh   = "m11b5",
    .Thirteenth = "m13b5",
    .Add9       = "m7b5add9",
    .Add11      = "m7b5add11",
    .PowerChord = "5",
  },
  .FullyDiminished = {
    .Triad      = "dim",
    .Seventh    = "dim7",
    .Ninth      = "dim9",
    .Eleventh   = "dim11",
    .Thirteenth = "dim13",
    .Add9       = "dimadd9",
    .Add11      = "dimadd11",
    .PowerChord = "5",
  },
  .MajorSeventh = {
    .Triad      = "",
    .Seventh    = "maj7",
    .Ninth      = "maj9",
    .Eleventh   = "maj11",
    .Thirteenth = "maj13",
    .Add9       = "majadd9",
    .Add11      = "majadd11",
    .PowerChord = "5",
  },
  .MinorSeventh = {
    .Triad      = "",
    .Seventh    = "m7",
    .Ninth      = "m9",
    .Eleventh   = "m11",
    .Thirteenth = "m13",
    .Add9       = "madd9",
    .Add11      = "madd11",
    .PowerChord = "5",
  },
  .MinorMajorSeventh = {
    .Triad      = "",
    .Seventh    = "mM7",
    .Ninth      = "mM9",
    .Eleventh   = "mM11",
    .Thirteenth = "mM13",
    .Add9       = "mMadd9",
    .Add11      = "mMadd11",
    .PowerChord = "5",
  },
  .AugmentedMajorSev = {
    .Triad      = "",
    .Seventh    = "augmaj7",
    .Ninth      = "augmaj9",
    .Eleventh   = "augmaj11",
    .Thirteenth = "augmaj13",
    .Add9       = "augmajadd9",
    .Add11      = "augmajadd11",
    .PowerChord = "5",
  },
  .Sus2 = {
    .Triad      = "sus2",
    .Seventh    = "7sus2",
    .Ninth      = "9sus2",
    .Eleventh   = "11sus2",
    .Thirteenth = "13sus2",
    .Add9       = "sus2add9",
    .Add11      = "sus2add11",
    .PowerChord = "5",
  },
  .Sus4 = {
    .Triad      = "sus4",
    .Seventh    = "7sus4",
    .Ninth      = "9sus4",
    .Eleventh   = "11sus4",
    .Thirteenth = "13sus4",
    .Add9       = "sus4add9",
    .Add11      = "sus4add11",
    .PowerChord = "5",
  }
}

@(private="file") @(rodata)
SHARP_SPELLINGS := [12]Note {
  { pitch = .C,  letter = 'C', accidental = .Natural},
  { pitch = .Cs, letter = 'C', accidental = .Sharp},
  { pitch = .D,  letter = 'D', accidental = .Natural},
  { pitch = .Ds, letter = 'D', accidental = .Sharp},
  { pitch = .E,  letter = 'E', accidental = .Natural},
  { pitch = .F,  letter = 'F', accidental = .Natural},
  { pitch = .Fs, letter = 'F', accidental = .Sharp},
  { pitch = .G,  letter = 'G', accidental = .Natural},
  { pitch = .Gs, letter = 'G', accidental = .Sharp},
  { pitch = .A,  letter = 'A', accidental = .Natural},
  { pitch = .As, letter = 'A', accidental = .Sharp},
  { pitch = .B,  letter = 'B', accidental = .Natural},
}

@(private="file") @(rodata)
FLAT_SPELLINGS := [12]Note {
  { pitch = .C,  letter = 'C', accidental = .Natural},
  { pitch = .Cs, letter = 'D', accidental = .Flat},
  { pitch = .D,  letter = 'D', accidental = .Natural},
  { pitch = .Ds, letter = 'E', accidental = .Flat},
  { pitch = .E,  letter = 'E', accidental = .Natural},
  { pitch = .F,  letter = 'F', accidental = .Natural},
  { pitch = .Fs, letter = 'G', accidental = .Flat},
  { pitch = .G,  letter = 'G', accidental = .Natural},
  { pitch = .Gs, letter = 'A', accidental = .Flat},
  { pitch = .A,  letter = 'A', accidental = .Natural},
  { pitch = .As, letter = 'B', accidental = .Flat},
  { pitch = .B,  letter = 'B', accidental = .Natural},
}

pitch_to_note :: proc(pc: PitchClass, prefer_flats: bool) -> Note {
  if prefer_flats {
    return FLAT_SPELLINGS[pc]
  }
  return SHARP_SPELLINGS[pc]
}

@(private="file") @(rodata)
LETTER_PITCH := [256]PitchClass {
  'C' = .C,
  'D' = .D,
  'E' = .E,
  'F' = .F,
  'G' = .G,
  'A' = .A,
  'B' = .B,
}

@(private="file") @(rodata)
LETTER_ORDER := [7]u8 { 'A', 'B', 'C', 'D', 'E', 'F', 'G' }

@(private="file") @(rodata)
LETTER_INDEX := [256]int {
  'A' = 0,
  'B' = 1,
  'C' = 2,
  'D' = 3,
  'E' = 4,
  'F' = 5,
  'G' = 6
}

@(private="file")
letter_step :: proc(start: u8, steps: int) -> u8 {
  idx := LETTER_INDEX[start]
  res := ((idx + steps) % 7 + 7) % 7
  return LETTER_ORDER[res]
}

@(private="file")
spell_note_as_letter :: proc(pc: PitchClass, letter: u8) -> Note {
  natural_pc       := LETTER_PITCH[letter]
  natural_semitone := int(natural_pc)
  target_semitons  := int(pc)

  diff := target_semitons - natural_semitone
  if diff >  6 do diff -= 12
  if diff < -6 do diff += 12

  accidental: Accidental
  switch diff {
  case  0: accidental = .Natural
  case  1: accidental = .Sharp
  case  2: accidental = .DoubleSharp
  case -1: accidental = .Flat
  case -2: accidental = .DoubleFlat
  case:    accidental = .Natural
  }

  return Note{ pitch = pc, letter = letter, accidental = accidental }
}

scale_build :: proc(root: Note, quality: ScaleQuality) -> Scale {
  scale := Scale{
    root    = root,
    quality = quality,
    len     = SCALE_LENGTHS[quality],
  }

  intervals    := SCALE_INTERVALS[quality]
  prefer_flats := KEY_ACCIDENTAL_PREFERENCE[root.pitch] == .Flat

  if quality == .Chromatic {
    for i in 0..<12 {
      semitones     := intervals[i]
      pc            := PitchClass((int(root.pitch) + semitones) % 12)
      scale.notes[i] = pitch_to_note(pc, prefer_flats)
    }
    return scale
  }

  for i in 0..<scale.len {
    semitones := intervals[i]
    pc := PitchClass((int(root.pitch) + semitones) % 12)
    if i == 0 {
      scale.notes[0] = root
      continue
    }
    expected_letter := letter_step(root.letter, i)
    scale.notes[i]   = spell_note_as_letter(pc, expected_letter)
  }

  return scale
}

scale_chord_at :: proc(scale: ^Scale, degree: ScaleDegree, extension: ChordExtension) -> (chord: Chord, ok: bool) {
  #partial switch scale.quality {
  case .Chromatic, .MajorPentatonic, .MinorPentatonic, .Blues: return {}, false
  }
  needed_indices := EXTENSION_DERGEE_INDICES[extension]
  for idx in needed_indices {
    if idx == -1 do break
    if idx >= scale.len do return {}, false
  }

  deg_idx      := int(degree) - 1

  resolved_quality: ChordQuality
  switch extension {
  case .Triad, .Add9, .Add11, .PowerChord:
    resolved_quality = DIATONIC_TRIADS[scale.quality][deg_idx]
  case .Seventh, .Ninth, .Eleventh, .Thirteenth:
    resolved_quality = DIATONIC_SEVENTHS[scale.quality][deg_idx]
  }

  chord = Chord{
    root      = scale.notes[deg_idx],
    quality   = resolved_quality,
    extension = extension,
    inversion = .Root,
    degree    = degree,
  }

  note_count := EXTENSIONS_LENGTHS[extension]
  for i in 0..<note_count {
    scale_idx  := needed_indices[i]
    rotated    := (scale_idx + deg_idx) % scale.len
    chord.notes = scale.notes[rotated]
  }
  chord.len  = note_count
  chord.bass = chord.notes[0]

  return chord, true
}

scale_diatonic_chords :: proc(scale: ^Scale, extenion: ChordExtension) -> (chords: [7]Chord) {
  for i in 0..<7 {
    deg := ScaleDegree(i + 1)
    chord, ok := scale_chord_at(scale, deg, extenion)
    if ok {
      chords[i] = chord
    }
  }
  return chords
}

@(private="file")
pc_normalise :: proc(semitones: int) -> int {
  return ((semitones % 12) + 12) % 12
}

note_transpose :: proc(note: Note, semitones: int, prefer_flats: bool) -> Note {
  pc := PitchClass(pc_normalise(int(note.pitch) + semitones))
  return pitch_to_note(pc, prefer_flats)
}

chord_transpose :: proc(chord: Chord, semitones: int) -> Chord {
  root_pc         := PitchClass(pc_normalise(int(chord.root.pitch) + semitones))
  prefer_flats    := KEY_ACCIDENTAL_PREFERENCE[root_pc] == .Flat
  root            := pitch_to_note(root_pc, prefer_flats)
  result          := chord
  result.root      = root
  result.inversion = .Root
  result.degree    = {}

  for i in 0..<chord.len {
    result.notes[i] = note_transpose(chord.notes[i], semitones, prefer_flats)
  }
  result.bass = result.notes[0]

  return result
}

// @(private)
// pc_interval_up :: proc(from, to: PitchClass) -> int {
//   return pc_normalise(int(to) - int(from))
// }
//
// @(private)
// pc_interval_down :: proc(from, to: PitchClass) -> int {
//   return pc_normalise(int(from) - int(to))
// }

chord_invert :: proc(chord: Chord, inversion: Inversion) -> (result: Chord, ok: bool) {
  if inversion > MAX_INVERSION[chord.extension] {
    return {}, false
  }

  result           = chord
  result.inversion = inversion

  n := int(inversion)
  for i in 0..<chord.len {
    result.notes[i] = chord.notes[(i + n) % chord.len]
  }
  result.bass = result.notes[0]

  return result, true
}

chord_all_inversions :: proc(chord: Chord, alloctor := context.allocator) -> []Chord {
  max_inv := int(MAX_INVERSION[chord.extension])
  result  := make([]Chord, max_inv + 1, alloctor)
  for i in 0..=max_inv {
    result[i], _ = chord_invert(chord, Inversion(i))
  }
  return result
}

format_note :: proc(note: Note, allocator := context.allocator) -> string {
  accidental: string
  switch note.accidental {
  case .Natural:     accidental = ""
  case .Sharp:       accidental = "#"
  case .Flat:        accidental = "b"
  case .DoubleSharp: accidental = "##"
  case .DoubleFlat:  accidental = "bb"
  }
  return fmt.aprint("%c%s", note.letter, accidental, allocator = allocator)
}

format_note_list :: proc(notes: []Note, allocator := context.allocator) -> string {
  parts := make([]string, len(notes), context.temp_allocator)
  for note, i in notes {
    parts[i] = format_note(notes[i], context.temp_allocator)
  }
  return strings.join(parts, ", ", allocator)
}

chord_extension_name :: proc(quality: ChordQuality, extension: ChordExtension) -> string {
  return EXTENSION_QUALITY_SUFFIX[quality][extension]
}

chord_name :: proc(chord: ^Chord, allocator := context.allocator) -> string {
  root   := format_note(chord.root, context.temp_allocator)
  suffix := chord_extension_name(chord.quality, chord.extension)
  return strings.concatenate({root, suffix}, allocator)
}

chord_inversion_name :: proc(chord: ^Chord, allocator := context.allocator) -> string {
  base := chord_name(chord, context.temp_allocator)
  if chord.inversion == .Root {
    return strings.clone(base, allocator)
  }
  bass_str := format_note(chord.bass, context.temp_allocator)
  return strings.concatenate({base, "/", bass_str}, allocator)
}

degree_display :: proc(degree: ScaleDegree, quality: ChordQuality, allocator := context.allocator) -> string {
  idx := int(degree)
  switch quality {
  case .Major, .Sus2, .Sus4, .MajorSeventh, .DominantSeventh:
    return strings.clone(ROMAN_UPPER[idx], allocator)
  case .Augmented, .AugmentedMajorSev:
    return strings.concatenate({ROMAN_UPPER[idx], "+"}, allocator)
  case .Minor, .MinorSeventh, .MinorMajorSeventh:
    return ROMAN_LOWER[idx]
  case .Diminished:
    return strings.concatenate({ROMAN_LOWER[idx], "\u00b0"},  allocator)
  case .HalfDiminished:
    return strings.concatenate({ROMAN_LOWER[idx], "\u00f87"}, allocator)
  case .FullyDiminished:
    return strings.concatenate({ROMAN_LOWER[idx], "\u00b07"}, allocator)
  }
  return strings.clone(ROMAN_UPPER[idx], allocator)
}

inversion_label :: proc(inv: Inversion) -> string {
  switch inv {
  case .Root:   return "root"
  case .First:  return "1st inv"
  case .Second: return "2nd inv"
  case .Third:  return "3rd inv"
  case .Fourth: return "4th inv"
  case .Fifth:  return "5th inv"
  case .Sixth:  return "6th inv"
  }
  return ""
}
