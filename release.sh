#!/bin/bash
# Cuts a release: ./release.sh 1.2.0
# - universal build, signed (Developer ID if $DEVELOPER_ID is set, else ad-hoc),
#   notarized (if $NOTARY_PROFILE is set — see `xcrun notarytool store-credentials`),
#   packaged as DMG + zip, published to GitHub Releases with notes from CHANGELOG.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

VERSION="${1:?usage: ./release.sh <version, e.g. 1.2.0>}"
APP="PhotoFilter.app"
DMG="PhotoFilter-$VERSION.dmg"
ZIP="PhotoFilter-$VERSION.zip"

echo "==> Preflight…"
[ -z "$(git status --porcelain)" ] || { echo "FAIL: working tree not clean" >&2; exit 1; }
bash Scripts/check-l10n.sh
swift build -c release 2>&1 | tee /tmp/pf-build.log > /dev/null
! grep -q "warning:" /tmp/pf-build.log || { echo "FAIL: warnings present" >&2; exit 1; }

echo "==> Building $VERSION (universal)…"
VERSION="$VERSION" bash build-app.sh --universal

echo "==> Signing…"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --options runtime --deep --sign "$DEVELOPER_ID" "$APP"
else
  echo "WARNING: \$DEVELOPER_ID not set — ad-hoc signing. Gatekeeper will block"
  echo "         downloads until users right-click→Open. Set DEVELOPER_ID to your"
  echo "         'Developer ID Application: …' identity once you have one."
  codesign --force --sign - "$APP"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Notarizing…"
  ditto -c -k --keepParent "$APP" "/tmp/$ZIP"
  xcrun notarytool submit "/tmp/$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
else
  echo "==> Skipping notarization (\$NOTARY_PROFILE not set)."
fi

echo "==> Packaging…"
rm -rf /tmp/pf-dmg "$DMG" "$ZIP"
mkdir -p /tmp/pf-dmg
cp -R "$APP" /tmp/pf-dmg/
ln -s /Applications /tmp/pf-dmg/Applications
hdiutil create -volname "PhotoFilter" -srcfolder /tmp/pf-dmg -format UDZO -quiet "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
rm -rf /tmp/pf-dmg

echo "==> Release notes from CHANGELOG…"
awk "/^## \[$VERSION\]/{flag=1; next} /^## \[/{flag=0} flag" CHANGELOG.md > /tmp/pf-notes.md
[ -s /tmp/pf-notes.md ] || { echo "FAIL: no CHANGELOG section for $VERSION" >&2; exit 1; }

# NOTE: keep a space (or braces) between $VARs and any non-ASCII char — macOS bash 3.2
# swallows multibyte chars into the variable name and dies under `set -u`.
echo "==> Publishing v${VERSION} ..."
git tag -f "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" "$ZIP" --title "PhotoFilter $VERSION" --notes-file /tmp/pf-notes.md

echo "==> Done: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/v$VERSION"
