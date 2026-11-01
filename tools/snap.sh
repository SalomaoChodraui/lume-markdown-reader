#!/bin/zsh
# Snapshots of every surface in light and dark, on fresh test settings.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=reader,settings tools/snap.sh
set -u
app=~/Applications/Lume.app/Contents/MacOS/Lume
shots=/tmp/Lume-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.lume.markdown-reader.savedState
rm -rf $shots
APP_STORE=/tmp/Lume-test APP_SNAPSHOT=$shots $app
