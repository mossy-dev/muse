#!/bin/sh
#
# Write muse.1 to stdout.
#
# The command surface is not written here. It is taken from `muse help`, which
# is the same string the binary prints, so the page cannot describe a flag the
# program does not have. Only the prose around it lives in this script -- the
# parts a usage summary has no room for.
#
# Usage: tools/manpage.sh [path-to-muse] > muse.1

set -eu

binary=${1:-./build}

# A bare name is a path here, not something to look up on PATH.
case "$binary" in
  */*) ;;
  *) binary="./$binary" ;;
esac

if [ ! -x "$binary" ]; then
  echo "manpage: no binary at $binary; run just build" >&2
  exit 1
fi

version=$("$binary" --version | cut -d' ' -f2)

# Honour SOURCE_DATE_EPOCH so a distribution can build the page reproducibly.
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  date=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d 2>/dev/null \
      || date -u -r "$SOURCE_DATE_EPOCH" +%Y-%m-%d)
else
  date=$(date -u +%Y-%m-%d)
fi

# Turn arbitrary text into something safe inside a .nf block: backslashes become
# the roff escape for one, hyphens become the ASCII hyphen rather than a Unicode
# one so the page can be copied out of, and a line opening with a control
# character is protected by a zero-width space.
literal() {
  sed -e 's/\\/\\e/g' -e 's/-/\\-/g' -e "s/^[.']/\\\\\&&/"
}

cat <<ROFF
.TH MUSE 1 "$date" "muse $version" "User Commands"
.SH NAME
muse \\- composable music theory CLI
.SH SYNOPSIS
.B muse
.I command
.RI [ operand " ...]"
.SH DESCRIPTION
.B muse
answers questions about scales, chords, intervals, voicings and transpositions,
and it composes: the output of one invocation is valid input to the next.
.PP
Every line
.B muse
prints carries a datum in field one, delimited by a tab, and anything after it
is annotation for a reader. The datum is ordinary notation, such as
.BR "G major" ,
.BR Am7 ,
.B "C E G"
or
.BR "G3 C4 E4 B4" ,
so any line can be piped into the next command or typed back in by hand. There
is no second, machine-only format.
.PP
A terminal changes layout and colour, never content: columns are padded on a
terminal and tab-separated in a pipe, and field one is the same bytes either
way.
.PP
Every command reads its operand from its arguments, and from standard input when
it has none.
.SH COMMANDS
The surface below is what
.B muse help
prints.
.PP
.nf
.RS 2
$("$binary" help | literal)
.RE
.fi
.SH EXIT STATUS
.TP
.B 0
Success.
.TP
.B 1
A usage or parse error. The offending token is echoed on standard error.
.TP
.B 2
A well-formed request with no musical answer: a degree beyond the scale, an
inversion of a single note, or a scale that cannot be spelled without a triple
accidental.
.PP
Nothing reaches standard output on failure. A command parses every datum in its
input before it renders any of them, so a failure anywhere leaves the output
empty rather than partial.
.SH ENVIRONMENT
.TP
.B NO_COLOR
Set to any value to suppress colour, as if
.B \\-\\-color never
had been passed.
.TP
.B TERM
A value of
.B dumb
suppresses colour.
.SH EXAMPLES
Build a scale and harmonize it:
.PP
.nf
.RS 2
$ muse scale G major | muse chords
.RE
.fi
.PP
Take a progression by degree, voice it, and write a MIDI file:
.PP
.nf
.RS 2
$ muse scale C major | muse chords I V vi IV | muse voice drop2 | muse midi \\-o loop.mid
.RE
.fi
.PP
Ask what a set of notes is called:
.PP
.nf
.RS 2
$ muse name A C E G
Am7  A C E G
.RE
.fi
.PP
Ask everything at once:
.PP
.nf
.RS 2
$ muse chord Cmaj7 | muse info
.RE
.fi
.SH NOTES
.B muse midi
refuses to write to a terminal, since positional arguments belong to the datum
and a filename cannot go there. Redirect it, or use
.BR \\-o .
.PP
The JSON schema is unstable and may change without notice. It says what
.B muse
knows about a datum rather than promising how that is spelled.
.SH SEE ALSO
The full documentation, including the chord grammar and the design, is at
.PP
.RS 2
https://github.com/mossy\\-dev/muse
.RE
.SH AUTHOR
Jake Carr.
ROFF
