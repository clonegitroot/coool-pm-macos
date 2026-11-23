# Building Coool PM yourself

The source repository contains the native macOS app, native MCP tool, local-model helper and editable Icon Composer asset. Build on a Mac with full Xcode and its command-line tools selected.

1. Clone a checkout you can access and open a terminal in that repository.
2. On Apple Silicon, install Xcode's Metal compiler component if missing: `xcodebuild -downloadComponent MetalToolchain`.
3. Run the build:

```sh
./build.sh
codesign --verify --deep --strict "Coool PM.app"
```

The first build retrieves pinned SQLCipher and Swift package dependencies, verifies the SQLCipher download and compiles the optional Apple Silicon AI helper. Model weights are a separate opt-in download inside the app. Intel builds omit the helper. The icon is compiled from **Assets/AppIcon.icon**.

Open the resulting **Coool PM.app** when ready to set up a library, or try the fictional demo. A build using the same identifier as an existing installation can open its existing library, so retain the recovery key and a backup before changing installations.

Local builds use ad-hoc signing. Signed distribution, notarization and provisioned CloudKit sync need additional Apple configuration. You can build a local app without publishing it or enabling CloudKit.

The GitHub [development guide](https://github.com/clonegitroot/coool-pm/blob/main/docs/DEVELOPMENT.md) includes checks and provisioning details. The [Claude/Codex build prompt](https://github.com/clonegitroot/coool-pm/blob/main/docs/BUILD_WITH_AI.md) helps an AI coding assistant build the existing checkout without using real client records. Opening these links uses your browser; this article is available offline.
