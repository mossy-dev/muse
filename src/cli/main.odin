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

/*
The version this binary reports. A release build stamps the tag it was cut from
with `-define:MUSE_VERSION=1.0.0`; a build from a working tree says so instead of
claiming a release it is not.
*/
VERSION :: #config(MUSE_VERSION, "dev")

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
Read the command line and hand off to the command it names, which is the row of
COMMANDS that carries the word. There is no switch here to fall out of step with
the usage text, since both read the same table.
*/
dispatch :: proc(arguments: []string) -> int {
  options, token, options_ok := options_parse(arguments)
  if !options_ok {
    return fail(EXIT_USAGE, "bad option", token)
  }
  if options.help {
    return command_help(options)
  }
  if options.version {
    return command_version(options)
  }

  if len(options.command) == 0 {
    os.write_string(os.stderr, usage_text(context.temp_allocator))
    return EXIT_USAGE
  }

  for command in COMMANDS {
    if command.name == options.command {
      return command.run(options)
    }
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
