# muse — Technical Design Document

## Overview

`muse` is a music theory library with a CLI on top, written in Odin. It answers
questions about scales, chords, intervals, voicings, and transpositions, and it
composes: the output of one invocation is valid input to the next.

The composability model is borrowed from `pastel`, and so is the reason it works
there — **a color is its own serialization**. `#ff0000` printed by one command
parses back to the same color in the next. This design applies that rule to
music: the wire format is ordinary musical notation. `Cmaj7` is what a human
reads and what the parser consumes. There is no second, machine-only format.

---

## What went wrong in the previous design

Recorded because the new design is mostly a reaction to it.

1. **Derived facts were stored as tables.** `DIATONIC_TRIADS` and
   `DIATONIC_SEVENTHS` (2 × 13 × 7 hand-written entries) restate what stacking
   thirds through a scale already produces. `EXTENSION_QUALITY_SUFFIX` is a
   `[ChordQuality][ChordExtension]` outer product — 104 strings, most of them
   nonsense (`Diminished` × `Thirteenth` = `dim13`). `SHARP_SPELLINGS` /
   `FLAT_SPELLINGS` / `KEY_ACCIDENTAL_PREFERENCE` guess at note spelling that
   interval arithmetic determines exactly.

   The tables are not merely verbose, they are wrong in places, and that is the
   point: hand-maintained redundancy drifts. `CHORD_INTERVALS[.MajorSeventh]`
   is `{0,4,7,0}` — no seventh. `.MinorMajorSeventh` is `{0,3,7,10}` — that is a
   minor seventh chord. `parse_scale_quality("chromatic")` returns
   `.MajorPentatonic`. None of these are reachable in a design that computes.

2. **`ChordQuality` conflated quality with size.** It contains both `Major` and
   `MajorSeventh`, so quality and `ChordExtension` are not orthogonal, so their
   combination needs a full lookup table, so half that table is undefined
   behaviour dressed up as data.

3. **No interval type.** Everything is a bare semitone count, which is why
   spelling needed heuristics and fallbacks at all. Semitones cannot distinguish
   an augmented second from a minor third, so the spelling of a transposed chord
   was never recoverable — only guessable.

4. **No octave.** `Note` is a pitch class. A voicing is an ordered set of
   *pitches*; without octaves, "voicing" collapses into rotating an array, which
   is what `chord_invert` does. Drop-2, open position, and shell voicings are
   inexpressible. `MAX_INVERSION` exists to police a model that cannot represent
   the thing it is policing.

5. **The `muse:scale:...` pipe protocol.** A bespoke positional format
   duplicating the type system in stringly form, with an appended optional
   `chord:` segment located by scanning for the literal token `chord`. Every new
   concept costs an encoder, a decoder, and a token table. It was also dead on
   arrival: `format_note` calls `fmt.aprint` with a format string, which
   concatenates rather than formats.

6. **TTY detection changed the data model.** `is_tty` selected between rich
   output and the pipe protocol, so `muse gmaj > file` and `muse gmaj | less`
   produced structurally different things. A terminal check should decide
   *styling*, never *content*.

7. **Per-command stdin fallback.** `read_root_quality` threads
   `fallback_root, fallback_quality, has_fallback` through every subcommand, and
   each subcommand re-implements the "args, else pipe, else error" ladder.

---

## Core model

Four types, layered. Each is a strict refinement of the one above.

```odin
// A letter name plus an alteration. No octave, no frequency.
Note :: struct {
  letter     : Letter,  // enum { C, D, E, F, G, A, B }
  alteration : int,     // -2..=2, flats negative
}

// A Note placed in an octave. Scientific pitch notation: C4 is middle C.
Pitch :: struct {
  note   : Note,
  octave : int,
}

// A diatonic distance and a chromatic distance, together.
Interval :: struct {
  steps     : int,  // letter steps: 0 unison, 2 third, 6 seventh, 7 octave
  semitones : int,
}
```

`Interval` carrying both numbers is the change everything else follows from. A
major third is `{2, 4}`; a diminished fourth is `{3, 4}`. They sound alike and
spell differently, and the type says so.

Deriving a pitch class is arithmetic, not a lookup:

```odin
note_pitch_class :: proc(note: Note) -> int {
  return (LETTER_SEMITONES[note.letter] + note.alteration) %% 12
}
```

Adding an interval picks the letter by step count, then solves for the
alteration that lands on the required semitone. Spelling is a consequence:

```odin
note_add_interval :: proc(note: Note, interval: Interval) -> (Note, bool)
```

It returns `false` when the answer needs a triple accidental, which is the only
honest response and never happens in practice. `SHARP_SPELLINGS`,
`FLAT_SPELLINGS`, `KEY_ACCIDENTAL_PREFERENCE`, and `spell_note_as_letter` all
delete. C transposed up a minor third is E♭, not D♯, because the interval said
so — no key-preference table is consulted.

