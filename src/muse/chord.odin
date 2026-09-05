package muse

import "core:fmt"
import "core:slice"
import "core:strings"

/*
A root, an interval set measured from it, and the canonical symbol naming that
set. The intervals are always the complete stack: the eleventh a thirteenth
chord drops is present here and is removed only when the chord is realized into
notes, which is what makes --literal a rendering choice rather than a second
kind of chord.

bass carries slash notation. It is a claim about what sounds underneath rather
than a member of the interval set, and it survives printing without changing
what the chord is.
*/
Chord :: struct {
  root      : Note,
  symbol    : string,
  intervals : []Interval,
  bass      : Maybe(Note),
}

/*
One named interval set. The table is read forwards to build a chord and
backwards to identify one, so a name and its intervals cannot disagree.

There is no alias field. Every accepted spelling of a symbol is a spelling of
its tokens, and the token tables below carry those; a template is reached by its
interval set and never by its name. The set of names muse can produce is exactly
this table, which is the boundary parking lot item F in DESIGN.md describes.
*/
ChordTemplate :: struct {
  symbol    : string,
  intervals : []Interval,
}

@(rodata)
CHORD_TEMPLATES := []ChordTemplate {
  { "",       { UNISON, MAJOR_THIRD, PERFECT_FIFTH } },
  { "m",      { UNISON, MINOR_THIRD, PERFECT_FIFTH } },
  { "dim",    { UNISON, MINOR_THIRD, DIMINISHED_FIFTH } },
  { "aug",    { UNISON, MAJOR_THIRD, AUGMENTED_FIFTH } },
  { "sus2",   { UNISON, MAJOR_SECOND, PERFECT_FIFTH } },
  { "sus4",   { UNISON, PERFECT_FOURTH, PERFECT_FIFTH } },
  { "5",      { UNISON, PERFECT_FIFTH } },

  { "6",      { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SIXTH } },
  { "m6",     { UNISON, MINOR_THIRD, PERFECT_FIFTH, MAJOR_SIXTH } },
  { "69",     { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SIXTH, MAJOR_NINTH } },
  { "m69",    { UNISON, MINOR_THIRD, PERFECT_FIFTH, MAJOR_SIXTH, MAJOR_NINTH } },

  { "7",      { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH } },
  { "maj7",   { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH } },
  { "m7",     { UNISON, MINOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH } },
  { "mMaj7",  { UNISON, MINOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH } },
  { "dim7",   { UNISON, MINOR_THIRD, DIMINISHED_FIFTH, DIMINISHED_SEVENTH } },
  { "m7b5",   { UNISON, MINOR_THIRD, DIMINISHED_FIFTH, MINOR_SEVENTH } },
  { "aug7",   { UNISON, MAJOR_THIRD, AUGMENTED_FIFTH, MINOR_SEVENTH } },
  { "maj7#5", { UNISON, MAJOR_THIRD, AUGMENTED_FIFTH, MAJOR_SEVENTH } },
  { "7b5",    { UNISON, MAJOR_THIRD, DIMINISHED_FIFTH, MINOR_SEVENTH } },
  { "7sus4",  { UNISON, PERFECT_FOURTH, PERFECT_FIFTH, MINOR_SEVENTH } },
  { "add9",   { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_NINTH } },
  { "madd9",  { UNISON, MINOR_THIRD, PERFECT_FIFTH, MAJOR_NINTH } },

  { "9",      { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH } },
  { "maj9",   { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH, MAJOR_NINTH } },
  { "m9",     { UNISON, MINOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH } },
  { "mMaj9",  { UNISON, MINOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH, MAJOR_NINTH } },
  { "m9b5",   { UNISON, MINOR_THIRD, DIMINISHED_FIFTH, MINOR_SEVENTH, MAJOR_NINTH } },

  { "11",     { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH } },
  { "m11",    { UNISON, MINOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH } },
  { "maj11",  { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH } },
  { "m11b5",  { UNISON, MINOR_THIRD, DIMINISHED_FIFTH, MINOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH } },

  { "13",     { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH, MAJOR_THIRTEENTH } },
  { "m13",    { UNISON, MINOR_THIRD, PERFECT_FIFTH, MINOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH, MAJOR_THIRTEENTH } },
  { "maj13",  { UNISON, MAJOR_THIRD, PERFECT_FIFTH, MAJOR_SEVENTH, MAJOR_NINTH, PERFECT_ELEVENTH, MAJOR_THIRTEENTH } },
}

/*
A quality contributes a triad and, when a seventh or higher is called for, which
seventh. Two of them are seventh-chord glyphs rather than triad names and imply
their seventh with no extension written; one of them, mMaj, is meaningless
without an extension and says so.

alteration carries the b5 that makes ø a spelling of m7b5 rather than a
quality of its own, so the half-diminished chord needs no special case in the
builder and none in the printer.
*/
@(private)
ChordQualityToken :: struct {
  token            : string,
  triad            : []Interval,
  seventh          : Interval,
  implies_seventh  : bool,
  requires_seventh : bool,
  symbol           : string,
  alteration       : string,
}

