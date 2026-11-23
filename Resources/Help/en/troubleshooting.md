# Troubleshooting

## Finder reports a permissions or ownership error

Drag **Coool PM** out of the disk image and open the copy. If you lack permission to write to the system Applications folder, copy it to your own Applications folder. If it still fails, report the exact error, where it happened, and your macOS version.

## A feature or project is missing

Check **Settings → Features** and the project's overrides. Hidden features keep their data. Use sidebar search, show archived records, or show clients without active projects. Folders belong to one client.

## The calculation is locked

An approved proposal fixes its calculation. Use a change order for extra scope. Issued or linked activity also limits what can be undone. Do not delete invoice history to change an agreement.

## The export reports missing information

Use the checklist in **Create document…**. Check business/recipient details, document number, service period and language-specific text. Install a DOCX template, not a Pages file. Template-based PDF export needs Pages; XRechnung XML needs its local validator setup.

## The local model will not download or load

Enable local AI and choose an eligible model. The download may take time; **Downloaded** appears after file checks pass. Check the visible error and disk space. Retry a failed download; cancelled partial downloads are discarded. A running inference task can be cancelled, then a smaller model loaded. Local inference needs Apple Silicon and the bundled helper.

## The AI draft is incomplete or chooses the wrong rates

Shorten the brief or remove one reference when context is too large. Review role, pricing method, days/units and scope before applying. Matching selected reference positions can supply saved rates; unmatched positions stay unpriced. You can apply them and finish prices in the project. Model-authored prices are ignored. Placeholder or malformed responses are retried once; a local model can still be wrong.

## A report differs from the project forecast

Reports use invoice issue, booking and work dates. Cash received is gross and follows payment dates. Project forecasts use the agreed fee and expected remaining costs. Check selected year/month, undated bookings, corrections and whether a file was actually booked. [Explain the DB stages](help://controlling).

## The backup says there are changes

Autosave does not create an archive. Press **⌘⌥B** and check its completion status. If another Mac has changed the private sync copy, resolve the conflict before choosing a version. [Backup and recovery](help://backups).

## The recovery key is missing

An existing unlocked installation may still have its Keychain copy. Coool PM has no service that can recover a lost secret. Do not reset or remove working copies while investigating. Never include recovery keys, client data or unredacted financial documents in an issue report.
