#!/bin/zsh
# Builds dist/Lume-<version>.dmg: universal (Apple Silicon + Intel), signed with
# Developer ID and the hardened runtime, notarized, and stapled.
#
#   SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" tools/release.sh
#
# Notarization uses NOTARY_PROFILE (made once with `xcrun notarytool
# store-credentials`) or APPLE_ID, APPLE_PASSWORD (app-specific), and APPLE_TEAM_ID.
# --no-notarize builds and signs only: a local check of the bundle and the DMG.
set -euo pipefail
repo=${0:A:h:h}
name=Lume
version=$(plutil -extract CFBundleShortVersionString raw "$repo/Info.plist.in")
build=$(git -C "$repo" rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)
scratch="$HOME/Library/Developer/$name/release"
dist="$repo/dist"
identity=${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}
notarize=1
[[ " $* " == *" --no-notarize "* ]] && notarize=0

submit() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$1" --apple-id "${APPLE_ID:?}" --password "${APPLE_PASSWORD:?}" \
      --team-id "${APPLE_TEAM_ID:?}" --wait
  fi
}

echo "==> Lume $version ($build)"
swift build -c release --arch arm64 --arch x86_64 --package-path "$repo" --scratch-path "$scratch" 2>&1 \
  | grep -E "error|warning:|Compiling|Build complete" | grep -v "^\[" || true
bin="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$repo" --scratch-path "$scratch" --show-bin-path 2>/dev/null | tail -1)/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
for arch in arm64 x86_64; do
  lipo "$bin" -verify_arch $arch || { echo "the binary has no $arch slice"; exit 1; }
done
vtool -show-build "$bin" | grep -q "minos 14.0" || { echo "the binary does not target macOS 14"; exit 1; }

rm -rf "$dist"
mkdir -p "$dist"
app="$dist/$name.app"
"$repo/tools/bundle.sh" "$bin" "$app" "$build"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

if (( notarize )); then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$app" "$dist/$name.zip"
  submit "$dist/$name.zip"
  xcrun stapler staple "$app"
  rm "$dist/$name.zip"
fi

echo "==> Making the DMG"
dmg="$dist/$name-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Aplicativos"
hdiutil create -volname "$name $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
codesign --force --timestamp --sign "$identity" "$dmg"

if (( notarize )); then
  echo "==> Notarizing the DMG"
  submit "$dmg"
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
  spctl --assess --type execute --verbose=2 "$app"
fi

(cd "$dist" && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
echo "==> $dmg"
