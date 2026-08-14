package main

import "core:os"
import "core:strings"
import "core:unicode/utf8"

/*
One output line: the datum another command reads back, and the annotation
columns a human reads. Field one is the same bytes whether it lands on a
terminal, in a file or in a pipe; only what follows it is laid out for the eye.
*/
Row :: struct {
  datum       : string,
  annotations : []string,
}

/*
Spaces between padded columns on a terminal. Two is enough to separate a note
list from a roman numeral and narrow enough that a harmonized scale still fits a
default terminal.
*/
COLUMN_GAP :: 2

DIM   :: "\e[2m"
RESET :: "\e[0m"

/*
Write rows to stdout, aligned into columns and dimmed on a terminal and
tab-separated everywhere else.

The choice is presentation only. Both forms carry the same fields in the same
order, so a redirect and a pipe differ in whitespace and in nothing a parser
reads.
*/
render :: proc(rows: []Row) {
  os.write_string(os.stdout, render_text(rows, output_is_terminal(), output_uses_color()))
}

/*
The text render writes. Layout is a parameter rather than a lookup so that both
forms can be produced and compared without a terminal to produce them on.
*/
render_text :: proc(rows: []Row, aligned, colored: bool, allocator := context.allocator) -> string {
  if len(rows) == 0 {
    return ""
  }

  columns := 0
  for row in rows {
    columns = max(columns, row_field_count(row))
  }

  widths := make([]int, columns, context.temp_allocator)
  if aligned {
    for row in rows {
      for column in 0 ..< row_field_count(row) {
        widths[column] = max(widths[column], utf8.rune_count(row_field(row, column)))
      }
    }
  }

  builder := strings.builder_make(allocator)
  for row in rows {
    count := row_field_count(row)

    for column in 0 ..< count {
      field := row_field(row, column)

      if colored && column > 0 {
        strings.write_string(&builder, DIM)
        strings.write_string(&builder, field)
        strings.write_string(&builder, RESET)
      } else {
        strings.write_string(&builder, field)
      }

      if column == count - 1 {
        break
      }
      if aligned {
        for _ in utf8.rune_count(field) ..< widths[column] + COLUMN_GAP {
          strings.write_byte(&builder, ' ')
        }
      } else {
        strings.write_byte(&builder, '\t')
      }
    }

    strings.write_byte(&builder, '\n')
  }

  return strings.to_string(builder)
}

@(private)
row_field_count :: proc(row: Row) -> int {
  return 1 + len(row.annotations)
}

@(private)
row_field :: proc(row: Row, column: int) -> string {
  if column == 0 {
    return row.datum
  }
  if column - 1 < len(row.annotations) {
    return row.annotations[column - 1]
  }
  return ""
}
