# Build or install Coool PM

The public source release includes [local build instructions](DEVELOPMENT.md). The DMG steps below apply to prebuilt tester releases when available.

## Requirements

- An **Apple Silicon Mac** (M1 or later).
- **macOS 14 Sonoma or later**. This is the declared minimum target; this first beta was built and smoke-tested on macOS 27.3. Older supported versions still need tester verification.
- Xcode is **not** needed to install the DMG. Intel Macs can use the source-build instructions; this download is arm64 only.

## Install

1. Download the DMG from the tester release where it was provided.
2. Open the DMG and drag **Coool PM** onto the **Applications** folder shortcut.
3. Eject the disk image and open Coool PM from Applications.
4. This tester build is ad-hoc signed and **not notarized by Apple**. If macOS blocks it, first attempt to open the app, then go to **System Settings → Privacy & Security → Open Anyway** and confirm for this app. Do this only for the build you intentionally obtained from this repository. Follow [Apple's instructions](https://support.apple.com/en-us/102445). You do not need to disable Gatekeeper globally or run quarantine-removal commands.
5. Choose **Explore demo library**, or save your recovery key and configure your own workspace. Help is available under **Help → Coool PM Help** (`⌘?`).

The DMG contains the app and a shortcut to `/Applications`, with a custom Finder background. It does not contain user libraries, recovery keys, business settings or AI model weights. Optional models are downloaded inside the app.

## If Finder reports a permissions or ownership error

Copy the app out of the mounted DMG before launching it. If you lack permission to write to **Applications**, copy it to a folder you own, such as **Applications** inside your home folder, and open that copy. If it still fails, report the exact Finder message, whether the failure occurred while copying or opening, and your macOS version. Keep the original encrypted library and recovery key.

## Updating an existing installation

Quit all running copies first. Keep the recovery key and a current encrypted backup before replacing an existing installation. The distributed app uses the generic identifier `app.cooolpm.desktop`; a separately customized build may use a different preferences/Keychain domain while still referring to the same library folder. Do not reset the app to work around a key mismatch. Use the supported recovery/restore flow described in the [privacy guide](PRIVACY.md).

This build uses the local library and encrypted file backups. iCloud Drive can store backups; provisioned private CloudKit sync and notarized distribution require separate signing configuration.

## Check the download

Download `SHA256SUMS.txt` alongside the DMG. In the folder containing both, run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Report bugs through repository Issues with reproduction steps and fictional examples. Never attach real client records or a recovery key.
