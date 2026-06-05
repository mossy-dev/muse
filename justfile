default:
  @just --list

build:
  odin build . -debug -out:build

release:
  odin build . -o:speed -out:build

run: build
  ./build

clean:
  rm -f build
