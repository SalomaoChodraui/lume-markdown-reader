#!/bin/zsh
# Runs the in-app self-test on a folder in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.lume.markdown-reader.savedState
APP_STORE=/tmp/Lume-self ~/Applications/Lume.app/Contents/MacOS/Lume --selftest
