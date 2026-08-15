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

  scale <root> [name]      build a scale, defaulting to major
  chord <symbol>           build a chord from a symbol
  chords [degrees ...]     harmonize a scale, every degree or the ones named
                           a degree is 4, IV or iv; the case is muse's to get
  notes                    reduce anything to its bare note list
  interval <a> <b>         name the interval between two notes
  transpose <interval>     transpose, preserving spelling
  invert <n>               invert a voicing
  voice <style>            realize as pitches: close open drop2 drop3 shell
  name <notes ...>         identify the chord or scale a note set forms
  in <key>                 annotate input with its degrees in a key
  midi                     write a Standard MIDI File
  json                     structured output for programs; unstable, see below
  numbers                  bare MIDI note numbers, one line per item
  info                     everything muse knows about the input
  help                     print this message

  --size 3|7|9|11|13       how far to stack a harmonization, default 3
  --octave <n>             where a realization sounds, default 4
  --literal                keep the degree a chord's realization drops
  --color <when>           auto, always or never; default auto
  --plain                  drop the annotation columns and print field one
  --tempo <bpm>            beats per minute of a MIDI file, default 120
  --meter <n/d>            time signature of a MIDI file, default 4/4
  --duration <n/d>         how long each item sounds, default one bar
  -k, --key <scale>        the key degrees and signatures are named in
  -o <file>                write a MIDI file here instead of to stdout

Every command reads its operand from its arguments, and from stdin when it has
none, so any line muse prints can be piped into the next command or typed back
in by hand.

The json schema is unstable and may change without notice. It says what muse
knows about a datum rather than promising how that is spelled; it settles when
something depends on it.
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
    return fail(EXIT_USAGE, "bad option", token)
  }
  if options.help {
    return command_help()
  }

  switch options.command {
  case "":
    os.write_string(os.stderr, USAGE)
    return EXIT_USAGE
  case "scale":
    return command_scale(options)
  case "chord":
    return command_chord(options)
  case "chords":
    return command_chords(options)
  case "notes":
    return command_notes(options)
  case "interval":
    return command_interval(options)
  case "transpose":
    return command_transpose(options)
  case "invert":
    return command_invert(options)
  case "voice":
    return command_voice(options)
  case "name":
    return command_name(options)
  case "in":
    return command_in(options)
  case "midi":
    return command_midi(options)
  case "json":
    return command_json(options)
  case "numbers":
    return command_numbers(options)
  case "info":
    return command_info(options)
  case "help":
    return command_help()
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
