package main

import "core:os"

import "../muse"

/*
Why a sink and not a transform: a MIDI file does not parse as notation, so
nothing can follow it in a chain. It reads field one and derives everything else
from the parsed datum, exactly as a transform does, which is what makes it a
test of the text protocol rather than a way around it.
*/

/*
What can stop a file being written. The datum that caused it is reported
alongside, so the message names the line rather than the command.
*/
MidiError :: enum {
  None,
  NotNotation,
  NotAKey,
  Unspellable,
  OutOfRange,
}

/*
Write the input as a Standard MIDI File: every item the same length, laid end to
end, at the tempo and meter the flags asked for.

Anything that is not a voicing is realized on the way through, so a scale or a
bare symbol writes a file without a voice step in front of it.
*/
command_midi :: proc(options: Options) -> int {
  if midi_refuses_terminal(options.output, output_is_terminal()) {
    return fail(
      EXIT_USAGE,
      "refusing to write a MIDI file to a terminal",
      "redirect it or pass -o FILE",
    )
  }

  data, data_ok := input_read(options)
  if !data_ok {
    return fail(EXIT_USAGE, "no input", options.command)
  }

  bytes, token, error := midi_bytes(data, options)
  switch error {
  case .None:
  case .NotNotation:
    return fail(EXIT_USAGE, "not notation", token)
  case .NotAKey:
    return fail(EXIT_USAGE, "not a key", token)
  case .Unspellable:
    return fail(EXIT_NO_ANSWER, "no spelling within double accidentals", token)
  case .OutOfRange:
    return fail(EXIT_NO_ANSWER, "outside the range MIDI can number", token)
  }

  if len(options.output) > 0 {
    if write_error := os.write_entire_file(options.output, bytes); write_error != nil {
      return fail(EXIT_USAGE, "cannot write", options.output)
    }
    return EXIT_SUCCESS
  }

  os.write(os.stdout, bytes)
  return EXIT_SUCCESS
}

/*
Binary belongs in a file or a pipe and not on a screen. Redirection is the unix
answer and -o FILE is the other one, so a terminal with neither is a request
muse declines rather than one it garbles.

The check is a predicate over the terminal rather than a reading of it, which is
what lets the rule be tested without a terminal to test it on. It runs before
the input is read, so a refusal costs the pipeline in front of it nothing.
*/
@(private)
midi_refuses_terminal :: proc(output: string, is_terminal: bool) -> bool {
  return len(output) == 0 && is_terminal
}

/*
The bytes a run of input encodes to. Every line is parsed and realized before
anything is written, which is the same rule the transforms follow: a failure on
the last line leaves no half-written file.

The key signature comes from -k where it is given and from the first datum that
is a scale otherwise, so `muse scale G major | muse midi` carries its own key and
a chain that has lost its scale can be told one. A run naming no key writes no
key signature rather than guessing at C major.

Returns the offending datum with the failure, and an empty token where the
failure belongs to no single line.
*/
@(private)
midi_bytes :: proc(
  data      : []string,
  options   : Options,
  allocator := context.allocator,
) -> ([]byte, string, MidiError) {
  items     := make([dynamic]muse.Voicing, 0, len(data), allocator)
  smf       := midi_options(options)
  key_found := false

  if len(options.key) > 0 {
    key, key_ok := scale_read(options.key, allocator)
    if !key_ok {
      return nil, options.key, .NotAKey
    }
    smf.key   = key
    key_found = true
  }

  for text in data {
    datum, datum_ok := datum_parse(text, allocator)
    if !datum_ok {
      return nil, text, .NotNotation
    }

    if scale, is_scale := datum.(muse.Scale); is_scale && !key_found {
      smf.key   = scale
      key_found = true
    }

    voicings, voicings_ok := midi_items(datum, options, allocator)
    if !voicings_ok {
      return nil, text, .Unspellable
    }

    for voicing in voicings {
      if !muse.smf_in_range(voicing) {
        return nil, text, .OutOfRange
      }
      append(&items, voicing)
    }
  }

  bytes, encode_ok := muse.smf_encode(items[:], smf, allocator)
  if !encode_ok {
    return nil, "", .OutOfRange
  }

  return bytes, "", .None
}

/*
The items one datum sounds as.

A scale is a run of single notes, one to an item, because a scale is a melody
and a chord is not: DESIGN.md's own remark that a scale reads better as quarter
notes than as seven whole bars only makes sense if its notes are the items. A
`voice` step in front of the sink makes the same scale one chord, which is how
the cluster is asked for.
*/
@(private)
midi_items :: proc(
  datum     : Datum,
  options   : Options,
  allocator := context.allocator,
) -> ([]muse.Voicing, bool) {
  voicing, _, realized_ok := datum_realize(datum, options.octave, options.literal, allocator)
  if !realized_ok {
    return nil, false
  }

  if _, is_scale := datum.(muse.Scale); !is_scale {
    single := make([]muse.Voicing, 1, allocator)
    single[0] = voicing
    return single, true
  }

  run := make([]muse.Voicing, len(voicing.pitches), allocator)
  for pitch, index in voicing.pitches {
    run[index] = muse.voicing_make([]muse.Pitch{ pitch }, allocator)
  }
  return run, true
}

/*
The encoder's options from the command line's. The duration a flag did not give
is one bar, which is a length only the meter knows, so it is resolved here where
both have been read.
*/
@(private)
midi_options :: proc(options: Options) -> muse.SmfOptions {
  smf := muse.smf_default_options()

  smf.tempo    = options.tempo
  smf.meter    = options.meter
  smf.duration = options.duration.? or_else muse.meter_bar(options.meter)

  return smf
}
