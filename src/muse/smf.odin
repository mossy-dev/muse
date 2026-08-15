package muse

/*
A time signature: how many beats a bar holds, over the note value that takes the
beat. The unit is a power of two, since a Standard MIDI File writes it as an
exponent rather than as a number.
*/
Meter :: struct {
  beats : int,
  unit  : int,
}

/*
How long one item sounds, as a fraction of a whole note: 1/4 is a quarter note
and 4/4 is a bar of common time. muse has a uniform grid rather than rhythm, so
this is every note's length and there is nothing else about time to say.
*/
Duration :: struct {
  numerator   : int,
  denominator : int,
}

/*
Everything the encoder needs that the notes themselves do not carry. The key is
what makes the library's spelling work survive into a file: MIDI collapses Eb
and D# to note 63, and the key signature event is where a reader recovers which
of them was meant.
*/
SmfOptions :: struct {
  tempo             : int,
  meter             : Meter,
  duration          : Duration,
  key               : Maybe(Scale),
  velocity          : u8,
  channel           : u8,
  ticks_per_quarter : int,
}

SMF_DEFAULT_TEMPO     :: 120
SMF_DEFAULT_VELOCITY  :: 80
SMF_TICKS_PER_QUARTER :: 480

META_TEMPO          :: 0x51
META_TIME_SIGNATURE :: 0x58
META_KEY_SIGNATURE  :: 0x59
META_END_OF_TRACK   :: 0x2F

NOTE_ON  :: 0x90
NOTE_OFF :: 0x80

MIDI_LOWEST  :: 0
MIDI_HIGHEST :: 127

/*
The defaults DESIGN.md fixes: 120bpm, 4/4, velocity 80, channel 1, 480 ticks per
quarter, and one item to the bar. They live here rather than in the CLI so that
the flags which move them have one thing to move.
*/
smf_default_options :: proc() -> SmfOptions {
  meter := Meter{ beats = 4, unit = 4 }

  return SmfOptions {
    tempo             = SMF_DEFAULT_TEMPO,
    meter             = meter,
    duration          = meter_bar(meter),
    velocity          = SMF_DEFAULT_VELOCITY,
    channel           = 0,
    ticks_per_quarter = SMF_TICKS_PER_QUARTER,
  }
}

/*
One bar of a meter as a duration. A bar of 4/4 is four quarters, which is a
whole note, and a bar of 7/8 is seven eighths of one.
*/
meter_bar :: proc(meter: Meter) -> Duration {
  return Duration{ numerator = meter.beats, denominator = meter.unit }
}

/*
A duration in ticks. A whole note is four quarters, and a quarter is whatever
the division in the file header says it is.
*/
duration_ticks :: proc(duration: Duration, ticks_per_quarter: int) -> int {
  return ticks_per_quarter * 4 * duration.numerator / duration.denominator
}

/*
Encode voicings as a format 0 Standard MIDI File: one track, every item sounding
for the same duration, laid end to end.

The bytes are returned and nothing is written, which is what keeps the library
free of I/O and the encoder testable without a filesystem.

Returns false when a pitch falls outside MIDI's range of 128 notes, which an
octave far enough from middle C will reach.
*/
smf_encode :: proc(
  voicings  : []Voicing,
  options   : SmfOptions,
  allocator := context.allocator,
) -> ([]byte, bool) {
  track := make([dynamic]u8, 0, 128, context.temp_allocator)

  smf_write_meta(&track, 0, META_TIME_SIGNATURE, []u8 {
    u8(options.meter.beats), smf_note_value_power(options.meter.unit), 24, 8,
  })

  microseconds := 60_000_000 / options.tempo
  smf_write_meta(&track, 0, META_TEMPO, []u8 {
    u8(microseconds >> 16), u8(microseconds >> 8), u8(microseconds),
  })

  if key, has_key := options.key.?; has_key {
    if sharps, minor, key_ok := smf_key_signature(key); key_ok {
      smf_write_meta(&track, 0, META_KEY_SIGNATURE, []u8 { u8(sharps & 0xFF), minor ? 1 : 0 })
    }
  }

  ticks      := duration_ticks(options.duration, options.ticks_per_quarter)
  status_on  := u8(NOTE_ON)  | (options.channel & 0x0F)
  status_off := u8(NOTE_OFF) | (options.channel & 0x0F)

  for voicing in voicings {
    if !smf_in_range(voicing) {
      return nil, false
    }

    for pitch in voicing.pitches {
      smf_write_vlq(&track, 0)
      append(&track, status_on, u8(pitch_midi(pitch)), options.velocity)
    }

    for pitch, index in voicing.pitches {
      smf_write_vlq(&track, index == 0 ? ticks : 0)
      append(&track, status_off, u8(pitch_midi(pitch)), 0)
    }
  }

  smf_write_meta(&track, 0, META_END_OF_TRACK, nil)

  header := make([dynamic]u8, 0, 6, context.temp_allocator)
  smf_write_u16(&header, 0)
  smf_write_u16(&header, 1)
  smf_write_u16(&header, options.ticks_per_quarter)

  file := make([dynamic]u8, 0, len(track) + 22, allocator)
  smf_write_chunk(&file, "MThd", header[:])
  smf_write_chunk(&file, "MTrk", track[:])

  return file[:], true
}

