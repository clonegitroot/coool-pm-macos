# Sicherung, Wiederherstellung und Synchronisierung

Änderungen werden automatisch in der Bibliothek auf diesem Mac gespeichert. Über **Sicherungen** verwaltest du separate verschlüsselte Sicherungskopien. **⌘⌥B** erstellt eine neue Kopie. Coool PM erinnert beim Schließen standardmäßig nach zwei Tagen ohne aktuelle Sicherung. Unter **Einstellungen → Bibliothek** kannst du das Intervall ändern oder **Nie** wählen. Wenn du die Erinnerung schließt, wird sie um dasselbe Intervall verschoben. Bietet Coool PM beim Beenden eine Sicherung an, bleiben deine Änderungen auch mit **Schließen** lokal gespeichert. **Sicherung erstellen und schließen** legt zusätzlich eine Kopie an.

Öffne die Sicherungsverwaltung über den Status in der Titelleiste oder **Einstellungen → Bibliothek**. Ohne automatisches Ziel verwendet die App den lokalen Sicherungsordner. Du kannst ein eigenes Ziel wählen, einzelne Archive separat speichern und tägliche automatische Sicherungen bei laufender App konfigurieren.

## Inhalt und Wiederherstellung

Ein Archiv umfasst aktive und archivierte Projekte, Verzeichnisse, Kontakte, Ordner, gespeicherte Anlagen, Kalkulationen, Dokument- und Rechnungshistorie, Zahlungen, Kosten, Zeiten und reservierte Nummern. Hinzu kommen Geschäftsdaten, Gestaltung, Vorlagen, Bedingungen, Staffeln, Kategorien, Ziele und portable Oberflächenvorgaben. Extern installierte Schriften, eigenständige Exporte und Modellgewichte gehören nicht dazu. Modellwahl und Leerlaufregel werden übernommen; lokale Dienste und Zielpfade richtest du am Zielgerät neu ein.

Auf einem neuen Mac wählst du bei der Einrichtung einen vorhandenen Schlüssel und stellst danach das Archiv wieder her. Bei abweichenden Schlüsseln fragt die App nach dem Schlüssel des Archivs und speichert die eingehenden Daten unter dem Zielschlüssel. Die Wiederherstellung ersetzt die Bibliothek; zuvor wird eine verschlüsselte Sicherung des vorhandenen Stands angelegt.

## iCloud und Zurücksetzen

Ein Sicherungsziel in iCloud Drive wird von macOS synchronisiert. Eine für CloudKit provisionierte App kann zusätzlich ein verschlüsseltes Archiv in der privaten CloudKit-Datenbank synchronisieren. Verwende für gemeinsam genutzte Bibliotheken denselben Schlüssel. Bei Änderungen auf beiden Seiten musst du einen Stand auswählen.

**Zurücksetzen** befindet sich ausschließlich in den Einstellungen und verlangt Touch ID oder das Mac-Passwort. Bibliothek bzw. App und Bibliothek können getrennt zurückgesetzt werden. Es wird vorher gesichert. Bestehende Sicherungen und die private iCloud-Kopie bleiben erhalten; beim vollständigen Reset werden auch Einrichtung, Vorlagen, Vorgaben und der lokale Verschlüsselungsschlüssel entfernt. Danach öffnet sich die Bibliothekseinrichtung. Bewahre den bisherigen Wiederherstellungsschlüssel für ältere Sicherungen auf.

[Datenschutz, Schlüssel und genaue Sicherungsgrenzen](help://privacy).
