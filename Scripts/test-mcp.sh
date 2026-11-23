#!/bin/zsh
set -eu
cd "${0:A:h}/.."
Scripts/build-sqlcipher.sh
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
# Test protocol/operations with synthetic authentication only. Never read the user's Keychain/preferences.
python3 - "$scratch/main.swift" <<'PY'
import pathlib,sys
s=pathlib.Path('MCP/main.swift').read_text()
start=s.index('        let domain = LibraryKey.applicationID as CFString')
end=s.index('        if method == "initialize"',start)
s=s[:start]+'''        guard testEnabled else { return error(-32001, "Disabled test connection", id: id) }
        VaultSession.shared.unlock(testKey)
'''+s[end:]
s=s.replace('guard let key = try LibraryKey.saved() else { throw VaultError.missingKey }','let key = testKey')
s=s[:s.index('// MCP stdio sends')]
s+='\n'+pathlib.Path('Tests/MCP/Checks.swift').read_text()
pathlib.Path(sys.argv[1]).write_text(s)
PY
cipher=".build/sqlcipher-4.10.0-$(uname -m)"
models=(Sources/{LibraryVault,EncryptedSQLite,AppLanguage,BillingSchedule,BusinessProfile,BusinessReporting,ClientDocument,DayRateLibrary,Estimate,ExportNaming,InlineText,InvoiceLedger,LetterLayout,ProjectControl,ProjectDatabase,ProjectFolder,XRechnung}.swift)
swiftc -I "$cipher/include" "$cipher/sqlcipher.o" -framework Security -module-cache-path "$scratch/modules" "${models[@]}" "$scratch/main.swift" -o "$scratch/check"
"$scratch/check" "$scratch"