MIDI number falls out of `Pitch` and handles the octave-boundary spellings
correctly without a special case, since the octave belongs to the letter:

```odin
pitch_midi :: proc(pitch: Pitch) -> int {
  return (pitch.octave + 1) * 12 +
         LETTER_SEMITONES[pitch.note.letter] + pitch.note.alteration
}
```

B♯3 is 60 and C♭4 is 59, as they should be.

---

## Collections

```odin
Scale :: struct {
  root      : Note,
  name      : string,      // canonical template name, e.g. "major"
  intervals : []Interval,  // from root, ascending, excluding the octave
}

Chord :: struct {
  root      : Note,
  symbol    : string,      // canonical, e.g. "maj7"
  intervals : []Interval,
  bass      : Maybe(Note), // slash chords: a harmonic claim, not a voicing
}

Voicing :: struct {
  pitches : []Pitch,       // ordered low to high
}
```

Slices, not `[12]Note` with a companion `len` field. A chord with a 13th and
alterations exceeds seven notes, a synthetic scale can exceed twelve, and the
fixed arrays cap both while shadowing the `len` builtin.

`Scale` and `Chord` store intervals rather than realized notes, so the notes are
generated on demand at whatever spelling and register is asked for. `Voicing` is
the only type holding concrete pitches, because that is the only type that
is *about* concrete pitches.

### Inversion is a voicing operation

Rotating a chord's notes does not invert a chord; raising its lower tones by an
octave does. `Chord` therefore has no `inversion` field and no `MAX_INVERSION`
guard. `voicing_invert(v, n)` moves the bottom `n` pitches up an octave, valid
for any `n`, on any voicing, including ones muse did not build. Slash notation
(`Cmaj7/E`) is a property of `Chord.bass` and is set deliberately, not inferred
from note order.

---

## Templates: one table per concept, both directions

A single table drives construction, printing, and identification.

```odin
ChordTemplate :: struct {
  symbol    : string,      // canonical output spelling
  aliases   : []string,    // accepted on input: "M7", "Δ", "-7"
  intervals : []Interval,
}

ScaleTemplate :: struct {
  name      : string,
  aliases   : []string,
  intervals : []Interval,
}
```

This replaces `CHORD_INTERVALS`, `CHORD_QUALITY_NAMES`,
`EXTENSION_QUALITY_SUFFIX`, `PIPE_CHORD_QUALITY_TOKEN`, and the
`parse_chord_quality` switch with one array; likewise `SCALE_INTERVALS`,
`SCALE_LENGTHS`, `PIPE_SCALE_QUALITY_TOKEN`, and `parse_scale_quality`.
Printing and parsing cannot disagree, because they read the same row.

Identification is the table searched backwards: normalize a set of notes to
intervals from a candidate root, match against templates, and report the best
fit. `muse name C E G B` → `Cmaj7`. Constructing and identifying become inverse
functions over one table, which makes them cheap to property-test against each
other.

### Chord symbols are parsed, not enumerated

`ChordExtension` as an enum forces a table for every quality it might combine
with. Real chord symbols are a small grammar:

```
symbol := root quality? extension? modifier* ("/" bass)?
```

`C7b9#11/E` parses to a root, a base template, and a list of alterations applied
to it. Adding `b13` costs one modifier rule rather than thirteen table rows.

### Harmonization is computed

`scale_chord_at(scale, degree, size)` stacks alternating scale members from the
degree, wrapping with octave displacement. For seven-note scales this is
stacking thirds and reproduces the old `DIATONIC_TRIADS` /
`DIATONIC_SEVENTHS` tables exactly. For other scales it produces whatever it
produces, which is then run through chord identification — so a pentatonic stack
is named honestly (a sus or quartal voicing, or an unnamed interval set) rather
than being a zeroed placeholder row that returns `ok = false`.

---

## Pipeline protocol: notation is the protocol

There is no `muse:` protocol. Output lines are notation, and notation parses.

- One item per line. **Field one is the datum**, delimited by a tab rather than
  by whitespace, since a datum may itself contain spaces; anything after it is
  annotation for humans and is discarded on input. Parking lot item 9 covers
  reading back a line that was formatted for a terminal.
- Field one is always a canonical *name* (`G major`, `Am7`, `C E G`), never a
  format only muse understands.
- Annotation columns carry roman numerals, note lists, interval names, MIDI
  numbers — anything derived.