@(rodata)
@(private)
CHORD_QUALITY_TOKENS := []ChordQualityToken {
  { "m",         { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MINOR_SEVENTH,      false, false, "m",    "" },
  { "min",       { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MINOR_SEVENTH,      false, false, "m",    "" },
  { "-",         { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MINOR_SEVENTH,      false, false, "m",    "" },

  { "maj",       { UNISON, MAJOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, false, "maj",  "" },
  { "M",         { UNISON, MAJOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, false, "maj",  "" },
  { "Δ",         { UNISON, MAJOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      true,  false, "maj",  "" },

  { "mMaj",      { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "mmaj",      { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "minMaj",    { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "minmaj",    { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "mΔ",        { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "-Δ",        { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      false, true,  "mMaj", "" },
  { "m(maj7)",   { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      true,  false, "mMaj", "" },
  { "min(maj7)", { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      true,  false, "mMaj", "" },
  { "-(maj7)",   { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MAJOR_SEVENTH,      true,  false, "mMaj", "" },

  { "dim",       { UNISON, MINOR_THIRD, DIMINISHED_FIFTH },  DIMINISHED_SEVENTH, false, false, "dim",  "" },
  { "°",         { UNISON, MINOR_THIRD, DIMINISHED_FIFTH },  DIMINISHED_SEVENTH, false, false, "dim",  "" },

  { "aug",       { UNISON, MAJOR_THIRD, AUGMENTED_FIFTH },   MINOR_SEVENTH,      false, false, "aug",  "" },
  { "+",         { UNISON, MAJOR_THIRD, AUGMENTED_FIFTH },   MINOR_SEVENTH,      false, false, "aug",  "" },

  { "ø",         { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MINOR_SEVENTH,      true,  false, "m",    "b5" },
  { "ø7",        { UNISON, MINOR_THIRD, PERFECT_FIFTH },     MINOR_SEVENTH,      true,  false, "m",    "b5" },
}

@(private)
ChordExtensionKind :: enum {
  Stack,
  Power,
  Sixth,
  SixNine,
}

/*
The extension number says how high to stack: every odd degree from the seventh
up to it. Three tokens are exceptions rather than heights, and are marked as
such rather than folded into the degree.
*/
@(private)
ChordExtensionToken :: struct {
  token  : string,
  symbol : string,
  kind   : ChordExtensionKind,
  degree : int,
}

@(rodata)
@(private)
CHORD_EXTENSION_TOKENS := []ChordExtensionToken {
  { "5",   "5",  .Power,   0 },
  { "6",   "6",  .Sixth,   0 },
  { "69",  "69", .SixNine, 0 },
  { "6/9", "69", .SixNine, 0 },
  { "7",   "7",  .Stack,   7 },
  { "9",   "9",  .Stack,   9 },
  { "11",  "11", .Stack,  11 },
  { "13",  "13", .Stack,  13 },
}

@(private)
ChordModifierKind :: enum {
  Suspension,
  Alteration,
  Addition,
  Omission,
}

@(private)
ChordModifier :: struct {
  kind   : ChordModifierKind,
  degree : int,
  token  : string,
}

/*
The six alterations muse reads, each as the degree it changes and the interval
on either side of the change. A raised fourth is written #11 and a lowered
sixth b13, so neither needs a row, and everything outside this set is a parse
error naming the token rather than a guess.

The table is read in both directions. A symbol reaches it by token, and an
interval set reaches it by holding a row's altered interval where the row's
natural one was expected, which is how identification names a chord the
template table has no row for.
*/
@(private)
ChordAlteration :: struct {
  token   : string,
  degree  : int,
  natural : Interval,
  altered : Interval,
}

@(rodata)
@(private)
CHORD_ALTERATIONS := []ChordAlteration {
  { "b5",   5, PERFECT_FIFTH,    DIMINISHED_FIFTH   },
  { "#5",   5, PERFECT_FIFTH,    AUGMENTED_FIFTH    },
  { "b9",   9, MAJOR_NINTH,      MINOR_NINTH        },
  { "#9",   9, MAJOR_NINTH,      AUGMENTED_NINTH    },
  { "#11", 11, PERFECT_ELEVENTH, AUGMENTED_ELEVENTH },
  { "b13", 13, MAJOR_THIRTEENTH, MINOR_THIRTEENTH   },
}

/*
The degrees add contributes, and the interval each one names. A second and a
ninth are the same pitch class and different intervals, so both are here and a
voicing can tell them apart.
*/
@(private)
ChordAddition :: struct {
  token    : string,
  degree   : int,
  interval : Interval,
}

@(rodata)
@(private)
CHORD_ADDITIONS := []ChordAddition {
  { "add2",   2, MAJOR_SECOND     },
  { "add4",   4, PERFECT_FOURTH   },
  { "add6",   6, MAJOR_SIXTH      },
  { "add9",   9, MAJOR_NINTH      },
  { "add11", 11, PERFECT_ELEVENTH },
  { "add13", 13, MAJOR_THIRTEENTH },
}

/*
Build a chord on a root from a template row. The intervals and the symbol are
copied rather than borrowed, so nothing hands a caller a slice of rodata.
*/
chord_make :: proc(root: Note, template: ChordTemplate, allocator := context.allocator) -> Chord {
  return Chord {
    root      = root,
    symbol    = strings.clone(template.symbol, allocator),
    intervals = slice.clone(template.intervals, allocator),
  }
}

/*
Add an interval to a chord, replacing any interval of the same number, and name
the result.

The naming is identification's, asked of the interval set rather than of notes,
so the result carries the exact intervals it was built from: C7 with an
augmented ninth is C7#9 and not C7b9 spelled differently. Returns false when
the set is past the modifier limit, which is the point at which the note list
is the shorter answer.
*/
chord_add_interval :: proc(chord: Chord, interval: Interval, allocator := context.allocator) -> (Chord, bool) {
  intervals := make([dynamic]Interval, 0, len(chord.intervals) + 1, context.temp_allocator)
  append(&intervals, ..chord.intervals)
  intervals_replace(&intervals, interval)
  intervals_sort(intervals[:])

  reading, found := chord_read_intervals(chord.root, intervals[:])
  if !found {
    return {}, false
  }

  named := chord_reading_chord(reading, allocator)
  named.bass = chord.bass
  return named, true
}

/*
The intervals a chord drops when it is realized. A natural eleventh and a major
third are a minor ninth apart, so one of them goes: the eleventh in a chord that
also has a thirteenth, the third otherwise. A chord with no seventh stacked
nothing, so an eleventh in it was asked for deliberately and stays.

Derived from the interval set alone, which is what keeps identification
symmetric with construction.
*/
chord_omissions :: proc(chord: Chord, allocator := context.allocator) -> []Interval {
  omitted, has_omission := intervals_omission(chord.intervals)
  if !has_omission {
    return nil
  }

  omissions := make([]Interval, 1, allocator)
  omissions[0] = omitted
  return omissions
}

/*
Realize a chord as notes, ascending from the root, with the omission applied.
literal keeps the full stack instead, which is the same chord printed two ways.

A slash bass sounds below the chord and so comes first. One that is already a
chord tone rotates the stack to start on itself rather than being repeated,
which is what makes C/E read E G C; one that is not is placed in front of the
stack it does not belong to. The order is the order a voicing realizes in, so
voicing_close is this list with octaves attached.

Returns false when a note would need more than a double accidental.
*/
chord_notes :: proc(chord: Chord, literal := false, allocator := context.allocator) -> ([]Note, bool) {
  omitted, has_omission := intervals_omission(chord.intervals)

  notes := make([dynamic]Note, 0, len(chord.intervals) + 1, allocator)

  for interval in chord.intervals {
    if has_omission && !literal && interval == omitted {
      continue
    }

    note, ok := note_add_interval(chord.root, interval)
    if !ok {
      delete(notes)
      return nil, false
    }
    append(&notes, note)
  }

  bass, has_bass := chord.bass.?
  if !has_bass {
    return notes[:], true
  }

  index, is_chord_tone := slice.linear_search(notes[:], bass)
  if !is_chord_tone {
    inject_at(&notes, 0, bass)
    return notes[:], true
  }

  rotated := make([dynamic]Note, 0, len(notes), allocator)
  append(&rotated, ..notes[index:])
  append(&rotated, ..notes[:index])
  delete(notes)

  return rotated[:], true
}

/*
Read a chord symbol: a root, an optional quality, an optional extension number,
any number of modifiers, and an optional slash bass. Every accepted spelling and
the canonical form it prints as are enumerated in docs/CHORD-SYMBOLS.md.

An accidental immediately after the root letter binds to the root, so C#11 is a
C sharp eleventh chord. chord_ambiguity reports the symbols where the other
reading also parses.
*/
chord_parse :: proc(text: string, allocator := context.allocator) -> (Chord, bool) {
  symbol_text := text
  bass        : Maybe(Note)

  if slash := strings.last_index_byte(text, '/'); slash >= 0 {
    if note, note_ok := note_parse(text[slash + 1:]); note_ok {
      bass        = note
      symbol_text = text[:slash]
    }
  }

  root, rest, root_ok := note_prefix_parse(symbol_text)
  if !root_ok {
    return {}, false
  }

  modifiers := make([dynamic]ChordModifier, 0, 4, context.temp_allocator)

  quality, has_quality := chord_quality_match(rest)
  if has_quality {
    rest = rest[len(quality.token):]
    if len(quality.alteration) > 0 {
      append(&modifiers, ChordModifier{ .Alteration, 5, quality.alteration })
    }
  }

  extension, has_extension := chord_extension_match(rest)
  if has_extension {
    rest = rest[len(extension.token):]
  }

  if has_extension && extension.kind == .Power && has_quality {
    return {}, false
  }
  if quality.requires_seventh && !(has_extension && extension.kind == .Stack) {
    return {}, false
  }

  for len(rest) > 0 {
    if rest[0] == '(' {
      closing := strings.index_byte(rest, ')')
      if closing < 0 {
        return {}, false
      }

      inner := rest[1:closing]
      for len(inner) > 0 {
        if inner[0] == ',' {
          inner = inner[1:]
          continue
        }
        modifier, remainder, modifier_ok := chord_modifier_parse(inner)
        if !modifier_ok {
          return {}, false
        }
        append(&modifiers, modifier)
        inner = remainder
      }

      rest = rest[closing + 1:]
      continue
    }

    modifier, remainder, modifier_ok := chord_modifier_parse(rest)
    if !modifier_ok {
      return {}, false
    }
    append(&modifiers, modifier)
    rest = remainder
  }

  intervals, symbol := chord_build(quality, has_quality, extension, has_extension, modifiers[:], allocator)

  return Chord {
    root      = root,
    symbol    = symbol,
    intervals = intervals,
    bass      = bass,
  }, true
}

/*
The interval set a base and its modifiers come to, and the canonical symbol
naming it. chord_parse reads tokens and calls this; identification proposes
tokens and calls the same thing, so a name muse prints is a name muse reads.
*/
@(private)
chord_build :: proc(
  quality       : ChordQualityToken,
  has_quality   : bool,
  extension     : ChordExtensionToken,
  has_extension : bool,
  modifiers     : []ChordModifier,
  allocator     := context.allocator,
) -> ([]Interval, string) {
  intervals := chord_stack(quality, has_quality, extension, has_extension)
  for modifier in modifiers {
    chord_apply_modifier(&intervals, modifier)
  }
  intervals_sort(intervals[:])

  symbol := chord_symbol(intervals[:], quality, has_quality, extension, has_extension, modifiers, allocator)
  return slice.clone(intervals[:], allocator), symbol
}

/*
The same chord on a root moved by an interval, slash bass and all. The symbol
and the interval set are the chord's identity and neither moves, so a
transposition is a change of root and nothing else, and transposing back returns
the chord that set out.

Returns false when the new root or the new bass needs more than a double
accidental.
*/
chord_transpose :: proc(chord: Chord, interval: Interval, allocator := context.allocator) -> (Chord, bool) {
  root, root_ok := note_add_interval(chord.root, interval)
  if !root_ok {
    return {}, false
  }

  transposed := Chord {
    root      = root,
    symbol    = strings.clone(chord.symbol, allocator),
    intervals = slice.clone(chord.intervals, allocator),
  }

  if bass, has_bass := chord.bass.?; has_bass {
    moved, moved_ok := note_add_interval(bass, interval)
    if !moved_ok {
      return {}, false
    }
    transposed.bass = moved
  }

  return transposed, true
}

/*
The canonical spelling of a chord: root, symbol, and the slash bass when there
is one. Parsing this returns the chord it was printed from.
*/
chord_string :: proc(chord: Chord, allocator := context.allocator) -> string {
  root := note_string(chord.root, context.temp_allocator)

  if bass, has_bass := chord.bass.?; has_bass {
    return fmt.aprintf(
      "%s%s/%s",
      root,
      chord.symbol,
      note_string(bass, context.temp_allocator),
      allocator = allocator,
    )
  }
  return fmt.aprintf("%s%s", root, chord.symbol, allocator = allocator)
}

/*
The unambiguous spelling of the other reading of a symbol whose root swallowed
an accidental, or false when only one reading parses. C#11 is a C sharp eleventh
chord and also, if the accidental is read as a modifier, C with a sharp
eleventh; this returns C(#11) so the caller can say which one it took.

The suggestion is validated by parsing it, so a spelling is only offered when it
really is the other reading.
*/
chord_ambiguity :: proc(text: string, allocator := context.allocator) -> (string, bool) {
  if _, parse_ok := chord_parse(text, context.temp_allocator); !parse_ok {
    return "", false
  }

  _, rest, root_ok := note_prefix_parse(text)
  if !root_ok || len(rest) == len(text) - 1 {
    return "", false
  }

  sign, sign_width := accidental_prefix(text[1:])
  if sign_width == 0 {
    return "", false
  }

  degree, degree_width := scan_digits(text[1 + sign_width:])
  token, token_ok      := chord_alteration_token(sign, degree)
  if !token_ok {
    return "", false
  }

  spelling := fmt.aprintf(
    "%c(%s)%s",
    text[0],
    token,
    text[1 + sign_width + degree_width:],
    allocator = allocator,
  )
  if _, spelling_ok := chord_parse(spelling, context.temp_allocator); !spelling_ok {
    delete(spelling, allocator)
    return "", false
  }
  return spelling, true
}

/*
Name the chord a set of notes forms, or false when nothing within the modifier
limit reads them.

A reading is a base -- a quality and an extension, stacked by the same proc the
parser stacks with -- plus the modifiers that carry whatever the base does not.
Every root in turn is tried against every base, and the readings that survive
are ranked by DESIGN.md's order: fewest modifiers, then the earliest root
supplied, then the modifier order canonical output already uses, then the
shorter symbol. So A C E G is Am7 while C E G A is C6, and C E G Bb Db is C7b9
rather than a note list.

A root further along makes the first note a slash bass, and a first note that
belongs to no reading is dropped and becomes one, which is how a bass outside
the chord is recovered.
*/
chord_identify :: proc(notes: []Note, allocator := context.allocator) -> (Chord, bool) {
  unique := make([dynamic]Note, 0, len(notes), context.temp_allocator)
  for note in notes {
    if !slice.contains(unique[:], note) {
      append(&unique, note)
    }
  }
  if len(unique) == 0 {
    return {}, false
  }

  if reading, found := chord_read_notes(unique[:]); found {
    chord := chord_reading_chord(reading, allocator)
    if reading.root_index != 0 {
      chord.bass = unique[0]
    }
    return chord, true
  }

  if len(unique) == 1 {
    return {}, false
  }

  if reading, found := chord_read_notes(unique[1:]); found {
    chord := chord_reading_chord(reading, allocator)
    chord.bass = unique[0]
    return chord, true
  }

  return {}, false
}

/*
Whether two chords are the same chord. Chord holds a slice, so it is not
comparable with ==.
*/
chord_equal :: proc(a, b: Chord) -> bool {
  if a.root != b.root || a.symbol != b.symbol {
    return false
  }

  a_bass, a_has_bass := a.bass.?
  b_bass, b_has_bass := b.bass.?
  if a_has_bass != b_has_bass || (a_has_bass && a_bass != b_bass) {
    return false
  }

  return intervals_equal(a.intervals, b.intervals)
}

/*
The interval set a quality and an extension stack up to, before modifiers.
*/
@(private)
chord_stack :: proc(
  quality       : ChordQualityToken,
  has_quality   : bool,
  extension     : ChordExtensionToken,
  has_extension : bool,
) -> [dynamic]Interval {
  intervals := make([dynamic]Interval, 0, 8, context.temp_allocator)

  triad   := []Interval{ UNISON, MAJOR_THIRD, PERFECT_FIFTH }
  seventh := MINOR_SEVENTH
  if has_quality {
    triad   = quality.triad
    seventh = quality.seventh
  }

  if has_extension && extension.kind == .Power {
    append(&intervals, UNISON, PERFECT_FIFTH)
    return intervals
  }

  append(&intervals, ..triad)

  if !has_extension {
    if has_quality && quality.implies_seventh {
      append(&intervals, seventh)
    }
    return intervals
  }

  switch extension.kind {
  case .Power:
  case .Sixth:
    append(&intervals, MAJOR_SIXTH)
  case .SixNine:
    append(&intervals, MAJOR_SIXTH, MAJOR_NINTH)
  case .Stack:
    append(&intervals, seventh)
    if extension.degree >=  9 { append(&intervals, MAJOR_NINTH) }
    if extension.degree >= 11 { append(&intervals, PERFECT_ELEVENTH) }
    if extension.degree >= 13 { append(&intervals, MAJOR_THIRTEENTH) }
  }

  return intervals
}

@(private)
chord_apply_modifier :: proc(intervals: ^[dynamic]Interval, modifier: ChordModifier) {
  switch modifier.kind {
  case .Suspension:
    intervals_remove_steps(intervals, 2)
    if modifier.degree == 2 {
      intervals_replace(intervals, MAJOR_SECOND)
    } else if !intervals_has_steps(intervals[:], 10) {
      intervals_replace(intervals, PERFECT_FOURTH)
    }
  case .Alteration:
    intervals_replace(intervals, chord_alteration_interval(modifier.token))
  case .Addition:
    intervals_replace(intervals, chord_addition_interval(modifier.degree))
  case .Omission:
    intervals_remove_steps(intervals, modifier.degree - 1)
  }
}

/*
The canonical symbol for a parsed chord. A set that is a template takes that
template's name whatever route the parse took, so C7#5 and Caug7 print alike and
parsing cannot disagree with identification. Anything else re-emits its tokens
in canonical order: quality, extension, suspension, alterations, additions,
omissions, each group by ascending degree.

Parentheses go around an alteration that would otherwise sit against the root
letter, since bare juxtaposition there rebinds to the root.
*/
@(private)
chord_symbol :: proc(
  intervals     : []Interval,
  quality       : ChordQualityToken,
  has_quality   : bool,
  extension     : ChordExtensionToken,
  has_extension : bool,
  modifiers     : []ChordModifier,
  allocator     := context.allocator,
) -> string {
  if template, found := chord_template_match(intervals); found {
    return strings.clone(template.symbol, allocator)
  }

  quality_symbol := has_quality ? quality.symbol : ""

  extension_symbol := ""
  if has_extension {
    extension_symbol = extension.symbol
  } else if has_quality && quality.implies_seventh {
    extension_symbol = "7"
  }

  ordered := slice.clone(modifiers, context.temp_allocator)
  slice.sort_by(ordered, proc(a, b: ChordModifier) -> bool {
    if a.kind != b.kind {
      return a.kind < b.kind
    }
    return a.degree < b.degree
  })

  builder := strings.builder_make(allocator)
  strings.write_string(&builder, quality_symbol)
  strings.write_string(&builder, extension_symbol)

  parenthesized := len(quality_symbol) == 0 &&
                   len(extension_symbol) == 0 &&
                   len(ordered) > 0 &&
                   ordered[0].kind == .Alteration
  if parenthesized {
    strings.write_byte(&builder, '(')
  }

  for modifier, index in ordered {
    if parenthesized && modifier.kind != .Alteration && index > 0 && ordered[index - 1].kind == .Alteration {
      strings.write_byte(&builder, ')')
      parenthesized = false
    }
    strings.write_string(&builder, modifier.token)
  }
  if parenthesized {
    strings.write_byte(&builder, ')')
  }

  return strings.to_string(builder)
}

@(private)
chord_quality_match :: proc(text: string) -> (ChordQualityToken, bool) {
  match : ChordQualityToken
  found := false

  for candidate in CHORD_QUALITY_TOKENS {
    if strings.has_prefix(text, candidate.token) && (!found || len(candidate.token) > len(match.token)) {
      match = candidate
      found = true
    }
  }

  return match, found
}

@(private)
chord_extension_match :: proc(text: string) -> (ChordExtensionToken, bool) {
  match : ChordExtensionToken
  found := false

  for candidate in CHORD_EXTENSION_TOKENS {
    if strings.has_prefix(text, candidate.token) && (!found || len(candidate.token) > len(match.token)) {
      match = candidate
      found = true
    }
  }

  return match, found
}

@(private)
chord_modifier_parse :: proc(text: string) -> (ChordModifier, string, bool) {
  if strings.has_prefix(text, "sus") {
    rest := text[3:]
    if strings.has_prefix(rest, "2") {
      return ChordModifier{ .Suspension, 2, "sus2" }, rest[1:], true
    }
    if strings.has_prefix(rest, "4") {
      return ChordModifier{ .Suspension, 4, "sus4" }, rest[1:], true
    }
    return ChordModifier{ .Suspension, 4, "sus4" }, rest, true
  }

  if strings.has_prefix(text, "add") {
    degree, width := scan_digits(text[3:])
    token, ok     := chord_addition_token(degree)
    if width == 0 || !ok {
      return {}, "", false
    }
    return ChordModifier{ .Addition, degree, token }, text[3 + width:], true
  }

  omission_prefix := 0
  if strings.has_prefix(text, "omit") {
    omission_prefix = len("omit")
  } else if strings.has_prefix(text, "no") {
    omission_prefix = len("no")
  }
  if omission_prefix > 0 {
    degree, width := scan_digits(text[omission_prefix:])
    token, ok     := chord_omission_token(degree)
    if width == 0 || !ok {
      return {}, "", false
    }
    return ChordModifier{ .Omission, degree, token }, text[omission_prefix + width:], true
  }

  sign, sign_width := accidental_prefix(text)
  if sign_width == 0 {
    return {}, "", false
  }

  degree, degree_width := scan_digits(text[sign_width:])
  token, token_ok      := chord_alteration_token(sign, degree)
  if degree_width == 0 || !token_ok {
    return {}, "", false
  }
  return ChordModifier{ .Alteration, degree, token }, text[sign_width + degree_width:], true
}

@(private)
chord_alteration_token :: proc(sign: u8, degree: int) -> (string, bool) {
  for alteration in CHORD_ALTERATIONS {
    lowered := alteration.altered.semitones < alteration.natural.semitones
    if alteration.degree == degree && lowered == (sign == 'b') {
      return alteration.token, true
    }
  }
  return "", false
}

@(private)
chord_alteration_interval :: proc(token: string) -> Interval {
  for alteration in CHORD_ALTERATIONS {
    if alteration.token == token {
      return alteration.altered
    }
  }
  return UNISON
}

@(private)
chord_addition_token :: proc(degree: int) -> (string, bool) {
  for addition in CHORD_ADDITIONS {
    if addition.degree == degree {
      return addition.token, true
    }
  }
  return "", false
}

@(private)
chord_addition_interval :: proc(degree: int) -> Interval {
  for addition in CHORD_ADDITIONS {
    if addition.degree == degree {
      return addition.interval
    }
  }
  return UNISON
}

@(private)
chord_omission_token :: proc(degree: int) -> (string, bool) {
  switch degree {
  case  3: return "no3",  true
  case  5: return "no5",  true
  case  7: return "no7",  true
  case  9: return "no9",  true
  case 11: return "no11", true
  case 13: return "no13", true
  }
  return "", false
}

@(private)
chord_template_match :: proc(intervals: []Interval) -> (ChordTemplate, bool) {
  for template in CHORD_TEMPLATES {
    if intervals_equal(intervals, template.intervals) {
      return template, true
    }
  }
  return {}, false
}

/*
How many modifiers a name may carry before "no name" is the more honest answer.
Every symbol docs/CHORD-SYMBOLS.md admits needs at most two, and a chord that
needs three is one a reader would rather see as notes.
*/
@(private)
CHORD_MODIFIER_LIMIT :: 2

/*
One way of reading a set of intervals: where it is rooted, the interval set the
name parses back to, the name, and what it cost to say. cost counts the
modifiers in the symbol, and a set the template table names costs nothing
whatever route reached it -- Cm7b5 is a name, not a C minor seventh with a
remark attached.

kinds orders equal-cost readings by the modifiers they carry, in the order
canonical output writes them, so a suspension is preferred to an omission and
C F G B is Cmaj7sus4 rather than Cmaj11no9.
*/
@(private)
ChordReading :: struct {
  root       : Note,
  root_index : int,
  intervals  : []Interval,
  symbol     : string,
  cost       : int,
  kinds      : int,
}

/*
The best reading of a set of notes, taken from every root in turn. Comparison
is by spelled interval, reduced to within an octave since notes carry no
register: C to A is a major sixth here whether it was written as a sixth or as
a thirteenth, but never as a diminished seventh.
*/
@(private)
chord_read_notes :: proc(notes: []Note) -> (ChordReading, bool) {
  best  : ChordReading
  found := false

  for root, index in notes {
    observed := make([dynamic]Interval, 0, len(notes), context.temp_allocator)
    for note in notes {
      append(&observed, interval_between(root, note))
    }
    intervals_sort(observed[:])

    chord_read_at_root(root, index, observed[:], true, &best, &found)
  }

  return best, found
}

/*
The best reading of an interval set at a known root, matched exactly rather
than reduced. The set is already a stack measured from its root, so a ninth is
a ninth and there is no realization to see through.
*/
@(private)
chord_read_intervals :: proc(root: Note, intervals: []Interval) -> (ChordReading, bool) {
  best  : ChordReading
  found := false

  chord_read_at_root(root, 0, intervals, false, &best, &found)
  return best, found
}

/*
Every base against one root, keeping the best reading that survives.

A base is a quality and an extension stacked by chord_stack, optionally
suspended -- the parser's own construction, so the space searched is exactly
the space of symbols the parser accepts, and no outer product is stored. What
the base does not account for becomes modifiers, and a candidate is kept only
once its symbol has been parsed back and found to name the set it came from.

reduced compares within an octave and tries the base's realization as well as
its full stack, which is how C11's five sounding notes reach the six-interval
chord that names them.
*/
@(private)
chord_read_at_root :: proc(
  root       : Note,
  root_index : int,
  observed   : []Interval,
  reduced    : bool,
  best       : ^ChordReading,
  found      : ^bool,
) {
  qualities  := chord_canonical_qualities()
  extensions := chord_canonical_extensions()

  for quality_index in -1 ..< len(qualities) {
    quality     : ChordQualityToken
    has_quality := quality_index >= 0
    if has_quality {
      quality = qualities[quality_index]
    }

    for extension_index in -1 ..< len(extensions) {
      extension     : ChordExtensionToken
      has_extension := extension_index >= 0
      if has_extension {
        extension = extensions[extension_index]
      }

      if has_extension && extension.kind == .Power && has_quality {
        continue
      }
      if quality.requires_seventh && !(has_extension && extension.kind == .Stack) {
        continue
      }

      for suspension in CHORD_SUSPENSIONS {
        base := chord_stack(quality, has_quality, extension, has_extension)
        if suspension.degree != 0 {
          chord_apply_modifier(&base, suspension)
        }
        intervals_sort(base[:])

        omitted, has_omission := intervals_omission(base[:])
        for omit in ([2]bool{ false, true }) {
          if omit && !(reduced && has_omission) {
            continue
          }

          realized := make([dynamic]Interval, 0, len(base), context.temp_allocator)
          for interval in base {
            if omit && interval == omitted {
              continue
            }
            append(&realized, interval)
          }

          modifiers := make([dynamic]ChordModifier, 0, CHORD_MODIFIER_LIMIT + 1, context.temp_allocator)
          if suspension.degree != 0 {
            append(&modifiers, suspension)
          }

          if !chord_derive_modifiers(observed, realized[:], reduced, &modifiers) {
            continue
          }
          if len(modifiers) > CHORD_MODIFIER_LIMIT {
            continue
          }

          intervals, symbol := chord_build(
            quality, has_quality, extension, has_extension, modifiers[:], context.temp_allocator,
          )
          if !chord_realizes_as(intervals, observed, reduced) {
            continue
          }

          cost := len(modifiers)
          if _, is_template := chord_template_match(intervals); is_template {
            cost = 0
          }

          reading := ChordReading {
            root       = root,
            root_index = root_index,
            intervals  = intervals,
            symbol     = symbol,
            cost       = cost,
            kinds      = chord_reading_kinds(modifiers[:]),
          }
          if found^ && !chord_reading_better(reading, best^) {
            continue
          }
          if !chord_reading_reparses(reading) {
            continue
          }

          best^  = reading
          found^ = true
        }
      }
    }
  }
}

/*
The three things a base may do with its third: keep it, or replace it with a
second or a fourth.
*/
@(rodata)
@(private)
CHORD_SUSPENSIONS := []ChordModifier {
  {},
  { .Suspension, 2, "sus2" },
  { .Suspension, 4, "sus4" },
}

/*
The modifiers that carry an observed set beyond a base, or false when notation
has no way to say the difference.

Degrees are compared one at a time, a degree being a step count within an
octave, so a ninth answers for a second and an eleventh for a fourth. A degree
the base holds and the set alters becomes an alteration; one the set holds
alone becomes an alteration where the interval is an altered one and an
addition otherwise; one the base holds and the set drops becomes an omission.

Only the stacked degrees -- the seventh, ninth, eleventh and thirteenth -- may
be dropped. A reading that discards the chord's own third or fifth is not a
name for it, and refusing there is what keeps a cluster reported as the notes
it is.
*/
@(private)
chord_derive_modifiers :: proc(
  observed  : []Interval,
  base      : []Interval,
  reduced   : bool,
  modifiers : ^[dynamic]ChordModifier,
) -> bool {
  base_intervals,     base_present,     base_ok     := intervals_by_degree(base)
  observed_intervals, observed_present, observed_ok := intervals_by_degree(observed)
  if !base_ok || !observed_ok {
    return false
  }

  for degree in 0 ..< 7 {
    switch {
    case !base_present[degree] && !observed_present[degree]:
      continue

    case base_present[degree] && observed_present[degree]:
      if intervals_agree(base_intervals[degree], observed_intervals[degree], reduced) {
        continue
      }
      alteration, ok := chord_alteration_replacing(base_intervals[degree], observed_intervals[degree], reduced)
      if !ok {
        return false
      }
      append(modifiers, ChordModifier{ .Alteration, alteration.degree, alteration.token })

    case base_present[degree]:
      number    := interval_number(base_intervals[degree])
      token, ok := chord_omission_token(number)
      if number < 7 || !ok {
        return false
      }
      append(modifiers, ChordModifier{ .Omission, number, token })

    case:
      if alteration, ok := chord_alteration_adding(observed_intervals[degree], reduced); ok {
        append(modifiers, ChordModifier{ .Alteration, alteration.degree, alteration.token })
        continue
      }
      addition, ok := chord_addition_adding(observed_intervals[degree], reduced)
      if !ok {
        return false
      }
      append(modifiers, ChordModifier{ .Addition, addition.degree, addition.token })
    }

    if len(modifiers) > CHORD_MODIFIER_LIMIT {
      return false
    }
  }

  return true
}

/*
Whether an interval set realizes as the set observed, with every interval
reduced when the observation came from notes. This is the check that makes the
derivation answerable to something other than itself.

Both realizations count. muse chord C13 and muse chord C13 --literal are the
same chord printed two ways, so both note sets have to reach C13, which means
the omission is a form the set may take and not one it must.
*/
@(private)
chord_realizes_as :: proc(intervals: []Interval, observed: []Interval, reduced: bool) -> bool {
  omitted, has_omission := intervals_omission(intervals)

  for omit in ([2]bool{ false, true }) {
    if omit && !(reduced && has_omission) {
      continue
    }

    realized := make([dynamic]Interval, 0, len(intervals), context.temp_allocator)
    for interval in intervals {
      if omit && interval == omitted {
        continue
      }
      append(&realized, reduced ? interval_simple(interval) : interval)
    }
    intervals_sort(realized[:])

    if intervals_equal(realized[:], observed) {
      return true
    }
  }

  return false
}

/*
Whether a reading's symbol, written on its root, reads back as the chord it
names. A name muse cannot parse is not a name, and the one hazard is real: an
alteration written bare against a root letter rebinds to the root, which is why
canonical output parenthesizes it and why this asks rather than assumes.
*/
@(private)
chord_reading_reparses :: proc(reading: ChordReading) -> bool {
  text := strings.concatenate(
    { note_string(reading.root, context.temp_allocator), reading.symbol },
    context.temp_allocator,
  )

  parsed, ok := chord_parse(text, context.temp_allocator)
  if !ok || parsed.root != reading.root {
    return false
  }
  return intervals_equal(parsed.intervals, reading.intervals)
}

/*
DESIGN.md's ranking, in order: fewest modifiers, the earliest root supplied,
the modifier order canonical output uses, the shorter symbol, and the symbol
itself so that two runs answer alike.
*/
@(private)
chord_reading_better :: proc(candidate, best: ChordReading) -> bool {
  if candidate.cost != best.cost {
    return candidate.cost < best.cost
  }
  if candidate.root_index != best.root_index {
    return candidate.root_index < best.root_index
  }
  if candidate.kinds != best.kinds {
    return candidate.kinds < best.kinds
  }
  if len(candidate.symbol) != len(best.symbol) {
    return len(candidate.symbol) < len(best.symbol)
  }
  return candidate.symbol < best.symbol
}

/*
A reading's modifier kinds as one number, ascending, with absent slots ranking
last so that fewer modifiers of the same kind sort ahead of more.
*/
@(private)
chord_reading_kinds :: proc(modifiers: []ChordModifier) -> int {
  sorted := slice.clone(modifiers, context.temp_allocator)
  slice.sort_by(sorted, proc(a, b: ChordModifier) -> bool {
    return a.kind < b.kind
  })

  absent := len(ChordModifierKind)
  key    := 0
  for index in 0 ..< CHORD_MODIFIER_LIMIT {
    digit := absent
    if index < len(sorted) {
      digit = int(sorted[index].kind)
    }
    key = key * (absent + 1) + digit
  }
  return key
}

@(private)
chord_reading_chord :: proc(reading: ChordReading, allocator := context.allocator) -> Chord {
  return Chord {
    root      = reading.root,
    symbol    = strings.clone(reading.symbol, allocator),
    intervals = slice.clone(reading.intervals, allocator),
  }
}

/*
One quality per canonical spelling, and one extension per canonical token, read
off the tables the parser reads. The bases identification searches are the
product of these two, so a quality or an extension added for the parser is
searched by identification without being named twice.

A quality carrying an alteration is skipped: it is a spelling of another
quality and that alteration, and the alteration reaches the set as a modifier.
*/
@(private)
chord_canonical_qualities :: proc() -> []ChordQualityToken {
  qualities := make([dynamic]ChordQualityToken, 0, len(CHORD_QUALITY_TOKENS), context.temp_allocator)

  for candidate in CHORD_QUALITY_TOKENS {
    if len(candidate.alteration) > 0 {
      continue
    }

    named := false
    for quality in qualities {
      if quality.symbol == candidate.symbol {
        named = true
        break
      }
    }
    if !named {
      append(&qualities, candidate)
    }
  }

  return qualities[:]
}

@(private)
chord_canonical_extensions :: proc() -> []ChordExtensionToken {
  extensions := make([dynamic]ChordExtensionToken, 0, len(CHORD_EXTENSION_TOKENS), context.temp_allocator)

  for candidate in CHORD_EXTENSION_TOKENS {
    named := false
    for extension in extensions {
      if extension.symbol == candidate.symbol {
        named = true
        break
      }
    }
    if !named {
      append(&extensions, candidate)
    }
  }

  return extensions[:]
}

@(private)
chord_alteration_replacing :: proc(natural, altered: Interval, reduced: bool) -> (ChordAlteration, bool) {
  for alteration in CHORD_ALTERATIONS {
    if alteration.natural == natural && intervals_agree(alteration.altered, altered, reduced) {
      return alteration, true
    }
  }
  return {}, false
}

@(private)
chord_alteration_adding :: proc(interval: Interval, reduced: bool) -> (ChordAlteration, bool) {
  for alteration in CHORD_ALTERATIONS {
    if intervals_agree(alteration.altered, interval, reduced) {
      return alteration, true
    }
  }
  return {}, false
}

/*
The addition an interval names, highest degree first: reduced to within an
octave a second and a ninth are one note, and the ninth is the one a symbol
that stacks anything at all means.
*/
@(private)
chord_addition_adding :: proc(interval: Interval, reduced: bool) -> (ChordAddition, bool) {
  #reverse for addition in CHORD_ADDITIONS {
    if intervals_agree(addition.interval, interval, reduced) {
      return addition, true
    }
  }
  return {}, false
}

/*
An interval set indexed by degree within an octave, so that a base and an
observation can be compared a degree at a time. Returns false when two
intervals land on one degree, which is a set no symbol spells.
*/
@(private)
intervals_by_degree :: proc(intervals: []Interval) -> (found: [7]Interval, present: [7]bool, ok: bool) {
  for interval in intervals {
    degree := interval_simple(interval).steps
    if present[degree] {
      return {}, {}, false
    }
    found[degree]   = interval
    present[degree] = true
  }
  return found, present, true
}

@(private)
intervals_agree :: proc(interval, other: Interval, reduced: bool) -> bool {
  return reduced ? interval_simple(interval) == interval_simple(other) : interval == other
}

@(private)
intervals_omission :: proc(intervals: []Interval) -> (Interval, bool) {
  has_third   := slice.contains(intervals, MAJOR_THIRD)
  has_eleventh := slice.contains(intervals, PERFECT_ELEVENTH)
  if !has_third || !has_eleventh || !intervals_has_steps(intervals, 6) {
    return {}, false
  }

  if intervals_has_steps(intervals, 12) {
    return PERFECT_ELEVENTH, true
  }
  return MAJOR_THIRD, true
}

@(private)
intervals_has_steps :: proc(intervals: []Interval, steps: int) -> bool {
  for interval in intervals {
    if interval.steps == steps {
      return true
    }
  }
  return false
}

@(private)
intervals_remove_steps :: proc(intervals: ^[dynamic]Interval, steps: int) {
  for index := len(intervals) - 1; index >= 0; index -= 1 {
    if intervals[index].steps == steps {
      ordered_remove(intervals, index)
    }
  }
}

@(private)
intervals_replace :: proc(intervals: ^[dynamic]Interval, interval: Interval) {
  intervals_remove_steps(intervals, interval.steps)
  append(intervals, interval)
}

@(private)
intervals_sort :: proc(intervals: []Interval) {
  slice.sort_by(intervals, proc(a, b: Interval) -> bool {
    if a.steps != b.steps {
      return a.steps < b.steps
    }
    return a.semitones < b.semitones
  })
}

@(private)
intervals_equal :: proc(a, b: []Interval) -> bool {
  if len(a) != len(b) {
    return false
  }
  for interval, index in a {
    if interval != b[index] {
      return false
    }
  }
  return true
}

@(private)
accidental_prefix :: proc(text: string) -> (sign: u8, width: int) {
  if len(text) == 0 {
    return 0, 0
  }
  switch text[0] {
  case 'b': return 'b', 1
  case '#': return '#', 1
  }
  if strings.has_prefix(text, "♭") {
    return 'b', len("♭")
  }
  if strings.has_prefix(text, "♯") {
    return '#', len("♯")
  }
  return 0, 0
}

@(private)
scan_digits :: proc(text: string) -> (value: int, width: int) {
  for width < len(text) && is_digit(text[width]) {
    value  = value * 10 + int(text[width] - '0')
    width += 1
  }
  return
}
