# Contributing

Bug reports, chord symbols muse gets wrong, and scales it cannot spell are all
welcome — a failing example pasted into an issue is worth more than a
description of it.

## Getting set up

You need [Odin](https://odin-lang.org/docs/install/) and, for the recipes,
[just](https://github.com/casey/just).

```
just test       # the library, the CLI, and the golden transcripts
just build      # ./build, one binary, debug
just release    # optimized
```

`just test` is the gate. It has to be green before a pull request, and CI runs
the same three things on Linux x86_64, macOS arm64 and macOS x86_64.

## The transcript is the contract

`tests/transcript.txt` is a list of pipelines and exactly what they print.
`tests/transcript.sh` re-runs every one and diffs the result, so a change that
alters a single column of a single line fails until the transcript says so too.

That is deliberate. muse's one claim is that the output of a command is valid
input to the next, and the transcript is that claim written down. If your change
alters output, update the transcript in the same commit and the diff will show a
reviewer precisely what a user will see.

Adding a pipeline is the cheapest way to cover new behaviour, and it is not a
substitute for a unit test — new library behaviour gets tests in the same commit
as the code, not after.

## How changes land

`main` is protected. Work on a branch, open a pull request, and wait for CI and
an approving review. There is no path around this, including for the maintainer.

Commit messages are one line, imperative in mood, no trailing period.

## Style

`docs/DESIGN.md` is the reference; the summary is:

- Two-space indent, spaces not tabs.
- Expanded names — `session_manager`, not `sm`.
- Block comments above a proc, saying why. Not inline comments, and not comments
  restating the code.
- **Nothing derivable is stored.** If a table can be computed from intervals,
  compute it. The rewrite this codebase came out of exists because hand-written
  tables of derived facts drifted out of agreement with each other.
- No speculative error handling for cases that cannot occur.
- The library allocates through an `allocator := context.allocator` parameter and
  the caller owns the result; scratch goes through `context.temp_allocator`. The
  CLI runs off one arena and frees it at exit.

## Where things are

| Path | What lives there |
|---|---|
| `src/muse/` | the library: notes, intervals, scales, chords, voicings, MIDI |
| `src/cli/` | argument parsing, commands, rendering, sinks |
| `tests/` | the transcript and its runner |
| `docs/` | design, the chord grammar, the build order |
| `packaging/` | AUR and Homebrew packaging, and the release process |

Unit tests sit beside the code they cover, as `*_test.odin`.

## Open questions

The parking lot at the end of `docs/DESIGN.md` lists what is deliberately
unsettled — the JSON schema's stability, harmonizing by subset, and the rest. If
you want to work on something larger, start there or open an issue first.
