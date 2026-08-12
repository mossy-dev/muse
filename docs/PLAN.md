# muse — Implementation Plan

Phases are ordered by dependency and each one ends in something testable. Read
`DESIGN.md` first; this document says what to build and in what order, not why.

## Rules that apply to every phase

- **A phase ends with `just test` green.** No phase lands with a failing test.
- **No empty stubs.** The previous attempt died holding four procs with empty
  bodies (`parse_chord_quality`, `parse_extension`, `parse_degree`,
  `parse_offset`) and a file that would not compile. If something is not
  implemented in this phase, it does not exist yet — no signature, no
  placeholder, no zeroed table row standing in for a decision.
- **One commit per phase**, imperative subject, no trailing work.
- **Tests are written in the same phase as the code they cover**, not after.
- **Nothing derivable gets stored.** If a table can be computed from intervals,
  compute it. This is the failure the rewrite exists to correct.
- **Open questions go to the parking lot in `DESIGN.md`**, not into a comment
  and not into an invented default.

---

## Phase 0 — Foundation *(complete)*

`src/muse/note.odin`, `src/muse/interval.odin` and their tests. `Letter`,
`Note`, `Pitch`, `Interval`, spelling arithmetic, MIDI, interval quality both
directions, interval parsing, named interval constants. 23 tests.

Committed on branch `rewrite` as `a1a13a9`, along with the `DESIGN.md` rewrite,
the `justfile` `test` recipe, and the removal of the five obsolete sources.

---

## Phase 1 — Notation for notes and pitches *(complete)*

The smallest layer that makes everything after it readable, and the first half
of the claim that output is valid input.

**Files:** `src/muse/notation.odin`, `src/muse/notation_test.odin`

**Build**
- `note_parse` / `note_string` — `C`, `F#`, `Bb`, `Gbb`, `Cx`.
- `pitch_parse` / `pitch_string` — `C4`, `F#-1`, `Bb10`.
- Accept Unicode accidentals on input (`♭ ♯ 𝄫 𝄪`), emit ASCII.
- Accept `x` for a double sharp on input; emit `##`.

**Gate**
- `note_parse(note_string(n)) == n` across all 7 letters × all 5 alterations.
- `pitch_parse(pitch_string(p)) == p` across a representative octave range,
  including negative octaves and the B#/Cb boundary.
- Malformed input rejected: `H`, `C#b`, `""`, `Cb#`, `4C`.

**Unblocks** every later test's readability, and all CLI note output.

---

## Phase 2 — Chord symbol specification *(complete; document only, no code)*

The riskiest piece, and the one the old design collapsed under. It gets written
down before a parser is attempted.

The rules are now settled in `DESIGN.md` — the grammar production, quality
picking the triad and the seventh, extension numbers stacking odd degrees, `6`
and `add` and `no` as stated exceptions, the eleventh-against-third omission and
`--literal`, and greedy root binding with a warning. This phase turns those
rules into an enumeration a parser can be tested against.

**File:** `docs/CHORD-SYMBOLS.md`

**Write**
- Every accepted input, with its canonical output and resulting interval set
  beside it. This table is the phase 3 test fixture, so it is the deliverable
  and not an illustration.
- The alias set, per parking lot item E: `Δ`, `ø`, `°`, `-`, `+`, `M`, `min`,
  `maj`, Unicode accidentals. First cut only, grown when something real fails.
- Worked derivations for the awkward cases: `C13`, `C11`, `Cm11`, `C6`, `C69`,
  `Cadd9`, `C7sus4`, `C7b9#11`, `Cm7b5`, `Cdim7`, `CmMaj7`, `C/E`, `C/D`.
- The exact condition that triggers the ambiguity warning: the root letter is
  followed immediately by an accidental, and the remainder also parses under the
  reading where that accidental is a modifier.

**Gate** every rule in `DESIGN.md` appears in the table with at least one worked
example, and no entry in the table contradicts another.

Written. `CHORD-SYMBOLS.md` closes its own section 12 with the rule-to-section
coverage map. Three things it settled that `DESIGN.md` had left implicit, each
argued in place: the omission rule is keyed on the interval set alone (`M3` and
`P11` and a seventh), canonicalization is a whole-set template lookup before it
is a token re-emission, and `Δ` and `ø` imply a seventh where `°` does not. It
also corrected the `C#11` example in `DESIGN.md`, which printed a ninth chord's
notes, and opened parking lot item F on naming chords no template matches.

---

## Phase 3 — Chords *(complete)*

**Files:** `src/muse/chord.odin`, `src/muse/chord_test.odin`

**Build**
- `Chord`, `ChordTemplate`, and the one template table driving construction,
  printing, parsing and identification.
