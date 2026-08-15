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

transcript: build
  ./tests/transcript.sh

run: build
  ./build

install: release
  install -Dm755 build {{destdir}}{{prefix}}/bin/muse
  install -Dm644 LICENSE {{destdir}}{{prefix}}/share/licenses/muse/LICENSE

clean:
  rm -f build
