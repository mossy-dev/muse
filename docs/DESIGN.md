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

Realizing a chord has to put it somewhere, and the default is the octave
containing middle C: the bass note takes octave 4, so a close C major triad is
MIDI 60, 64, 67. `--octave` moves it. Choosing 4 rather than a lower register is
partly that close voicings then sit where a reader expects them and partly that
60 is the number everyone can check at a glance.

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

### Ranking among equal identifications

A, C, E and G are Am7 and are equally C6. The notes do not choose, so the rule
does, in this order:

1. Prefer the reading rooted on the lowest note supplied. Input order carries
   information and discarding it would be perverse.
2. Prefer a tertian reading — a clean stack of thirds from the root — over one
   that is not.
3. Prefer the reading with fewer alterations in its symbol.
4. Prefer the shorter canonical symbol.
5. Break remaining ties by root pitch class ascending, so output is stable
   across runs.

Only the winner is printed; `--all` lists every match in this order. For
A C E G rules 1 and 2 agree on Am7, which is the answer a musician gives.

Scale identification uses the same first rule and stops there: the answer is
rooted at the first note supplied, so C D E F G A B is C major and not A minor.
The other rotations are real readings and appear as annotation, or as their own
lines under `--all`.

### Chord symbols are parsed, not enumerated

`ChordExtension` as an enum forces a table for every quality it might combine
with. Real chord symbols are a small grammar:

```
symbol   := root quality? extension? modifier* ("/" bass)?
quality  := "m" | "min" | "-" | "maj" | "M" | "Δ" | "dim" | "°" | "aug" | "+" | "ø"
extension:= "5" | "6" | "7" | "9" | "11" | "13"
modifier := "(" alteration ")" | alteration | "sus" ("2"|"4")? | "add" number | "no" number
```

`C7b9#11/E` parses to a root, a base template, and a list of alterations applied
to it. Adding `b13` costs one modifier rule rather than thirteen table rows.

**Quality picks the triad and the seventh; the extension number says how high to
stack.** This is the rule the old outer-product table was a frozen enumeration
of. A quality contributes a triad and, when a seventh or higher is called for,
which seventh: none by default, minor for a bare dominant, major for `maj`,
diminished for `dim`, minor for `m` and `ø`. An extension number then includes
every odd degree from the seventh up to it, so `C9` is a dominant seventh with a
ninth and `Cm11` carries its ninth too.

Three tokens behave differently and are stated as exceptions rather than
absorbed into the rule: `6` substitutes a sixth for the seventh instead of
stacking, `add` contributes its degree without the intervening stack, and `no`
removes one.

**A natural eleventh and a major third are mutually exclusive.** In an eleventh
chord the eleventh wins and the third is dropped; in a thirteenth chord the
third wins and the eleventh is dropped. This is convention, but it is also the
better spelling — the two are a minor ninth apart and the clash is why players
omit one. The rule is deterministic, so identification stays symmetric, and the
dropped degree is named in an annotation column rather than vanishing:

```
$ muse chord C13
C13     C E G Bb D A      omits 11

$ muse chord C11
C11     C G Bb D F        omits 3
```

`--literal` suppresses the omission and emits the full stack. It is a rendering
flag only: a `Chord` always holds the complete interval set, and the omission is
applied when the chord is realized into notes. `muse chord C13` and
`muse chord C13 --literal` are the same value printed two ways, so the symbol
round trip is unaffected, and identification recognizes both note sets as `C13`.

**An accidental immediately after the root letter binds to the root.** The root
is read by the same note parser used everywhere else, so `C#11` is a C-sharp
eleventh chord and `Cb5` is a C-flat power chord; C with a sharp eleventh is
written `C(#11)`. The ambiguity exists only when nothing separates the root from
the modifier — in `C7#11` the `7` closes the root and no question arises. Where
a symbol admits both readings, muse says how it read it:

```
$ muse chord C#11
C#11    C# G# B D# F#      omits 3
note: read as root C#; write C(#11) for C with a sharp eleventh
```

The warning goes to stderr, so it never contaminates a pipeline.

### Harmonization is computed

`scale_chord_at(scale, degree, size)` stacks alternating scale members from the
degree, wrapping with octave displacement. For seven-note scales this is
stacking thirds and reproduces the old `DIATONIC_TRIADS` /
`DIATONIC_SEVENTHS` tables exactly.

