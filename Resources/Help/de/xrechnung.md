# XRechnung

Hinterlege unter **Einstellungen → XRechnung** Verkäuferadresse, elektronische Adresse und Kennungsschema, Kontakt, Bankverbindung und Identifikation. Käuferadresse, Endpoint und Referenz werden im XRechnung-Bereich des Kunden gepflegt. Ausgestellte Rechnungen behalten die zugehörigen Werte als Snapshot.

Die Exportmaske zeigt fehlende Angaben. Ein lokal eingerichtetes Java und der KoSIT-Validator prüfen XML, bevor XML und Prüfbericht gespeichert werden. Standardpfade liegen unter **Application Support/Coool PM/XRechnung** mit `java/bin/java`, `validator.jar` und `rules/scenarios.xml`; eigene Pfade sind in den Einstellungen möglich. Verwende zusammenpassende Validator- und Regeldateien.

Die kaufmännische Auftragsnummer ist getrennt von der elektronischen Käuferreferenz. Trage beide ein, wenn sie benötigt werden. Ein PDF-/DOCX-Export allein ist keine XRechnung-XML-Datei.

[Build- und Entwicklungsinformationen](help://building).
