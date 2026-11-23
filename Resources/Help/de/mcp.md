# Externe KI über MCP verbinden

MCP ist eine optionale lokale Verbindung für kompatible Clients wie Claude oder Codex. Sie ist unabhängig vom integrierten lokalen Modell und zunächst ausgeschaltet.

1. Aktiviere bei Bedarf Integrationen unter **Einstellungen → Funktionen**.
2. Aktiviere MCP unter **Einstellungen → Bibliothek** und bestimme, ob Finanzdaten oder das Anlegen von Entwürfen freigegeben werden.
3. Kopiere die erzeugte Konfiguration in den MCP-Client. Der Helfer **CooolPM-MCP** liegt im App-Paket; verwende den absoluten Pfad aus den Einstellungen.
4. Bei aktiviertem Startschutz muss Coool PM geöffnet und entsperrt bleiben.

Lesefunktionen liefern Kunden und Projekte. Finanzzugriff ergänzt Sätze, Kosten und Auswertungen. Schreibzugriff kann Kunden, Projektentwürfe und Kalkulationspositionen anlegen. Freigegebene oder archivierte Kalkulationen bleiben geschützt. Finanzzugriff und Entwurfsbearbeitung benötigen jeweils den passenden Schalter in den Einstellungen und das entsprechende Startargument. Beim Ausschalten eines Schalters entfällt die Berechtigung für nachfolgende Anfragen in bestehenden Sitzungen. Wenn du MCP ausschaltest, werden alle weiteren Werkzeuganfragen abgelehnt.

Der externe Client entscheidet, ob Ergebnisse an seinen KI-Anbieter weitergegeben werden. Prüfe dessen Konfiguration, bevor du sensible Zugriffe erlaubst. Für die integrierte lokale KI muss MCP nicht aktiviert werden.

[Datenschutzdetails](help://privacy) · [Lokale KI einrichten](help://local-ai).

## Namensschutz und ChatGPT

Alle MCP-Antworten verwenden stabile Kennungen wie **Project <UUID>** und **Client <UUID>**. Echte Namen sowie Projekt- und Kundennummern werden nicht übertragen. Individuelle Phasen und Positionen heißen **Phase 1**, **Entry 1** usw., da ihre Texte Namen enthalten könnten. IDs, Verknüpfungen, Status und ausdrücklich freigegebene Beträge bleiben sichtbar. Eigene Eingaben in eine externe KI fallen nicht unter diesen Filter; Kennungen garantieren keine vollständige Anonymität.

Reguläres ChatGPT benötigt einen berechtigten Account für eigene MCP-Verbindungen und einen Secure MCP Tunnel, der den stdio-Helfer direkt starten kann. Die lokale Konfiguration allein reicht nicht aus. Die Einrichtung und aktuelle Account-Grenzen stehen in `docs/CHATGPT_MCP.md` im Quellcode-Repository. Ältere App- und MCP-Prozesse müssen nach Installation der Version mit Namensschutz neu gestartet werden.
