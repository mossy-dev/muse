# Packaging and releases

Everything downstream keys off a tag. Cutting one is the whole release; the rest
of this file is what to do with the artifacts it produces.

## Cutting a release

```
git tag -a v0.1.0 -m 'v0.1.0'
git push origin v0.1.0
```

That starts `.github/workflows/release.yml`, which on Linux x86_64, macOS arm64
and macOS x86_64 builds with `-o:speed`, runs both test packages and the
transcript, checks that the binary reports the tag it was cut from, and then
publishes the release with a `.tar.gz` per platform and a `SHA256SUMS` beside
them.

The version is not written down anywhere in the source tree. `VERSION` in
`src/cli/main.odin` reads `-define:MUSE_VERSION` and says `dev` when nobody
passed one, so a tag is the only thing that names a release and no file has to
be bumped in step with it.

## Arch, via the AUR

Two packages live in `aur/`: `muse-cli` builds from the tagged source with
`odin` from `extra`, and `muse-cli-bin` unpacks the released binary.

They are not called `muse`. `extra/muse` is the MusE sequencer, and the AUR
rejects a name the official repositories already hold. The binary is still
installed as `/usr/bin/muse`, which is free: MusE ships `muse4`.

Publishing needs an AUR account with an SSH key registered, so it is done by
hand rather than by CI:

```
cd packaging/aur/muse-cli
# set pkgver to the new version, then:
updpkgsums                      # replaces the SKIP placeholder with real hashes
makepkg --printsrcinfo > .SRCINFO
makepkg -si                     # build it once in a clean chroot before pushing

git clone ssh://aur@aur.archlinux.org/muse-cli.git aur-muse-cli
cp PKGBUILD .SRCINFO aur-muse-cli/
cd aur-muse-cli && git commit -am 'v0.1.0' && git push
```

`.SRCINFO` is generated, so it is not kept in this repository — only the
`PKGBUILD` the generation reads.

## macOS, via Homebrew

`homebrew/muse.rb` is a template for a tap, not a live formula. Create
`mossy-dev/homebrew-tap` once, then per release copy the file to
`Formula/muse.rb` there, set `version`, and paste the three checksums out of the
release's `SHA256SUMS`.

Users then install with:

```
brew install mossy-dev/tap/muse
```

`muse` is free in homebrew-core, so the formula could move there once the
project clears Homebrew's notability bar. A tap has no such bar and works today.
