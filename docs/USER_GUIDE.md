# User guide

This guide and the native offline help use the same source articles. Open **Help → Coool PM Help** or **⌘?** inside the app.

- [Getting started](#getting-started)
- [Clients, freelancers and projects](#clients-freelancers-and-projects)
- [Calculations, day rates and rebates](#calculations-day-rates-and-rebates)
- [Proposals, templates and change orders](#proposals-templates-and-change-orders)
- [Invoices and payments](#invoices-and-payments)
- [Costs, DB1, DB2 and forecasts](#costs-db1-db2-and-forecasts)
- [Business reports and monthly goals](#business-reports-and-monthly-goals)
- [Local AI and reference projects](#local-ai-and-reference-projects)
- [Writing useful AI briefs](#writing-useful-ai-briefs)
- [Settings and personalization](#settings-and-personalization)
- [Backups, recovery and synchronization](#backups-recovery-and-synchronization)
- [Privacy, encryption and recovery keys](#privacy-encryption-and-recovery-keys)
- [XRechnung](#xrechnung)
- [Connecting external AI through MCP](#connecting-external-ai-through-mcp)
- [Building Coool PM yourself](#building-coool-pm-yourself)
- [Troubleshooting](#troubleshooting)

## Getting started

Use **File** to create a project, client, freelancer or folder and to manage backups. Use **View** to open Projects, Business overview, Clients or Freelancers (⌘1–⌘4), or to change which projects and clients appear in the sidebar. Search the macOS **Help** menu for a command by name.

Open **Explore demo library** to follow a guided tour of a fictional project, from estimating through costs, a proposal, and billing. Choose **Skip tour** at any step to explore freely. You can reopen the demo or start the tour from **Settings → General**. Demo edits disappear when you close it. To set up a real library, save, print, or copy your recovery key to a safe place, then confirm you have it and continue. For an existing backup, follow the [Privacy and recovery](#privacy-encryption-and-recovery-keys).

Setup lets you choose the interface and document languages, business details, client numbering, default payment deadline and day rates. Return to it from **Settings → General → Open setup…**. In Settings you can also configure tax and bank details, logo, fonts, footer columns, project blocks and rich-text terms. Resize the Settings window to give the preview more space. In a text field, press `⌘Return` to insert a line break in a multiline value such as an address.

### Usage profiles and features

Onboarding offers Solo creative, Creative producer and Project manager profiles. Solo creative shows a smaller interface and income, expenses and profit summaries. Creative producer adds teams and cost controlling. Project manager also enables detailed reports and starts with personal earnings goals hidden.

Open **Settings → Features** to preview and apply another profile or adjust team planning, cost controlling, advanced billing, detailed reporting, integrations and monthly goals individually. Existing installations retain their current features until you make a selection. Choosing a profile leaves MCP access off until you explicitly enable the connection.

Each project has **Features for this project** at the bottom of the window. Select Default to inherit global preferences, or explicitly turn team planning, controlling or advanced billing on or off for that project. Hidden records remain stored and contribute to financial totals. Existing billing schedules remain accessible. Profiles and project overrides are included in encrypted backups.

### Finding help

Open **Help → Coool PM Help** or press **⌘?**. Search for a feature, select a topic in the sidebar, or follow links between topics. Help works offline and stays available during setup or while the library is locked. The app language also selects the help language.

[Continue with clients and projects](#clients-freelancers-and-projects).

## Clients, freelancers and projects

Use **File → Duplicate project** (⌘D) or the project’s context menu to reuse its calculation. The copy starts as a new inquiry. It carries over calculation items, rates and phase text. Assign the new client, dates and project number. The original client, files, proposals, invoices and booked activity stay with the original project.

1. In **Contacts hub → Clients**, add a company and its contacts. Choose a primary contact and enter the contract, NDA, and any client-specific payment or rebate terms. **Save to Contacts…** exports a vCard for Apple Contacts and other contacts apps.
2. Enter the client’s project acronym. For example, an acronym of `NL` produces project numbers such as `NL-001`. Without an acronym, the client number supplies the prefix. Coool PM assigns the project number when you export your first proposal or import a sent proposal. If the project still has no client at that point, the prefix is `PRJ-`. Use **Assign project number** in Project Overview to reserve it earlier. Once assigned, the number stays with the project.
3. In the project overview, assign the agency, end client and invoice recipient, and choose the contact for the proposal or invoice. Add planned start and end dates and a purchase order reference if needed. The PO appears on invoices alongside the invoice number.
4. In **Contacts hub → Freelancers**, keep each person’s contact details, role, agreed day rate and NDA. Use the person’s menu to export a contact card or archive their record. The Mail, Call and Website shortcuts use the saved contact details.

New client numbers default to `KD` followed by four random digits. In setup or **Settings → Business → Client defaults**, change the prefix and width or choose consecutive allocation. Existing numbers keep their values. Deleting a client or project reserves its number within the library.

Projects are grouped by client in the sidebar. Clients without active projects are hidden by default. Enable **Show clients without active projects** in Library actions to display them. Create folders from **Library actions** or the client context menu. Move a project through its context menu. A folder belongs to one client. Reassigning a project to another client clears incompatible folder membership. Select a folder to open its financial report and CSV export.

Project stages cover inquiry, proposal, accepted, in progress, invoiced, and closed. Labels follow the interface language. Archive records to hide them from everyday selection while preserving their history. Use **Show archived projects** or **Show archived clients** to find and restore them. Contact archive actions are available in the client editor.

Delete actions require confirmation. Deleting a project removes its documents and financial activity from reports while retaining issued invoice number reservations. Deleting a client removes its contacts and folders and detaches related projects. Previously issued document snapshots remain with their projects.

## Calculations, day rates and rebates

Open **Estimate** and generate Pre-Production, Production, Post-Production, and Data-Handling phases, or add your own. Each phase supports multiple people and items, quantities, rates, costs, and relevant day lengths.

| Method | Selling calculation | Cost treatment | Rebate |
| --- | --- | --- | --- |
| Own progressive | Your eligible days advance the configured tiers | Internal | Included |
| Own fixed rate | Quantity × agreed rate | Internal | Included |
| Internal crew | Quantity × agreed rate | Internal | Included |
| External crew | Quantity × agreed rate | External | Excluded |
| Fixed fee | Quantity × fee | Internal | Included |
| Owned equipment | Quantity × rate | Internal | Included |
| Expense | Quantity × rate | External | Excluded |

Fixed-rate producer days can optionally count toward later progressive tiers. External and internal crew keep their agreed selling rates. Set your own rates in setup, **Settings → Day rates**, or the project estimate. A new project without a saved schedule starts with an unconfigured producer rate. Older projects retain their calculation basis. Save named schedules in Settings for reuse. Applying a schedule copies its values to the project.

Set a client default rebate in the client editor. A project rebate overrides it. Leave the project field blank to inherit the client default, or enter zero to waive it. Rebates reduce eligible selling amounts while underlying costs retain their entered values. Changing a client rebate updates unapproved draft projects. Approved proposal values remain frozen.

Under **Settings → Pricing categories**, rename the built-in labels or create a custom category based on an existing method. Its saved calculation method stays fixed. This lets labels match your workflow while rate and margin behavior remains defined.

[Use local AI to prepare a reviewed draft](#local-ai-and-reference-projects).

## Proposals, templates and change orders

Use **Documents** for proposals and supplier invoices. Follow **Open client invoices** to issue, track or import a client invoice in **Billing**. Use **Controlling** to see how booked supplier costs affect the project margin.

Use **Create document…** to choose a proposal, language, document number, editable text, scope, dates, and output format. The checklist identifies missing information and placeholders. Draft exports remain available while details are completed.

Export PDF for sharing or DOCX for editing in Word or Pages. Imported Word templates can be managed in Settings. Template-based PDF rendering requires Pages. Generated documents are retained in project history with dated, versioned names ending in `_v01`, `_v02`, and so on. Export a starter Word template from Settings, edit it in Word or Pages, then save it as DOCX and install it for that document type and language. First-page header, three footer columns, typefaces and terms can also be configured in the built-in layout. Cover letters and terms start on dedicated pages.

In **Documents**, mark proposals sent or clear their sent status. You can also import already-sent proposals. Approving a proposal fixes its base fee and calculation. Later adjustments go through change orders. Imported proposals need their agreed net fee entered during acceptance.

Invoices have their own cover text and payment deadline; they omit proposal phases and the terms section. [Continue with invoices and payments](#invoices-and-payments).

## Invoices and payments

Choose **Create invoice** for a client invoice. Start with the recipient, milestone, service period, document date and VAT. Red checklist items explain what you still need to issue the invoice. Expand **Document text** or **Export and billing options** for additional wording and format choices.

Set payment deadlines and split billing in **Billing → Payment terms…**. Choose percentage or fixed instalments that reconcile to the agreed fee. The client’s default payment deadline comes from **Settings → Business → Client defaults** when the client is created. Override it for the client or project as needed. Invoice titles and cover text describe the partial invoice. The payment terms on an invoice show its deadline. Proposal terms can include the full instalment schedule.

Create an invoice from the planned instalment or remaining balance. The issue action records its number, amounts, recipient, and document. The export checklist explains missing data. Enter a reason for agreed amount adjustments. For expenses flagged **Bill at cost**, select the amounts to add as separate invoice positions. They stay separate from the service instalment. A custom Word invoice template can position the PO and itemization using `{{purchase_order}}` and `{{invoice_positions}}`.

To record a sent invoice, import its file and copy the original invoice number, dates, net amount, VAT rate, and VAT amount. Match it to an instalment where appropriate. An imported file becomes part of financial totals after it is recorded in Billing.

Record dated payments, including partial receipts. **Mark paid** records the outstanding gross amount. If an invoice was issued by mistake and has no send, acceptance, payment or correction activity, use **Undo invoice creation…**. The app retains its audit copy and reserves its number. For an invoice with subsequent activity, issue a linked correction. You can also discard eligible unsent document drafts while keeping the next version number moving forward.

## Costs, DB1, DB2 and forecasts

Import supplier invoices in **Documents**, then book the supplier, reference, net cost, and invoice date. Assign a phase and estimated cost line where relevant. Invoice dates determine the month and year used in business reporting.

For private estimates, open **Controlling → External costs → Add cost…** and enter the planned net amount. Assign a phase or keep the cost project-wide. This estimate stays inside the project. When the actual amount is known, record the booked cost and date. Leave the planned amount blank for an unforeseen expense. For an imported supplier invoice, match it to the planned cost when booking it, so the forecast and actual refer to the same expense. Leave **Bill at cost** off for costs you absorb. Turn it on to make the amount selectable as an invoice position.

The **Controlling** tab compares approved budget, actual costs, and forecast. Enter commitments, match received bills, and mark completed cost lines. Log internal time using the applicable internal rate. Open **Explain forecast differences** to see how each contributing item changes revenue, supplier costs, internal costs, DB1 and DB2 in the selected view.

DB1 deducts direct external costs from the fee basis. DB2 also deducts internal costs. Project forecast metrics use the project’s fee and expected remaining costs. Business-period reports use recorded invoice and transaction dates.

## Business reports and monthly goals

Open **Business overview**, select a year, then choose the full year or a month. Choose **Set monthly goal for year…** to apply the same net invoicing target to all twelve months, replacing any earlier goals for that year. Select a month to refine its goal. Hover over a colored bar segment in the annual chart to see the project and its invoiced amount.

| Metric | Basis |
| --- | --- |
| Net invoiced | Recorded invoices and signed corrections by invoice issue date |
| Cash received | Gross receipts and refunds by payment date |
| Supplier costs | Net supplier invoices and separately booked project expenses by invoice or booking date |
| Recorded time costs | Internal time × recorded rate by work date |
| DB1 | Net invoiced − supplier costs |
| DB2 | DB1 − recorded time costs |

Undated supplier bookings are counted and flagged separately. Archived project activity remains included. Use **Export CSV…** for the selected period or the project-row export for an individual project. Files use UTF-8, semicolon separators, and decimal formatting matching the app language. The summaries provide working papers for bookkeeping and accountant review.

## Local AI and reference projects

Drafts organize work in production order and state client deliverables, assumptions and open questions. Calculation review runs separately from drafting. It uses the app’s computed amounts and shows progress, errors or confirmation when the model returns no additional findings.

Open **Settings → Local AI** and enable the assistant. Model cards show download sizes, estimated memory requirements and limitations. The recommendation depends on your Mac’s unified memory. Available memory, project size and other apps affect performance.

Select a model and choose **Download model…**. Downloads retrieve pinned, integrity-checked files from Hugging Face. After downloading, inference works locally. Weights are stored in the local Application Support/Coool PM/AIModels folder.

In a project, choose **Local AI…**. **Draft from brief** proposes an editable introduction, phases, roles and quantities. Review assumptions, questions and quantities, then select what to apply. Coool PM calculates amounts using its own engine and your saved rates. Review copied reference rates or enter agreed selling rates yourself. Unpriced drafts can be applied for completion later. **Review calculation** adds advisory scope findings alongside exact app checks. Approved projects support review. Applying new drafts requires an editable inquiry/proposal project.

The context disclosure lists the data used. Client contact records, attachments and unselected projects are excluded. Selected reference summaries are explicitly listed. Pasted briefs may include information you supply. Applied drafts can be undone while affected fields are unchanged and have no linked activity.

Starting an action loads the selected model automatically. Settings shows loading, ready, generating, unloading and error states. Cancel tasks, load or unload manually, release after each task, choose an idle timeout or keep loaded while open. Memory pressure releases idle models and may interrupt an active task. Unloading stops the inference process. Downloads remain until removed. Switching models releases the previous model first.

The three options use Qwen3 at 4-bit precision. The lightweight model is intended for short wording and draft assistance. Complex estimates and nuanced scope reviews require careful review, particularly with the small model. Model descriptions provide guidance. Output can be incomplete or incorrect.

Encrypted backups include the selected model ID and idle policy. Weights are downloaded again on a new Mac. AI enablement is a local device preference, independent of external MCP access.

#### Pricing and reference projects in AI drafts

The assistant receives all available calculation methods and renamed/custom categories: own progressive days, own fixed days, internal crew, external supplier crew, fixed fees, expenses and owned equipment. It receives the project’s fixed-day tier-count setting and rebate. Crew never uses the owner’s progressive tiers. Internal crew is rebate eligible and its cost belongs to DB2; external crew and expense costs belong to DB1 and receive no rebate.

Each generated position has an editable role and pricing picker. A role names the service or job; it is independent of how it is priced. Enter agreed fixed rates and unit costs yourself. The app ignores model-supplied prices and calculates totals from reviewed inputs. Switching calculation methods clears rates and costs; switching between categories with the same method keeps them.

Expand **Reference projects (optional)** and choose up to two other projects, including archived projects. Search by title or project number. Nothing is selected initially. The prompt includes only selected historical scope/calculation summaries, limited to the first three phases, four entries per phase and short scope/deliverable excerpts. Contacts, documents and terms are excluded. The current brief takes priority. Historical quantities and rates are examples that need review, not new agreements. Large current projects plus references may exceed a model’s context limit; shorten the brief or remove a reference.

Responses containing the old placeholder sentences are rejected and retried once. Review mode accepts findings/questions without proposing new phases. Small local models can still misclassify positions or estimate effort incorrectly. Always check the selected method, quantities and scope before applying.

#### Reusing reference rates and finishing prices later

Selecting a reference also makes its saved line rates available. The assistant can identify a source position with its reference ID; an exact role/method match is also accepted when unambiguous. Coool PM copies the recorded selling rate, cost and day length directly from that position. Model-authored monetary values remain ignored. Positions with a different method, an unknown source or conflicting matching prices remain unpriced. Cost values are included only with cost controlling enabled.

Choose **Own day-rate schedule** to reuse one selected reference’s progressive tiers, or choose **Keep current project rates**. The first selected reference is the initial schedule choice. The preview lists the copied schedule. Applying it with own progressive positions changes the project-wide schedule, including existing own progressive positions; the confirmation explains this and Undo restores the previous schedule.

A missing price never blocks applying an editable AI draft. The preview warns that its total is incomplete; fill in prices later in the project calculation. Each numeric field has a visible label: days/units, selling rate or unit price, and internal or supplier cost, with EUR and day/unit shown explicitly.

[Briefing checklist and copyable prompting examples](#writing-useful-ai-briefs).

## Writing useful AI briefs

The local assistant prepares a draft or reviews the current calculation. It does not send documents, issue invoices, approve proposals, inspect attached media or search every project automatically. Its context is shown in the disclosure. You choose up to two older projects explicitly.

### Before you generate

1. Enable and download a suitable model in **Settings → Local AI**. Hardware recommendations and memory figures are estimates. The small model works best with short, focused requests.
2. In the project, choose **Local AI…**, then **Draft from brief** or **Review calculation** and the output language.
3. Select references if needed. Choose the own day-rate schedule to copy, or keep the current project's schedule.
4. Describe the new work in plain language. Use actual roles, exact days and explicit pricing methods. Start with a small scope instead of a long client email.

### A useful brief includes

- **Deliverables:** number, duration or format of outputs; versions, subtitles and feedback rounds where known.
- **Work:** what you do yourself and what other people do. State days per role; the model should not convert days to hours.
- **Pricing:** your own progressive or fixed days, internal crew included in your fee, external suppliers, service packages, purchases and owned equipment.
- **Boundaries:** what is included, excluded, supplied by the client or still unknown.
- **References:** what to reuse and what to change. Old quantities, agreements and dates are not automatically valid for the new job.

If you mention a fixed rate, enter or check its actual amount in the preview. Model-authored monetary values are ignored. Matching selected reference positions can provide their saved rates and costs directly.

### Example: a small solo production

```text
Draft a proposal for one 60-second film and three 15-second cutdowns.
I do the work myself: one filming day at my own fixed day rate,
and two editing days using my progressive schedule.
Include one feedback round. The client supplies the location.
Do not add crew or extra positions. Ask only about missing requirements.
Leave unknown prices unfilled; I will complete them in the preview.
```

After generation, verify the filming line uses **Own fixed rate**, the editing line uses **Own progressive**, and the quantities remain one and two days.

### Example: distinguish internal and external crew

```text
Plan two filming days and two editing days.
I produce the project myself using my progressive schedule.
A camera operator works two days as INTERNAL crew integrated in my fee.
An external sound supplier works two days as EXTERNAL crew.
Add one purchased music licence as an expense and two units of my owned camera kit.
Do not apply my progressive tiers to crew. Do not invent additional positions or prices.
```

Check **Internal crew** versus **External crew** carefully. They affect rebates and the DB stages differently. A job title such as Editor or Photographer does not determine whether someone is the owner or crew; say who performs the work.

### Example: reuse a selected project and its rates

First select the older project in the reference picker, then write:

```text
Use the selected reference as the structure and rate reference.
The new job has one interview, one filming day and two editing days.
Reuse saved prices only for matching roles and pricing methods.
Keep the new quantities above. Do not carry over old deadlines or extra crew.
Leave unmatched prices at zero and ask about genuinely missing deliverables.
```

The app copies rates only from selected, matching records. Translated roles can be linked by the model to a reference position; exact unambiguous role/method matches are also supported. Different methods, conflicting matches or unknown sources can remain unpriced. You can still apply the draft and complete prices later. Copying a reference's own progressive schedule affects existing own progressive positions too; inspect the preview and confirmation.

Only compact summaries are included: up to three phases and four lines per phase, short scope/deliverable text, tiers and relevant calculation values. The model does not see the complete old proposal, attachments, client contacts or terms. Supply any missing context explicitly rather than asking it to infer unseen material.

### Example: review an existing calculation

Choose **Review calculation**, then write:

```text
Check the current calculation against this scope:
one filming day for three interviews, two editing days, one feedback round,
one final 60-second film with subtitles.
Look for duplicated work, missing sound/data-handling effort,
unclear internal versus external crew, and mismatched quantities.
Return concrete findings and unanswered questions. Do not create new phases.
```

The app's displayed totals and deterministic checks come from its calculation engine. The model's findings are advisory. Do not treat an unmentioned issue as proof that everything is correct.

### Reviewing and refining

Check the introduction, scope, actual role names, pricing methods, days/units, selling rates and costs. Numeric labels distinguish per-day and per-unit amounts. Verify the reference source and your own rate schedule. Select only the phases you want to add; they append to the current calculation. Selected introduction text replaces that language's current proposal introduction.

Missing prices show an incomplete-total note but do not block an editable draft. **Undo applied draft** restores the affected fields while unchanged and unlinked. Approved projects support review; they do not accept new AI draft calculations.

For a weak result, try one smaller, more specific brief. State the correction directly: “The camera operator is internal crew; I do the editing myself.” Generating again replaces the preview. There is no ongoing chat memory. Re-enter the relevant facts in each request; applied project data can be used as current context on a later request. Shorten the brief or remove a reference if the context limit is exceeded.

[Model downloads and memory controls](#local-ai-and-reference-projects) · [Pricing methods](#calculations-day-rates-and-rebates) · [Data protection](#privacy-encryption-and-recovery-keys).

## Settings and personalization

Open **Coool PM → Settings…** or press **⌘,**. Drag a window edge or corner to resize Settings. In **Templates** and **Terms**, drag the divider to give the form or PDF preview more space. The sidebar groups related settings.

- **Features:** choose a usage profile and individual feature switches. Project overrides live at the bottom of the project window. Hiding a feature keeps its data.
- **General:** interface and document language, appearance, project autosave, demo library, guided tour and setup. Help follows the interface language; document output can use a different language.
- **Business:** sender identity, tax/bank details, client numbering defaults and payment deadline.
- **Day rates:** create, name and save your own progressive schedules; copy one into a project when needed.
- **Pricing categories:** rename labels or add categories based on one of the seven calculation methods.
- **Templates:** German/English proposal and invoice styling, custom fonts, first-page header, footer columns, project blocks and Word templates.
- **Terms:** rich-text terms and project/client variables. Cover letters and terms remain on separate pages. Project payment terms supply the deadline and instalment timeline.
- **XRechnung:** seller identifiers and local validator configuration.
- **Library:** backups, optional synchronization, launch authentication, MCP and reset options.
- **Local AI:** optional model downloads, hardware guidance, load/unload and idle policy.

In **Business**, use Return to add a line in the address or bank details. Select text and use the toolbar or ⌘B, ⌘I and ⌘U to format it.

The title-bar checkmark is green when project autosave is on and orange when it’s off. With autosave off, choose **Save Project Edits** or press **⌘S**. Unsaved edits stay in memory until saved or discarded and are excluded from backups. Document export, invoice issuance and other explicit library actions still write to the library.

Update-enabled builds check at launch by default. Change this in **Settings → Updates**. Installation requires confirmation.

Use **⌘Return** to insert a line break in supported multiline settings fields. In rich-text fields, format headings or other text with the available controls. Font files installed separately on the Mac are not embedded in backups.

[Learn about backups and reset](#backups-recovery-and-synchronization).

## Backups, recovery and synchronization

The main window shows **Autosave on** while the local library is open. Choose **Backups** to manage recovery copies or press **⌘⌥B** to create one. To enable launch authentication, configure external MCP access or reset the library, open **Settings → Library**.

The [Privacy and recovery](#privacy-encryption-and-recovery-keys) lists the contents of an archive, explains how optional iCloud sync works and walks through restoring on a new Mac.



### Autosave and backup are different

Edits are saved automatically on this Mac. A backup is a separate encrypted recovery copy. **Backups & Recovery** shows whether that copy is current. By default, Coool PM offers to create a backup on close after two days without a backup if the recovery copy is out of date. Change the interval or choose **Never** under **Settings → Library**. Closing the reminder postpones it for the same interval. If Coool PM offers to create a backup on close, choose **Close** to leave with your edits saved locally, or **Create Backup and Close** to also write a recovery copy.

For the complete inventory, key recovery and reset behavior, read [Privacy and recovery](#privacy-encryption-and-recovery-keys). Local model downloads are configured under **Settings → Local AI**.

## Privacy, encryption and recovery keys

### What Coool PM stores

| Storage | Contents and protection |
| --- | --- |
| `~/Library/Application Support/Coool PM/Projects.sqlite` | SQLCipher encrypts database pages, including client and freelancer details, projects, calculations, invoice history, payment records, numbering reservations, and copies of attached documents. SQLite temporary tables use memory. |
| App preferences | The app encrypts the business identity, addresses, tax and bank details, branding and terms, rate schedules, custom pricing, goals and configured file paths. Ordinary interface preferences and operational metadata such as backup timestamps and synchronization state can be readable. |
| macOS Keychain | A device-local Keychain entry holds the library secret. The app derives separate keys for database encryption, backups and protected preferences. |
| Document files | An import copies a document into the library. Its source file stays at its original location. Installed DOCX templates, exported documents, CSV reports and vCards use their normal formats in the filesystem. |
| Document processing | Quick Look, template processing in Pages, sample Word documents, and local XRechnung validation can use ordinary temporary files. Some helpers remove their files when finished. Opened samples, interrupted operations and caches managed by other apps or macOS can leave copies behind. |

An unlocked app uses decrypted records in memory to display and edit them. The library encryption applies to Coool PM’s own storage. Earlier plaintext backups, prior disk snapshots, exported files, printed copies and files received by other people have separate lifetimes. An upgrade cannot retroactively encrypt those copies.

### Recovery key and launch lock

On first setup, choose **Create key**, then save the text file, print the key, or use **Copy recovery key** to store it somewhere safe. The recovery key file is readable text. Store it separately from your backups. Anyone with the key and an archive can decrypt its contents. Coool PM has no recovery service that can replace a lost key.

For an existing plaintext library, use the updated build for the same installation, with older copies of the app closed. Setup converts the existing database into an encrypted copy, checks the converted file and replaces the local database. Retain your recovery key and a verified backup across the upgrade.

In **Settings → Library**, turn on **Require Touch ID or Mac password on launch** to have macOS authenticate you before the library and business settings open. The Mac login password or Touch ID unlocks this installation. The portable recovery key decrypts an archive on another Mac. Resetting always requires macOS authentication, including when launch authentication is off.

### What a backup includes

A new `.cooolbackup` file is an authenticated, encrypted archive. It contains the following workspace data.

- All active and archived projects, client folders, client and freelancer directories, contacts, attached contracts and NDAs.
- Calculations, phase details, proposal approvals, change orders, planned and booked costs, time records, billing schedules, invoices, corrections, payments, project attachments and document history.
- Client, project and invoice number reservations, including reservations retained after deletion.
- Your business profile, logo, document styling, terms, payment and numbering defaults, day-rate schedules, pricing categories and monthly goals.
- The installed German and English proposal and invoice Word templates, language and appearance preferences, sidebar visibility settings and onboarding completion.

The archive carries attachment **copies held by the app**. Files and fonts installed elsewhere on disk, separately exported copies and external applications such as the validator are outside its scope. Configure trusted Java and validator paths on the destination Mac. The recovery key, launch lock and MCP authorizations, backup destination and sync account association belong to the local Mac. Reconnect local services and choose backup destinations on the receiving Mac.

### Creating and restoring a backup

1. Open **Settings → Library → Manage backups and sync…** or click **Backups** in the main window. **Create Backup Now** (`⌘⌥B` in the library) writes a new dated archive. With no automatic destination, the app uses `~/Library/Application Support/Coool PM/Backups/`.
2. Choose **Create Backup Elsewhere…** for a separate destination, or choose a folder for automatic daily backups while the app is running. Project edits are autosaved locally by default. With autosave disabled, save pending edits before creating a recovery copy. The optional prompt when closing offers to create a separate recovery copy.
3. To recover on a new Mac, open the app and choose **Use existing key** during setup. Then choose **Restore from Backup…**, select the archive and review the replacement confirmation. Restoring into a library with a different key prompts for the archive’s key. Incoming records are stored under the destination library’s key.
4. Restore replaces the current workspace. The app first writes an encrypted recovery copy of the existing workspace to the local Backups folder. It can import supported archives from earlier plaintext versions. Those original files remain in their original format.

**Settings → Library → Reset options…** offers a library-only reset or an app-and-library reset. Both take a recovery backup and clear local records and number history after device authentication. The wider reset also clears business setup, installed templates, preferences and the local encryption key, then returns to library setup. Keep the previous recovery key to open backups made before the reset. Existing backups and the private iCloud copy survive a local reset.

### Optional sharing

**iCloud Drive** copies an encrypted backup when you choose a destination inside iCloud Drive. Restore an archive to use that copy as a workspace. In a build provisioned for **CloudKit**, automatic sync or **Sync now** sends an encrypted archive and a content digest to the private database under your Apple account. Cloud storage also exposes service metadata such as modification time. Use the same recovery key across Macs that share a library. If both sides change, the app asks which version to use.

**AI access** is a local stdio MCP connection, disabled by default under **Settings → Library**. Read tools return UUID-based client/project aliases, statuses and numbered phases. Real names, client/project numbers and custom labels are withheld. Financial access and draft edits each require their switch in Coool PM and the matching MCP startup flag. Turning either switch off revokes that access for subsequent requests in existing sessions. The available tools return structured fields and summaries. The MCP client controls where its results go next. Turn the connection off in Settings to stop subsequent requests.

**Document export** writes the file you select. Pages can open a Word template to produce a PDF, and the locally configured XRechnung validator processes invoice XML. **Save to Contacts…** writes a vCard that you can import into a contacts app. Coool PM does not require a developer-hosted account or analytics service to use the local library.

### Optional local AI

Local AI is off initially. Choosing Download retrieves pinned model files from Hugging Face and its download infrastructure. The provider receives normal network metadata such as IP address and the requested model. File sizes and SHA-256 hashes are checked before installation. Model files contain weights and tokenizer/configuration data.

After download, a bundled native helper runs inference on the Mac. It receives the current project title, day-rate tiers, calculation lines, applicable rebate and entered brief. Internal cost values are included when cost controlling is enabled. The available pricing category names and methods are included. Other projects are included only when explicitly selected in the reference picker, which starts empty. Up to two selected projects contribute short scope/deliverable excerpts and compact calculation summaries (up to three phases and four lines per phase, plus rate tiers and rebate). Contacts, bank/tax fields, documents, terms and unselected projects are excluded. The assistant’s context disclosure identifies the information used.

Briefs, responses and inference caches stay in process memory until discarded or the helper exits. The app saves no chat history and sends no inference requests to a remote service. Applying suggestions stores the resulting text and lines as encrypted project data. Unloading, cancellation and quitting stop the helper. macOS manages virtual memory and diagnostics.

Weights are ordinary files in the local AIModels folder and can be removed in Settings. Backups carry the Local AI enablement preference, selected model and idle policy. Restore requires downloading weights again. External MCP has separate enablement and permissions.

## XRechnung

Configure seller address, electronic address and scheme, contact details, banking, and seller identification in **Settings → XRechnung**. Configure buyer address, endpoint, and reference in the client editor’s XRechnung tab. Issued invoice snapshots retain applicable defaults.

The export form identifies missing fields. A configured Java runtime and KoSIT validator validate the XML before it is saved with the validation report. See the development guide for paths and dependencies.

The purchase order is separate from the electronic buyer reference. Configure both when required. This app supports local validation; a DOCX/PDF export alone is not an XRechnung XML file.


The default validator folder is **Application Support/Coool PM/XRechnung**, with `java/bin/java`, `validator.jar` and `rules/scenarios.xml`. Override these paths in Settings when needed. Use matching KoSIT validator and scenario/rule versions. [Build and development overview](#building-coool-pm-yourself).

## Connecting external AI through MCP

MCP is an optional local connection for Claude, Codex and other compatible clients. It is separate from the built-in local model and starts off.

1. Enable integrations in **Settings → Features** if they are hidden by your profile.
2. Open **Settings → Library**, enable MCP and choose whether the configuration may include financial data or draft creation.
3. Copy the generated configuration into the MCP client. The executable is **CooolPM-MCP** inside the app bundle; use the absolute path supplied by Settings.
4. With launch authentication enabled, keep Coool PM open and unlocked while the client uses the library.

Read tools can list clients and projects. Financial access adds rates, costs and reports. Write access can create clients, draft projects and calculation lines. Approved or archived calculations stay protected. Financial access and draft edits each require the matching Settings switch and startup flag. Turning a switch off revokes that permission for subsequent requests in existing sessions. Turn MCP off to stop all subsequent tool requests.

The external client decides whether to send returned data to its AI provider. Review that client's configuration before enabling sensitive access. Coool PM's local AI does not require MCP to be enabled.

[Read the data-sharing details](#privacy-encryption-and-recovery-keys) or [configure the local assistant](#local-ai-and-reference-projects).

### Name privacy and ChatGPT

All MCP responses use stable aliases such as **Project <UUID>** and **Client <UUID>**. Real names and project/client numbers are withheld. Custom phase and entry labels become **Phase 1**, **Entry 1**, etc., because they may contain identifying text. IDs, links, statuses and explicitly permitted amounts remain visible. Text you type into an external AI is outside this filter; aliases do not guarantee complete anonymity.

Regular ChatGPT requires an eligible custom MCP account and a Secure MCP Tunnel (which can run the stdio helper directly). A local configuration alone does not connect it. See `docs/CHATGPT_MCP.md` in the source repository for setup and current account limitations. Older app/MCP processes must be restarted after installing the privacy-enabled build.

## Building Coool PM yourself

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

## Troubleshooting

### Finder reports a permissions or ownership error

Drag **Coool PM** out of the disk image and open the copy. If you lack permission to write to the system Applications folder, copy it to your own Applications folder. If it still fails, report the exact error, where it happened, and your macOS version.

### A feature or project is missing

Check **Settings → Features** and the project's overrides. Hidden features keep their data. Use sidebar search, show archived records, or show clients without active projects. Folders belong to one client.

### The calculation is locked

An approved proposal fixes its calculation. Use a change order for extra scope. Issued or linked activity also limits what can be undone. Do not delete invoice history to change an agreement.

### The export reports missing information

Use the checklist in **Create document…**. Check business/recipient details, document number, service period and language-specific text. Install a DOCX template, not a Pages file. Template-based PDF export needs Pages; XRechnung XML needs its local validator setup.

### The local model will not download or load

Enable local AI and choose an eligible model. The download may take time; **Downloaded** appears after file checks pass. Check the visible error and disk space. Retry a failed download; cancelled partial downloads are discarded. A running inference task can be cancelled, then a smaller model loaded. Local inference needs Apple Silicon and the bundled helper.

### The AI draft is incomplete or chooses the wrong rates

Shorten the brief or remove one reference when context is too large. Review role, pricing method, days/units and scope before applying. Matching selected reference positions can supply saved rates; unmatched positions stay unpriced. You can apply them and finish prices in the project. Model-authored prices are ignored. Placeholder or malformed responses are retried once; a local model can still be wrong.

### A report differs from the project forecast

Reports use invoice issue, booking and work dates. Cash received is gross and follows payment dates. Project forecasts use the agreed fee and expected remaining costs. Check selected year/month, undated bookings, corrections and whether a file was actually booked. [Explain the DB stages](#costs-db1-db2-and-forecasts).

### The backup says there are changes

Autosave does not create an archive. Press **⌘⌥B** and check its completion status. If another Mac has changed the private sync copy, resolve the conflict before choosing a version. [Backup and recovery](#backups-recovery-and-synchronization).

### The recovery key is missing

An existing unlocked installation may still have its Keychain copy. Coool PM has no service that can recover a lost secret. Do not reset or remove working copies while investigating. Never include recovery keys, client data or unredacted financial documents in an issue report.