For scales that are not heptatonic the same stacking applies, and the result is
run through chord identification. Where a name exists it is used. Where none
does, the datum for that line is the note list itself, which is a legitimate
datum that downstream commands already accept, with the interval pattern as
annotation. Nothing is special-cased to fail, and no zeroed table row stands in
for a decision — those were the previous design's answer and they are the reason
`muse chords C majpent` returned nothing at all.

---

## Pipeline protocol: notation is the protocol

There is no `muse:` protocol. Output lines are notation, and notation parses.

- One item per line. **Field one is the datum**, delimited by a tab rather than
  by whitespace, since a datum may itself contain spaces; anything after it is
  annotation for humans and is discarded on input.
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

$ muse scale G major | muse chords --size 7 | muse notes
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
- **There is no output format flag.** Notation is the only thing muse commands
  emit. Anything else — JSON, a MIDI file — is produced by a sink, and sinks
  are commands.
- **Context that a name cannot carry is passed explicitly.** Roman numerals need
  a key, so commands that need one take `-k/--key G major`. Nothing is smuggled
  through an invisible channel.

### Transforms and sinks

Every command is one or the other, and which it is can be read off whether its
output parses.

A **transform** takes notation and emits notation, so it can appear anywhere in
a chain. A **sink** emits something else — structured data, a binary file, prose
— and therefore ends one. Making sinks ordinary commands rather than a
`--format` flag keeps the distinction visible in `--help`, and it takes the
representation question out of every transform: a transform has exactly one way
to print itself.

It also puts the pipeline protocol under load in a useful way. A sink reads
field one and nothing else, exactly as a transform does, then derives everything
it emits from the parsed datum. If `muse chords G major | muse json` can produce
full chord objects, the text protocol is provably complete enough to reconstruct
the model — the sinks are the invariant's test harness rather than a bypass
around it.

Annotation columns do not survive into a sink, because they never survive
anywhere: a roman numeral is commentary relative to a key, not a property of the
chord. Sinks take the same explicit context flags transforms do, so
`muse json -k "G major"` gets degrees into the output by the normal route.

### One input rule

Every command reads its operand from positional arguments; if there are none, it
reads stdin. That single rule lives in one helper and replaces
`read_root_quality`'s `has_fallback` plumbing and each subcommand's fallback
ladder.

Reading a datum takes two more rules, both small enough to state completely:

- **From arguments:** join the remaining positional arguments with single spaces
  and parse the result. `muse chord C E G` and `muse chord "C E G"` are the same
  request, and no command needs to know how the shell split its input.
- **From a line:** if the line contains a tab, the datum is everything before
  the first one; otherwise the whole line is the datum. A piped line always has
  its tab. A line copied off a terminal is space-padded rather than tabbed, but
  it is also being retyped as arguments by then, where the join rule applies.

---

## Command surface

Transforms, which emit notation and compose freely:

| Command | Purpose |
|---|---|
| `scale <root> [name]` | build a scale (default `major`) |
| `chord <symbol>` | build a chord from a symbol |
| `chords [--size 3\|7\|9…]` | harmonize every degree of a scale |
| `degree <n> [--size]` | harmonize one degree; accepts `IV`, `iv`, `4` |
| `notes` | reduce anything to its bare note list |
| `interval <a> <b>` | name the interval between two notes |
| `transpose <interval\|±semitones>` | transpose, preserving spelling |
| `invert <n>` | invert a voicing |
| `voice <close\|open\|drop2\|drop3\|shell>` | realize a chord as pitches |
| `name <notes…>` | identify the chord or scale a note set forms |
| `in <key>` | annotate input with its degrees in a key |

Sinks, which end a chain:

| Command | Purpose |
|---|---|
| `midi` | write a Standard MIDI File |
| `json` | structured output for programs |
| `numbers` | bare MIDI note numbers, for scripts |
| `info` | everything muse knows about the input |

Deleted from the old surface: `sevenths` / `7ths`, which was `ChordsCmd` with a
different default and duplicated its struct verbatim — now `chords --size 7`.

An earlier draft also listed `csv`, cut for being a flatter `json` aimed at a
spreadsheet nobody had asked for. `json` covers structured output and `numbers`
covers the scripting case between them.

### A transform needs no context its input does not carry

An earlier draft listed `extend <n>`, growing chords on stdin to sevenths and
beyond. It is cut, and the reason generalizes into a rule worth keeping.

