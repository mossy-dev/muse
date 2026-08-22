package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import "../muse"

/*
The ASCII keyboard, which is the one output that shows rather than names. A
reader who does not take a chord symbol at sight can still see where its notes
fall under a hand, and that is the whole of what this is for.

It is a sink, and that is forced rather than chosen: a keyboard is several lines
tall where the protocol is one item to a line, and nothing it draws parses. It
still reads field one and derives everything else, exactly as json and numbers
do, so it is one more witness that the text protocol carries the whole model.

Presentation, so it lives here rather than in the library. A MIDI file is an
encoding a program reads back; a drawing is for the eye and has no meaning
outside a terminal.
*/

/*
One octave is 28 columns and shares its right edge with the next, so a keyboard
of n octaves is 28n + 1 columns wide and successive octaves line up.
*/
KEYBOARD_OCTAVE_COLUMNS :: 28

/*
A white key is four columns: the wall on its left, and the three of the foot it
exposes below the black keys. A press is marked on the middle column of the row
above that foot, which leaves the foot free to draw the key's outline.
*/
WHITE_KEY_COLUMNS :: 4

/*
A black key stands two rows above the white keys and ends on a third. Two is
enough for it to read as standing over them rather than beside them, and the
lower of the two is where a press on it is marked.
*/
KEYBOARD_BLACK_ROWS :: 2

/*
What one column of a keyboard shows. The root is drawn `R` rather than `*` and
coloured on a terminal, so it survives a pipe on the glyph alone: a mark that
only a colour distinguished would be lost the moment the drawing left the
screen, and the drawing is the one output with no words in it to fall back on.
*/
@(private)
KeyMark :: enum {
  Unpressed,
  Pressed,
  Root,
}

/*
Draw the input on a keyboard, one keyboard to a datum, with the keys it sounds
pressed.
*/
command_keys :: proc(options: Options) -> int {
  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  text, token, error := keyboard_text(
    data, options, color_chosen(options.color, output_uses_color()),
  )
  if error != .None {
    return sink_fail(error, token)
  }

  os.write_string(os.stdout, text)
  return EXIT_SUCCESS
}

/*
Every keyboard, built before a byte of it is written, separated by a blank line
as info's blocks are.
*/
@(private)
keyboard_text :: proc(
  data      : []string,
  options   : Options,
  colored   : bool,
  allocator := context.allocator,
) -> (string, string, SinkError) {
  builder := strings.builder_make(allocator)

  for text, index in data {
    datum, datum_ok := datum_parse(text, context.temp_allocator)
    if !datum_ok {
      return "", text, .NotNotation
    }

    if index > 0 {
      strings.write_byte(&builder, '\n')
    }
    if error := keyboard_block(&builder, datum, options, colored); error != .None {
      return "", text, error
    }
  }

  return strings.to_string(builder), "", .None
}

/*
One datum: the line it came in on, then the drawing under it.
*/
@(private)
keyboard_block :: proc(
  builder : ^strings.Builder,
  datum   : Datum,
  options : Options,
  colored : bool,
) -> SinkError {
  header, header_ok := keyboard_header(datum, options, colored, context.temp_allocator)
  if !header_ok {
    return .Unspellable
  }

  marks, register, marks_ok := keyboard_keys(datum, options.literal, context.temp_allocator)
  if !marks_ok {
    return .Unspellable
  }

  strings.write_string(builder, header)
  keyboard_draw(builder, marks, register, colored)
  return .None
}

/*
The line a keyboard is headed by, which is where the spelling lives: a drawing
can only show a pitch class, so Bb is named above a keyboard that marks the same
key A# would.

It names exactly what the picture marks and nothing else. A chord's symbol is
not its notes, so they follow it; a voicing and a note list carry theirs in field
one already, so neither repeats them.

Alignment is not asked of the terminal. There is one row to a keyboard, so
column padding has nothing to align against, and the drawing under it has a
fixed width in any case.
*/
@(private)
keyboard_header :: proc(
  datum     : Datum,
  options   : Options,
  colored   : bool,
  allocator := context.allocator,
) -> (string, bool) {
  spelling := datum_string(datum, allocator)
  rows     := make([]Row, 1, context.temp_allocator)
  rows[0]   = Row{ datum = spelling }

  _, is_voicing := datum.(muse.Voicing)
  _, is_notes   := datum.(Notes)

  if !is_voicing && !is_notes {
    notes, notes_ok := datum_notes(datum, options.literal, context.temp_allocator)
    if !notes_ok {
      return "", false
    }

    root, has_root := keyboard_root(datum)

    annotations := make([]string, 1, context.temp_allocator)
    annotations[0] = keyboard_notes(
      notes, has_root ? root : nil, colored, context.temp_allocator,
    )
    rows[0].annotations = annotations
  }

  return render_text(
    options.plain ? rows_plain(rows, context.temp_allocator) : rows, false, colored, allocator,
  ), true
}

