default:
  @just --list

build:
  odin build src/cli -debug -out:build

release:
  odin build src/cli -o:speed -out:build

test:
  odin test src/muse

run: build
  ./build

clean:
  rm -f build
