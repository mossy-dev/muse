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

## Phase 0 — Foundation *(complete, uncommitted)*

`src/muse/note.odin`, `src/muse/interval.odin` and their tests. `Letter`,
`Note`, `Pitch`, `Interval`, spelling arithmetic, MIDI, interval quality both
directions, interval parsing, named interval constants. 23 tests.

**Immediate action:** commit this, plus the `DESIGN.md` rewrite, the `justfile`
`test` recipe, and the removal of the five obsolete sources.

---

## Phase 1 — Notation for notes and pitches

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

## Phase 2 — Chord symbol specification *(document only, no code)*

The riskiest piece, and the one the old design collapsed under. It gets written
down and agreed before a parser is attempted.

**File:** `docs/CHORD-SYMBOLS.md`

**Decide and tabulate**
- The grammar, unambiguously: root, quality, extension number, modifiers,
  parenthesised alterations, slash bass.
- Which extension numbers imply which lower tones. `C9` implies a dominant
  seventh; `C6` implies no seventh; `Cm11` implies a ninth. This is the exact
  place the old `[ChordQuality][ChordExtension]` outer product came from, so
  the rule must be stated as a rule and not as a table of outcomes.
- Whether `C13` emits the eleventh, and generally whether muse emits the full
  stack or the conventional one. Recommendation in the parking lot.
- The `Cb5` ambiguity — root `Cb` with a fifth, or `C` with a flatted fifth —
  and the binding rule that resolves it.
- Canonical output spelling for every alias set (`m7b5` / `ø`, `Δ` / `maj7`,
  `-` / `m`, `+` / `aug`).
- The full accepted-input table, with the canonical output beside each entry.
  This table is the phase 3 test fixture.

**Gate** the document exists, the ambiguities above have stated resolutions,
and the corresponding parking-lot entries in `DESIGN.md` are struck.

---

## Phase 3 — Chords

**Files:** `src/muse/chord.odin`, `src/muse/chord_test.odin`

**Build**
- `Chord`, `ChordTemplate`, and the one template table driving construction,
  printing, parsing and identification.
- `chord_make(root, template)`, `chord_notes(chord)`, `chord_add_interval`.
- `chord_parse` / `chord_string` implementing phase 2's grammar.
- `chord_identify(notes) -> (Chord, bool)` with a stated ranking rule for the
  cases where several readings fit — Am7 and C6 are the same four notes, and
  the rule that picks between them is written in the doc before it is coded.

**Gate**
- Every row of phase 2's accepted-input table parses to the expected chord and
  prints back as the canonical spelling.
- `chord_identify(chord_notes(c)) == c` for every template × all 12 roots.
- `chord_parse(chord_string(c)) == c` for the same cross product.
- Slash chords round trip, including a bass that is not a chord tone.

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
- `scale_identify(notes)` — subject to the modal ambiguity parking-lot entry.

**Gate**
- Harmonizing every seven-note template reproduces the classical tables the old
  `DIATONIC_TRIADS` and `DIATONIC_SEVENTHS` hard-coded. Check the old values in
  git at `0d6af1b:theory.odin`, minus its two known wrong rows.
- Every note of every harmonized chord is a member of its parent scale.
- Every seven-note scale spells each letter exactly once, across all 12 roots
  and every heptatonic template.
- Non-heptatonic scales harmonize per the parking-lot decision, and the
  pentatonic and blues templates are not special-cased to fail.

---

## Phase 5 — Voicings

**Files:** `src/muse/voicing.odin`, `src/muse/voicing_test.odin`

**Build**
- `Voicing` over `[]Pitch`, ordered low to high.
- `voicing_close(chord, octave)` as the realization entry point.
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

## Phase 7 — Full command surface

**Build** `chords`, `degree`, `extend`, `transpose`, `invert`, `voice`, `name`,
`in`, `info`, and `help`.

**Gate** every command reads its operand from arguments and from stdin, and
every command's output re-parses as another command's input. The command table
in `DESIGN.md` and the implemented set match exactly.

---

## Phase 8 — Formats, color, and the pipeline guarantee

**Build**
- `--format text|json|csv|midi`, defaulting to text and never switching itself.
- `--color auto|always|never`, `--plain` to drop annotation columns.
- A JSON schema for each output type, per the parking-lot entry.
- Golden transcript tests running the real binary over the pipelines in
  `DESIGN.md` and comparing verbatim.
- `README.md` with the worked examples.

**Gate** the golden transcripts pass, so "output is valid input" is enforced
rather than asserted.

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
