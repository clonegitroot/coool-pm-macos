# Build Coool PM with Claude or Codex

Use this when you want an AI coding assistant to build the existing app on your Mac. Start the assistant in a checkout of this repository, with local terminal and file access. You need access to this repository and a full Xcode installation. This prompt builds the source; it does not recreate the app from screenshots.

Copy the prompt below. Replace bracketed text only if it applies to you.

```text
Build Coool PM from this repository on my Mac.

Goal: produce a working local "Coool PM.app", verify it, and tell me where it is
and how to launch it. Work in the existing checkout. Read repository instructions,
README.md and docs/DEVELOPMENT.md before making changes.

1. Inspect the checkout and current changes, macOS architecture, selected Xcode,
   Swift toolchain and available disk space. Preserve my existing work.
2. Use the existing ./build.sh pipeline. This app is built with swiftc plus its
   pinned dependencies; do not invent an Xcode project or rewrite the app.
   Keep the pinned SQLCipher and MLX dependencies, encryption and bundle identity.
3. If Xcode setup or its Metal compiler component is missing, explain the exact
   prerequisite. The supported Metal install command is:
   xcodebuild -downloadComponent MetalToolchain
   Let me complete any Xcode license, account or system authentication steps.
4. Build with ./build.sh. Its scripts build SQLCipher, the app, the MCP helper,
   the optional Apple Silicon local-AI helper and the Icon Composer resources.
   Model weights are not needed for building. Intel omits local inference.
5. Resolve actual build failures with focused fixes. Do not upgrade dependencies,
   replace encryption, enable cloud sync or change signing just to bypass errors.
6. Verify the result with:
   codesign --verify --deep --strict "Coool PM.app"
   Run the relevant synthetic checks in Scripts/, including the financial, vault,
   directory, AI-draft, AI-store and help checks. Report failures honestly.
   Optional network/model-inference tests are separate; tell me before using
   large model downloads or optional external validators.
7. Do not open, reset, migrate or overwrite an existing real library or Keychain
   entry for testing. Use synthetic records and disposable test locations.
   Do not copy databases, backups, recovery keys, client documents, bank/tax data,
   personal logos or credentials into source, logs, screenshots or commits.
8. Keep MCP, local AI and cloud services opt-in. Do not publish, push changes,
   sign for distribution or notarize unless I request it. Local ad-hoc signing
   and provisioned CloudKit/distribution are different setups.
9. Finish with the app's absolute path, build/check results, any remaining limits,
   and the command to open it. Let me launch it when ready. Explain that a build
   with the same bundle identifier can open an existing installation's library.

[Optional: tell the assistant about a custom checkout path or known toolchain issue.]
```

Use the repository's [development guide](DEVELOPMENT.md) for exact script names and optional services. Check the [privacy and recovery guide](PRIVACY.md) before replacing an existing installation. The app's Help menu and the [English](USER_GUIDE.md) / [German](USER_GUIDE_DE.md) user guides explain first setup and the fictional demo.

## After the first build

Configure your own business information, templates, rates and language in the app. These are library settings; you do not need to commit personal details to customize the app for your freelance business.

For a code change in your own fork, use this smaller follow-up:

```text
In this Coool PM checkout, implement: [describe one specific change].
First inspect the existing implementation and repository guidance. Preserve the
native macOS style, German/English localization, Decimal financial arithmetic,
approval/issued-invoice protections, encryption and backward compatibility.
Use fictional fixtures. Update relevant offline help articles under Resources/Help,
then run Scripts/update-help-docs.py so the repository guides stay aligned.
Build and run checks appropriate to the change. Do not touch a real user library,
commit personal data, or push/publish without my instruction. Report the result
and anything that remains unverified.
```

## Prompts for the assistant inside Coool PM

The build prompt above is for an external coding agent. For the integrated local production assistant, use the [English prompting and usage guide](AI_GUIDE.md) or [German guide](AI_GUIDE_DE.md). They include examples for solo work, crew, reference rates and calculation reviews. The local assistant can suggest a draft; it does not build or modify the app.
