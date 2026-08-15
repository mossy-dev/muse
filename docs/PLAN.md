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

## Phase 4 — Scales *(complete)*

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

Built, 16 tests. Both classical tables are in `scale_test.odin` as the fixture
and are reproduced across all 12 roots; nothing in `scale.odin` knows what a
diatonic seventh is. The old tables' two broken rows never arise, since the
qualities they named were right and only `CHORD_INTERVALS` was wrong.

Four things the build settled:

- **Size is a note count**, not a degree: 3 is a triad and 4 a seventh chord.
  The CLI's `--size 3|7|9|11|13` is the musician's spelling of the same thing and
  maps to 3, 4, 5, 6, 7 in phase 7, where the flag lives.
- **Stacking stops rather than repeating a note.** Alternate members of a
  six-note scale come back round to the root after three, so a blues scale
  harmonizes into three-note chords whatever size is asked for. Every degree
  still produces a line, which is the gate.
- **The degree label reads the notes, not the chord.** A stack no template names
  still has a third and a fifth, so it still has a numeral; deriving the label
  from a `Chord` would have left the chromatic scale's lines unlabelled.
- **`scale_parse` takes no default name.** `muse scale G` means G major, but that
  default belongs to the command with an argument missing. A parser that read a
  bare `C` as a scale would make every chord symbol ambiguous.

`scale_parse` / `scale_string` were not in the build list and are here anyway:
`G major` is a pipeline datum, so it has to parse, and the round trip is a phase
gate everywhere else. `AUGMENTED_UNISON` and `AUGMENTED_SIXTH` joined
`interval.odin` for the chromatic scale's ascending spelling.

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

## Phase 6 — CLI core *(complete)*

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

Built, 14 tests, and `just test` now runs both packages: `odin test` tolerates
the `main` proc, so the CLI's pure halves — the argument grammar, the datum
reader, the renderer — are testable without a process. The golden transcripts
that run the real binary stay in phase 9 where the plan puts them.

Three deviations from the file list, each for the same reason:

- **`tty.odin`, not `tty_unix.odin` and `tty_windows.odin`.** `core:terminal`
  already carries the `isatty` and `GetConsoleMode` calls behind one generic,
  along with the `NO_COLOR` and `TERM` reading a hand-rolled pair would have
  grown next. Two files of syscall bindings would restate a dependency rather
  than remove one.
- **`command.odin` holds the four commands**, because `DESIGN.md` says
  `main.odin` is dispatch only and means it.
- **`render_text` takes layout as a parameter** and `render` supplies it from
  the terminal check. That is what makes "a redirect and a pipe agree on field
  one" a test rather than a manual comparison.

Three things the build settled:

- **Layout is a parameter of rendering, not a mode of the program.** The only
  thing `output_is_terminal` reaches is column padding and color. Reading stdin
  is not gated on it, so `muse chord` with no arguments blocks on a terminal
  exactly as `cat` does, rather than growing a fourth TTY-dependent behaviour.
- **A command parses every datum in its input before rendering any of it.** That
  is what makes "no partial output on failure" true for a piped file of symbols
  and not only for a single bad argument.
- **`--literal` belongs to the invocation, not to the datum.** `muse chord C13
  --literal | muse notes` prints the idiomatic realization, because field one
  is `C13` and the next command renders it its own way. The flag is carried on
  `Options` and passed at realization, never into a parsed chord.

`Datum` is the union of everything field one can hold — scale, chord, note list,
voicing — and it is the CLI's own type rather than the library's, since it exists
only to decide which parser a line belongs to. The one overlap the ordering
settles is a single token like `C5`, which reads as the power chord rather than
as a one-note voicing.

---

## Phase 7 — Full transform surface *(complete)*

**Build** `chords`, `degree`, `transpose`, `invert`, `voice`, `name`, `in`, and
`help`.

**Gate** every transform reads its operand from arguments and from stdin, and
every transform's output re-parses as another transform's input. The transform
table in `DESIGN.md` and the implemented set match exactly.

Built, 22 tests: 14 in `cli`, and 8 in `muse` for the transposition the library
gained on the way. `DESIGN.md`'s transform table and the dispatch switch now
match name for name.

