#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# Optional network regression: downloads about 1% of the small model, then cancels.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -parse-as-library -module-cache-path "$scratch/modules" Sources/{AppLanguage,LocalAIModel,LocalAIModelStore}.swift Tests/LocalAIStore/Progress.swift -o "$scratch/check"
"$scratch/check"