`muse chord C | muse extend 7` cannot be answered. Diatonically the answer is
Cmaj7; by symbol convention a bare seventh is dominant, so C7. Resolving it
needs a key, and the key is exactly what the chord symbol `C` does not carry.

The key is not missing from the pipeline, though — it *is* the datum, right up
until a collection expands into its members. `muse scale G major` puts `G major`
in field one, `chords` reads it, and the key evaporates only because `chords`
replaces one collection with seven members. So the problem is not transport. The
problem is that harmonizing and extending were split across that expansion, and
`chords --size 7` does both on the near side of it, where the key is still
present.

Hence the rule: **if a transform needs context its input datum does not carry,
the pipeline was split in the wrong place.** Fixing the split is available;
threading hidden state is what the old `muse:` protocol did, and re-earning that
mistake for one command would be a poor trade.

### Where a key comes from

Nothing on the surface currently needs a key it is not handed: `in` takes one as
its argument, `degree` and `chords` read the scale from their input. When
something does need one, it takes `-k/--key`, defaulting to C major.

Config files and an environment variable are the other conventional paths and
both are plausible later. Neither is in scope until muse has a packaging story,
and adding a config format before there is a platform to install it on would be
building the second half of a bridge.

**`in` annotates and never transforms.** It adds roman numerals and degree
labels relative to the key and leaves field one exactly as it found it, so it
can sit anywhere in a pipeline without changing what the next command receives.
Respelling notes to suit a key signature is a different operation on different
data, and folding it into `in` would make a commentary command silently mutate
its input.

`voice` offers `close`, `open`, `drop2`, `drop3` and `shell`. An earlier draft
listed `spread`, which was cut: `open` already means displacing alternate chord
tones by an octave, and `spread` had no definition beyond a vague sense of being
wider. A style with no crisp definition cannot be tested and does not belong on
the surface.

---

## MIDI output

`muse midi` is what makes the tool generative rather than only informative, and
it is the reason the chain has an end worth reaching:

```
muse scale G major | muse chords --size 7 | muse voice drop2 | muse midi > loop.mid
```

**It writes to stdout and refuses a terminal.** Positional arguments belong to
the datum under the one input rule, so a filename cannot go there; redirection
is the natural unix answer, with `-o FILE` for when it is not. Refusing to dump
binary into a terminal gives TTY detection a third job, and like the other two —
color, column padding — it is presentation only and never touches the model.

**muse has a uniform grid, not rhythm.** This is a deliberate puncture of the
non-goal below, fenced as narrowly as it can be: every item takes the same
duration, laid end to end, and nothing else about time is expressible. No
patterns, no swing, no velocity shaping, no second track. Defaults are 120bpm,
4/4, velocity 80, channel 1, 480 ticks per quarter, format 0, one item per bar.
`--tempo`, `--meter` and `--duration` move them; `--duration 1/4` is the usual
one, since a scale reads better as quarter notes than as seven whole bars.

Deliberately absent is `--bars N`. Fitting seven chords into eight bars has no
obvious rule, and guessing at one would be the same mistake as the old design's
placeholder table rows.

**The key signature meta event is worth emitting.** MIDI collapses Eb and D# to
note 63, so this is exactly where the library's spelling work would normally
stop mattering. SMF carries a key signature event and DAWs read it to choose
enharmonics, so when the pipeline knows the key, that spelling survives into the
notation view of whatever it lands in.

**Encoding lives in the library, writing lives in the CLI.** `smf.odin` produces
a `[]byte` and returns it; `cli` writes the bytes. The rule that the library
performs no I/O is what allows the encoder to be tested without a filesystem,
and SMF is small enough — chunk headers, variable-length delta times, three meta
events — that this costs nothing to arrange.

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
    smf.odin            Standard MIDI File encoding to a byte slice
  cli/
    main.odin           dispatch only
    args.odin           argument grammar, the args-else-stdin rule, the datum
    command.odin        the transforms
    render.odin         columns and color
    sink.odin           midi, json, numbers, info
    tty.odin            terminal detection, over core:terminal
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

**Unspellable results.** `note_add_interval` refuses anything needing a triple
accidental, and a few root and template pairings reach that: G## harmonic minor
wants an F###. Reaching it at all takes a root that is already doubly altered,
since every scale on a singly altered root stays within double accidentals. The
CLI reports which degree failed and, when respelling the root enharmonically
succeeds, names that root as the suggestion. It does not silently respell —
`muse scale G## harmonic` asked a precise question and deserves a precise no.

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