**A command's own argument comes off the front of its operands, and what is left
is the datum.** `operand_take` is the whole rule, so the one input rule is
untouched: `muse voice drop2 Cmaj7` and `muse chord Cmaj7 | muse voice drop2`
reach the same code. A key is the exception that needed a second rule, since
`G harmonic minor` is three tokens — `key_take` takes the longest prefix that
reads as a scale, so `muse in G major Am` splits where a reader expects.

Five things the build settled:

- **In `transpose`, a bare number is semitones and a quality letter is an
  interval.** `transpose 3` and `transpose M3` differ, which is the only way to
  have both forms `DESIGN.md` asks for. The semitone form has to invent a
  spelling, and `interval_from_semitones` takes the major, minor or perfect
  interval of that distance; the tritone is the one distance none of those spans
  and it takes the augmented fourth.
- **`name` reads a scale before a chord.** C D E F G A B is C major, though the
  same notes are equally a Cmaj13, and every set the two readings compete over
  is large enough that the scale is the question being asked. The chord reading
  is still reachable by asking `muse chord` for it, whereas chord-first would
  leave the major scale with no way to be named at all.
- **`voice` and `invert` realize anything that is not already a voicing**, so a
  scale voices without a chord step in front of it. Only `shell` needs a chord,
  for the reason phase 5 recorded, and a note set that names none is exit code
  2 rather than a parse error. `voicing_stack` became public as
  `voicing_from_notes`, since stacking notes is what realizing anything else is.
- **`in` reads the degree off the notes as they stand, except for a chord's
  slash bass.** A voicing carries no root, so its lowest pitch is the only thing
  a numeral can be measured from; a symbol carries one explicitly, so `C/E` in C
  major is `I` and not `iii`. Roots outside the key take the accidental that
  carries the key's own degree to them, which is how `bIII` and `#iv°` are
  written and why no table of chromatic degrees exists.
- **Transposition is library work.** `scale_transpose`, `chord_transpose` and
  `voicing_transpose` join their own files, so `DESIGN.md`'s invertibility
  property is a property test over every template and root rather than a CLI
  transcript. A scale whose new root spells but whose degrees do not is
  `scale_notes`' answer to give, since it is what knows which degree ran out.

`--size` is carried on `Options` as a note count, translated once where the flag
is read, so `chords` and `degree` never see the musician's numbering. `help`
prints to stdout and exits 0, where a command line with nothing on it prints the
same text to stderr and exits 1.

---

## Phase 8 — MIDI *(complete)*

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

Built, 19 tests: 11 in `muse` and 8 in `cli`. The decoder the gate asks for is
in `smf_test.odin`, and it refuses anything the encoder does not emit — a chunk
out of place, a running status, a voice message that is not a note — so the two
halves disagreeing is a failure rather than a shrug. The golden fixture is the
74 bytes of `muse chord Cmaj7 | muse midi`, event by event.

**The last gate is not met.** The file was not opened in a DAW; that check needs
a machine with one. `fluidsynth` renders the file without complaint, but it also
renders a truncated copy of it without complaint, so it is not evidence.

Five things the build settled:

- **A scale is a run and everything else is a stack.** Seven notes one to an
  item, rather than a seven-note cluster in one bar. `DESIGN.md`'s own remark
  that a scale reads better as quarter notes than as seven whole bars only
  parses if its notes are the items. A `voice` step in front of the sink makes
  the same scale one chord, which is how the cluster is asked for, so both
  readings are reachable and the datum's own form decides which one is default.
- **`-k/--key` is here, though the flag list said `--tempo`, `--meter` and
  `--duration`.** The key signature comes from the first datum that is a scale,
  which covers `muse scale G major | muse midi`; but `DESIGN.md`'s own MIDI
  pipeline harmonizes the scale away before the sink sees it, so without the
  flag the case the key signature exists for is the case that cannot reach it.
  It is the explicit context flag `DESIGN.md` already specifies for sinks. A run
  naming no key writes no key signature rather than guessing at C major.
- **The signature is arithmetic, not a table.** A letter's place on the circle
  of fifths is its semitone count times seven within the octave, an accidental
  moves the root seven places, and a minor mode reads three places back. A mode
  is minor when it has a minor third and no major one, which is the only reading
  of MIDI's two modes that needs nothing stored. Past seven accidentals the
  event is omitted, since notation has no signature to write there either.
