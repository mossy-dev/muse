# muse — Chord Symbol Specification

The grammar and its rules are settled in `DESIGN.md`. This document turns them
into an enumeration: every accepted form, its canonical output, and the interval
set it produces. **The tables below are the phase 3 test fixture**, not an
illustration — a row is a test case, read column by column.

Interval abbreviations are `interval.odin`'s: `P1 m3 M3 P4 d5 P5 A5 M6 d7 m7 M7
m9 M9 A9 P11 A11 m13 M13`. Note lists are the *idiomatic* realization, with the
omission rule already applied; the `omits` column names what was dropped. Roots
are C unless a row says otherwise.

---

## 1. Grammar

```
symbol     := root quality? extension? modifier* bass?
root       := letter accidental*                 ; note.odin's parser, greedy
quality    := "m" | "min" | "-" | "maj" | "M" | "Δ"
            | "mMaj" | "mmaj" | "minMaj" | "minmaj" | "mΔ" | "-Δ"
            | "m(maj7)" | "min(maj7)" | "-(maj7)"
            | "dim" | "°" | "aug" | "+" | "ø" | "ø7"
extension  := "5" | "6" | "69" | "6/9" | "7" | "9" | "11" | "13"
modifier   := alteration | sus | add | omit | "(" modifier (","? modifier)* ")"
alteration := "b5" | "#5" | "b9" | "#9" | "#11" | "b13"
sus        := "sus" ("2" | "4")?                 ; bare "sus" is "sus4"
add        := "add" ("2"|"4"|"6"|"9"|"11"|"13")
omit       := ("no" | "omit") ("3"|"5"|"7"|"9"|"11"|"13")
bass       := "/" root
```

Parsing is left to right and each slot is matched longest-first: `min` before
`m`, `maj` before `M`, `69` before `6`, `13` before `1`. The quality and the
extension appear at most once each; modifiers repeat freely. Unicode accidentals
(`♭ ♯ 𝄫 𝄪`) and `x` are read anywhere a root is read, `♭` and `♯` are read in an
alteration too, and all of them are emitted as ASCII.
Roots are uppercase — `cmaj7` is a parse error, because `c` is not a letter the
note parser accepts.

The bass is the last `/` whose remainder parses as a note. A `/` whose remainder
is not a note is not a bass, which is what leaves `C6/9` free to mean `C69`.

---

## 2. Quality

A quality contributes a triad, and it contributes *which seventh* when a seventh
or higher is called for. It never adds a seventh on its own, with the two stated
exceptions.

| Token | Aliases | Triad | Its seventh | Implies a seventh |
|---|---|---|---|---|
| *(none)* | | `P1 M3 P5` | `m7` | no |
| `m` | `min`, `-` | `P1 m3 P5` | `m7` | no |
| `maj` | `M` | `P1 M3 P5` | `M7` | no |
| `Δ` | | `P1 M3 P5` | `M7` | **yes** |
| `mMaj` | `mmaj`, `minMaj`, `mΔ`, `-Δ` | `P1 m3 P5` | `M7` | no; requires an extension of 7 or more |
| `dim` | `°` | `P1 m3 d5` | `d7` | no |
| `aug` | `+` | `P1 M3 A5` | `m7` | no |
| `ø` | `ø7` | `P1 m3 d5` | `m7` | **yes** |

`Δ` and `ø` are seventh-chord glyphs in practice, so a bare `CΔ` is `Cmaj7` and a
bare `Cø` is `Cm7b5`. `°` is not: `C°` is the triad, `C°7` the seventh chord.
That asymmetry is convention, and it is the reason `°` is not given the same
implication as the other two.

`ø` is a spelling of `m` + `b5`, and canonical output says so: it re-emits as
`m7b5`, `m9b5`, `m11b5`. `Δ` re-emits as `maj`.

A major seventh over an augmented triad is written `maj7#5`. There is no
two-quality form — `CaugMaj7` is a parse error.

---

## 3. Extension

The number says how high to stack. It includes **every odd degree from the
seventh up to itself**, unaltered unless a modifier says otherwise.

