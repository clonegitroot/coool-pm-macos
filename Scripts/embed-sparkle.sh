#!/bin/zsh
set -eu
if [[ $# -ne 2 ]]; then
    print -u2 'Usage: embed-sparkle.sh SPARKLE_DISTRIBUTION APP_BUNDLE'
    exit 1
fi
framework="$1/Sparkle.framework"
contents="$2/Contents"
[[ "$(plutil -extract CFBundleShortVersionString raw "$framework/Resources/Info.plist")" == 2.10.1 ]]
codesign --verify --deep --strict "$framework"
mkdir -p "$contents/Frameworks"
ditto "$framework" "$contents/Frameworks/Sparkle.framework"
cp "$1/LICENSE" "$contents/Resources/Sparkle-LICENSE"
plist="$contents/Info.plist"
plutil -insert SUFeedURL -string 'https://clonegitroot.github.io/coool-pm-macos/appcast.xml' "$plist"
plutil -insert SUPublicEDKey -string 'TOMz3zBR43dnxrcasUgLgxO0kOVIqvkdAnI+gZnWQZ4=' "$plist"
plutil -insert SURequireSignedFeed -bool YES "$plist"
plutil -insert SUSignedFeedFailureExpirationInterval -integer 0 "$plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
plutil -insert SUEnableSystemProfiling -bool NO "$plist"
plutil -insert SUEnableAutomaticChecks -bool YES "$plist"
plutil -insert SUAllowsAutomaticUpdates -bool NO "$plist"