- `chord_make(root, template)`, `chord_notes(chord)`, `chord_add_interval`.
- `chord_parse` / `chord_string` implementing phase 2's grammar.
- `chord_omissions(chord)` deriving the dropped degrees. A `Chord` always holds
  the full interval set; omission happens when it is realized into notes, which
  is what keeps `--literal` a rendering flag rather than a second chord type.
- `chord_identify(notes) -> (Chord, bool)`, applying the ranking in `DESIGN.md`.

**Gate**
- Every row of phase 2's accepted-input table parses to the expected chord and
  prints back as the canonical spelling.
- `chord_identify(chord_notes(c)) == c` for every template × all 12 roots.
- `chord_parse(chord_string(c)) == c` for the same cross product.
- **Both realizations identify alike.** The idiomatic and literal note sets of
  the same chord must both identify as that chord, or `--literal` breaks the
  pipeline: `muse chord C13 --literal | muse name` has to say `C13`.
- A C E G identifies as Am7, not C6, and reversing the input to C E G A gives
  C6 — the ranking's first rule doing its job.
- Slash chords round trip, including a bass that is not a chord tone.

Built, 15 tests. Three things the gates did not anticipate, each recorded in
`CHORD-SYMBOLS.md`:

- **Template realizations have to be pairwise distinct**, or identification is
  ambiguous at a single root and the round trip fails for whichever template
  loses. `9sus4` was cut for realizing exactly as `C11` does. A test asserts the
  property, and it is what leaves DESIGN's ranking rules 2 to 5 with nothing to
  arbitrate: only rule 1, the root taken from input order, is implemented.
- **A slash chord's notes need not round trip even though its symbol does.**
  D C E G is `C/D` and equally `Cadd9/D`, and identification prefers the reading
  that accounts for every note. The symbol is the datum, so the pipeline holds.
- **`chord_add_interval` returns false when the result has no template**, since
  naming a set that is a template plus an alteration is parking lot item F.

---

## Phase 4 — Scales

**Files:** `src/muse/scale.odin`, `src/muse/scale_test.odin`

**Build**
- `Scale`, `ScaleTemplate`, the template table, `scale_notes`.
- `scale_chord_at(scale, degree, size)` by stacking alternating scale members,
  naming the result through `chord_identify` rather than a diatonic table.
- `scale_harmonize(scale, size)` over every degree.
- Roman numeral degree labels, with case and suffix from the resolved chord
  quality.
- `scale_identify(notes)`, rooted at the first note supplied, with the other
  modal readings as annotation.

**Gate**
- Harmonizing every seven-note template reproduces the classical tables the old
  `DIATONIC_TRIADS` and `DIATONIC_SEVENTHS` hard-coded. Check the old values in
  git at `0d6af1b:theory.odin`, minus its two known wrong rows.
- Every note of every harmonized chord is a member of its parent scale.
- Every seven-note scale spells each letter exactly once, across all 12 roots
  and every heptatonic template.
- Non-heptatonic scales harmonize rather than failing: every degree of a
  pentatonic or blues scale produces a line, named where a name exists and
  carrying its note list as the datum where none does.
- `muse scale G## harmonic` reports the degree that outran double accidentals
  and suggests the enharmonic root, rather than emitting a wrong spelling.

---

## Phase 5 — Voicings *(complete; taken before phase 4)*

**Files:** `src/muse/voicing.odin`, `src/muse/voicing_test.odin`

**Build**
- `Voicing` over `[]Pitch`, ordered low to high.
- `voicing_close(chord, octave)` as the realization entry point, defaulting the
  bass to octave 4 so a close C major triad is MIDI 60, 64, 67.
- `voicing_invert(v, n)`, valid for any n on any voicing.
- `voicing_drop(v, n)` covering drop-2 and drop-3, `voicing_shell`,
  `voicing_open`.
- Slash bass placement: `Chord.bass` lands on the bottom of the realization.

**Gate**
- Pitches ascend in every voicing every operation produces.
- Inversion preserves the pitch-class set.
- Drop-2 on a four-note close voicing moves the second voice from the top down
  an octave and nothing else.
- `chord_identify` on a voicing's pitch classes returns the source chord.

Built, 14 tests. Taken out of order: voicings need chords and pitches and
nothing a scale provides, so phase 4 is the only one still open behind the CLI.

Two decisions the build settled:

- **Realization order lives in `chord_notes`, not in the voicing code.** A close
  voicing is that note list with octaves attached, one voice per note in the
  lowest octave that clears the one below. That forced a correction to phase 3:
  a bass that is already a chord tone now rotates the stack to start on itself
  rather than being moved to the front of it, so `C/E` reads E G C and realizes
  as the first inversion a player would write, instead of E4 C5 G5.