/*
The notes a keyboard marks, with the root picked out where the datum names one.

The dim of the annotation column has to be re-established after the root, since
a reset ends every attribute rather than the colour alone. Nothing here is
aligned, so the escapes cannot throw a column width out.
*/
@(private)
keyboard_notes :: proc(
  notes     : []muse.Note,
  root      : Maybe(muse.Note),
  colored   : bool,
  allocator := context.allocator,
) -> string {
  spellings := make([]string, len(notes), context.temp_allocator)

  for note, index in notes {
    spelling := muse.note_string(note, context.temp_allocator)

    if named, has_root := root.?; colored && has_root && note == named {
      spelling = strings.concatenate(
        []string{ RESET, ROOT, spelling, RESET, DIM }, context.temp_allocator,
      )
    }
    spellings[index] = spelling
  }

  return strings.join(spellings, " ", allocator)
}

/*
The note a datum calls its root, where it has one to call.

A scale and a chord carry theirs. A voicing and a bare note list do not, so they
are identified, exactly as `voice` identifies a voicing to name it `Cmaj7/G` --
a set of notes that names no chord simply has no root to mark.
*/
@(private)
keyboard_root :: proc(datum: Datum) -> (muse.Note, bool) {
  switch value in datum {
  case muse.Scale:
    return value.root, true
  case muse.Chord:
    return value.root, true
  case muse.Voicing:
    notes := muse.voicing_notes(value, context.temp_allocator)
    chord, named := muse.chord_identify(notes, context.temp_allocator)
    return chord.root, named
  case Notes:
    chord, named := muse.chord_identify(([]muse.Note)(value), context.temp_allocator)
    return chord.root, named
  }

  return {}, false
}

/*
The keys a datum presses, as a column per column of the drawing, and the octave
the leftmost keyboard begins on where there is more than one of them.

Register is derived and never asked for. A chord, a scale or a note list has
none and draws a single octave; a voicing draws the octaves it spans and marks a
pitch class twice when it sounds twice.

An octave is the one a pitch's letter belongs to, which is what puts B#3 on the
C at the left of the third keyboard rather than on the one at the right of the
second. The header carries the spelling that says so.
*/
@(private)
keyboard_keys :: proc(
  datum     : Datum,
  literal   : bool,
  allocator := context.allocator,
) -> (marks: []KeyMark, register: Maybe(int), ok: bool) {
  columns := keyboard_columns()
  octaves := 1
  lowest  := 0

  if voicing, is_voicing := datum.(muse.Voicing); is_voicing {
    lowest   = voicing.pitches[0].octave
    highest := lowest
    for pitch in voicing.pitches {
      lowest  = min(lowest,  pitch.octave)
      highest = max(highest, pitch.octave)
    }

    octaves = highest - lowest + 1
    marks   = make([]KeyMark, keyboard_width(octaves), allocator)
    for pitch in voicing.pitches {
      board  := pitch.octave - lowest
      column := board * KEYBOARD_OCTAVE_COLUMNS + columns[muse.note_pitch_class(pitch.note)]
      marks[column] = .Pressed
    }
  } else {
    notes, notes_ok := datum_notes(datum, literal, context.temp_allocator)
    if !notes_ok {
      return nil, nil, false
    }

    marks = make([]KeyMark, keyboard_width(1), allocator)
    for note in notes {
      marks[columns[muse.note_pitch_class(note)]] = .Pressed
    }
  }

  if root, has_root := keyboard_root(datum); has_root {
    column := columns[muse.note_pitch_class(root)]
    for board in 0 ..< octaves {
      index := board * KEYBOARD_OCTAVE_COLUMNS + column
      if marks[index] == .Pressed {
        marks[index] = .Root
      }
    }
  }

  return marks, octaves > 1 ? lowest : nil, true
}

/*
The drawing itself: the top edge, the rows a black key stands in, the row it ends
on, the white keys below it, the row that closes them, and the labels.

Every key is marked in the row above its own foot, so the two feet draw an
unbroken outline whatever is pressed and a black mark sits above a white one by
the same distance the key itself does.
*/
@(private)
keyboard_draw :: proc(
  builder  : ^strings.Builder,
  marks    : []KeyMark,
  register : Maybe(int),
  colored  : bool,
) {
  for _ in 0 ..< len(marks) {
    strings.write_byte(builder, '_')
  }
  strings.write_byte(builder, '\n')

  for row in 0 ..< KEYBOARD_BLACK_ROWS {
    marking := row == KEYBOARD_BLACK_ROWS - 1
    for column in 0 ..< len(marks) {
      face := marking ? keyboard_face(marks[column]) : ' '
      keyboard_write_cell(builder, keyboard_black_cell(column, face), colored)
    }
    strings.write_byte(builder, '\n')
  }

  for column in 0 ..< len(marks) {
    strings.write_byte(builder, keyboard_black_cell(column, '_'))
  }
  strings.write_byte(builder, '\n')

  for column in 0 ..< len(marks) {
    if column % WHITE_KEY_COLUMNS == 0 {
      strings.write_byte(builder, '|')
    } else {
      keyboard_write_cell(builder, keyboard_face(marks[column]), colored)
    }
  }
  strings.write_byte(builder, '\n')

  for column in 0 ..< len(marks) {
    strings.write_byte(builder, column % WHITE_KEY_COLUMNS == 0 ? '|' : '_')
  }
  strings.write_byte(builder, '\n')

  keyboard_labels(builder, len(marks), register)
}

