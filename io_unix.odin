#+build linux, darwin
package muse

import "core:sys/posix"

is_stdout_tty :: proc() -> bool {
  return bool(posix.isatty(posix.STDOUT_FILENO))
}

is_stdin_piped :: proc() -> bool {
  return !bool(posix.isatty(posix.STDIN_FILENO))
}
