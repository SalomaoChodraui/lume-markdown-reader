#!/bin/zsh
# Wraps a built Lume binary in an app bundle. Used by build.sh and release.sh.
# Usage: tools/bundle.sh <binary> <path/to/Lume.app> <build number>
set -euo pipefail
repo=${0:A:h:h}
bin=$1
app=$2
build=$3
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/pt-BR.lproj"
cp "$bin" "$app/Contents/MacOS/Lume"
sed -e "s/__BUILD__/$build/" "$repo/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
car="$repo/Resources/Assets.car"
if [[ ! -f "$car" || -n "$(find "$repo/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
  "$repo/tools/make_icon.sh"
fi
cp -X "$car" "$repo/Resources/AppIcon.icns" "$app/Contents/Resources/"
# The reader page, the guide, the licenses. pt-BR.lproj makes the system menu items Portuguese.
cp -R "$repo/Resources/Web" "$repo/Resources/Guide" "$app/Contents/Resources/"
cp "$repo/LICENSE" "$repo/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
xattr -cr "$app"
