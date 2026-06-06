package muse

import "core:io"
import "core:os"
import "core:bufio"
import "core:strings"

read_first_stdin_line :: proc(allocator := context.allocator) -> (line: string, ok: bool) {
  r: bufio.Reader
  bufio.reader_init(&r, io.to_reader(os.to_stream(os.stdin)), allocator = context.temp_allocator)
  defer bufio.reader_destroy(&r)

  raw, err := bufio.reader_read_string(&r, '\n', context.temp_allocator)
  if err != nil && err != .EOF {
    return "", false
  }
  if len(raw) == 0 {
    return "", false
  }

  trimmed := strings.trim_right(raw, "\r\n")
  return strings.clone(trimmed, allocator), true
}
