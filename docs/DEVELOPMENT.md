# Development

## Build

Install Xcode, select its command-line tools and run `./build.sh` from the repository root. The first build downloads the pinned SQLCipher source, checks its SHA-256 digest, generates the amalgamation and compiles it against Apple CommonCrypto. The architecture-specific object and headers are cached under `.build/`. The installed app can run offline.

The build links the same SQLCipher implementation into the SwiftUI app and its native MCP executable, copies localization resources and the SQLCipher license, then signs the bundle. Run `codesign --verify --deep --strict "Coool PM.app"` to verify the resulting local signature.

## Code map

- Sources/Estimate.swift contains decimal calculations, rate schedules, rebates, and approval snapshots.
- ProjectDatabase.swift handles SQLCipher transactions, identifiers, reservations and Codable aggregates. EncryptedSQLite.swift migrates legacy plaintext libraries. LibraryVault.swift, ProtectedSetting.swift and VaultGate.swift manage encryption, Keychain and launch authentication.
- LibraryView.swift and ProjectLibrarySidebar.swift own navigation and client folders.
- DocumentPanel.swift, ClientDocument.swift, LetterLayout.swift, and WordTemplate.swift produce documents.
- InvoiceLedger.swift tracks issued invoices, corrections, and payments.
- BusinessReporting.swift calculates period totals and CSV output.
- LibraryBackup.swift and CloudLibrarySync.swift manage archives and optional private sync.
- MCP/main.swift implements the local stdio MCP server.

## Synthetic checks

Run the test scripts from the repository root.

```sh
Scripts/test-directories.sh
Scripts/test-financials.sh
Scripts/test-vault.sh
Scripts/test-ai-drafts.sh
Scripts/test-ai-store.sh
Scripts/test-help.sh
```

The suites use synthetic records. Directory checks cover number reservations, financial checks exercise calculations and document outputs, and vault checks cover encryption and recovery. Keep real libraries, documents and recovery keys outside the checkout.

## MCP

Enable the local MCP connection in **Settings → Library**, select the permissions to include in the client configuration and copy it. MCP defaults to off. When launch authentication is enabled, keep the app open and unlocked while using an MCP client. Configure the client to execute the absolute path to Coool PM.app/Contents/MacOS/CooolPM-MCP. The transport uses newline-delimited JSON-RPC on stdin/stdout.

Read tools include list_projects, list_clients, and get_project. Add --allow-financials for project financial details and get_business_overview. Add --allow-write for create_client, create_draft_project, set_project_calculation, and append_project_phases. Replacement requires confirm_replace=true. Approved and archived calculations are protected. A --library argument selects an isolated SQLite library for development.

Pricing tokens include own_progressive, own_fixed, internal_crew, crew, fixed_fee, expense, and owned_equipment. Internal crew receives rebates, external crew and expenses do not. New categories reuse these calculation methods.

## CloudKit provisioning

The standard build uses a local SQLCipher database. For a provisioned build, configure COOOL_CLOUDKIT_CONTAINER, COOOL_SIGNING_IDENTITY, COOOL_PROVISIONING_PROFILE, and COOOL_ENTITLEMENTS. Register an app identifier and private CloudKit container, and configure record type CooolLibrary with digest (String) and archive (Asset). Verify offline edits and conflict resolution on two signed-in Macs before relying on sync. Use one issuing Mac for invoice numbering. Distribution also requires signing and notarization.

## XRechnung

Settings accepts paths for Java, the KoSIT validator JAR, and the validator scenarios.xml. Blank paths use ~/Library/Application Support/Coool PM/XRechnung with java/bin/java, validator.jar, and rules/scenarios.xml. Download the current matching validator bundle from the official KoSIT distribution. The app saves XML only after validation succeeds. Configure seller and buyer identifiers, endpoints, addresses and payment details before export. A purchase order is a separate business reference from the electronic buyer reference.

## Repository hygiene

Commit source, localization, documentation, and synthetic screenshots. Exclude runtime databases, backups, client documents, client-specific logos, signing profiles, credentials, and app bundles. The app identifier in this source distribution is generic. A separately installed personal build may have a different preferences domain.

## Embedded inference helper

The build compiles LocalAI/ with Swift Package Manager, using committed Package.resolved and pinned MLX Swift LM. Apple Silicon builds require Xcode’s Metal compiler component. Install it using xcodebuild -downloadComponent MetalToolchain if needed. Intel builds omit the optional helper.

Scripts/build-local-ai.sh stages CooolPM-AI, Metal/resource bundles and dependency licenses. The app starts the helper in its MacOS folder and exchanges JSON lines over stdin/stdout. No network listener is started. Models load from a verified local directory. Errors omit native diagnostics, stderr is discarded and core dumps are disabled in the helper.

LocalAIController coordinates loading, explicit/idle/pressure unloading, cancellation and switching. Unloading terminates the helper and waits for process exit before reporting released memory. LocalAIModelStore retrieves pinned assets and verifies hashes. AIDraft validates generated JSON and guards application and undo against stale or linked records.

Run Scripts/test-ai-drafts.sh and Scripts/test-ai-store.sh for synthetic validation and download-state checks. Real inference requires Apple Silicon and a supported downloaded model. Hardware recommendations and memory figures are estimates.