- **The five styles split by what they need.** `close` and `shell` take a chord,
  because a shell has to know which degrees are the third and the seventh, and a
  voicing alone does not carry that. `invert`, `drop` and `open` take a voicing
  and work on anything, muse-built or not.

`voicing_shell` keeps the root, the third or the suspension standing in for it,
and the seventh or the sixth. That rule is stated nowhere in `DESIGN.md`, which
only names the style; it is written down here because `C7sus4` and `C6` both
have an answer under it and neither has one under "root, third, seventh".

---

## Phase 6 — CLI core

First phase with a running binary. `just build` works again from here.

**Files:** `src/cli/main.odin`, `src/cli/args.odin`, `src/cli/render.odin`,
`src/cli/tty_unix.odin`, `src/cli/tty_windows.odin`

**Build**
- Arena allocator for the process, freed at exit.
- The one input rule: positional arguments, else stdin. A single helper.
- Tab-separated text rendering, datum in field one, annotations after.
- TTY detection driving color and column padding only.
- Commands: `scale`, `chord`, `notes`, `interval`.
- Error reporting to stderr with the offending token echoed; exit codes 0, 1, 2
  per `DESIGN.md`.

**Gate**
- `muse scale G major | muse notes` works end to end.
- Redirecting to a file and piping produce identical field one.
- A malformed argument exits 1 with no stdout output.

---

## Phase 7 — Full transform surface

**Build** `chords`, `degree`, `transpose`, `invert`, `voice`, `name`, `in`, and
`help`.

**Gate** every transform reads its operand from arguments and from stdin, and
every transform's output re-parses as another transform's input. The transform
table in `DESIGN.md` and the implemented set match exactly.

---

## Phase 8 — MIDI

The first output that is not notation, and the phase that makes the tool
generative. Depends on phase 5 for realization and phase 6 for writing bytes.

**Files:** `src/muse/smf.odin`, `src/muse/smf_test.odin`, and the `midi` sink

**Build**
- Variable-length quantity encoding, chunk headers, and a format 0 single track.
- Tempo, time signature, and key signature meta events, plus end of track.
- `smf_encode(voicings, options) -> []byte` in the library, returning bytes and
  touching no filesystem.
- The `midi` sink: stdout by default, `-o FILE` alternative, refusing to write
  binary to a terminal.
- `--tempo`, `--meter`, `--duration`, defaulting to 120bpm, 4/4, one bar each.
- Realize anything that is not already a voicing on the way through, so a scale
  or a bare note writes a file without a `voice` step.

**Gate**
- A decoder written in the test file reads back what the encoder produced: every
  note-on is matched by a note-off, delta times sum to the expected length, and
  the meta events carry the values asked for.
- Golden byte comparison for one fixed pipeline, so accidental format drift is
  caught rather than reasoned about.
- `muse chord Cmaj7 | muse midi` into a terminal exits non-zero and writes
  nothing to stdout.
- A file from `muse scale G major | muse midi` opens in a DAW and shows seven
  notes spelled to the key signature. Manual, once, recorded in the commit.

---

## Phase 9 — Remaining sinks, color, and the pipeline guarantee

**Build**
- The `json`, `numbers` and `info` sinks, each reading field one only and
  deriving the rest, per parking lot item A. `json` documented as unstable.
- `--color auto|always|never`, `--plain` to drop annotation columns.
- Golden transcript tests running the real binary over the pipelines in
  `DESIGN.md` and comparing verbatim.
- `README.md` with the worked examples.

**Gate** the golden transcripts pass, so "output is valid input" is enforced
rather than asserted. `muse chords G major | muse json` produces complete chord
objects, which is the proof that the text protocol carries the whole model.

---

## Sequencing notes

The chain is linear and each phase genuinely needs the one before it, with two
exceptions worth knowing: phase 1 depends only on phase 0, and phase 2 is a
document that could be written at any point. If work stalls, phase 2 is the one
to do while stalled — it is the largest remaining unknown and it costs no code.

Phase 6 is the first point at which the tool is usable. Nothing before it
produces a binary, which is a deliberate consequence of building the library
first; resist adding a throwaway main earlier, because the previous attempt's
CLI-shaped types leaked back into the theory layer and that is how `Chord`
ended up carrying an `inversion` field.

Phase 8 is the first point at which the tool is *useful* — a MIDI file in a DAW
is a different kind of output than a column of chord symbols, and it is the
phase most worth reaching. It is placed after the full transform surface because
a pipeline ending in `midi` is only interesting if the pipeline in front of it
can build something worth writing.
