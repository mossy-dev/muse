package main

import "core:os"
import "core:terminal"

/*
Terminal detection decides presentation and never content. Column padding and
color appear on a terminal; a pipe or a file gets tab-separated fields. Field
one is the same bytes either way, which is what stops `muse scale G major > f`
and `muse scale G major | muse notes` telling different stories.

One file rather than the per-platform pair the design sketched: core:terminal
already carries the isatty and GetConsoleMode calls, along with the NO_COLOR and
TERM reading that a hand-rolled version would have grown next.
*/
output_is_terminal :: proc() -> bool {
  return terminal.is_terminal(os.stdout)
}

output_uses_color :: proc() -> bool {
  return output_is_terminal() && terminal.color_enabled && !terminal.is_dumb
}