| Token | Adds | On C, with no quality |
|---|---|---|
| `5` | *(exception)* root and fifth only, no third | `P1 P5` |
| `6` | *(exception)* triad + `M6`, no seventh | `P1 M3 P5 M6` |
| `69` | *(exception)* triad + `M6` + `M9` | `P1 M3 P5 M6 M9` |
| `7` | triad + the quality's seventh | `P1 M3 P5 m7` |
| `9` | 7 + `M9` | `P1 M3 P5 m7 M9` |
| `11` | 9 + `P11` | `P1 M3 P5 m7 M9 P11` |
| `13` | 11 + `M13` | `P1 M3 P5 m7 M9 P11 M13` |

`5` takes no quality: it deletes the third, so a quality would have nothing to
say. `Cm5` is a parse error. `6` and `69` take any quality, since a sixth over a
minor or diminished triad is well defined.

---

## 4. Modifiers

**Alteration.** `bN` / `#N` sets degree N to the altered interval: it replaces
that degree if the set already has it, and adds it if not. It adds nothing else —
only an extension number stacks, so `C7#11` has no ninth.

| Token | Interval | Replaces | Adds when absent |
|---|---|---|---|
| `b5` | `d5` | `P5` | `d5` |
| `#5` | `A5` | `P5` | `A5` |
| `b9` | `m9` | `M9` | `m9` |
| `#9` | `A9` | `M9` | `A9` |
| `#11` | `A11` | `P11` | `A11` |
| `b13` | `m13` | `M13` | `m13` |

These six are the whole set. `b7`, `#4`, `b11`, `#13` and the rest are parse
errors naming the offending token; a raised fourth is written `#11`.

**`sus`.** Removes the third and adds `M2` (`sus2`) or `P4` (`sus4`). When the
set already carries an eleventh, `sus4` removes the third and adds nothing,
since `P4` and `P11` are the same pitch class — that is what makes `C13sus4` six
notes rather than seven.

**`add`.** Contributes one degree without the intervening stack. `add2` is `M2`,
`add4` is `P4`, `add6` is `M6`, `add9` is `M9`, `add11` is `P11`, `add13` is
`M13`. `add2` and `add9` are different intervals in the same pitch class and stay
distinct, because a voicing can tell them apart.

**`no` / `omit`.** Removes a degree by number, whatever its quality: `no5` drops
`P5`, `d5` or `A5` alike.

**Parentheses.** Wrap any modifier or a comma-separated run of them. `C7(b9)`,
`C7(b9,#11)` and `C7b9#11` are the same chord.

---

## 5. The eleventh against the third

A natural eleventh and a major third are a minor ninth apart, and one of them is
dropped when the chord is realized into notes. The condition is a property of the
interval set alone, so `chord_omissions` is derivable and identification stays
symmetric:

> If the set contains `M3` **and** `P11` **and** a seventh of any quality, then
> drop `P11` if the set also contains a thirteenth, otherwise drop `M3`.

Three consequences, each with a row in the tables below:

- `Cm11` keeps everything — the clash needs a *major* third.
- `C13#11` keeps everything — the clash needs a *natural* eleventh.
- `Cadd11` keeps everything — no seventh, so nothing was stacked and the added
  note was asked for deliberately.

`--literal` suppresses the drop and prints the full stack. It is a rendering
flag: the `Chord` holds the complete interval set either way, the symbol is
unaffected, and both note sets identify as the same chord.

---

## 6. Canonical output

One canonical spelling per interval set, in this order:

1. **Look the whole interval set up in the template table.** A hit supplies the
   symbol, whatever route the parse took: `C7#5` prints `Caug7`, `Cno3` prints
   `C5`, `C(#5)` prints `Caug`. Parse and identify therefore cannot disagree.
2. **On a miss**, emit the tokens: canonical quality, extension, then modifiers
   ordered `sus`, alterations by ascending degree, `add` by ascending degree,
   `no` by ascending degree.
3. **Then the bass**, as `/` + note.

Output is ASCII: `Δ ø ° - + M min ♭ ♯ 𝄫 𝄪 x` all disappear on the way out. A
major triad's symbol is the empty string, so `Chord{root=C, symbol=""}` prints
`C`.

Parentheses are emitted in exactly one case: an alteration with no quality and no
extension in front of it, where bare juxtaposition would rebind to the root.
Hence `C(#11)`, and hence no parentheses in `C7b9#11`.

The whole-set lookup uses each template's **full** interval set. Identification
also matches idiomatic sets, so `C13no11` prints as itself but its notes identify
as `C13`.

