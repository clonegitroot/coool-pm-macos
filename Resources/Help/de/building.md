# Coool PM selbst bauen

Das Repository enthält die native macOS-App, den MCP-Helfer, den lokalen Modellprozess und die bearbeitbare Icon-Composer-Datei. Benötigt werden ein Mac und eine vollständige Xcode-Installation mit ausgewählten Kommandozeilenwerkzeugen.

1. Klone ein Repository, auf das du zugreifen kannst, und öffne darin ein Terminal.
2. Installiere auf Apple Silicon bei Bedarf Xcodes Metal-Komponente: `xcodebuild -downloadComponent MetalToolchain`.
3. Baue und prüfe die App:

```sh
./build.sh
codesign --verify --deep --strict "Coool PM.app"
```

Der erste Build lädt versionsgebundene SQLCipher- und Swift-Paket-Abhängigkeiten, prüft den SQLCipher-Download und kompiliert auf Apple Silicon den KI-Helfer. Modellgewichte werden später optional in der App geladen. Intel-Builds lassen den KI-Helfer weg. Das Symbol wird aus **Assets/AppIcon.icon** kompiliert.

Öffne die fertige **Coool PM.app**, wenn du eine Bibliothek einrichten oder die fiktive Demo ausprobieren möchtest. Ein Build mit derselben Kennung wie eine bestehende Installation kann deren Bibliothek öffnen. Bewahre deshalb vor einem Installationswechsel Schlüssel und Sicherung auf.

Lokale Builds werden ad hoc signiert. Signierte Verteilung, Notarisierung und provisionierte CloudKit-Synchronisierung benötigen zusätzliche Apple-Konfiguration. Ein lokaler Build erfordert keine Veröffentlichung oder aktiviertes CloudKit.

Im [Entwicklungsleitfaden](https://github.com/clonegitroot/coool-pm/blob/main/docs/DEVELOPMENT.md) findest du Prüfungen und Provisionierung. Die [Claude-/Codex-Promptvorlage](https://github.com/clonegitroot/coool-pm/blob/main/docs/BUILD_WITH_AI.md) unterstützt den Build des vorhandenen Codes ohne echte Kundendaten. Diese Links öffnen den Browser; der Artikel selbst ist offline verfügbar.
