#!/bin/zsh
set -eu
cd "${0:A:h}/.."

if [[ $# -ne 1 ]]; then
    print -u2 'Usage: Scripts/build-local-ai.sh OUTPUT_DIRECTORY'
    exit 1
fi
output="$1"
mkdir -p "$output/Licenses"
if [[ "$(uname -m)" != "arm64" ]]; then
    print -u2 'Local AI is available on Apple Silicon. Building the app without the inference helper.'
    exit 0
fi
if ! xcrun metal --version >/dev/null 2>&1; then
    print -u2 'Install the Apple Metal compiler with: xcodebuild -downloadComponent MetalToolchain'
    exit 1
fi
swift build --package-path LocalAI -c release --force-resolved-versions --product CooolPM-AI -Xswiftc -parse-as-library
products="$(swift build --package-path LocalAI -c release --show-bin-path)"
mkdir -p "$output"
cp "$products/CooolPM-AI" "$output/CooolPM-AI"
for resource in "$products"/*.bundle(N); do
    ditto "$resource" "$output/${resource:t}"
done
mkdir -p "$output/Licenses"
for package in mlx-swift mlx-swift-lm swift-transformers swift-jinja swift-numerics swift-collections swift-crypto swift-asn1 yyjson; do
    source="LocalAI/.build/checkouts/$package"
    for license in "$source"/LICENSE*(N); do
        if [[ -f "$license" ]]; then cp -f "$license" "$output/Licenses/$package-${license:t}.txt"; fi
    done
done