```
$ muse scale G major
G major        G A B C D E F#

$ muse scale G major | muse chords
G              I      G B D
Am             ii     A C E
Bm             iii    B D F#
C              IV     C E G
D              V      D F# A
Em             vi     E G B
F#dim          vii°   F# A C

$ muse scale G major | muse chords | muse extend 7 | muse notes
G B D F#
A C E G
...
```

Every intermediate line above can be typed by hand as an argument. That is the
whole test of the format.

Consequences worth stating:

- **TTY affects layout and color only.** Column padding and ANSI styling appear
  on a terminal; a pipe gets single-tab separation. Field one is byte-identical
  either way. `--color auto|always|never` overrides detection; `--plain`
  suppresses annotation columns.
- **`--format text|json|csv|midi`** selects representation explicitly, defaulting
  to `text`. Piping never silently changes it. `json` exists for callers who
  want structure without parsing notation; it is not the pipeline format.
- **Context that a name cannot carry is passed explicitly.** Roman numerals need
  a key, so commands that need one take `-k/--key G major`. Nothing is smuggled
  through an invisible channel.

### One input rule

Every command reads its operand from positional arguments; if there are none, it
reads stdin. That single rule lives in one helper and replaces
`read_root_quality`'s `has_fallback` plumbing and each subcommand's fallback
ladder.

---

## Command surface

| Command | Purpose |
|---|---|
| `scale <root> [name]` | build a scale (default `major`) |
| `chord <symbol>` | build a chord from a symbol |
| `chords [--size 3\|7\|9…]` | harmonize every degree of a scale |
| `degree <n> [--size]` | harmonize one degree; accepts `IV`, `iv`, `4` |
| `extend <n>` | grow chords on stdin to 7ths, 9ths, 13ths |
| `notes` | reduce anything to its bare note list |
| `interval <a> <b>` | name the interval between two notes |
| `transpose <interval\|±semitones>` | transpose, preserving spelling |
| `invert <n>` | invert a voicing |
| `voice <close\|open\|drop2\|drop3\|shell\|spread>` | realize a chord as pitches |
| `name <notes…>` | identify the chord or scale a note set forms |
| `in <key>` | reinterpret input in a key; adds roman numerals |
| `info` | everything muse knows about the input |

Deleted from the old surface: `sevenths` / `7ths`, which was `ChordsCmd` with a
different default and duplicated its struct verbatim — now `chords --size 7`.

`transpose` accepts interval names (`+m3`, `-P5`) as well as semitone counts.
Semitones alone cannot determine spelling; interval names can, and the old
design's inability to say `m3` rather than `+3` is why it needed a preference
table to guess the result.

---

## Package layout

```
src/
  muse/                 library; no I/O, no stdout, no os
    note.odin           Letter, Note, Pitch, arithmetic, MIDI
    interval.odin       Interval, naming, arithmetic
    scale.odin          Scale, ScaleTemplate table, harmonization
    chord.odin          Chord, ChordTemplate table, identification
    voicing.odin        Voicing, inversion, drop and open voicings
    notation.odin       parse and print notation — the round trip
  cli/
    main.odin           dispatch only
    args.odin           argument grammar, the args-else-stdin rule
    render.odin         columns, color, --format backends
    tty_unix.odin       terminal detection
    tty_windows.odin
```

The old design's separation of theory from I/O was correct and is kept. The
change is that the theory half is an importable package with no CLI assumptions
in it, so the round-trip property between `notation.odin`'s parser and printer
can be tested without a process.

---

## Conventions

**Memory.** The CLI allocates everything from one arena and frees it at exit; a
process that runs for four milliseconds has no reason to track ownership. The
library takes an `allocator := context.allocator` parameter on every proc that
allocates, and callers own the result. Internal scratch uses
`context.temp_allocator`. The old rule that "`degree_display` always returns an
owned string so callers have a consistent contract" is kept and generalized: no
proc in the library ever returns a borrowed slice of a rodata table.

**Errors.** Parse failures return a specific error enum value naming the failed
token, printed to stderr with the offending input echoed. No partial output on
failure. Exit codes: `0` success, `1` usage or parse error, `2` a well-formed
request with no musical answer (a degree beyond the scale, an inversion of a
single note).

**Tables.** `@(rodata)` stays for genuinely arbitrary data — the template arrays,
letter-to-semitone, roman numerals. It goes for anything derivable.

**Style.** Two-space indent, expanded names, block comments above procs.
Unchanged.

---

## Testing

Absent from the old design; the bug list above is the cost of that. `core:testing`,
run by `just test`, with the properties the model makes available:

- **Round trip.** For every template and every root: `print(parse(s)) == s`, and
  `identify(notes(chord)) == chord`. This alone catches every naming bug listed
  at the top of this document.
- **Transposition is invertible.** `transpose(transpose(x, i), -i) == x`,
  including spelling. The old model cannot pass this; the new one must.
