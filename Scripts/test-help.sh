#!/bin/zsh
set -eu
cd "${0:A:h}/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
Scripts/update-help-docs.py --check
swiftc -module-cache-path "$scratch/modules" Sources/HelpLibrary.swift Tests/Help/main.swift -o "$scratch/check"
"$scratch/check" "$PWD/Resources/Help"