/*
Whether every pitch of a voicing has a MIDI number to be written as. Middle C is
60 and the range is 128 notes wide, so a voicing five octaves either side of it
has nowhere to go.

The encoder asks this before it writes anything; a caller asks it to know which
of the voicings it handed over is the one with no answer.
*/
smf_in_range :: proc(voicing: Voicing) -> bool {
  for pitch in voicing.pitches {
    number := pitch_midi(pitch)
    if number < MIDI_LOWEST || number > MIDI_HIGHEST {
      return false
    }
  }
  return true
}

/*
The key signature a scale is written with: sharps counted positive and flats
negative, and whether the mode is minor.

A natural letter's place on the circle of fifths is its semitone count times
seven within the octave -- C is 0, G is 1, D is 2 -- which reaches F at eleven
and is read as minus one, the single flat F major carries. An accidental on the
root moves the root seven places, and a minor mode is written with the signature
of its relative major, three places back.

A mode is minor when it holds a minor third and no major one, so a dorian scale
is written as the minor key on its own tonic. MIDI has the two modes and no
others, and choosing between them by the third is the only reading that needs no
table.

Returns false past seven in either direction, which is where notation runs out
of signatures: G# minor has five sharps and Ab minor seven flats, but D# major
would want nine.
*/
@(private)
smf_key_signature :: proc(scale: Scale) -> (sharps: int, minor: bool, ok: bool) {
  position := (LETTER_SEMITONES[scale.root.letter] * 7) %% 12
  if position > 5 {
    position -= 12
  }

  sharps = position + 7 * scale.root.alteration
  minor  = scale_is_minor(scale)
  if minor {
    sharps -= 3
  }

  return sharps, minor, sharps >= -7 && sharps <= 7
}

/*
Whether a scale is written as a minor key: it has a minor third over its tonic
and no major one.
*/
@(private)
scale_is_minor :: proc(scale: Scale) -> bool {
  has_minor_third := false

  for interval in scale.intervals {
    if interval == MAJOR_THIRD {
      return false
    }
    if interval == MINOR_THIRD {
      has_minor_third = true
    }
  }

  return has_minor_third
}

/*
A meta event: its delta time, its kind, and its payload behind a length.
*/
@(private)
smf_write_meta :: proc(bytes: ^[dynamic]u8, delta: int, kind: u8, payload: []u8) {
  smf_write_vlq(bytes, delta)
  append(bytes, 0xFF, kind)
  smf_write_vlq(bytes, len(payload))
  append(bytes, ..payload)
}

/*
A chunk: a four byte tag, the length of what follows, and the body.
*/
@(private)
smf_write_chunk :: proc(bytes: ^[dynamic]u8, tag: string, body: []u8) {
  append(bytes, ..transmute([]u8)tag)
  smf_write_u32(bytes, len(body))
  append(bytes, ..body)
}

/*
A variable-length quantity: seven bits to the byte, most significant first, with
the high bit set on every byte but the last. This is how a Standard MIDI File
writes every delta time, and it is why a file of whole notes is no larger than a
file of sixteenths.
*/
@(private)
smf_write_vlq :: proc(bytes: ^[dynamic]u8, value: int) {
  buffer : [5]u8
  count  := 0

  remaining := value
  for {
    buffer[count] = u8(remaining & 0x7F)
    count        += 1
    remaining   >>= 7
    if remaining == 0 {
      break
    }
  }

  for index := count - 1; index >= 0; index -= 1 {
    continues := index > 0 ? u8(0x80) : 0
    append(bytes, buffer[index] | continues)
  }
}

@(private)
smf_write_u32 :: proc(bytes: ^[dynamic]u8, value: int) {
  append(bytes, u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value))
}

@(private)
smf_write_u16 :: proc(bytes: ^[dynamic]u8, value: int) {
  append(bytes, u8(value >> 8), u8(value))
}

/*
The exponent a note value is written as: a quarter note is 2, an eighth is 3.
*/
@(private)
smf_note_value_power :: proc(unit: int) -> u8 {
  power : u8 = 0
  for value := unit; value > 1; value /= 2 {
    power += 1
  }
  return power
}
