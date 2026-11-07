class Speakback < Formula
  desc "Read text aloud on your Mac with Kokoro-82M, fully on device"
  homepage "https://github.com/YashSharmaa/speakback"
  url "https://github.com/YashSharmaa/speakback/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "13775c2f905afe73a01af06176c39fcecad393fc9a9d7881741bc3ea3264a311"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    # Swift 6.2 or later, from Xcode or the command-line tools.
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "speak"
    # Only the binary: FluidAudio's unused LuxTTS resource bundle is left out on purpose.
    bin.install ".build/release/speak"
  end

  def caveats
    <<~EOS
      speak is a command-line tool, so there is no app to copy to /Applications.
      The first run downloads about 90 MB of Core ML models into
        ~/Library/Application Support/speak
      Teach a coding agent to read answers aloud:
        speak install-skill --claude     (or --codex, --opencode, --print)
    EOS
  end

  test do
    assert_match "1.0.0", shell_output("#{bin}/speak --version")
    assert_match "Jason", shell_output("#{bin}/speak --normalize 'Parse the JSON.'")
  end
end
