package muse

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:testing"

/*
One event a decoded track holds: when it sounds, what it is, and its bytes. A
meta event carries 0xFF as its status and its kind beside it; a note event
carries its channel status and leaves the kind at zero.
*/
DecodedEvent :: struct {
  tick   : int,
  status : u8,
  kind   : u8,
  data   : []u8,
}

DecodedFile :: struct {
  format   : int,
  tracks   : int,
  division : int,
  events   : []DecodedEvent,
}

/*
Read back what the encoder produced. It lives in the test file because muse
writes MIDI files and does not read them, and because a gate that says "every
note-on is matched by a note-off" needs something that can count them.

Returns false on anything the encoder does not emit -- a chunk out of place, a
running status, a voice message that is not a note -- so the decoder disagreeing
with the encoder is a failure rather than a shrug.
*/
smf_decode :: proc(bytes: []byte, allocator := context.allocator) -> (DecodedFile, bool) {
  file   : DecodedFile
  offset := 0

  tag, header, header_ok := decode_chunk(bytes, &offset)
  if !header_ok || tag != "MThd" || len(header) != 6 {
    return {}, false
  }
  file.format   = decode_u16(header[0:2])
  file.tracks   = decode_u16(header[2:4])
  file.division = decode_u16(header[4:6])

  track_tag, track, track_ok := decode_chunk(bytes, &offset)
  if !track_ok || track_tag != "MTrk" || offset != len(bytes) {
    return {}, false
  }

  events := make([dynamic]DecodedEvent, 0, 16, allocator)
  tick   := 0
  cursor := 0

  for cursor < len(track) {
    delta, delta_ok := decode_vlq(track, &cursor)
    if !delta_ok || cursor >= len(track) {
      return {}, false
    }
    tick += delta

    status := track[cursor]
    cursor += 1

    if status == 0xFF {
      if cursor >= len(track) {
        return {}, false
      }
      kind   := track[cursor]
      cursor += 1

      length, length_ok := decode_vlq(track, &cursor)
      if !length_ok || cursor + length > len(track) {
        return {}, false
      }

      append(&events, DecodedEvent{ tick, status, kind, track[cursor:][:length] })
      cursor += length
      continue
    }

    if status & 0xF0 != NOTE_ON && status & 0xF0 != NOTE_OFF {
      return {}, false
    }
    if cursor + 2 > len(track) {
      return {}, false
    }

    append(&events, DecodedEvent{ tick, status, 0, track[cursor:][:2] })
    cursor += 2
  }

  file.events = events[:]
  return file, true
}

@(private = "file")
decode_chunk :: proc(bytes: []byte, offset: ^int) -> (tag: string, body: []byte, ok: bool) {
  if offset^ + 8 > len(bytes) {
    return "", nil, false
  }

  tag    = string(bytes[offset^:][:4])
  length := decode_u32(bytes[offset^ + 4:][:4])
  offset^ += 8

  if offset^ + length > len(bytes) {
    return "", nil, false
  }

  body = bytes[offset^:][:length]
  offset^ += length
  return tag, body, true
}

@(private = "file")
decode_vlq :: proc(bytes: []byte, cursor: ^int) -> (value: int, ok: bool) {
  for count := 0; count < 4; count += 1 {
    if cursor^ >= len(bytes) {
      return 0, false
    }

    piece  := bytes[cursor^]
    cursor^ += 1
    value   = value << 7 | int(piece & 0x7F)

    if piece & 0x80 == 0 {
      return value, true
    }
  }
  return 0, false
}

@(private = "file")
decode_u16 :: proc(bytes: []byte) -> int {
  return int(bytes[0]) << 8 | int(bytes[1])
}

@(private = "file")
decode_u32 :: proc(bytes: []byte) -> int {
  return int(bytes[0]) << 24 | int(bytes[1]) << 16 | int(bytes[2]) << 8 | int(bytes[3])
}

@(private = "file")
hex_string :: proc(bytes: []byte, allocator := context.allocator) -> string {
  builder := strings.builder_make(allocator)
  for value in bytes {
    fmt.sbprintf(&builder, "%02x", value)
  }
  return strings.to_string(builder)
}

/*
A voicing from a chord symbol, which is what every pipeline into the encoder
ends with.
*/
@(private = "file")
voicing_of :: proc(t: ^testing.T, symbol: string, octave := 4) -> Voicing {
  chord, chord_ok := chord_parse(symbol, context.temp_allocator)
  testing.expectf(t, chord_ok, "%s did not parse", symbol)

  voicing, voicing_ok := voicing_close(chord, octave, false, context.temp_allocator)
  testing.expectf(t, voicing_ok, "%s did not realize", symbol)

  return voicing
}

