# muse — Technical Design Document

## Overview

`muse` is a CLI music theory tool written in Odin. Given a scale, chord, or
degree, it prints notes, diatonic chords, voicings, inversions, and transpositions.
It is composable: the output of one invocation can be piped into another, modeled
after the `pastel` color tool.

---

## File Structure

| File | Responsibility |
|---|---|
| `theory.odin` | All music theory types, constants, and logic. No I/O. |
| `io.odin` | TTY detection, stdin reading. No theory. |
| `parse.odin` | CLI argument parsing, pipe protocol encode/decode. |
| `keyboard.odin` | ASCII piano keyboard rendering. |
| `display.odin` | All formatted stdout output, theming. |
| `main.odin` | Entry point and dispatch only. |

---

## Key Design Decisions

### Canonical pitch representation
Pitches are stored as a `PitchClass` enum (C through B, 12 values). Spelling
(whether a pitch is F# or Gb) is captured separately in a `Note` struct which
pairs a `PitchClass` with a letter (`'A'..'G'`) and an `Accidental`. This means
enharmonic equivalents are representable and distinguishable.

### Note spelling
For diatonic scales, notes are spelled by enforcing strict letter-name sequencing
(each degree gets the next letter A–G) and computing the required accidental from
the difference between that letter's natural pitch and the actual pitch class.
For chromatic scales and transposed chords where no letter constraint exists,
spelling falls back to a key accidental preference table (sharps or flats per root).

### Rodata tables
All lookup tables (scale intervals, chord qualities, diatonic chord tables, spelling
tables, etc.) are declared as `@(rodata)` package-level variables using `:=`.

### Chord model
A `Chord` carries its harmonic root, its bass note (which differs from root when
inverted), a `ChordQuality` (the base harmonic character), a `ChordExtension`
(how many notes: triad through 13th, add9, add11, power chord), an `Inversion`,
and the diatonic `ScaleDegree` it came from (zeroed if chromatic/transposed).
Chord quality is resolved from two separate tables: `DIATONIC_TRIADS` for
triad-based extensions and `DIATONIC_SEVENTHS` for seventh-and-above extensions.

### Inversions
Inversions are a transformation on an already-built chord, not a build parameter.
`chord_invert` rotates the notes array and updates the bass field. The harmonic
root is never changed. `MAX_INVERSION` per extension type enforces validity.
Display uses slash notation (e.g. `Cmaj7/E`).

### Transposition
`chord_transpose` shifts all notes by a semitone offset, re-spells using the new
root's accidental preference, and clears the degree field since the result is no
longer diatonic to any tracked scale. The original scale context is preserved in
the pipe output so downstream commands can treat the transposed chord's root as
an implied new key.

### Pipe protocol
When stdout is not a TTY, each display proc emits a single machine-readable line
instead of human output. Format:

```
muse:scale:<root>:<quality>:<note1>,<note2>,...
```

If a chord was resolved (e.g. from a transpose command), a chord segment is appended:

```
muse:scale:<root>:<quality>:<notes>:chord:<root>:<quality>:<notes>
```

Downstream invocations read the first stdin line, detect the `muse:` prefix, decode
the context, and use it as their working scale or chord. This enables:

```sh
muse gmaj | muse chords
muse gmaj iv +2 | muse chords
muse c#min | muse sevenths
```

### TTY vs pipe output
`is_stdout_tty` and `is_stdin_piped` use stat on POSIX and GetConsoleMode on
Windows. Every display proc takes an `is_tty: bool` parameter and branches on it —
rich ANSI colored output with the ASCII keyboard for TTY, plain pipe protocol line
otherwise.

### Scales without diatonic chord structure
`MajorPentatonic`, `MinorPentatonic`, `Blues`, and `Chromatic` have no clean
7-degree stacking. `scale_chord_at` returns `ok=false` for these. The diatonic
chord tables contain zero values for these rows as documented placeholders.

### Memory conventions
All procs that return strings take an optional `allocator` parameter defaulting to
`context.allocator`. Internal intermediate strings use `context.temp_allocator`.
Callers own returned strings and slices. `chord_all_inversions` and
`chord_all_inversions` allocate slices — callers in the CLI path should use a temp
allocator and free after display. `degree_display` always returns an owned string
(never a raw literal) so callers have a consistent contract.

### Display theming
`display.odin` owns a `Theme` struct of RGB+bold `Style` values. A `DEFAULT_THEME`
is defined there. Styles are only applied when `is_tty` is true; otherwise all
style calls are no-ops returning the input string unchanged. Separate style slots
exist for: root note, other scale notes, major/minor/diminished degree labels,
chord names, chord notes, transposed/highlighted results, and muted/inactive text.

---
