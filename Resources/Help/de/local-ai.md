# Lokale KI und Referenzprojekte

Entwürfe gliedern die Arbeit nach Produktionsablauf und benennen Liefergegenstände, Annahmen und offene Fragen. Die Kalkulationsprüfung verwendet berechnete Beträge aus der App. Sie zeigt Fortschritt, Fehler oder eine Bestätigung, wenn das Modell keine weiteren Auffälligkeiten meldet.

Aktiviere die optionale KI unter **Einstellungen → Lokale KI**. Sie ist zunächst ausgeschaltet. Modellkarten zeigen Downloadgröße, geschätzten Speicherbedarf und Grenzen. Die Empfehlung richtet sich nach dem Arbeitsspeicher deines Macs; freie Kapazität, andere Apps und Projektgröße beeinflussen die Nutzung. Lokale Inferenz benötigt Apple Silicon.

Wähle ein Modell und lade es herunter. Die Dateien kommen versionsgebunden von Hugging Face und werden auf Größe und Prüfsumme geprüft. Danach arbeitet die Inferenz lokal. Modellgewichte liegen im lokalen Ordner **Application Support/Coool PM/AIModels**.

## Entwerfen und prüfen

Öffne im Projekt **Lokale KI …**. **Entwurf aus Briefing** schlägt Anschreiben, Phasen, Rollen und Mengen vor. Prüfe Annahmen, offene Fragen und Kalkulationsarten. Rollen und Berechnungsmethoden sind getrennt und bearbeitbar. Alle sieben Methoden sowie eigene Kategorien werden berücksichtigt. Die App berechnet Geldbeträge mit ihrer eigenen Kalkulation.

**Kalkulation prüfen** verbindet konkrete App-Prüfungen mit unverbindlichen KI-Hinweisen. Freigegebene Projekte können geprüft werden; neue Kalkulationsentwürfe lassen sich nur in bearbeitbare Anfrage-/Angebotsprojekte übernehmen. Platzhalter oder unvollständige Antworten werden einmal erneut versucht. Lokale Modelle können trotzdem Mengen oder Kalkulationsarten falsch wählen.

## Ältere Projekte und Sätze übernehmen

Unter **Referenzprojekte (optional)** kannst du bis zu zwei andere, auch archivierte Projekte nach Titel oder Nummer suchen und auswählen. Anfangs ist nichts ausgewählt. Verwendet werden kompakte Leistungs- und Kalkulationszusammenfassungen: bis zu drei Phasen, je vier Positionen sowie kurze Leistungs- und Ergebnistexte. Kontakte, Dokumente, AGB und nicht ausgewählte Projekte bleiben ausgeschlossen. Das aktuelle Briefing hat Vorrang.

Passende Referenzpositionen können über ihre Referenz-ID oder eine eindeutige Übereinstimmung von Rolle und Methode verknüpft werden. Die App kopiert Verkaufssatz, Kosten und Tageslänge direkt aus den ausgewählten Datensätzen. Erfundene Modellpreise werden ignoriert. Mehrdeutige oder unpassende Positionen bleiben unbepreist. Kosten werden nur bei aktiviertem Controlling übernommen.

Unter **Eigene Tagessatzstaffel** wählst du eine Referenzstaffel oder behältst die aktuellen Projektsätze. Anfangs ist die erste gewählte Referenz vorgesehen. Die Vorschau zeigt Quelle und Staffelwerte. Bei Übernahme mit gestaffelten Eigenleistungen ersetzt diese Staffel die projektweiten eigenen Sätze, auch für vorhandene Positionen. Die Bestätigung weist darauf hin; Rückgängig stellt die vorherigen Werte wieder her.

Fehlende Preise verhindern die Übernahme nicht. Die Vorschau markiert die Summe als unvollständig. Ergänze die Sätze später im Projekt. Felder sind nach Tagen/Einheiten, Verkaufssatz bzw. Stückpreis und internen/Fremdkosten beschriftet.

## Modellspeicher und Datenschutz

Aufgaben laden das Modell automatisch. In den Einstellungen kannst du laden, entladen, abbrechen, nach jeder Aufgabe oder nach Leerlauf entladen und das Modell offen halten. Ein Wechsel gibt das vorherige Modell zuerst frei. Speicherdruck kann ungenutzte Modelle entladen oder aktive Aufgaben abbrechen. Entladen beendet den Helferprozess; die Download-Dateien bleiben erhalten.

Briefing und ausgewählter Kontext bleiben während der Verarbeitung lokal. Es wird kein Chatverlauf gespeichert. Übernommene Entwürfe werden als verschlüsselte Projektdaten abgelegt. Sicherungen enthalten Modellauswahl und Leerlaufregel, nicht die großen Gewichte. Auf einem neuen Mac werden diese erneut geladen. Die lokale KI ist unabhängig von externem MCP.

[Datenschutz im Detail](help://privacy).

[Briefing-Checkliste und kopierbare Promptbeispiele](help://ai-prompting).