/*
The character a mark is drawn with. `R` is wider on the page than `*`, which is
the point: the root is the note the others are heard against, so it should not
read as the faintest thing on the keyboard.
*/
@(private)
keyboard_face :: proc(mark: KeyMark) -> byte {
  switch mark {
  case .Root:      return 'R'
  case .Pressed:   return '*'
  case .Unpressed: return ' '
  }
  return ' '
}

/*
One cell, coloured where it turned out to be the root and the terminal takes
colour. Every other cell is written as it stands, so the escapes in a drawing
number exactly as many as there are roots on it.
*/
@(private)
keyboard_write_cell :: proc(builder: ^strings.Builder, cell: byte, colored: bool) {
  if colored && cell == 'R' {
    strings.write_string(builder, ROOT)
    strings.write_byte(builder, cell)
    strings.write_string(builder, RESET)
    return
  }
  strings.write_byte(builder, cell)
}

/*
What one column holds in the rows the black keys occupy: the key's own face
where a boundary carries one, the walls immediately beside it, the white key
separators at every other boundary, and the gap over a white key elsewhere.

The face is what distinguishes the three rows -- the key, a press, or the line
it ends on -- so it is the only thing they differ by.
*/
@(private)
keyboard_black_cell :: proc(column: int, face: byte) -> byte {
  switch column % WHITE_KEY_COLUMNS {
  case 0:
    return keyboard_is_black(column) ? face : '|'
  case 1:
    return keyboard_is_black(column - 1) ? '|' : ' '
  case 3:
    return keyboard_is_black(column + 1) ? '|' : ' '
  }
  return ' '
}

/*
Whether a column carries a black key. Black keys straddle the boundary between
two white keys, and there is one wherever two letters stand two semitones apart:
none between E and F, none between B and C, and none on the edges a keyboard
shares with its neighbour.

Reading it off the letters is what keeps this the only part of the drawing with
a wrong answer rather than a table that could disagree with the note arithmetic.
*/
@(private)
keyboard_is_black :: proc(column: int) -> bool {
  position := column %% KEYBOARD_OCTAVE_COLUMNS
  if position == 0 || position % WHITE_KEY_COLUMNS != 0 {
    return false
  }
  return letter_semitones_to_next(muse.Letter(position / WHITE_KEY_COLUMNS - 1)) == 2
}

/*
The column each pitch class stands on within one octave: the middle of a white
key's foot, or the boundary a black key straddles.

It is computed from the letters rather than written down, so the twelve entries
cannot drift from the seven that generate them.
*/
@(private)
keyboard_columns :: proc() -> [12]int {
  columns : [12]int

  for white in 0 ..< len(muse.Letter) {
    natural  := muse.note_pitch_class(muse.Note{ muse.Letter(white), 0 })
    boundary := (white + 1) * WHITE_KEY_COLUMNS

    columns[natural] = white * WHITE_KEY_COLUMNS + 2
    if keyboard_is_black(boundary) {
      columns[natural + 1] = boundary
    }
  }

  return columns
}

/*
The letters under the white keys, with an octave number after each C once there
is more than one keyboard to tell apart.

The row is trimmed on the right, since the last label sits two columns short of
the edge and trailing whitespace is not part of a drawing.
*/
@(private)
keyboard_labels :: proc(builder: ^strings.Builder, width: int, register: Maybe(int)) {
  line := make([]byte, width, context.temp_allocator)
  slice.fill(line, ' ')

  for board in 0 ..< width / KEYBOARD_OCTAVE_COLUMNS {
    for white in 0 ..< len(muse.Letter) {
      column := board * KEYBOARD_OCTAVE_COLUMNS + white * WHITE_KEY_COLUMNS + 2
      name   := muse.note_string(muse.Note{ muse.Letter(white), 0 }, context.temp_allocator)
      copy(line[column:], name)

      if lowest, numbered := register.?; numbered && white == 0 {
        copy(line[column + len(name):], fmt.tprintf("%d", lowest + board))
      }
    }
  }

  strings.write_string(builder, strings.trim_right_space(string(line)))
  strings.write_byte(builder, '\n')
}

/*
How wide a keyboard of this many octaves is, sharing one edge between each pair.
*/
@(private)
keyboard_width :: proc(octaves: int) -> int {
  return KEYBOARD_OCTAVE_COLUMNS * octaves + 1
}

/*
How far the next letter stands above this one, wrapping at B so that B to C is a
semitone rather than an octave less one.
*/
@(private)
letter_semitones_to_next :: proc(letter: muse.Letter) -> int {
  next := muse.Letter((int(letter) + 1) %% len(muse.Letter))
  return (
    muse.note_pitch_class(muse.Note{ next,   0 }) -
    muse.note_pitch_class(muse.Note{ letter, 0 })
  ) %% 12
}
