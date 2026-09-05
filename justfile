# The version a build stamps into the binary. A release passes the tag it is cut
# from; a build from a working tree leaves it as dev.
version := env("MUSE_VERSION", "dev")

# Where `just install` puts things, and the staging root a packager prepends.
prefix  := env("PREFIX", "/usr/local")
destdir := env("DESTDIR", "")

default:
  @just --list

build:
  odin build src/cli -debug -out:build -define:MUSE_VERSION={{version}}

release:
  odin build src/cli -o:speed -out:build -define:MUSE_VERSION={{version}}

test: build
  odin test src/muse
  odin test src/cli
  ./tests/transcript.sh
  ./tests/completions.sh

transcript: build
  ./tests/transcript.sh

run: build
  ./build

# The page is generated rather than kept, since its command surface is the
# binary's own help text and a stored copy could disagree with it.
man: build
  ./tools/manpage.sh build > muse.1

# The completions are generated for the same reason the page is: the commands,
# the flags and the words each one takes come from `muse help`.
completions: build
  ./tools/completions.sh build bash > muse.bash
  ./tools/completions.sh build zsh  > _muse
  ./tools/completions.sh build fish > muse.fish

install: release
  ./tools/manpage.sh build > muse.1
  ./tools/completions.sh build bash > muse.bash
  ./tools/completions.sh build zsh  > _muse
  ./tools/completions.sh build fish > muse.fish
  install -Dm755 build {{destdir}}{{prefix}}/bin/muse
  install -Dm644 muse.1 {{destdir}}{{prefix}}/share/man/man1/muse.1
  install -Dm644 muse.bash {{destdir}}{{prefix}}/share/bash-completion/completions/muse
  install -Dm644 _muse {{destdir}}{{prefix}}/share/zsh/site-functions/_muse
  install -Dm644 muse.fish {{destdir}}{{prefix}}/share/fish/vendor_completions.d/muse.fish
  install -Dm644 LICENSE {{destdir}}{{prefix}}/share/licenses/muse/LICENSE

clean:
  rm -f build muse.1 muse.bash _muse muse.fish
