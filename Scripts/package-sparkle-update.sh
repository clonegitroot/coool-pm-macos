#!/bin/zsh
set -eu
if [[ $# -ne 4 ]]; then
    print -u2 'Usage: package-sparkle-update.sh SPARKLE_DISTRIBUTION APP_BUNDLE OUTPUT_DIRECTORY RELEASE_NOTES.md'
    exit 1
fi
sparkle="${1:A}"
app="${2:A}"
output="${3:A}"
notes="${4:A}"
[[ -s "$notes" && "$notes" == *.md ]]
base_url='https://davidsattler.de/vibes/updates/coool-pm/'
plist="$app/Contents/Info.plist"
account='coool-pm-beta'

codesign --verify --deep --strict "$app"
[[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == app.cooolpm.desktop ]]
[[ "$(plutil -extract SUFeedURL raw "$plist")" == "${base_url}appcast.xml" ]]
[[ "$(plutil -extract SUPublicEDKey raw "$plist")" == "$("$sparkle/bin/generate_keys" --account "$account" -p)" ]]
[[ "$(plutil -extract SURequireSignedFeed raw "$plist")" == true ]]
[[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$plist")" == true ]]
[[ "$(plutil -extract SUSignedFeedFailureExpirationInterval raw "$plist")" == 0 ]]
version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]
archive="Coool-PM-${version}-arm64.zip"
mkdir -p "$output"
[[ ! -e "$output/$archive" ]]
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp "$notes" "$stage/${archive%.zip}.md"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
"$sparkle/bin/generate_appcast" --account "$account" --maximum-deltas 0 --embed-release-notes --download-url-prefix "$base_url" "$stage"
"$sparkle/bin/sign_update" --account "$account" --verify "$stage/appcast.xml"
python3 - "$stage/appcast.xml" <<'PYVERIFY'
import sys
from xml.etree import ElementTree

item = ElementTree.parse(sys.argv[1]).find("./channel/item")
if item is None or not (item.findtext("description") or "").strip():
    sys.exit("Sparkle appcast is missing embedded release notes.")
PYVERIFY
mv "$stage/$archive" "$output/$archive"
mv "$stage/appcast.xml" "$output/appcast.xml"
