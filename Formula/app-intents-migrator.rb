class AppIntentsMigrator < Formula
  desc "Scan and migrate SiriKit code to App Intents"
  homepage "https://github.com/divyaravitech/AppIntentsMigrator"
  url "https://github.com/divyaravitech/AppIntentsMigrator/archive/refs/tags/v1.0.1.tar.gz"
  # Recompute with Scripts/update-formula-sha.sh once the repository is public —
  # the release tarball 404s while it is private, and a naive curl|shasum will
  # silently hash the error page.
  sha256 "f2c285d71b3be49fc337491628e3204e5fa7023992ca0574c5be75355e608500"
  license "MIT"
  head "https://github.com/divyaravitech/AppIntentsMigrator.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/app-intents-migrator"
  end

  test do
    (testpath/"Legacy.swift").write <<~SWIFT
      import Intents
      class IntentHandler: INExtension {}
    SWIFT
    output = shell_output("#{bin}/app-intents-migrator scan #{testpath} --no-json")
    assert_match "INExtension subclasses: 1", output
  end
end
