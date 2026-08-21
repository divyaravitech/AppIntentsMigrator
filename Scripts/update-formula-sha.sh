#!/usr/bin/env bash
# Recompute the Homebrew formula's sha256 from a published release tarball.
#
# Uses `curl --fail`. Without it, curl exits 0 on a 404 and pipes the error page
# into shasum, producing a plausible-looking hash of the words "Not Found" — which
# is exactly how a bad SHA got committed once already.
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version>   e.g. $0 1.0.0" >&2; exit 2; }

REPO="divyaravitech/AppIntentsMigrator"
URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"
FORMULA="$(dirname "$0")/../Formula/app-intents-migrator.rb"

echo "Fetching $URL"
SHA="$(curl --fail --silent --location "$URL" | shasum -a 256 | awk '{print $1}')"

[ "${#SHA}" -eq 64 ] || { echo "unexpected hash: $SHA" >&2; exit 1; }
echo "sha256 = $SHA"

/usr/bin/sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$FORMULA"
/usr/bin/sed -i '' -E "s|/v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz|/v${VERSION}.tar.gz|" "$FORMULA"
echo "Updated $FORMULA"
