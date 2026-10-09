class AppIntentsMigrator < Formula
  desc "Scan and migrate SiriKit code to App Intents"
  homepage "https://github.com/divyaravitech/AppIntentsMigrator"
  url "https://github.com/divyaravitech/AppIntentsMigrator/releases/download/v1.0.1/app-intents-migrator-macos-universal.tar.gz"
  sha256 "e050b4f25e49d81f002cc792d584f4e6a564c153fbd25cf57f9fbf52d5209d06"
  version "1.0.1"
  license "MIT"

  # Installs the prebuilt universal binary. Building from source would pull in
  # swift-syntax and require a full Xcode plus Command Line Tools, which is a lot
  # to ask for a command-line scanner.
  def install
    bin.install "app-intents-migrator"
  end

  test do
    (testpath/"Legacy.swift").write <<~SWIFT
      import Intents
      class IntentHandler: INExtension {}
    SWIFT
    output = shell_output("#{bin}/app-intents-migrator scan #{testpath} --no-json")
    assert_match "INExtension subclasses: 1", output
    assert_match version.to_s, shell_output("#{bin}/app-intents-migrator --version")
  end
end
