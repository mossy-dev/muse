# muse

[![ci](https://github.com/mossy-dev/muse/actions/workflows/ci.yml/badge.svg)](https://github.com/mossy-dev/muse/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A music theory CLI that composes. It answers questions about scales, chords,
intervals, voicings and transpositions, and the output of one invocation is
valid input to the next.

```
$ muse scale C major | muse chords I V vi IV | muse voice drop2 | muse midi > loop.mid
```

The binary reads notation on stdin and writes notation on stdout, so the shell
you already have is the sequencer.

## Install

Build it. muse needs [Odin](https://odin-lang.org/docs/install/) and nothing
else:

```
git clone https://github.com/mossy-dev/muse
cd muse
odin build src/cli -o:speed -out:muse
```

Put the resulting binary on your `PATH`.

Or with [just](https://github.com/casey/just):

```
just test       # the library, the CLI, and the golden transcripts
just install    # binary, man page and licence; honours PREFIX and DESTDIR
```

Then `muse --version` and `man muse`.

### Packages

Not yet published. The Arch and Homebrew packaging lives in
[`packaging/`](packaging/), and the first tagged release turns it on, along with
prebuilt binaries for Linux x86_64, macOS arm64 and macOS x86_64.

When it lands: `paru -S muse-cli` on Arch, `brew install mossy-dev/tap/muse` on
macOS. The command is `muse` either way.

## Worked examples

Scales, and the chords in them:

```
$ muse scale G major
G major  G A B C D E F#

$ muse scale G major | muse chords
G      I     G B D
Am     ii    A C E
Bm     iii   B D F#
C      IV    C E G
D      V     D F# A
Em     vi    E G B
F#dim  vii°  F# A C

$ muse chords G major --size 7
Gmaj7   Imaj7   G B D F#
Am7     ii7     A C E G
Bm7     iii7    B D F# A
Cmaj7   IVmaj7  C E G B
D7      V7      D F# A C
Em7     vi7     E G B D
F#m7b5  viiø7   F# A C E
```

Harmonizing stacks alternate members of the scale and names the result by
identifying it, so a pentatonic or a blues scale harmonizes too, and a stack
no template names carries its notes as the datum instead.

A degree sequence is a progression, in the order it was asked for:

```
$ muse chords I V vi IV C major
C   I   C E G
G   V   G B D
Am  vi  A C E
F   IV  F A C
```

A degree is written `4`, `IV` or `iv`, and the three are the same request. Case
carries quality when a numeral is printed.

Chord symbols are parsed rather than enumerated, and the degree a realization
drops is named rather than vanishing:

```
$ muse chord C13
C13  C E G Bb D A  omits 11

$ muse chord C11
C11  C G Bb D F  omits 3
```

`--literal` prints the full stack. It is a rendering flag: the chord holds the
complete interval set either way, and both realizations identify as `C13`.

Identification is the template table read backwards, ranked by the reading rooted
on the lowest note supplied:

```
$ muse name A C E G
Am7  A C E G

$ muse name C E G A
C6  C E G A
```

Voicings work on pitches, so inversion raises tones by an octave rather than
rotating an array:

```
$ muse chord Cmaj7 | muse voice drop2
G3 C4 E4 B4  Cmaj7/G

$ muse scale C major | muse chords I V vi IV | muse voice drop2
E3 C4 G4  C/E
B3 G4 D5  G/B
C4 A4 E5  Am/C
A3 F4 C5  F/A
```

Transposition preserves spelling, because an interval carries a letter distance
and a semitone distance together:

```
$ muse transpose m3 Cmaj7
Ebmaj7  Eb G Bb D

$ muse interval C E
M3  major third  4 semitones
```

`in` annotates with degrees and changes field one in no way at all, so it can sit
anywhere in a pipeline:

```
$ muse scale C major | muse chords | muse in C major
C     I
Dm    ii
Em    iii
F     IV
G     V
Am    vi
Bdim  vii°
```

## Sinks

A sink emits something that is not notation, so it ends a chain.

```
$ muse chord Cmaj7 | muse numbers
60 64 67 71

$ muse chord Cmaj7 | muse json
[
  {
    "type": "chord",
    "symbol": "Cmaj7",
    "root": "C",
    "bass": null,
    "notes": ["C", "E", "G", "B"],
    "intervals": ["P1", "M3", "P5", "M7"],
    "omitted": []
  }
]

$ muse scale G major | muse info
G major
  type      scale
  root      G
  notes     G A B C D E F#
  intervals P1 M2 M3 P4 P5 M6 M7
  midi      67 69 71 72 74 76 78
  triads    G Am Bm C D Em F#dim
  sevenths  Gmaj7 Am7 Bm7 Cmaj7 D7 Em7 F#m7b5
```

The JSON schema is **unstable** and may change without notice.

`muse midi` writes a Standard MIDI File to stdout but refuses a terminal. Use
`> FILE` or `-o FILE`. Every item takes the same duration, laid end to end:
`--tempo`, `--meter` and `--duration` move that, but nothing else about time is
expressible.

```
$ muse scale G major | muse chords --size 7 | muse voice drop2 | muse midi > loop.mid
```

The key signature is written where the pipeline knows a key — from a scale in the
input, or from `-k G major`. MIDI collapses Eb and D# to note 63, so this is
where the spelling work would otherwise stop mattering.

`muse keys` shows what every other command names.

```
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

## Commands

Transforms, which emit notation and compose freely:

| Command | Purpose |
|---|---|
| `scale <root> [name]` | build a scale, defaulting to major |
| `chord <symbol>` | build a chord from a symbol |
| `chords [degrees…]` | harmonize a scale: every degree, or the ones named |
| `notes` | reduce anything to its bare note list |
| `interval <a> <b>` | name the interval between two notes |
| `transpose <interval\|±semitones>` | transpose, preserving spelling |
| `invert <n>` | invert a voicing |
| `voice <close\|open\|drop2\|drop3\|shell>` | realize as pitches |
| `name <notes…>` | identify the chord or scale a note set forms |
| `in <key>` | annotate input with its degrees in a key |

Sinks, which end a chain:

| Command | Purpose |
|---|---|
| `midi` | write a Standard MIDI File |
| `json` | structured output for programs; unstable |
| `numbers` | bare MIDI note numbers, for scripts |
| `info` | everything muse knows about the input |
| `keys` | draw the input on an ASCII keyboard |

Flags:

| Flag | Purpose |
|---|---|
| `--size 3\|7\|9\|11\|13` | how far to stack a harmonization, default 3 |
| `--octave <n>` | where a realization sounds, default 4 |
| `--literal` | keep the degree a chord's realization drops |
| `--color auto\|always\|never` | whether to style output, default auto |
| `--plain` | drop the annotation columns and print field one |
| `--tempo <bpm>` | beats per minute of a MIDI file, default 120 |
| `--meter <n/d>` | time signature of a MIDI file, default 4/4 |
| `--duration <n/d>` | how long each item sounds, default one bar |
| `-k, --key <scale>` | the key to write a file in or name degrees against |
| `-o <file>` | write a MIDI file here instead of to stdout |
| `--help`, `--version` | print the command surface, or the version |

`man muse` says all of this again, at length.


## Platforms

Linux and macOS, on x86_64 and arm64. CI builds and runs the full suite on
Linux x86_64, macOS arm64 and macOS x86_64 for every change.

Windows is not supported and not refused: there is no platform-specific code in
the tree — terminal detection goes through `core:terminal`, which handles it —
so it may already work.

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md). The short version: `just test` has to be
green, `main` takes changes only through a pull request, and a change that alters
a single column of a single line of output has to say so in
`tests/transcript.txt`.

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — the model, the pipeline protocol, and what
  the previous design got wrong.
- [`docs/CHORD-SYMBOLS.md`](docs/CHORD-SYMBOLS.md) — the chord grammar, worked
  case by case.
- [`docs/PLAN.md`](docs/PLAN.md) — the build order, and what each phase settled.
- [`packaging/README.md`](packaging/README.md) — cutting a release, and where the
  packages go.

## License

MIT. See [LICENSE](LICENSE).
