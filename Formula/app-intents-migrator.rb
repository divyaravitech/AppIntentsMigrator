class AppIntentsMigrator < Formula
  desc "Scan and migrate SiriKit code to App Intents"
  homepage "https://github.com/divyaravitech/AppIntentsMigrator"
  url "https://github.com/divyaravitech/AppIntentsMigrator/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
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
