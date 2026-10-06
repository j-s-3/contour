# Homebrew formula for Contour. The repo doubles as its own tap:
#
#   brew tap j-s-3/contour https://github.com/j-s-3/contour
#   brew install --HEAD j-s-3/contour/contour
#
# HEAD-only until there are tagged releases to pin a url/sha256 to.
class Contour < Formula
  desc "Native macOS PR review app that validates engineering decisions, not every line"
  homepage "https://github.com/j-s-3/contour"
  license "Apache-2.0"
  head "https://github.com/j-s-3/contour.git", branch: "main"

  # Package.swift declares swift-tools-version 6.4, which ships with Xcode 27.
  depends_on xcode: ["27.0", :build]
  depends_on macos: :sequoia

  def install
    # `swift` resolves through xcode-select, which may point at the Command Line Tools.
    # Their compiler rejects code that builds under Xcode 27's toolchain, so build with
    # the Xcode the formula depends on, the same toolchain CI uses.
    ENV["DEVELOPER_DIR"] = MacOS::Xcode.prefix.to_s

    # SwiftPM's own sandbox can't nest inside Homebrew's build sandbox.
    system "swift", "build", "--disable-sandbox", "-c", "release"

    # `Bundle.module` looks for the resource bundle next to the executable, so the two
    # stay together in libexec and bin gets a wrapper rather than a symlink.
    libexec.install ".build/release/Contour", ".build/release/Contour_Contour.bundle"
    (bin/"contour").write <<~SH
      #!/bin/bash
      exec "#{libexec}/Contour" "$@"
    SH
  end

  def caveats
    <<~EOS
      Contour drives an AI CLI you're already signed in to: either `pi` or
      Claude Code (`claude`, 2.1.24+). Install and sign in to one of them.
      `gh` is optional and only needed for private pull requests.

      Launch with:
        contour
    EOS
  end

  test do
    assert_predicate libexec/"Contour", :executable?
    assert_path_exists libexec/"Contour_Contour.bundle/Contents/Resources/AppIcon.icns"
  end
end
