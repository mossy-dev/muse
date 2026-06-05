package muse

import "core:os"

Command :: union {
  CmdScale,
  CmdChords,
  CmdSevenths,
  CmdTranspose,
  CmdInfo,
  CmdAll,
  CmdHelp,
}

CmdScale    :: struct { root: Note, quality: ScaleQuality }
CmdChords   :: struct { root: Note, quality: ScaleQuality }
CmdSevenths :: struct { root: Note, quality: ScaleQuality }
CmdInfo     :: struct { root: Note, quality: ScaleQuality }
CmdAll      :: struct { root: Note, quality: ScaleQuality }
CmdHelp     :: struct {}

CmdTranspose :: struct {
  root         : Note,
  quality      : ScaleQuality,
  degree       : ScaleDegree,
  semitone     : int,
  with_seventh : bool,
}

PipeContext :: struct {
  scale_valid : bool,
  root        : Note,
  quality     : ScaleQuality,
  notes       : [12]Note,
  notes_len   : int,
  chord_valid : bool,
  chord       : Chord,
}

parse_command :: proc(args: []string, ctx: PipeContext) -> (Command, string)

parse_scale_token :: proc(s: string) -> (root: Note, quality: ScaleQuality, ok: bool)

parse_note_token :: proc(s: string) -> (note: Note, ok: bool)

parse_roman :: proc(s: string) -> (degree: ScaleDegree, ok: bool)

parse_semitone_offset :: proc(s: string) -> (semitones: int, ok: bool)

parse_pipe_context :: proc(line: string) -> PipeContext

encode_pipe_context :: proc(scale: Scale, chord: Maybe(Chord)) -> string
