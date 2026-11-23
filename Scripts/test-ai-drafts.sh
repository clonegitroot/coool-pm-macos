#!/bin/zsh
set -eu
cd "${0:A:h}/.."
Scripts/build-sqlcipher.sh
cipher=".build/sqlcipher-4.10.0-$(uname -m)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
models=(Sources/{AIDraft,AppLanguage,BillingSchedule,BusinessProfile,ClientDocument,DayRateLibrary,EncryptedSQLite,Estimate,ExportNaming,InlineText,InvoiceLedger,LetterLayout,LibraryVault,ProjectControl,ProjectDatabase,PricingCatalog,ProjectFolder,XRechnung}.swift)
swiftc -I "$cipher/include" "$cipher/sqlcipher.o" -framework Security -module-cache-path "$scratch/modules" "${models[@]}" Tests/AIDrafts/main.swift -o "$scratch/test"
"$scratch/test"