---

## 7. Root binding and the ambiguity warning

An accidental immediately after the root letter binds to the root, greedily, by
the same note parser used everywhere else. `C#11` is a C-sharp eleventh chord.

**The warning condition, exactly:** the root parse consumed at least one
accidental, *and* the symbol re-parses successfully when the root is taken as the
bare letter and that accidental begins a modifier instead. Both readings valid
means muse says which one it took, on stderr, exit code unchanged:

```
$ muse chord C#11
C#11    C# G# B D# F#     omits 3
note: read as root C#; write C(#11) for C with a sharp eleventh
```

Since the alteration set has six members, so does the ambiguous set:

| Input | Read as | Other reading | Suggested spelling |
|---|---|---|---|
| `Cb5` | `Cb` power chord | C triad with a lowered fifth | `C(b5)` |
| `C#5` | `C#` power chord | C triad with a raised fifth | `C(#5)`, or `Caug` |
| `Cb9` | `Cb` dominant ninth | C triad with a flat ninth | `C(b9)` |
| `C#9` | `C#` dominant ninth | C triad with a sharp ninth | `C(#9)` |
| `C#11` | `C#` eleventh | C triad with a sharp eleventh | `C(#11)` |
| `Cb13` | `Cb` thirteenth | C triad with a flat thirteenth | `C(b13)` |

Everything else binds silently, because only one reading parses:

| Input | Read as | Why no warning |
|---|---|---|
| `C7#11` | C dominant seventh, raised eleventh | the `7` closed the root |
| `Cm#5` | C minor, raised fifth | the `m` closed the root |
| `C#7` | `C#` dominant seventh | `#7` is not an alteration |
| `Cb6` | `Cb` sixth | `b6` is not an alteration |
| `Cbb5` | `Cbb` power chord | `bb5` is not an alteration |
| `Cb` | `Cb` major triad | nothing follows the accidental |

---

## 8. Accepted input

