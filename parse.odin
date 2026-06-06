package muse

import "core:os"
import "core:strings"

ScaleCmd :: struct {
  root    : Note,
  quality : ScaleQuality,
}

ChordsCmd :: struct {
  root      : Note,
  quality   : ScaleQuality,
  extension : ChordExtension
}

SeventhCmd :: struct {
  root      : Note,
  quality   : ScaleQuality,
  extension : ChordExtension
}

TransposeCmd :: struct {
  degree    : ScaleDegree,
  semitones : int,
}

InfoCmd       :: struct { root: Note, quality: ScaleQuality }
EverythingCmd :: struct { root: Note, quality: ScaleQuality }
HelpCmd       :: struct {}

Command :: union {
  ScaleCmd,
  ChordsCmd,
  SeventhCmd,
  TransposeCmd,
  InfoCmd,
  EverythingCmd,
  HelpCmd,
}

PipeContext :: struct {
  scale : Scale,
  chord : Maybe(Chord)
}

ParseResult :: struct {
  command : Command,
  pipe    : Maybe(PipeContext),
}

ParseError :: enum {
  None,
  NoInput,
  UnknownSubcommand,
  BadNote,
  BadQuality,
  BadDegree,
  BadOffset,
  BadExtension,
  BadPipeline,
  TooManyArgs,
}

@(rodata)
PIPE_SCALE_QUALITY_TOKEN := [ScaleQuality]string {
  .Major           = "major",
  .NaturalMinor    = "minor",
  .HarmonicMinor   = "harmonic",
  .MelodicMinor    = "melodic",
  .Dorian          = "dorian",
  .Phrygian        = "phrygian",
  .Lydian          = "lydian",
  .Mixolydian      = "mixolydian",
  .Locrian         = "locrian",
  .MajorPentatonic = "majpent",
  .MinorPentatonic = "minpent",
  .Blues           = "blues",
  .Chromatic       = "chromatic",
}

@(rodata)
PIPE_CHORD_QUALITY_TOKEN := [ChordQuality]string {
  .Major             = "maj",
  .Minor             = "min",
  .Diminished        = "dim",
  .Augmented         = "aug",
  .Sus2              = "sus2",
  .Sus4              = "sus4",
  .MajorSeventh      = "maj7",
  .DominantSeventh   = "dom7",
  .MinorSeventh      = "min7",
  .MinorMajorSeventh = "minmaj7",
  .HalfDiminished    = "hdim",
  .FullyDiminished   = "fdim",
  .AugmentedMajorSev = "augmaj7",
}

@(rodata)
PIPE_EXTENSION_TOKEN := [ChordExtension]string {
  .Triad      = "triad",
  .Seventh    = "7th",
  .Ninth      = "9th",
  .Eleventh   = "11th",
  .Thirteenth = "13th",
  .Add9       = "add9",
  .Add11      = "add11",
  .PowerChord = "power",
}

parse :: proc(args: []string, stdin_line: string, allocator := context.allocator) -> (ParseResult, ParseError) {
  result: ParseResult

  if strings.has_prefix(stdin_line, "muse:") {
    ctx, ok, err := pipe_decode(stdin_line, allocator)
    if !ok || err != .None {
      return {}, err != .None ? err : .BadPipeline
    }
    result.pipe = ctx
  }

  if len(args == 0) {
    pipe, has_pipe := result.pipe
  }
}

pipe_encode_scale :: proc(b: ^strings.Builder, scale: ^Scale)

pipe_encode_scale_and_chord :: proc(b: ^strings.Builder, scale: ^Scale, chord: ^Chord)

pipe_decode :: proc(line: string, allocator := context.allocator) -> (ctx: PipeContext, ok: bool, err: ParseError) {
}

parse_note :: proc(token: string) -> (Note, bool)

parse_scale_quality :: proc(token: string) -> (ScaleQuality, bool)

parse_chord_quality :: proc(token: string) -> (ChordQuality, bool)

parse_degree :: proc(token: string) -> (ScaleDegree, bool)

parse_offset :: proc(token: string) -> (semitones: int, ok: bool)