- **`smf_in_range` is public so the CLI can name the line that failed.** The
  encoder refuses a pitch outside MIDI's 128 notes, but by then it no longer
  knows which input line the voicing came from. One definition, two callers,
  rather than a range check written twice.
- **The terminal refusal is a parameter, like the renderer's layout.** It runs
  before the input is read, so refusing costs the pipeline in front of it
  nothing, and `midi_refuses_terminal(output, is_terminal)` is a test rather
  than a manual comparison.

`Meter`, `Duration` and `SmfOptions` live in the library with the defaults on
them, and the CLI reads its own defaults from `smf_default_options` so the
numbers exist once. The duration a flag did not give is one bar, which is a
length only the meter knows, so the sink resolves it after both are read.

---

## Phase 9 — Remaining sinks, color, and the pipeline guarantee *(complete)*

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

Built, 9 more tests in `cli` and 25 pipelines in `tests/transcript.txt`. The
transcript is run by `tests/transcript.sh`, which `just test` now runs after both
packages; `just build` is a dependency of `test`, since a transcript needs a
binary to be a transcript of. Reverting one column of one line makes it fail,
which is the check that a golden file is worth keeping.

The gate holds: `muse chords G major | muse json` gives seven objects carrying
symbol, root, notes, intervals and omissions, and nothing reached the sink but
the seven symbols.

Five things the build settled:

- **A sink's whole output is built before a byte of it is written.** That is what
  makes "no partial output on failure" true of a file of symbols with a bad line
  at the end, and it is the same rule the transforms follow by rendering rows.
  `SinkError` is shared by all four sinks rather than being MIDI's own, so a line
  that is not notation exits 1 and a line with no musical answer exits 2 wherever
  it is met.
- **`json` emits one array rather than a line of JSON per line of input.** A sink
  is not in the pipeline protocol -- nothing reads it back -- so the one-item-per-
  line rule has no claim here, and a program reading a whole document is better
  served than one assembling a stream.
- **The degree in an object is the numeral `in` prints, from the same proc.** A
  sink takes `-k` exactly as a transform does, and going through `key_label`
  rather than around it is what stops a numeral in JSON and a numeral in a
  pipeline from disagreeing.
- **`--literal` reaches the sinks, and an object describes the realization it
  printed.** So `omitted` is empty under the flag, where the chord's own interval
  set is unchanged. The alternative -- a full stack of notes beside a claim that
  an eleventh was dropped -- is a contradiction on one line.
- **`info` omits a field it has no answer for rather than printing it blank**,
  which is what leaves a chord with no bass, a note set with no name, and a
  realization outside MIDI's 128 notes each one row shorter.

`--color` overrides detection in both directions and `--plain` drops the
annotation columns; neither can reach field one, which is the same guarantee the
layout already had. Alignment stays tied to the terminal, since a colour flag is
about colour.

---

## Phase 10 — The keyboard sink *(complete)*

An ASCII keyboard with the notes of the input pressed. It is the first output
that shows rather than names, and it is the cheapest way to make an interval or
a voicing obvious to someone who does not read symbols fluently.

**It is a sink, and that is forced rather than chosen.** A keyboard is several
lines tall, and the protocol is one item per line, so it cannot be an annotation
column on an existing command. Its output does not parse, so under `DESIGN.md`'s
test — a transform's output is valid input, a sink's is not — it ends a chain.
Which also means it reads field one and derives everything else, exactly as
`json` and `numbers` do, so it is one more witness that the text protocol
carries the whole model.

Depends on nothing after phase 6 and could be taken at any point from there;
it is last because nothing else waits on it.

**Files:** `src/cli/keyboard.odin`, `src/cli/keyboard_test.odin`

Presentation, so it lives in `cli/` rather than in the library. `smf.odin` goes
the other way because a MIDI file is an encoding a program will read back; a
drawing is for the eye, carries nothing the datum did not already have, and has
no meaning outside a terminal.

**Build**
- One octave is 28 columns and shares its right edge with the next, so a
  keyboard is the same drawing repeated and successive keyboards line up.