Twelve entries opened with this design. Nine are now settled and live in the
sections they govern: the chord grammar and its quality/seventh rule, extension
implication, the eleventh-against-third omission and `--literal`, root
accidental binding, identification ranking, modal ambiguity, non-heptatonic
harmonization, unspellable roots, the datum delimiter, `in` semantics, and the
voicing octave. What follows is what genuinely remains, plus what MIDI output
added on its way in.

**A. The JSON schema.** The shape below is enough to build against, with a
`type` discriminator on every object and `midi` present only where a register
exists — a chord has no octave, a voicing does.

```json
{ "type": "chord", "symbol": "Cmaj7", "root": "C", "bass": null,
  "notes": ["C","E","G","B"], "intervals": ["P1","M3","P5","M7"],
  "omitted": [] }
```

What is unsettled is whether this is a promise. Until muse is worth depending
on programmatically, `muse json` is explicitly unstable and says so in `--help`.
Revisit if anything ever consumes it.

**B. Harmonizing by subset rather than by stacking.** For pentatonic and blues
scales, a more useful question than "stack alternate members" is "which named
chords have all their tones in this scale". That is a different operation, not a
better implementation of the current one, so it stays out of `chords` and waits
for its own command — `fit`, or `chords --subset`. Deferred on scope, not on
uncertainty.

**C. A key that persists through a chain.** Considered and declined, recorded
here so it is revisited on evidence rather than re-argued from scratch.

The idea: a key introduced anywhere in a pipeline stays in effect downstream
until replaced, so commands needing one stop having to be told. The strongest
implementation is a **key line** — `in G major` prepends a line whose datum is
`G major`, and downstream commands read it if present. That keeps the stream
all-notation, since a scale is a legitimate datum, so it is a real mechanism
rather than a hack.

It was declined on cost. Line one becomes special, `notes` and `midi` and every
other command grow a branch for it, and "any intermediate line can be typed by
hand" stops holding. That last one is the whole pipeline invariant. Against
that, the benefit is currently zero: with `extend` cut, no command needs a key
it is not handed.

Revisit when a *third* command wants one — `voice-lead` and `fit` are the likely
candidates — at which point the trade is being made against real demand.

**D. Voice leading, and arpeggiation.** Both are `Voicing → Voicing`, so both
fit the model exactly, and both would make MIDI output markedly more musical:
`voice-lead` minimizing movement between successive chords so a progression
stops leaping around in parallel root position, and `arp` spreading a voicing
across time. Voice leading is the more valuable of the two and the more
interesting to specify, since "minimal movement" needs a stated cost function.

They are deferred rather than rejected. The line they sit just inside is the one
in the non-goals: an operation on voicings is music theory, whereas rhythm
patterns and humanization are a sequencer. Arpeggiation is the closest to that
line, since it is the first feature that would want more than a uniform grid.

**E. How much of the accepted-input table is worth carrying.** The grammar is
settled but the alias set is a judgement call with no natural boundary: `Δ`,
`ø`, `°`, `-` and `+` are clearly worth accepting, Unicode double accidentals
probably, and beyond that it is guesswork about notation nobody in this repo
writes. Phase 2 enumerates a first cut in `CHORD-SYMBOLS.md` and the table grows
when something real fails to parse.

**F. Naming a chord that is not a template.** Identification matches interval
sets against the template table, so `C E G Bb Db` — a `C7b9` — has no name and is
reported as a note list, exactly as a pentatonic harmonization is. Symbols built
by alteration are constructible and printable but not identifiable, which is an
asymmetry the round-trip gates do not catch because they range over templates.

The fix is not more rows. It is matching the nearest template and expressing the
remainder as alterations, which is an algorithm rather than a table and fits the
design. What it needs first is a stated limit — how many alterations are worth
carrying before "no name" is the more honest answer — and that limit is a
judgement best made against real output. Deferred until identification exists.

---

## Non-goals

Audio synthesis or playback. Notation rendering. Tuning systems other than
12-TET. Reading MIDI files — muse writes them and does not parse them.

Rhythm was a non-goal in the first draft of this document and is now a fenced
one. `muse midi` needs time to exist, so a uniform grid exists: equal durations
laid end to end, configurable in aggregate and in no other way. Patterns,
swing, velocity shaping, multiple tracks, and anything resembling a sequencer
stay out. The fence is the whole concession — see the MIDI section for where it
sits.

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