### 8.1 Triads

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C` | `C` | `P1 M3 P5` | C E G | |
| `Cmaj` | `C` | `P1 M3 P5` | C E G | |
| `CM` | `C` | `P1 M3 P5` | C E G | |
| `Cm` | `Cm` | `P1 m3 P5` | C Eb G | |
| `Cmin` | `Cm` | `P1 m3 P5` | C Eb G | |
| `C-` | `Cm` | `P1 m3 P5` | C Eb G | |
| `Cdim` | `Cdim` | `P1 m3 d5` | C Eb Gb | |
| `C°` | `Cdim` | `P1 m3 d5` | C Eb Gb | |
| `Caug` | `Caug` | `P1 M3 A5` | C E G# | |
| `C+` | `Caug` | `P1 M3 A5` | C E G# | |
| `C(#5)` | `Caug` | `P1 M3 A5` | C E G# | |
| `C(b5)` | `C(b5)` | `P1 M3 d5` | C E Gb | |
| `Csus4` | `Csus4` | `P1 P4 P5` | C F G | |
| `Csus` | `Csus4` | `P1 P4 P5` | C F G | |
| `Csus2` | `Csus2` | `P1 M2 P5` | C D G | |
| `C5` | `C5` | `P1 P5` | C G | |
| `Cno3` | `C5` | `P1 P5` | C G | |
| `Comit3` | `C5` | `P1 P5` | C G | |

### 8.2 Sixths

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C6` | `C6` | `P1 M3 P5 M6` | C E G A | |
| `Cm6` | `Cm6` | `P1 m3 P5 M6` | C Eb G A | |
| `C-6` | `Cm6` | `P1 m3 P5 M6` | C Eb G A | |
| `C69` | `C69` | `P1 M3 P5 M6 M9` | C E G A D | |
| `C6/9` | `C69` | `P1 M3 P5 M6 M9` | C E G A D | |
| `Cm69` | `Cm69` | `P1 m3 P5 M6 M9` | C Eb G A D | |

### 8.3 Sevenths

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C7` | `C7` | `P1 M3 P5 m7` | C E G Bb | |
| `Cmaj7` | `Cmaj7` | `P1 M3 P5 M7` | C E G B | |
| `CM7` | `Cmaj7` | `P1 M3 P5 M7` | C E G B | |
| `CΔ7` | `Cmaj7` | `P1 M3 P5 M7` | C E G B | |
| `CΔ` | `Cmaj7` | `P1 M3 P5 M7` | C E G B | |
| `Cm7` | `Cm7` | `P1 m3 P5 m7` | C Eb G Bb | |
| `Cmin7` | `Cm7` | `P1 m3 P5 m7` | C Eb G Bb | |
| `C-7` | `Cm7` | `P1 m3 P5 m7` | C Eb G Bb | |
| `CmMaj7` | `CmMaj7` | `P1 m3 P5 M7` | C Eb G B | |
| `Cmmaj7` | `CmMaj7` | `P1 m3 P5 M7` | C Eb G B | |
| `CminMaj7` | `CmMaj7` | `P1 m3 P5 M7` | C Eb G B | |
| `CmΔ7` | `CmMaj7` | `P1 m3 P5 M7` | C Eb G B | |
| `Cm(maj7)` | `CmMaj7` | `P1 m3 P5 M7` | C Eb G B | |
| `Cdim7` | `Cdim7` | `P1 m3 d5 d7` | C Eb Gb Bbb | |
| `C°7` | `Cdim7` | `P1 m3 d5 d7` | C Eb Gb Bbb | |
| `Cm7b5` | `Cm7b5` | `P1 m3 d5 m7` | C Eb Gb Bb | |
| `Cø` | `Cm7b5` | `P1 m3 d5 m7` | C Eb Gb Bb | |
| `Cø7` | `Cm7b5` | `P1 m3 d5 m7` | C Eb Gb Bb | |
| `C-7b5` | `Cm7b5` | `P1 m3 d5 m7` | C Eb Gb Bb | |
| `Caug7` | `Caug7` | `P1 M3 A5 m7` | C E G# Bb | |
| `C+7` | `Caug7` | `P1 M3 A5 m7` | C E G# Bb | |
| `C7#5` | `Caug7` | `P1 M3 A5 m7` | C E G# Bb | |
| `C7b5` | `C7b5` | `P1 M3 d5 m7` | C E Gb Bb | |
| `Cmaj7#5` | `Cmaj7#5` | `P1 M3 A5 M7` | C E G# B | |
| `C7sus4` | `C7sus4` | `P1 P4 P5 m7` | C F G Bb | |
| `C7sus` | `C7sus4` | `P1 P4 P5 m7` | C F G Bb | |
| `Cmaj7sus4` | `Cmaj7sus4` | `P1 P4 P5 M7` | C F G B | |

### 8.4 Ninths

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C9` | `C9` | `P1 M3 P5 m7 M9` | C E G Bb D | |
| `Cmaj9` | `Cmaj9` | `P1 M3 P5 M7 M9` | C E G B D | |
| `CM9` | `Cmaj9` | `P1 M3 P5 M7 M9` | C E G B D | |
| `CΔ9` | `Cmaj9` | `P1 M3 P5 M7 M9` | C E G B D | |
| `Cm9` | `Cm9` | `P1 m3 P5 m7 M9` | C Eb G Bb D | |
| `C-9` | `Cm9` | `P1 m3 P5 m7 M9` | C Eb G Bb D | |
| `CmMaj9` | `CmMaj9` | `P1 m3 P5 M7 M9` | C Eb G B D | |
| `Cm9b5` | `Cm9b5` | `P1 m3 d5 m7 M9` | C Eb Gb Bb D | |
| `Cø9` | `Cm9b5` | `P1 m3 d5 m7 M9` | C Eb Gb Bb D | |
| `Cdim9` | `Cdim9` | `P1 m3 d5 d7 M9` | C Eb Gb Bbb D | |
| `C9sus4` | `C9sus4` | `P1 P4 P5 m7 M9` | C F G Bb D | |
| `C7b9` | `C7b9` | `P1 M3 P5 m7 m9` | C E G Bb Db | |
| `C7#9` | `C7#9` | `P1 M3 P5 m7 A9` | C E G Bb D# | |
| `C7b9#11` | `C7b9#11` | `P1 M3 P5 m7 m9 A11` | C E G Bb Db F# | |
| `C7(b9,#11)` | `C7b9#11` | `P1 M3 P5 m7 m9 A11` | C E G Bb Db F# | |
| `Cadd9` | `Cadd9` | `P1 M3 P5 M9` | C E G D | |
| `Cmadd9` | `Cmadd9` | `P1 m3 P5 M9` | C Eb G D | |
| `Cm(add9)` | `Cmadd9` | `P1 m3 P5 M9` | C Eb G D | |
| `Cadd2` | `Cadd2` | `P1 M2 M3 P5` | C D E G | |

### 8.5 Elevenths

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C11` | `C11` | `P1 M3 P5 m7 M9 P11` | C G Bb D F | 3 |
| `Cm11` | `Cm11` | `P1 m3 P5 m7 M9 P11` | C Eb G Bb D F | |
| `Cmaj11` | `Cmaj11` | `P1 M3 P5 M7 M9 P11` | C G B D F | 3 |
| `Cm11b5` | `Cm11b5` | `P1 m3 d5 m7 M9 P11` | C Eb Gb Bb D F | |
| `C7#11` | `C7#11` | `P1 M3 P5 m7 A11` | C E G Bb F# | |
| `C9#11` | `C9#11` | `P1 M3 P5 m7 M9 A11` | C E G Bb D F# | |
| `Cmaj9#11` | `Cmaj9#11` | `P1 M3 P5 M7 M9 A11` | C E G B D F# | |
| `C(#11)` | `C(#11)` | `P1 M3 P5 A11` | C E G F# | |
| `Cadd11` | `Cadd11` | `P1 M3 P5 P11` | C E G F | |
| `C11no9` | `C11no9` | `P1 M3 P5 m7 P11` | C G Bb F | 3 |

### 8.6 Thirteenths

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `C13` | `C13` | `P1 M3 P5 m7 M9 P11 M13` | C E G Bb D A | 11 |
| `Cm13` | `Cm13` | `P1 m3 P5 m7 M9 P11 M13` | C Eb G Bb D F A | |
| `Cmaj13` | `Cmaj13` | `P1 M3 P5 M7 M9 P11 M13` | C E G B D A | 11 |
| `C13b9` | `C13b9` | `P1 M3 P5 m7 m9 P11 M13` | C E G Bb Db A | 11 |
| `C13#11` | `C13#11` | `P1 M3 P5 m7 M9 A11 M13` | C E G Bb D F# A | |
| `C13no11` | `C13no11` | `P1 M3 P5 m7 M9 M13` | C E G Bb D A | |
| `C13sus4` | `C13sus4` | `P1 P5 m7 M9 P11 M13` | C G Bb D F A | |
| `C7b13` | `C7b13` | `P1 M3 P5 m7 m13` | C E G Bb Ab | |

### 8.7 Slash chords

The bass never changes the interval set. It is a harmonic claim about what is
underneath, and phase 5 puts it at the bottom of a realization.

| Input | Canonical | Intervals | Bass | Chord tone |
|---|---|---|---|---|
| `C/E` | `C/E` | `P1 M3 P5` | E | yes, the third |
| `C/G` | `C/G` | `P1 M3 P5` | G | yes, the fifth |
| `Cmaj7/B` | `Cmaj7/B` | `P1 M3 P5 M7` | B | yes, the seventh |
| `Cm7/Eb` | `Cm7/Eb` | `P1 m3 P5 m7` | Eb | yes, the third |
| `C/D` | `C/D` | `P1 M3 P5` | D | no |
| `C/Bb` | `C/Bb` | `P1 M3 P5` | Bb | no |
| `C6/9/E` | `C69/E` | `P1 M3 P5 M6 M9` | E | yes, the third |
| `Ebmaj7/G` | `Ebmaj7/G` | `P1 M3 P5 M7` | G | yes, the third |

### 8.8 Other roots, for spelling

| Input | Canonical | Intervals | Notes | Omits |
|---|---|---|---|---|
| `F#m7b5` | `F#m7b5` | `P1 m3 d5 m7` | F# A C E | |
| `Ebmaj7` | `Ebmaj7` | `P1 M3 P5 M7` | Eb G Bb D | |
| `Db9` | `Db9` | `P1 M3 P5 m7 M9` | Db F Ab Cb Eb | |
| `Bb13` | `Bb13` | `P1 M3 P5 m7 M9 P11 M13` | Bb D F Ab C G | 11 |
| `Gbdim7` | `Gbdim7` | `P1 m3 d5 d7` | Gb Bbb Dbb Fbb | |
| `G##dim7` | `G##dim7` | `P1 m3 d5 d7` | G## B# D# F# | |
| `A♯m7` | `A#m7` | `P1 m3 P5 m7` | A# C# E# G# | |
| `E♭maj7` | `Ebmaj7` | `P1 M3 P5 M7` | Eb G Bb D | |
| `C𝄪` | `C##` | `P1 M3 P5` | C## E## G## | |
| `Cx7` | `C##7` | `P1 M3 P5 m7` | C## E## G## B# | |

### 8.9 The template set

The interval sets that carry a name, and therefore the only answers
`chord_identify` can give. They are enumerated as `CHORD_TEMPLATES` in
`chord.odin`, with the intervals above:

```
(major)  m  dim  aug  sus2  sus4  5
6  m6  69  m69
7  maj7  m7  mMaj7  dim7  m7b5  aug7  maj7#5  7b5  7sus4  add9  madd9
9  maj9  m9  mMaj9  m9b5
11  m11  maj11  m11b5
13  m13  maj13
```

Everything else in section 8 is constructible, printable and re-parseable, but
unnameable: `C7b9` has a canonical spelling and no template. See section 10.

No two of these realize alike, in either their full or their idiomatic form.
That is what keeps identification single-valued, and it is why `9sus4` is absent
— its notes are `C11`'s idiomatic realization exactly, and a table holding both
would have to guess which one a reader meant.

---

## 9. Worked derivations

The awkward cases, step by step. Each one is a row above; this is why the row
says what it says.

**`C13`** — no quality, so a major triad and a minor seventh. `13` stacks every
odd degree from the seventh: `m7 M9 P11 M13`. Full set `P1 M3 P5 m7 M9 P11 M13`.
`M3` and `P11` are both present, there is a seventh, and there is a thirteenth,
so realization drops the eleventh: **C E G Bb D A, omits 11**.

**`C11`** — same stack, stopping at `P11`: `P1 M3 P5 m7 M9 P11`. `M3` and `P11`
are both present with a seventh and no thirteenth, so the third goes:
**C G Bb D F, omits 3**.

**`Cm11`** — the `m` triad makes the third minor. `P1 m3 P5 m7 M9 P11`. The clash
rule needs a *major* third, so nothing is dropped: **C Eb G Bb D F**. This is the
row that makes the omission a property of the interval set rather than of the
extension number.

**`C6`** — `6` is an exception to stacking: it substitutes a sixth for the
seventh rather than adding to it. `P1 M3 P5 M6`, **C E G A**. Note that this is
the same pitch-class set as `Am7`; §10 says which one identification prints.

**`C69`** — a single extension token. Triad, `M6`, `M9`, with no seventh in
between: `P1 M3 P5 M6 M9`, **C E G A D**. `C6/9` is the same input; the slash
splitter leaves it alone because `9` is not a note, and canonical output is `C69`
so that nothing later has to disambiguate a slash.

**`Cadd9`** — `add` contributes its degree without the intervening stack, so
there is no seventh: `P1 M3 P5 M9`, **C E G D**. Contrast `C9`, which is
`P1 M3 P5 m7 M9`.

**`C7sus4`** — extension `7` with no quality gives `P1 M3 P5 m7`; `sus4` removes
the third and adds `P4`. Result `P1 P4 P5 m7`, **C F G Bb**. The fourth is `P4`
and not `P11`, because nothing stacked past the seventh.

**`C7b9#11`** — `P1 M3 P5 m7` from the quality and extension. `b9` finds no ninth
and adds `m9`; `#11` finds no eleventh and adds `A11`. An alteration adds only
its own degree, so there is no natural ninth and no natural eleventh:
`P1 M3 P5 m7 m9 A11`, **C E G Bb Db F#**. `M3` is present but `P11` is not, so
nothing is omitted.

**`Cm7b5`** — `m` triad, extension `7` taking the minor seventh, `b5` replacing
`P5` with `d5`: `P1 m3 d5 m7`, **C Eb Gb Bb**. `Cø` and `Cø7` produce the same
set by a different route, and canonical output is `Cm7b5` for all three.

**`Cdim7`** — the `dim` quality's seventh is diminished, which is the one case
where the seventh is neither major nor minor: `P1 m3 d5 d7`, **C Eb Gb Bbb**. The
double flat is correct and is the reason `Interval` carries steps: `d7` is a
seventh, so it is spelled on B.

**`CmMaj7`** — a single quality token, not `m` followed by `maj`. Minor triad,
major seventh: `P1 m3 P5 M7`, **C Eb G B**. Canonical capitalization is `mMaj7`,
which is the only place muse emits an interior capital.

**`C/E`** — root C, empty symbol, bass E. Interval set `P1 M3 P5`, unchanged; the
bass is stored on the chord and consumed at realization. `chord_string` prints
`C/E`, so the round trip carries the bass even though the intervals do not.

**`C/D`** — same shape, but D is not a chord tone. Nothing about the parse
changes; the annotation column says the bass is outside the chord, and
realization puts D underneath C E G. Note that the symbol round trips while the
*notes* do not: D C E G identifies as `Cadd9/D`, because a reading that accounts
for every note beats one that sets a note aside, and the two chords are the same
four notes. The symbol is the datum, and it survives.

---

## 10. What this table does not settle

**Identification is template matching.** `chord_identify` searches the templates
of section 8.9 in both their full and idiomatic realizations, and applies
`DESIGN.md`'s ranking. So
`C E G Bb D A` identifies as `C13` even though six of the thirteenth's seven
intervals are present, and `A C E G` identifies as `Am7` rather than `C6` by the
first ranking rule. A set built only by alteration, such as `C E G Bb Db`, has no
template and is reported as a note list. Naming those is parking lot item F in
`DESIGN.md`.

**The alias set is a first cut**, per parking lot item E. It grows when something
real fails to parse, not before.

**Unspellable chords are possible but rare.** A chord needing a triple accidental
is a well-formed request with no musical answer, so it exits 2 and names the
degree that failed. It takes a doubly altered root to reach: `Cbbdim7` wants a
`d7` above `Cbb`, which is a B lowered four times.

---

## 11. Rejected input

All of these exit 1 with the offending token echoed to stderr and nothing on
stdout.

| Input | Why |
|---|---|
| `` | empty |
| `H7` | `H` is not a letter |
| `cmaj7` | roots are uppercase |
| `C#b7` | accidentals must agree in direction |
| `Cbbb` | past a double accidental |
| `4C` | a symbol begins with a root |
| `C10` | `10` is not an extension |
| `Cm5` | `5` deletes the third, so it takes no quality |
| `CmMaj` | `mMaj` says which seventh, so it needs one; write `CmMaj7` |
| `CmMaj6` | same, and `6` is not a seventh |
| `C7b7` | `b7` is not an alteration |
| `C#4` | `4` is not an extension, and the root took the sharp; write `C(#11)` |
| `C7b11` | `b11` is not an alteration |
| `Cadd` | `add` needs a degree |
| `Cadd3` | `3` is not an addable degree; use the quality |
| `Cno` | `no` needs a degree |
| `C7alt` | not in the first-cut alias set |
| `CaugMaj7` | one quality per symbol; write `Cmaj7#5` |
| `Cmaj79` | one extension per symbol |
| `C7(b9` | unclosed parenthesis |
| `C/` | empty bass |
| `C/H` | bass is not a note |
| `Cmaj7xyz` | trailing text |

---

## 12. Coverage of `DESIGN.md`

The phase 2 gate is that every rule in the design appears here with at least one
worked example.

| Rule in `DESIGN.md` | Where |
|---|---|
| `symbol := root quality? extension? modifier* ("/" bass)?` | §1 |
| Quality picks the triad and the seventh | §2, and every §8.3 row |
| Extension stacks odd degrees from the seventh | §3, `C13` in §9 |
| `6` substitutes rather than stacks | §3, `C6` and `C69` in §9 |
| `add` contributes without the stack | §4, `Cadd9` in §9 |
| `no` removes a degree | §4, `Cno3` and `C13no11` in §8 |
| Eleventh against third, and which one wins | §5, `C11` / `C13` / `Cm11` in §9 |
| `--literal` is a rendering flag | §5 |
| Greedy root binding | §7 |
| The exact ambiguity-warning condition | §7, with the full six-row set |
| Aliases: `Δ ø ° - + M min maj`, Unicode accidentals | §2, §8.3, §8.8 |
| ASCII on output | §6, §8.8 |
| Identification ranking is template-based | §10 |
| Exit codes 1 and 2 | §10, §11 |
