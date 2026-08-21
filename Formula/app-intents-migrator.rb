class AppIntentsMigrator < Formula
  desc "Scan and migrate SiriKit code to App Intents"
  homepage "https://github.com/divyaravitech/AppIntentsMigrator"
  url "https://github.com/divyaravitech/AppIntentsMigrator/archive/refs/tags/v1.0.0.tar.gz"
  # Recompute with Scripts/update-formula-sha.sh once the repository is public —
  # the release tarball 404s while it is private, and a naive curl|shasum will
  # silently hash the error page.
  sha256 "4a00e12b8d06c544814897a7719859bd647ceef48ddd499afebb77e96948220c"
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
