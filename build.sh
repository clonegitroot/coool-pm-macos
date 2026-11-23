#!/bin/zsh
set -eu
cd "${0:A:h}"

bundle="Coool PM.app/Contents"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
Scripts/build-sqlcipher.sh
Scripts/build-local-ai.sh "$build_dir/local-ai"
cipher=".build/sqlcipher-4.10.0-$(uname -m)"
macos_min="${COOOL_MACOS_MIN:-14.0}"
target="$(uname -m)-apple-macosx${macos_min}"
cipher_flags=(-target "$target" -I "$cipher/include" "$cipher/sqlcipher.o" -framework Security)
models=(
    Sources/{LibraryVault,EncryptedSQLite,AppLanguage,BillingSchedule,BusinessProfile,BusinessReporting,ClientDocument,DayRateLibrary,Estimate,ExportNaming,InlineText,InvoiceLedger,LetterLayout,ProjectControl,ProjectDatabase,ProjectFolder,XRechnung}.swift
)
sparkle_flags=()
if [[ -n "${COOOL_SPARKLE_DIR:-}" ]]; then
    sparkle_flags=(-F "$COOOL_SPARKLE_DIR" -framework Sparkle)
fi
swiftc "${cipher_flags[@]}" "${sparkle_flags[@]}" -parse-as-library -O Sources/*.swift -o "$build_dir/CooolPM"
swiftc "${cipher_flags[@]}" -O "${models[@]}" MCP/main.swift -o "$build_dir/CooolPM-MCP"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp "$build_dir/CooolPM" "$build_dir/CooolPM-MCP" "$bundle/MacOS/"
if [[ -f "$build_dir/local-ai/CooolPM-AI" ]]; then
    cp "$build_dir/local-ai/CooolPM-AI" "$bundle/MacOS/"
fi
for resource in "$build_dir/local-ai"/*.bundle(N); do
    ditto "$resource" "$bundle/Resources/${resource:t}"
done
if [[ -f "$build_dir/local-ai/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" ]]; then
    cp "$build_dir/local-ai/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" "$bundle/Resources/mlx.metallib"
    rm -f "$bundle/MacOS/mlx.metallib"
    ln -s ../Resources/mlx.metallib "$bundle/MacOS/mlx.metallib"
fi
ditto "$build_dir/local-ai/Licenses" "$bundle/Resources/LocalAI-Licenses"
cp Info.plist "$bundle/Info.plist"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "$macos_min" "$bundle/Info.plist"
cp -R Resources/. "$bundle/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$bundle/Resources/"
if [[ -n "${COOOL_SPARKLE_DIR:-}" ]]; then
    Scripts/embed-sparkle.sh "$COOOL_SPARKLE_DIR" "Coool PM.app"
elif [[ -d "$bundle/Frameworks/Sparkle.framework" ]]; then
    rm -rf "$bundle/Frameworks/Sparkle.framework"
    rm -f "$bundle/Resources/Sparkle-LICENSE"
fi
Scripts/build-icon.sh "$build_dir/icon"
cp "$build_dir/icon/Assets.car" "$build_dir/icon/AppIcon.icns" "$bundle/Resources/"

# Bundle back-deployment Swift libraries so testers do not need Xcode.
mkdir -p "$bundle/Frameworks"
for executable in "$bundle/MacOS/CooolPM" "$bundle/MacOS/CooolPM-MCP" "$bundle/MacOS/CooolPM-AI"; do
    if [[ -f "$executable" ]]; then
        install_name_tool -add_rpath @executable_path/../Frameworks "$executable"
    fi
done
xcrun swift-stdlib-tool --copy --scan-folder "$bundle/MacOS" --platform macosx \
    --destination "$bundle/Frameworks" --sign "${COOOL_SIGNING_IDENTITY:--}"
# swift-stdlib-tool keeps an unsigned original while re-signing.
rm -f "$bundle/Frameworks/"*.original(N)

if [[ -n "${COOOL_CLOUDKIT_CONTAINER:-}" ]]; then
    : "${COOOL_SIGNING_IDENTITY:?Set a macOS signing identity for CloudKit}"
    : "${COOOL_PROVISIONING_PROFILE:?Set the matching macOS provisioning profile}"
    : "${COOOL_ENTITLEMENTS:?Set the signed target entitlements plist}"
    /usr/bin/plutil -replace CooolCloudKitContainer -string "$COOOL_CLOUDKIT_CONTAINER" "$bundle/Info.plist" 2>/dev/null ||
        /usr/bin/plutil -insert CooolCloudKitContainer -string "$COOOL_CLOUDKIT_CONTAINER" "$bundle/Info.plist"
    cp "$COOOL_PROVISIONING_PROFILE" "$bundle/embedded.provisionprofile"
    if [[ -f "$bundle/MacOS/CooolPM-AI" ]]; then codesign --force --options runtime --sign "$COOOL_SIGNING_IDENTITY" "$bundle/MacOS/CooolPM-AI"; fi
    codesign --force --options runtime --sign "$COOOL_SIGNING_IDENTITY" "$bundle/MacOS/CooolPM-MCP"
    codesign --force --options runtime --entitlements "$COOOL_ENTITLEMENTS" --sign "$COOOL_SIGNING_IDENTITY" "Coool PM.app"
else
    if [[ -f "$bundle/embedded.provisionprofile" ]]; then unlink "$bundle/embedded.provisionprofile"; fi
    if [[ -f "$bundle/MacOS/CooolPM-AI" ]]; then codesign --force --sign - "$bundle/MacOS/CooolPM-AI"; fi
    codesign --force --sign - "$bundle/MacOS/CooolPM-MCP"
    codesign --force --sign - "Coool PM.app"
fi
