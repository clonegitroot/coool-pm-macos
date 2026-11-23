# Datenschutz, Verschlüsselung und Schlüssel

## Gespeicherte Daten

SQLCipher verschlüsselt die lokale Datenbank mit Kunden-/Freelancerdaten, Projekten, Kalkulationen, Rechnungs- und Zahlungshistorie, Nummernreservierungen und gespeicherten Anlagenkopien. Sensible Geschäftsvorgaben wie Identität, Adresse, Bank-/Steuerangaben, Gestaltung, Bedingungen, Staffeln, Ziele und Dateipfade werden ebenfalls verschlüsselt. Normale Oberflächenvorgaben sowie betriebliche Zeitstempel und Synchronisierungsstatus können lesbar bleiben.

Der lokale Bibliotheksschlüssel liegt im macOS-Schlüsselbund. Beim Entsperren verarbeitet die App Daten im Arbeitsspeicher. macOS verwaltet virtuellen Speicher und Diagnosen. Die App bietet keinen Wiederherstellungsdienst für verlorene Schlüssel.

## Dateien außerhalb der Verschlüsselung

Importierte Dokumente werden in die Bibliothek kopiert; die Originale bleiben an ihrem ursprünglichen Ort. Installierte Word-Vorlagen, exportierte PDF-/DOCX-Dateien, CSV-Berichte und Kontaktkarten behalten ihre normalen Dateiformate. Vorschau, Pages-Konvertierung und lokale XRechnung-Validierung können temporäre Dokumentdateien erzeugen. Unterbrechungen oder von anderen Apps verwaltete Caches können Kopien zurücklassen. Frühere unverschlüsselte Sicherungen und Exporte werden durch ein Update nicht nachträglich verschlüsselt.

## Wiederherstellungsschlüssel und Startschutz

Speichere oder drucke den vollständigen Schlüssel bei der Einrichtung und bewahre ihn getrennt von Sicherungen auf. Die Schlüsseldatei ist lesbarer Text. Wer Schlüssel und Archiv besitzt, kann es entschlüsseln. Fehlen sowohl eine verwendbare lokale Schlüsselbundkopie als auch der Wiederherstellungsschlüssel, können Daten unzugänglich bleiben.

Unter **Einstellungen → Bibliothek** kannst du Touch ID bzw. das Mac-Passwort bei jedem Start verlangen. Dieser Startschutz entsperrt die Installation; ein übertragbarer Archivschlüssel dient der Wiederherstellung auf einem anderen Mac. Zurücksetzen verlangt die Geräteauthentifizierung auch ohne aktivierten Startschutz.

## Sicherungen und optionale Dienste

Neue `.cooolbackup`-Archive sind authentifiziert verschlüsselt. Sie enthalten die portable Bibliothek einschließlich in der App gespeicherter Anlagen und Einstellungen. Schlüssel, lokale Freigaben, Zielpfade, externe Schriften/Programme und große Modellgewichte gehören nicht dazu. Wiederherstellen legt zunächst eine verschlüsselte Rettungskopie an. Bereits vorhandene alte Archive behalten ihr ursprüngliches Format.

iCloud Drive kopiert Archive im gewählten Ordner. Eine passend provisionierte CloudKit-App sendet bei aktivierter Synchronisierung ein verschlüsseltes Archiv und einen Inhalts-Hash an die private Apple-Datenbank; normale Dienstmetadaten bleiben beim Anbieter sichtbar.

MCP ist zunächst aus. Ein externer KI-Client erhält mit Freigabe anonyme Kunden-/Projektkennungen, Status und nummerierte Phasen sowie optional Finanzdaten oder Schreibaktionen. Echte Namen, Kunden-/Projektnummern und individuelle Bezeichnungen werden nicht zurückgegeben. Der Client kann die freigegebenen Ergebnisse an seinen Anbieter senden. Prüfe die Konfiguration dieses Clients. Die integrierte lokale KI benötigt MCP nicht.

Der Modell-Download von Hugging Face übermittelt normale Verbindungsdaten wie IP-Adresse und Modellanfrage. Die anschließende Inferenz läuft lokal mit Briefing, Projektkalkulation, Kategorien und bewusst gewählten Referenzzusammenfassungen. Kontakte, Bank-/Steuerfelder, Anlagen, AGB und nicht ausgewählte Projekte werden nicht automatisch einbezogen. Eingefügter Freitext kann selbstverständlich eigene Informationen enthalten. Es gibt keinen gespeicherten Chatverlauf. Erst übernommene Ergebnisse werden zu verschlüsselten Projektdaten.

[Wiederherstellung und Sicherungsablauf](help://backups) · [MCP-Freigaben](help://mcp) · [Lokale KI](help://local-ai).
