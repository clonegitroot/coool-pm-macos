# XRechnung

Configure seller address, electronic address and scheme, contact details, banking, and seller identification in **Settings → XRechnung**. Configure buyer address, endpoint, and reference in the client editor’s XRechnung tab. Issued invoice snapshots retain applicable defaults.

The export form identifies missing fields. A configured Java runtime and KoSIT validator validate the XML before it is saved with the validation report. See the development guide for paths and dependencies.

The purchase order is separate from the electronic buyer reference. Configure both when required. This app supports local validation; a DOCX/PDF export alone is not an XRechnung XML file.


The default validator folder is **Application Support/Coool PM/XRechnung**, with `java/bin/java`, `validator.jar` and `rules/scenarios.xml`. Override these paths in Settings when needed. Use matching KoSIT validator and scenario/rule versions. [Build and development overview](help://building).