- Black keys straddle the boundary between two white keys, and there is none
  between E and F or between B and C. This is what makes it a keyboard rather
  than a row of twelve cells, and it is the only part of the drawing with a
  wrong answer.
- A pressed key is `*`: in the exposed foot of a white key, in place of the `#`
  on a black one. ASCII and not color, so the drawing survives a pipe, a paste,
  and a terminal that does no styling.
- One keyboard per datum, headed by the datum line itself, which is where the
  spelling lives: the picture can only show a pitch class, so `Bb` is named
  above a keyboard that marks the same key `A#` would.
- Register is derived, never asked for. A chord, a scale or a note list has none
  and draws a single octave; a voicing draws the octaves it spans and marks a
  pitch class twice when it sounds twice. The label row carries an octave number
  under each C once there is more than one.
- No trailing whitespace on any line.

**Gate**
- The three drawings below are the fixture, compared verbatim, so the anatomy is
  enforced rather than eyeballed once.
- The marked positions equal the datum's pitch-class set, over every chord
  template on all 12 roots. A keyboard that marks a key the chord does not hold
  is the one failure mode nobody would notice by looking.
- A two-octave keyboard is the one-octave drawing twice, less the shared edge.
- Piped and terminal output are byte-identical apart from color. The drawing has
  a fixed width and never reflows to the terminal.

```
$ muse chord C | muse keys
C	C E G
_____________________________
|  |#| |#|  |  |#| |#| |#|  |
|  |#| |#|  |  |#| |#| |#|  |
|  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |
|_*_|___|_*_|___|_*_|___|___|
  C   D   E   F   G   A   B

$ muse chord C7 | muse keys
C7	C E G Bb
_____________________________
|  |#| |#|  |  |#| |#| |*|  |
|  |#| |#|  |  |#| |#| |*|  |
|  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |
|_*_|___|_*_|___|_*_|___|___|
  C   D   E   F   G   A   B

$ muse chord Cmaj7 | muse voice drop2 | muse keys
G3 C4 E4 B4
_________________________________________________________
|  |#| |#|  |  |#| |#| |#|  |  |#| |#|  |  |#| |#| |#|  |
|  |#| |#|  |  |#| |#| |#|  |  |#| |#|  |  |#| |#| |#|  |
|  |_| |_|  |  |_| |_| |_|  |  |_| |_|  |  |_| |_| |_|  |
|   |   |   |   |   |   |   |   |   |   |   |   |   |   |
|___|___|___|___|_*_|___|___|_*_|___|_*_|___|___|___|_*_|
  C3  D   E   F   G   A   B   C4  D   E   F   G   A   B
```

`--octaves` is not in this phase. The span is derived from the datum in both
cases, and a flag overriding it can wait for someone who wants one.

Built, 6 tests in `cli` and 4 more pipelines in `tests/transcript.txt`. All three
drawings came out byte-identical to the fixture above on the first run, which is
the anatomy being derived rather than guessed at.

Four things the build settled:

- **The black keys are read off the letters, not off a table.** There is a black
  key at a boundary wherever two letters stand two semitones apart, which is
  `note_pitch_class` answering the question rather than a second statement of it
  that could drift from the first. The same derivation gives the twelve pitch
  classes their columns, so `keyboard_columns` is computed from the seven letters
  that generate it and cannot disagree with them.
- **The header names exactly what the picture marks.** Field one plus the notes
  drawn, and nothing else — so `C13` is headed by its six idiomatic notes and not
  by the `omits 11` column `muse chord` prints, since no key on the drawing
  answers to that eleventh. A voicing and a note list carry their spelling in
  field one already and so head a keyboard on their own.
- **Alignment is not asked of the terminal, where every other command asks.**
  There is one header row to a keyboard, so column padding has nothing to align
  against; the drawing under it is a fixed width in any case. That is what makes
  "piped and terminal are byte-identical apart from color" true by construction
  rather than by a comparison.
- **An octave is the letter's, not the sounding pitch's.** `B#3` marks the C at
  the left of the third keyboard rather than the one at the right of the second,
  because that is the octave `Pitch` already puts it in. The header carries the
  spelling that says so, which is the same division of labour the phase opened
  with.

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
