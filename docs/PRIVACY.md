# Privacy, backups and recovery

## What Coool PM stores

| Storage | Contents and protection |
| --- | --- |
| `~/Library/Application Support/Coool PM/Projects.sqlite` | SQLCipher encrypts database pages, including client and freelancer details, projects, calculations, invoice history, payment records, numbering reservations, and copies of attached documents. SQLite temporary tables use memory. |
| App preferences | The app encrypts the business identity, addresses, tax and bank details, branding and terms, rate schedules, custom pricing, goals and configured file paths. Ordinary interface preferences and operational metadata such as backup timestamps and synchronization state can be readable. |
| macOS Keychain | A device-local Keychain entry holds the library secret. The app derives separate keys for database encryption, backups and protected preferences. |
| Document files | An import copies a document into the library. Its source file stays at its original location. Installed DOCX templates, exported documents, CSV reports and vCards use their normal formats in the filesystem. |
| Document processing | Quick Look, template processing in Pages, sample Word documents, and local XRechnung validation can use ordinary temporary files. Some helpers remove their files when finished. Opened samples, interrupted operations and caches managed by other apps or macOS can leave copies behind. |

An unlocked app uses decrypted records in memory to display and edit them. The library encryption applies to Coool PM’s own storage. Earlier plaintext backups, prior disk snapshots, exported files, printed copies and files received by other people have separate lifetimes. An upgrade cannot retroactively encrypt those copies.

## Recovery key and launch lock

On first setup, choose **Create key**, then save the text file, print the key, or use **Copy recovery key** to store it somewhere safe. The recovery key file is readable text. Store it separately from your backups. Anyone with the key and an archive can decrypt its contents. Coool PM has no recovery service that can replace a lost key.

For an existing plaintext library, use the updated build for the same installation, with older copies of the app closed. Setup converts the existing database into an encrypted copy, checks the converted file and replaces the local database. Retain your recovery key and a verified backup across the upgrade.

In **Settings → Library**, turn on **Require Touch ID or Mac password on launch** to have macOS authenticate you before the library and business settings open. The Mac login password or Touch ID unlocks this installation. The portable recovery key decrypts an archive on another Mac. Resetting always requires macOS authentication, including when launch authentication is off.

## What a backup includes

A new `.cooolbackup` file is an authenticated, encrypted archive. It contains the following workspace data.

- All active and archived projects, client folders, client and freelancer directories, contacts, attached contracts and NDAs.
- Calculations, phase details, proposal approvals, change orders, planned and booked costs, time records, billing schedules, invoices, corrections, payments, project attachments and document history.
- Client, project and invoice number reservations, including reservations retained after deletion.
- Your business profile, logo, document styling, terms, payment and numbering defaults, day-rate schedules, pricing categories and monthly goals.
- The installed German and English proposal and invoice Word templates, language and appearance preferences, sidebar visibility settings and onboarding completion.

The archive carries attachment **copies held by the app**. Files and fonts installed elsewhere on disk, separately exported copies and external applications such as the validator are outside its scope. Configure trusted Java and validator paths on the destination Mac. The recovery key, launch lock and MCP authorizations, backup destination and sync account association belong to the local Mac. Reconnect local services and choose backup destinations on the receiving Mac.

## Creating and restoring a backup

1. Open **Settings → Library → Manage backups and sync…** or click **Backups** in the main window. **Create Backup Now** (`⌘⌥B` in the library) writes a new dated archive. With no automatic destination, the app uses `~/Library/Application Support/Coool PM/Backups/`.
2. Choose **Create Backup Elsewhere…** for a separate destination, or choose a folder for automatic daily backups while the app is running. Project edits are autosaved locally by default. With autosave disabled, save pending edits before creating a recovery copy. The optional prompt when closing offers to create a separate recovery copy.
3. To recover on a new Mac, open the app and choose **Use existing key** during setup. Then choose **Restore from Backup…**, select the archive and review the replacement confirmation. Restoring into a library with a different key prompts for the archive’s key. Incoming records are stored under the destination library’s key.
4. Restore replaces the current workspace. The app first writes an encrypted recovery copy of the existing workspace to the local Backups folder. It can import supported archives from earlier plaintext versions. Those original files remain in their original format.

**Settings → Library → Reset options…** offers a library-only reset or an app-and-library reset. Both take a recovery backup and clear local records and number history after device authentication. The wider reset also clears business setup, installed templates, preferences and the local encryption key, then returns to library setup. Keep the previous recovery key to open backups made before the reset. Existing backups and the private iCloud copy survive a local reset.

## Optional sharing

**iCloud Drive** copies an encrypted backup when you choose a destination inside iCloud Drive. Restore an archive to use that copy as a workspace. In a build provisioned for **CloudKit**, automatic sync or **Sync now** sends an encrypted archive and a content digest to the private database under your Apple account. Cloud storage also exposes service metadata such as modification time. Use the same recovery key across Macs that share a library. If both sides change, the app asks which version to use.

**AI access** is a local stdio MCP connection, disabled by default under **Settings → Library**. Read tools return UUID-based client/project aliases, statuses and numbered phases. Real names, client/project numbers and custom labels are withheld. Financial access and draft edits each require their switch in Coool PM and the matching MCP startup flag. Turning either switch off revokes that access for subsequent requests in existing sessions. The available tools return structured fields and summaries. The MCP client controls where its results go next. Turn the connection off in Settings to stop subsequent requests.

**Document export** writes the file you select. Pages can open a Word template to produce a PDF, and the locally configured XRechnung validator processes invoice XML. **Save to Contacts…** writes a vCard that you can import into a contacts app. Coool PM does not require a developer-hosted account or analytics service to use the local library.

## Optional local AI

Local AI is off initially. Choosing Download retrieves pinned model files from Hugging Face and its download infrastructure. The provider receives normal network metadata such as IP address and the requested model. File sizes and SHA-256 hashes are checked before installation. Model files contain weights and tokenizer/configuration data.

After download, a bundled native helper runs inference on the Mac. It receives the current project title, day-rate tiers, calculation lines, applicable rebate and entered brief. Internal cost values are included when cost controlling is enabled. The available pricing category names and methods are included. Other projects are included only when explicitly selected in the reference picker, which starts empty. Up to two selected projects contribute short scope/deliverable excerpts and compact calculation summaries (up to three phases and four lines per phase, plus rate tiers and rebate). Contacts, bank/tax fields, documents, terms and unselected projects are excluded. The assistant’s context disclosure identifies the information used.

Briefs, responses and inference caches stay in process memory until discarded or the helper exits. The app saves no chat history and sends no inference requests to a remote service. Applying suggestions stores the resulting text and lines as encrypted project data. Unloading, cancellation and quitting stop the helper. macOS manages virtual memory and diagnostics.

Weights are ordinary files in the local AIModels folder and can be removed in Settings. Backups carry the Local AI enablement preference, selected model and idle policy. Restore requires downloading weights again. External MCP has separate enablement and permissions.

## MCP name privacy

MCP responses use UUID-based project/client aliases and numbered phase/entry labels. Real names, project/client numbers, addresses, contact details and documents are not returned. Financial permissions are separate; permitted amounts and relationships can still be identifying. This protects app responses, not text entered into an external AI or previous conversations. Restart clients after updating. See [ChatGPT setup and limitations](CHATGPT_MCP.md).
