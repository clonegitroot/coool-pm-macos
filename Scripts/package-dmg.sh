#!/bin/zsh
set -eu
cd "${0:A:h}/.."
if [[ $# -ne 2 ]]; then
    print -u2 'Usage: Scripts/package-dmg.sh APP_PATH OUTPUT_DMG'
    print -u2 'Set COOOL_DMG_PYTHON to a Python environment with Packaging/requirements.txt installed.'
    exit 1
fi
app="${1:A}"
output="${2:A}"
python="${COOOL_DMG_PYTHON:-python3}"
[[ -f "$app/Contents/MacOS/CooolPM" ]] || { print -u2 'App executable missing.'; exit 1; }
[[ "$app:t" == 'Coool PM.app' ]] || { print -u2 'Expected an app named Coool PM.app.'; exit 1; }
codesign --verify --deep --strict "$app"
mkdir -p "${output:h}"
art="$(mktemp -d /tmp/coool-dmg-art.XXXXXX)"
trap 'rm -rf "$art"' EXIT
# Package a copy with portable permissions. Finder can preserve restrictive
# source modes and ACLs when copying out of a disk image.
staged="$art/Coool PM.app"
ditto --noacl "$app" "$staged"
chmod -R a+rX,go-w "$staged"
chmod a+rx "$staged"/Contents/MacOS/CooolPM*
codesign --verify --deep --strict "$staged"
"$python" Packaging/background.py "$art"
"$python" -m dmgbuild -s Packaging/dmg-settings.py -D "app=$staged" -D "background=$art/background.png" \
    'Coool PM' "$output"
hdiutil verify "$output"
