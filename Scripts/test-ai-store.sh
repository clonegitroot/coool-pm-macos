#!/bin/zsh
set -eu
cd "${0:A:h}/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -parse-as-library -module-cache-path "$scratch/modules" Sources/{AppLanguage,LocalAIModel,LocalAIModelStore}.swift Tests/LocalAIStore/main.swift -o "$scratch/check"
"$scratch/check"
