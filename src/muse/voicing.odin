package muse

import "core:slice"

/*
Concrete pitches, ordered low to high. This is the only type in the library that
is about register: Scale and Chord say which notes, a Voicing says where they
sound, and every operation here moves pitches between octaves without changing
which notes they are.
*/
Voicing :: struct {
  pitches : []Pitch,
}

/*
A voicing from pitches given in any order. The order is the invariant, so it is
established here rather than trusted from the caller.
*/
voicing_make :: proc(pitches: []Pitch, allocator := context.allocator) -> Voicing {
  ordered := slice.clone(pitches, allocator)
  pitches_sort(ordered)
  return Voicing{ pitches = ordered }
}

/*
Realize a chord in close position: its notes stacked upward from the root, each
in the lowest octave that keeps the voicing ascending.

octave places the bottom voice, and defaults to the one containing middle C, so
a close C major triad is MIDI 60, 64, 67. A slash bass takes that bottom octave
itself, which turns a chord tone in the bass into the inversion a player would
read and puts an outside bass underneath the chord entire.

literal keeps the eleventh a thirteenth chord drops. Returns false when a note
of the chord cannot be spelled.
*/
voicing_close :: proc(chord: Chord, octave := 4, literal := false, allocator := context.allocator) -> (Voicing, bool) {
  notes, notes_ok := chord_notes(chord, literal, context.temp_allocator)
  if !notes_ok {
    return {}, false
  }
  return voicing_stack(notes, octave, allocator), true
}

/*
Realize the degrees that carry a chord's quality and nothing else: the root, the
third or the suspension standing in for it, and the seventh or the sixth. The
fifth and the upper extensions go, since neither tells a listener which chord
this is.
*/
voicing_shell :: proc(chord: Chord, octave := 4, allocator := context.allocator) -> (Voicing, bool) {
  intervals := make([dynamic]Interval, 0, 3, context.temp_allocator)

  if root, found := intervals_find_steps(chord.intervals, 0); found {
    append(&intervals, root)
  }
  for steps in ([]int{ 2, 3, 1 }) {
    if interval, found := intervals_find_steps(chord.intervals, steps); found {
      append(&intervals, interval)
      break
    }
  }
  for steps in ([]int{ 6, 5 }) {
    if interval, found := intervals_find_steps(chord.intervals, steps); found {
      append(&intervals, interval)
      break
    }
  }

  shell := Chord {
    root      = chord.root,
    symbol    = chord.symbol,
    intervals = intervals[:],
    bass      = chord.bass,
  }
  return voicing_close(shell, octave, false, allocator)
}

/*
Spread a voicing by lifting every second voice an octave, so a close triad
becomes root, fifth, third. This is what open position means; a wider style with
no definition beyond being wider is not something that can be tested.
*/
voicing_open :: proc(voicing: Voicing, allocator := context.allocator) -> Voicing {
  pitches := slice.clone(voicing.pitches, allocator)

  for index := 1; index < len(pitches); index += 2 {
    pitches[index].octave += 1
  }

  pitches_sort(pitches)
  return Voicing{ pitches = pitches }
}

/*
Invert a voicing by moving its bottom pitch up an octave, n times over. This is
what inverting a chord actually is, and it is why Chord has no inversion field:
the operation needs register, so it belongs to the type that has one.

Valid for any n on any voicing, muse-built or not. Past the number of voices it
keeps going and the voicing rises by an octave each time round; a negative n
moves the top pitch down instead.
*/
voicing_invert :: proc(voicing: Voicing, n: int, allocator := context.allocator) -> Voicing {
  pitches := slice.clone(voicing.pitches, allocator)
  if len(pitches) == 0 {
    return Voicing{ pitches = pitches }
  }

  pitches_sort(pitches)
  for _ in 0 ..< n {
    pitches[0].octave += 1
    pitches_sort(pitches)
  }
  for _ in 0 ..< -n {
    pitches[len(pitches) - 1].octave -= 1
    pitches_sort(pitches)
  }

  return Voicing{ pitches = pitches }
}

/*
Drop the nth voice from the top down an octave: n of 2 and 3 are the drop-2 and
drop-3 voicings, and nothing else about the voicing moves.

Returns false for an n that names no inner voice, which is a well-formed request
with no answer rather than a malformed one.
*/
voicing_drop :: proc(voicing: Voicing, n: int, allocator := context.allocator) -> (Voicing, bool) {
  if n < 2 || n > len(voicing.pitches) {
    return {}, false
  }

  pitches := slice.clone(voicing.pitches, allocator)
  pitches_sort(pitches)
  pitches[len(pitches) - n].octave -= 1
  pitches_sort(pitches)

  return Voicing{ pitches = pitches }, true
}

/*
The notes a voicing sounds, low to high, each one once. This is what hands a
voicing back to chord_identify: the bottom pitch comes first, so the reading
rooted on the bass is the one the ranking prefers.
*/
voicing_notes :: proc(voicing: Voicing, allocator := context.allocator) -> []Note {
  notes := make([dynamic]Note, 0, len(voicing.pitches), allocator)

  for pitch in voicing.pitches {
    if !slice.contains(notes[:], pitch.note) {
      append(&notes, pitch.note)
    }
  }

  return notes[:]
}

/*
Place a run of notes in ascending order, the first in the given octave and each
one after it in the lowest octave that clears the pitch below. Enharmonic
neighbours are compared by sound, so a B# under a C lands in the octave that
keeps the voicing ascending rather than the one its letter suggests.
*/
@(private)
voicing_stack :: proc(notes: []Note, octave: int, allocator := context.allocator) -> Voicing {
  pitches := make([dynamic]Pitch, 0, len(notes), allocator)

  for note, index in notes {
    pitch := Pitch{ note = note, octave = octave }

    if index > 0 {
      previous := pitches[index - 1]
      pitch.octave = previous.octave
      for pitch_compare(pitch, previous) <= 0 {
        pitch.octave += 1
      }
    }

    append(&pitches, pitch)
  }

  return Voicing{ pitches = pitches[:] }
}

@(private)
intervals_find_steps :: proc(intervals: []Interval, steps: int) -> (Interval, bool) {
  for interval in intervals {
    if interval.steps == steps {
      return interval, true
    }
  }
  return {}, false
}

@(private)
pitches_sort :: proc(pitches: []Pitch) {
  slice.sort_by(pitches, proc(a, b: Pitch) -> bool {
    return pitch_compare(a, b) < 0
  })
}
