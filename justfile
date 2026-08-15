default:
  @just --list

build:
  odin build src/cli -debug -out:build

release:
  odin build src/cli -o:speed -out:build

test: build
  odin test src/muse
  odin test src/cli
  ./tests/transcript.sh

transcript: build
  ./tests/transcript.sh

run: build
  ./build

clean:
  rm -f build
