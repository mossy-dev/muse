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
Add an interval to a chord, replacing any interval of the same number, and
rename the result from the template table.

Returns false when the resulting set has no template, because muse would then
have no canonical way to spell it. Naming a set that is a template plus an
alteration is parking lot item F in DESIGN.md; until that exists, refusing is
the honest answer and the caller keeps the chord it had.
*/
chord_add_interval :: proc(chord: Chord, interval: Interval, allocator := context.allocator) -> (Chord, bool) {
  intervals := make([dynamic]Interval, 0, len(chord.intervals) + 1, context.temp_allocator)
  append(&intervals, ..chord.intervals)
  intervals_replace(&intervals, interval)
  intervals_sort(intervals[:])

  template, found := chord_template_match(intervals[:])
  if !found {
    return {}, false
  }

  return Chord {
    root      = chord.root,
    symbol    = strings.clone(template.symbol, allocator),
    intervals = slice.clone(intervals[:], allocator),
    bass      = chord.bass,
  }, true
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

  intervals := chord_stack(quality, has_quality, extension, has_extension)
  for modifier in modifiers {
    chord_apply_modifier(&intervals, modifier)
  }
  intervals_sort(intervals[:])

  return Chord {
    root      = root,
    symbol    = chord_symbol(intervals[:], quality, has_quality, extension, has_extension, modifiers[:], allocator),
    intervals = slice.clone(intervals[:], allocator),
    bass      = bass,
  }, true
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
Name the chord a set of notes forms, or false when no template matches.

The reading rooted on the first note supplied wins, per the ranking in
DESIGN.md: input order carries the bass and discarding it would be perverse, so
A C E G is Am7 while C E G A is C6. A root further along makes the first note a
slash bass, and a first note that belongs to no reading is dropped and becomes
one, which is how a bass outside the chord is recovered.

The remaining ranking rules have nothing to arbitrate. They separate two
templates matching at one root, and no two templates realize alike -- a property
the tests assert rather than assume. They are written when the table admits an
overlap that needs them.
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

  for root, index in unique {
    template, found := chord_match_at_root(root, unique[:])
    if !found {
      continue
    }

    chord := chord_make(root, template, allocator)
    if index != 0 {
      chord.bass = unique[0]
    }
    return chord, true
  }

  if len(unique) == 1 {
    return {}, false
  }

  for root in unique[1:] {
    template, found := chord_match_at_root(root, unique[1:])
    if !found {
      continue
    }

    chord := chord_make(root, template, allocator)
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

/*
The six alterations muse reads. A raised fourth is written #11 and a lowered
sixth b13, so neither needs a token of its own, and everything outside this set
is a parse error naming the token rather than a guess.
*/
@(private)
chord_alteration_token :: proc(sign: u8, degree: int) -> (string, bool) {
  switch {
  case sign == 'b' && degree ==  5: return "b5",  true
  case sign == '#' && degree ==  5: return "#5",  true
  case sign == 'b' && degree ==  9: return "b9",  true
  case sign == '#' && degree ==  9: return "#9",  true
  case sign == '#' && degree == 11: return "#11", true
  case sign == 'b' && degree == 13: return "b13", true
  }
  return "", false
}

@(private)
chord_alteration_interval :: proc(token: string) -> Interval {
  switch token {
  case "b5":  return DIMINISHED_FIFTH
  case "#5":  return AUGMENTED_FIFTH
  case "b9":  return MINOR_NINTH
  case "#9":  return AUGMENTED_NINTH
  case "#11": return AUGMENTED_ELEVENTH
  case "b13": return MINOR_THIRTEENTH
  }
  return UNISON
}

@(private)
chord_addition_token :: proc(degree: int) -> (string, bool) {
  switch degree {
  case  2: return "add2",  true
  case  4: return "add4",  true
  case  6: return "add6",  true
  case  9: return "add9",  true
  case 11: return "add11", true
  case 13: return "add13", true
  }
  return "", false
}

@(private)
chord_addition_interval :: proc(degree: int) -> Interval {
  switch degree {
  case  2: return MAJOR_SECOND
  case  4: return PERFECT_FOURTH
  case  6: return MAJOR_SIXTH
  case  9: return MAJOR_NINTH
  case 11: return PERFECT_ELEVENTH
  case 13: return MAJOR_THIRTEENTH
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
The template a set of notes forms when read from the given root, matching both
the full stack and the realization the omission rule produces so that
muse chord C13 --literal and muse chord C13 name the same chord.

Comparison is by spelled interval, reduced to within an octave since notes carry
no register: C to A is a major sixth here whether it was written as a sixth or
as a thirteenth, but never as a diminished seventh.
*/
@(private)
chord_match_at_root :: proc(root: Note, notes: []Note) -> (ChordTemplate, bool) {
  observed := make([dynamic]Interval, 0, len(notes), context.temp_allocator)
  for note in notes {
    append(&observed, interval_between(root, note))
  }
  intervals_sort(observed[:])

  for template in CHORD_TEMPLATES {
    if intervals_match_reduced(observed[:], template.intervals, false) {
      return template, true
    }
    if intervals_match_reduced(observed[:], template.intervals, true) {
      return template, true
    }
  }
  return {}, false
}

/*
Whether a set of intervals is a template's, reduced to within an octave and
optionally with the omission applied. Sizes have to agree and every reduced
template interval has to appear, which settles it: no template reduces to two
copies of one interval, so there is nothing for a count to disagree about.
*/
@(private)
intervals_match_reduced :: proc(observed: []Interval, intervals: []Interval, omit: bool) -> bool {
  omitted, has_omission := intervals_omission(intervals)

  size := len(intervals)
  if omit && has_omission {
    size -= 1
  }
  if size != len(observed) {
    return false
  }

  for interval in intervals {
    if omit && has_omission && interval == omitted {
      continue
    }
    if !slice.contains(observed, interval_simple(interval)) {
      return false
    }
  }
  return true
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
