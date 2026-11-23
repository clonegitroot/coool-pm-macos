#!/bin/zsh
set -eu
cd "${0:A:h}/.."
if [[ $# -ne 1 ]]; then
    print -u2 'Usage: Scripts/build-icon.sh OUTPUT_DIRECTORY'
    exit 1
fi
mkdir -p "$1"
xcrun actool --compile "$1" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$1/icon-info.plist" \
    --target-device mac Assets/AppIcon.icon