- **Harmonization is closed.** Every note of every diatonic chord is a member of
  its parent scale.
- **Spelling is well-formed.** Every seven-note scale uses each letter exactly
  once. This is the property the letter-stepping code was reaching for; here it
  is asserted rather than assumed.
- **Golden CLI transcripts.** The pipeline examples above, compared verbatim, so
  the "output is valid input" claim is enforced rather than aspirational.

---

## Parking lot

Decisions this design deliberately does not make. Each carries a proposed
default so that nothing here blocks starting; each must be settled before the
phase that depends on it, per `PLAN.md`. Strike entries as they are resolved.

**1. The chord symbol grammar.** `symbol := root quality? extension? modifier*
("/" bass)?` is a sketch, not a specification. Phase 2 writes the real one.
Everything from here to item 4 is part of it and is listed separately only
because each needs its own answer.

**2. Which lower tones an extension implies.** `C9` means a dominant seventh
with a ninth; `Cm11` implies the ninth as well; `C6` implies no seventh at all.
So an extension number is not a note, it is an instruction to stack up to that
number, with exceptions. The rule must be stated as a rule — the old
`[ChordQuality][ChordExtension]` table was what happened when it was not.

**3. Whether muse emits the full stack or the conventional one.** A literal
`C13` has seven notes including an eleventh that no player voices. Emitting the
full stack is consistent and makes identification symmetric; emitting the
conventional subset matches what a musician expects to read. *Proposed:* emit
the full stack, and let `voice` thin it, since a theory tool that silently drops
tones cannot be trusted as the input to another command.

**4. The `Cb5` binding ambiguity.** Root C-flat with a fifth, or C with a
flatted fifth. *Proposed:* an accidental binds greedily to the letter, so `Cb5`
is a C-flat power chord and the altered triad must be written `C(b5)`.

**5. Ranking among equally valid identifications.** A, C, E, G is Am7 and also
C6. The notes alone do not choose. *Proposed:* prefer the reading rooted on the
lowest supplied note, then the one built from stacked thirds, then the smaller
template — and report only the winner unless `--all` is given. The rule needs
writing down before `chord_identify` is coded, not after.

**6. Modal ambiguity in scale identification.** C major, A natural minor and D
dorian are one pitch-class set. *Proposed:* root the answer at the first note
supplied and report the other readings as annotation.

**7. Harmonizing non-heptatonic scales.** Stacking alternating members of a
pentatonic scale is not stacking thirds, and the resulting interval sets often
have no chord symbol. *Proposed:* emit them anyway, named by identification
where a name exists and by interval list where none does. What must not happen
is the old behaviour — a zeroed table row and `ok = false`.

**8. Roots that outrun double accidentals.** Some template and root pairings
need a triple sharp, and `note_add_interval` already refuses them. Whether the
CLI should then error, or respell the root enharmonically and say so, is
undecided. *Proposed:* error, naming the degree that failed, and suggest the
enharmonic root.

**9. Where the datum ends on an output line.** Field one may itself contain
spaces — `muse notes` emits `G B D` as a single datum — so the delimiter is a
tab, not whitespace. On a terminal, columns are space-padded instead, which
means a line copied off a terminal and pasted back as an argument has no tab in
it. *Proposed:* on input, split on tab when one is present, otherwise take the
whole line and attempt to parse it as a collection. Confirm this survives
contact with the phase 8 golden transcripts.

**10. The JSON schema.** `--format json` is specified to exist and nothing more.
It needs a shape per output type, and a decision on whether it is stable enough
to promise.

**11. `muse in <key>`.** Reinterpreting input in a key is in the command table
but its semantics are hand-waved. Does it respell notes, add roman numerals,
filter to diatonic members, or all three?

**12. Voicing details.** The default octave for realizing a chord (*proposed:*
C4 as the lowest chord tone) and what `spread` means as distinct from `open`.

---

## Non-goals

Audio synthesis or playback. Notation rendering. Tuning systems other than
12-TET. Rhythm, meter, and duration. MIDI file I/O — MIDI *note numbers* are an
output format, nothing more.

---

## Carried over from the previous design

Not everything was wrong.

| Kept | Note |
|---|---|
| Odin, single static binary, `justfile` | unchanged |
| Theory and I/O in separate layers | promoted to separate packages |
| Pitch class distinct from spelling | now derived from letter + alteration rather than stored alongside |
| `@(rodata)` tables for arbitrary data | scoped to data that is actually arbitrary |
| TTY detection via `isatty` / `GetConsoleMode` | kept; demoted to styling |
| Roman numeral degree display | kept as an annotation column |
| Piping as the central interaction | kept; the format changed |
| Scales, chords, inversions, transposition, extensions | the feature set was never the problem |
```