Qwen3 sampling uses temperature 0.7 and top-p 0.8 for non-thinking mode. Greedy decoding is avoided because the [model card](https://huggingface.co/Qwen/Qwen3-4B) warns about degradation and repetition. Every result still passes the app’s typed validation and requires review before applying.

`Scripts/test-ai-download-progress.sh` is an optional network regression. It cancels after roughly 1% of the smallest model and requires live progress during the weights transfer, then checks partial-file cleanup.

AI pricing tokens are resolved against a whitelist of built-in methods and configured preset IDs. Generated rates/costs are ignored; preset identity and method survive application. Reference projects are passed explicitly from the library, summarized to bounded scope/calculation fields, and never mutated. Draft tests cover all pricing methods, custom category validation, placeholder rejection, review-mode boundaries, reference opt-in/privacy and deterministic rebates/DB stages.

Reference-rate filling resolves model-selected IDs only against the bounded selected reference summaries, with an exact role/method fallback when prices are unambiguous. Rates/costs are copied from trusted records. Own schedule adoption is a separate reviewed project change with apply/undo coverage; absent prices do not block draft creation.

The editable Icon Composer source is `Assets/AppIcon.icon`. `Scripts/build-icon.sh` compiles it to the macOS asset catalog and ICNS fallback with Xcode actool. `build.sh` installs both outputs and the icon keys in Info.plist. Image text/EXIF metadata is stripped from the repository asset; its pixel data is preserved.

## Offline native help and documentation

`HelpCommands` replaces the standard Help item with a native `openWindow(id: HelpWindow.id)` action and the ⌘? shortcut. The Help scene is separate from the vault gate so setup/recovery instructions work before unlocking. `HelpView` uses a native split view, full-text search, selectable Markdown content and copyable code blocks. Internal `help://topic-id` links navigate only to bundled articles; external HTTP(S) links open the browser when clicked. No library records, network fetch or analytics are used by help.

Author topics under `Resources/Help/en` and `Resources/Help/de`, indexed by `Resources/Help/index.json`. The renderer supports headings, paragraphs, inline emphasis/links, lists, fenced code and tables. Run `Scripts/update-help-docs.py` to export `docs/USER_GUIDE*.md` and `docs/AI_GUIDE*.md`. `Scripts/test-help.sh` checks both languages, search, link routing, Markdown blocks and generated-doc drift. Keep all examples fictional. The packaged app receives these resources through the existing Resources copy step in `build.sh`.

`docs/BUILD_WITH_AI.md` contains the external Claude/Codex build prompt. It is separate from the end-user local-model prompting guide. Test Help from its menu, keyboard shortcut and while the vault is locked; check search, internal links, code blocks and both languages in a disposable app fixture.

The Help reader uses a small NSView attachment hook to bring its native window forward after initial creation. It does not take focus again during search or article updates.

## Tester DMG release

The standard build now targets macOS 14 explicitly (`COOOL_MACOS_MIN` can override the compiler target). Check all app/helper Mach-O minimum versions before packaging and do not infer cross-version runtime coverage from successful compilation. Build release binaries from a clean generic temporary checkout to avoid embedding personal build paths.

Create a Python environment with `Packaging/requirements.txt`, then run `COOOL_DMG_PYTHON=/path/to/venv/bin/python Scripts/package-dmg.sh "/path/to/Coool PM.app" "/path/to/output.dmg"`. The script copies the app into a temporary staging directory, removes access-control entries from the copy, normalizes bundle permissions and verifies its signature. It then draws the 1x/2x background, and uses dmgbuild to write Finder positions plus an Applications shortcut without AppleScript. It verifies the compressed image afterward. `dist/` and DMGs are excluded from Git. Release assets are uploaded separately.

Before publishing: run synthetic checks, verify signatures/resources/privacy, mount the final DMG read-only and inspect its contents/layout, confirm the Applications target, and publish SHA-256 checksums with explicit architecture, minimum OS and unnotarized-beta instructions. See [installation instructions](INSTALL.md). Keep the release prerelease until broader tester validation. No model weights or user workspace data belong in the image.

### MCP regression checks

Run `Scripts/test-mcp.sh` to exercise the JSON-RPC dispatcher and encrypted SQLite operations using a disposable library. Checks cover tool discovery, client/project creation, calculation replacement/append, pricing modes, financial visibility, read-only permissions, validation, and approved/archived calculation protection.

The runner generates a temporary test executable from `MCP/main.swift`, substituting only the preferences/Keychain authentication boundary with a synthetic key and enable flag. Production source is not changed. These checks do **not** replace an end-to-end client test of macOS Keychain access, launch authentication, or the live GUI unlock lease. Never point tests at a personal library.

## Sparkle tester updates

The updater-enabled build uses the official Sparkle 2.10.1 distribution. Verify the archive against the SHA-256 digest published on its release, unpack it, and set `COOOL_SPARKLE_DIR` to that absolute directory before running `./build.sh`. Builds without this option omit the updater. The tester build uses ad-hoc macOS signing and a dedicated EdDSA update key in the release Mac's Keychain. Never copy the private key into the repository or to the web host.

Increase both bundle versions before packaging. Create the manual installer with `Scripts/package-dmg.sh`. Run `Scripts/package-sparkle-update.sh "$COOOL_SPARKLE_DIR" "Coool PM.app" dist/sparkle release-notes.md` to produce the signed ZIP and appcast with embedded release notes. Test a clean installation and an in-app upgrade between builds before publishing. Upload the signed ZIP and manual installer to the matching version tag in [GitHub Releases](https://github.com/clonegitroot/coool-pm-macos/releases). Verify the published archive digest against the local SHA-256. Publish the signed `appcast.xml` last to the `updates-feed` branch, which GitHub Pages serves at `https://clonegitroot.github.io/coool-pm-macos/appcast.xml`. Verify the live XML matches the signed local file. Keep the previous archive available during rollout.

Existing testers install the first Sparkle-enabled DMG manually. After that, checks are available from the app menu and Settings → Updates. Background checks run at launch by default. An explicit Sparkle preference overrides the bundle default. Sparkle system profiling and automatic installation are disabled. Standard HTTPS request metadata may be visible to the hosting provider.