@(test)
test_variable_length_quantities_span_their_range :: proc(t: ^testing.T) {
  cases := []struct{ value: int, encoded: []u8 } {
    { 0,       { 0x00 } },
    { 64,      { 0x40 } },
    { 127,     { 0x7F } },
    { 128,     { 0x81, 0x00 } },
    { 480,     { 0x83, 0x60 } },
    { 1920,    { 0x8F, 0x00 } },
    { 16383,   { 0xFF, 0x7F } },
    { 1048576, { 0xC0, 0x80, 0x00 } },
  }

  for test_case in cases {
    bytes := make([dynamic]u8, 0, 4, context.temp_allocator)
    smf_write_vlq(&bytes, test_case.value)

    testing.expectf(
      t, slice.equal(bytes[:], test_case.encoded),
      "%d encoded as %s", test_case.value, hex_string(bytes[:], context.temp_allocator),
    )
  }
}

/*
The delta times a decoder reads back are the ones the encoder wrote, whatever
their width.
*/
@(test)
test_variable_length_quantities_round_trip :: proc(t: ^testing.T) {
  for value in ([]int{ 0, 1, 127, 128, 480, 1920, 16383, 16384, 1048576, 0x0FFFFFFF }) {
    bytes := make([dynamic]u8, 0, 4, context.temp_allocator)
    smf_write_vlq(&bytes, value)

    cursor := 0
    decoded, decoded_ok := decode_vlq(bytes[:], &cursor)

    testing.expectf(t, decoded_ok, "%d did not decode", value)
    testing.expect_value(t, decoded, value)
    testing.expect_value(t, cursor, len(bytes))
  }
}

@(test)
test_a_file_carries_one_format_zero_track :: proc(t: ^testing.T) {
  voicings := []Voicing{ voicing_of(t, "Cmaj7") }

  bytes, encode_ok := smf_encode(voicings, smf_default_options(), context.temp_allocator)
  testing.expect(t, encode_ok)

  file, decode_ok := smf_decode(bytes, context.temp_allocator)
  testing.expect(t, decode_ok)
  testing.expect_value(t, file.format, 0)
  testing.expect_value(t, file.tracks, 1)
  testing.expect_value(t, file.division, SMF_TICKS_PER_QUARTER)
}

/*
Every note-on is matched by a note-off, and nothing is left sounding at the end
of the track. This is the property a stuck note would break.
*/
@(test)
test_every_note_on_is_matched_by_a_note_off :: proc(t: ^testing.T) {
  voicings := []Voicing{ voicing_of(t, "Cmaj7"), voicing_of(t, "Fmaj7"), voicing_of(t, "G7") }

  bytes, encode_ok := smf_encode(voicings, smf_default_options(), context.temp_allocator)
  testing.expect(t, encode_ok)

  file, decode_ok := smf_decode(bytes, context.temp_allocator)
  testing.expect(t, decode_ok)

  sounding := 0
  ons      := 0
  for event in file.events {
    switch event.status & 0xF0 {
    case NOTE_ON:
      sounding += 1
      ons      += 1
    case NOTE_OFF:
      sounding -= 1
    }
    testing.expectf(t, sounding >= 0, "a note ended before it began at tick %d", event.tick)
  }

  testing.expect_value(t, ons, 12)
  testing.expect_value(t, sounding, 0)
}

/*
Items are laid end to end, so the track is as long as the number of items times
the duration each was given.
*/
@(test)
test_delta_times_sum_to_the_length_asked_for :: proc(t: ^testing.T) {
  voicings := []Voicing{ voicing_of(t, "C"), voicing_of(t, "F"), voicing_of(t, "G") }

  options := smf_default_options()
  options.duration = Duration{ 1, 4 }

  bytes, encode_ok := smf_encode(voicings, options, context.temp_allocator)
  testing.expect(t, encode_ok)

  file, decode_ok := smf_decode(bytes, context.temp_allocator)
  testing.expect(t, decode_ok)

  last := file.events[len(file.events) - 1]
  testing.expect_value(t, last.kind, u8(META_END_OF_TRACK))
  testing.expect_value(t, last.tick, 3 * SMF_TICKS_PER_QUARTER)
}

@(test)
test_meta_events_carry_the_values_asked_for :: proc(t: ^testing.T) {
  scale, scale_ok := scale_parse("G major", context.temp_allocator)
  testing.expect(t, scale_ok)

  options := smf_default_options()
  options.tempo = 90
  options.meter = Meter{ 3, 8 }
  options.key   = scale

  bytes, encode_ok := smf_encode([]Voicing{ voicing_of(t, "C") }, options, context.temp_allocator)
  testing.expect(t, encode_ok)

  file, decode_ok := smf_decode(bytes, context.temp_allocator)
  testing.expect(t, decode_ok)

  tempo, tempo_found         := meta_payload(file, META_TEMPO)
  signature, signature_found := meta_payload(file, META_TIME_SIGNATURE)
  key, key_found             := meta_payload(file, META_KEY_SIGNATURE)

  testing.expect(t, tempo_found && signature_found && key_found)
  testing.expect_value(t, decode_u32([]u8{ 0, tempo[0], tempo[1], tempo[2] }), 60_000_000 / 90)
  testing.expect_value(t, signature[0], u8(3))
  testing.expect_value(t, signature[1], u8(3))
  testing.expect_value(t, key[0], u8(1))
  testing.expect_value(t, key[1], u8(0))
}

