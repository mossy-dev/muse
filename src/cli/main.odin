package main

import "core:fmt"
import "core:mem/virtual"
import "core:os"

/*
Exit codes, per DESIGN.md. A usage or parse error is 1; a well-formed request
with no musical answer -- a scale that cannot be spelled, an interval notation
has no word for -- is 2.
*/
EXIT_SUCCESS   :: 0
EXIT_USAGE     :: 1
EXIT_NO_ANSWER :: 2

USAGE ::
`usage: muse <command> [operand ...]

  scale <root> [name]   build a scale, defaulting to major
  chord <symbol>        build a chord from a symbol
  notes                 reduce anything to its bare note list
  interval <a> <b>      name the interval between two notes

Every command reads its operand from its arguments, and from stdin when it has
none, so any line muse prints can be piped into the next command or typed back
in by hand.
`

/*
One arena for the process, released at exit. A run of muse is a few
milliseconds long and allocates a few kilobytes, so tracking ownership through
it would cost more than the memory does.
*/
main :: proc() {
  arena : virtual.Arena
  if error := virtual.arena_init_growing(&arena); error != nil {
    os.write_string(os.stderr, "muse: cannot allocate\n")
    os.exit(EXIT_USAGE)
  }
  context.allocator = virtual.arena_allocator(&arena)

  code := dispatch(os.args[1:])

  virtual.arena_destroy(&arena)
  os.exit(code)
}

/*
Read the command line and hand off to the command it names.
*/
dispatch :: proc(arguments: []string) -> int {
  options, token, options_ok := options_parse(arguments)
  if !options_ok {
    return fail(EXIT_USAGE, "unknown option", token)
  }

  switch options.command {
  case "":
    os.write_string(os.stderr, USAGE)
    return EXIT_USAGE
  case "scale":
    return command_scale(options)
  case "chord":
    return command_chord(options)
  case "notes":
    return command_notes(options)
  case "interval":
    return command_interval(options)
  }

  return fail(EXIT_USAGE, "unknown command", options.command)
}

/*
Report a failure on stderr with the offending token echoed, and hand back the
exit code the caller is to return.

Nothing has reached stdout by the time this is called: a command parses every
datum in its input before it renders any of them, so a failure anywhere leaves
the output empty rather than partial.
*/
fail :: proc(code: int, message: string, token: string) -> int {
  os.write_string(os.stderr, fmt.tprintf("muse: %s: %s\n", message, token))
  return code
}

/*
Say something about a result that is not a failure, such as which of two
readings of a chord symbol muse took. It goes to stderr so that it never
contaminates a pipeline.
*/
warn :: proc(text: string) {
  os.write_string(os.stderr, fmt.tprintf("note: %s\n", text))
}
