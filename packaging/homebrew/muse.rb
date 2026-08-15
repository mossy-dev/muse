# Formula for a Homebrew tap. It belongs in a repository named
# `mossy-dev/homebrew-tap`, at `Formula/muse.rb`, not in this one -- this copy is
# the template the release checklist copies over and re-stamps.
#
# The checksums come from the SHA256SUMS asset the release workflow publishes.

class Muse < Formula
  desc "Composable music theory CLI: scales, chords, voicings and MIDI, in pipelines"
  homepage "https://github.com/mossy-dev/muse"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/mossy-dev/muse/releases/download/v#{version}/muse-#{version}-macos-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end

    on_intel do
      url "https://github.com/mossy-dev/muse/releases/download/v#{version}/muse-#{version}-macos-x86_64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  on_linux do
    url "https://github.com/mossy-dev/muse/releases/download/v#{version}/muse-#{version}-linux-x86_64.tar.gz"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  end

  def install
    bin.install "muse"
    man1.install "muse.1"
  end

  test do
    assert_equal "muse #{version}", shell_output("#{bin}/muse --version").strip
    assert_match "G A B C D E F#", shell_output("#{bin}/muse scale G major")
    assert_match "Cmaj7", shell_output("#{bin}/muse name C E G B")
  end
end