/*
The signature a key is written with, over the roots that reach the edges of what
notation can write.
*/
@(test)
test_key_signatures_follow_the_circle_of_fifths :: proc(t: ^testing.T) {
  cases := []struct{ name: string, sharps: int, minor: bool, ok: bool } {
    { "C major",  0,  false, true  },
    { "G major",  1,  false, true  },
    { "F major",  -1, false, true  },
    { "Eb major", -3, false, true  },
    { "C# major", 7,  false, true  },
    { "Cb major", -7, false, true  },
    { "A minor",  0,  true,  true  },
    { "E minor",  1,  true,  true  },
    { "G# minor", 5,  true,  true  },
    { "Ab minor", -7, true,  true  },
    { "D dorian", -1, true,  true  },
    { "D# major", 0,  false, false },
  }

  for test_case in cases {
    scale, scale_ok := scale_parse(test_case.name, context.temp_allocator)
    testing.expectf(t, scale_ok, "%s did not parse", test_case.name)

    sharps, minor, ok := smf_key_signature(scale)
    testing.expectf(t, ok == test_case.ok, "%s was %v", test_case.name, ok)
    if !test_case.ok {
      continue
    }

    testing.expectf(t, sharps == test_case.sharps, "%s has %d sharps", test_case.name, sharps)
    testing.expectf(t, minor == test_case.minor, "%s minor is %v", test_case.name, minor)
  }
}

/*
A key with no signature to write leaves the event out rather than writing a
wrong one. Everything else in the file is unaffected.
*/
@(test)
test_a_key_past_seven_accidentals_writes_no_signature :: proc(t: ^testing.T) {
  scale, scale_ok := scale_parse("D# major", context.temp_allocator)
  testing.expect(t, scale_ok)

  options := smf_default_options()
  options.key = scale

  bytes, encode_ok := smf_encode([]Voicing{ voicing_of(t, "C") }, options, context.temp_allocator)
  testing.expect(t, encode_ok)

  file, decode_ok := smf_decode(bytes, context.temp_allocator)
  testing.expect(t, decode_ok)

  _, found := meta_payload(file, META_KEY_SIGNATURE)
  testing.expect(t, !found)
}

@(test)
test_a_pitch_outside_the_midi_range_has_no_file :: proc(t: ^testing.T) {
  high := voicing_of(t, "Cmaj7", 9)
  low  := voicing_of(t, "Cmaj7", -2)

  _, high_ok := smf_encode([]Voicing{ high }, smf_default_options(), context.temp_allocator)
  _, low_ok  := smf_encode([]Voicing{ low },  smf_default_options(), context.temp_allocator)

  testing.expect(t, !high_ok)
  testing.expect(t, !low_ok)
}

@(test)
test_durations_convert_to_ticks :: proc(t: ^testing.T) {
  testing.expect_value(t, duration_ticks(Duration{ 1, 4 }, 480), 480)
  testing.expect_value(t, duration_ticks(Duration{ 1, 8 }, 480), 240)
  testing.expect_value(t, duration_ticks(Duration{ 1, 1 }, 480), 1920)
  testing.expect_value(t, duration_ticks(meter_bar(Meter{ 4, 4 }), 480), 1920)
  testing.expect_value(t, duration_ticks(meter_bar(Meter{ 7, 8 }), 480), 1680)
  testing.expect_value(t, duration_ticks(meter_bar(Meter{ 3, 4 }), 480), 1440)
}

/*
The bytes of one fixed pipeline, so that a change in the format is caught rather
than reasoned about. Cmaj7 in close position at the defaults, event by event:

  the header chunk, format 0, one track, 480 ticks to the quarter
  the track chunk and its length
  4/4, twenty-four clocks to the metronome, eight demisemiquavers to the quarter
  500000 microseconds to the quarter, which is 120bpm
  C4 E4 G4 B4 on, at velocity 80
  the same four off, the first after a bar of 1920 ticks
  end of track
*/
@(test)
test_a_fixed_pipeline_has_fixed_bytes :: proc(t: ^testing.T) {
  golden := strings.concatenate([]string {
    "4d546864000000060000000101e0",
    "4d54726b00000034",
    "00ff580404021808",
    "00ff510307a120",
    "00903c50", "00904050", "00904350", "00904750",
    "8f00803c00", "00804000", "00804300", "00804700",
    "00ff2f00",
  }, context.temp_allocator)

  bytes, encode_ok := smf_encode(
    []Voicing{ voicing_of(t, "Cmaj7") }, smf_default_options(), context.temp_allocator,
  )
  testing.expect(t, encode_ok)
  testing.expect_value(t, hex_string(bytes, context.temp_allocator), golden)
}

@(private = "file")
meta_payload :: proc(file: DecodedFile, kind: u8) -> ([]u8, bool) {
  for event in file.events {
    if event.status == 0xFF && event.kind == kind {
      return event.data, true
    }
  }
  return nil, false
}
