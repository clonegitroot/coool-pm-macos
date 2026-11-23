#!/bin/zsh
set -eu
cd "${0:A:h}/.."
Scripts/build-sqlcipher.sh
cipher=".build/sqlcipher-4.10.0-$(uname -m)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
models=(Sources/{AppLanguage,BillingSchedule,BusinessProfile,BusinessReporting,ClientDocument,DayRateLibrary,EncryptedSQLite,Estimate,ExportNaming,InlineText,InvoiceLedger,LetterLayout,LibraryVault,ProjectControl,ProjectDatabase,ProjectFolder,WordTemplate,XRechnung}.swift)
swiftc -I "$cipher/include" "$cipher/sqlcipher.o" -framework Security -module-cache-path "$scratch/modules" "${models[@]}" Tests/Financials/main.swift -o "$scratch/test"
"$scratch/test"
