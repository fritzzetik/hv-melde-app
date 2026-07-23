# HV Melde App

Serverlose iPhone-App zur strukturierten Dokumentation von Vorfällen in verwalteten Objekten. Die App erzeugt auf dem Gerät ein gemeinsames PDF aus einem Geschäftsbrief und nummerierten Anlagen. Es kann anschließend über das iOS-Teilen-Menü, zum Beispiel per E-Mail, versendet werden.

## Leitplanken

- keine zentrale Datenbank und kein eigener Server
- kein Benutzerkonto, kein Tracking und keine Analyse-SDKs
- Verarbeitung und PDF-Erzeugung ausschließlich auf dem Gerät
- bewusste Trennung zwischen unveränderten Nachweisen und beschreibenden Angaben
- keine Zusage von „Gerichtsfestigkeit“; der technische Beweiswert wird nachvollziehbar unterstützt

## Erste Produktstufe

1. Objekt und Garagenbereich angeben
2. Vorfall mit Datum, Uhrzeit, Kennzeichen und Beschreibung erfassen
3. Angaben prüfen
4. PDF lokal erzeugen
5. Empfänger anhand des gewählten Objekts vorausfüllen
6. PDF per Mail versenden oder über das System-Teilen-Menü speichern

Über das Zahnrad lassen sich persönliche Absenderdaten, mehrere Objekte und wiederverwendbare Hausverwaltungen lokal hinterlegen. Jedes Objekt besitzt einen internen Namen, eine optionale offizielle Bezeichnung, einen Objekttyp, eine strukturierte Anschrift, eine eigene Melde-E-Mail-Adresse und die Zuordnung „Mieter“ oder „Eigentümer“.

Beim ersten Start führt ein mehrseitiges Tutorial durch die erforderliche Einrichtung und den Meldeablauf. Es kann später unter „Einstellungen → Hilfe“ erneut geöffnet werden.

Erzeugte Meldungen werden mit ihrem PDF dauerhaft im geschützten App-Verzeichnis gespeichert. Über das Fallarchiv lassen sie sich als offen oder erledigt führen, wieder öffnen und erneut teilen. Pro Meldung wird festgehalten, ob sie das gemietete beziehungsweise eigene Objekt oder eine Allgemeinfläche betrifft. Profil, Objekte, Hausverwaltungen, Falldaten, Fotos und PDFs können optional über den privaten iCloud-Bereich des Benutzers synchronisiert werden.

Für wiederkehrende Ruhestörungen gibt es zusätzlich fortlaufende Lärmprotokolle. Ein Protokoll sammelt über Wochen oder Monate beliebig viele Ruhestörungen und Einsätze beziehungsweise Maßnahmen in einer gemeinsamen Zeitleiste. Pro Vorfall können mehrere Videos mit Ton direkt aufgenommen oder aus der Mediathek übernommen werden. Beginn und Ende des gesamten Vorfalls werden getrennt von der Dauer der Beweisaufnahme festgehalten. Polizei- und andere Einsätze können mit Verständigungs-, Ankunfts- und Endzeit, frei definierbarer Art der Einsatzkräfte, Dienststelle, Namen beziehungsweise Dienstnummern, Aktenzeichen und Ergebnis dokumentiert werden.

Das Lärmprotokoll-PDF enthält einen Geschäftsbrief, eine chronologische Darstellung und ein Anlagenverzeichnis. Jede digitale Beweisdatei wird einem Eintrag wie `L-001` oder `E-001` zugeordnet und mit vollständiger SHA-256-Prüfsumme ausgewiesen. Das exportierbare Beweispaket enthält PDF, Originalvideos und ein maschinenlesbares JSON-Manifest in einer ZIP-Datei. Große Pakete können über Apple Mail mit Mail Drop gesendet oder über die Dateien-App in iCloud Drive gespeichert und von dort geteilt werden. Originalvideos bleiben bis zu einem ausdrücklichen Export ausschließlich im geschützten lokalen App-Verzeichnis; sie werden wegen ihrer Größe nicht automatisch als CloudKit-Dateien synchronisiert.

Für die lokale Bilderkennung wählt die Nutzerin oder der Nutzer eine feste Meldekategorie und importiert ein Foto oder nimmt es direkt auf. Apple Vision klassifiziert das Bild und liest mögliche Kennzeichen. Die zweite Erkennungsstufe schlägt zusätzlich Fahrzeugtyp, eine heuristisch bestimmte Farbe und relevante Nebenobjekte wie Matratze oder Sperrmüll vor. Vorschläge werden erst nach manueller Prüfung in die Meldung übernommen.

Optional kann in den Einstellungen die erweiterte lokale Analyse aktiviert werden. Auf kompatiblen Geräten formuliert das Apple-Intelligence-Modell aus den lokalen Vision-Ergebnissen einen sachlichen Beschreibungsvorschlag. Ist das Modell nicht verfügbar, verwendet die App automatisch ausschließlich die bestehende Vision-Erkennung. Es werden keine Fotos oder Analysedaten an OpenAI oder andere externe Anbieter übertragen.

Die Oberfläche ist auf Deutsch, Italienisch und Englisch verfügbar. Standardmäßig übernimmt sie Sprache und Region aus iOS; alternativ kann die App-Sprache manuell gewählt werden. Für Deutsch stehen Österreich, Deutschland, Schweiz und Liechtenstein als getrennte Regionen zur Verfügung. Pro Hausverwaltung kann unabhängig davon eine deutsche, italienische, englische oder deutsch-italienische Briefausgabe gewählt werden. Freitextfelder werden für fremdsprachige Briefe mit Apples lokalem Translation Framework vorübersetzt und können vor der PDF-Erstellung korrigiert werden. Automatisch übersetzte Briefseiten weisen darauf hin, dass die deutsche Originalfassung verbindlich ist. Falls das benötigte Sprachmodell nicht unterstützt, noch nicht verfügbar oder dessen Download blockiert ist, kann der Vorgang jederzeit abgebrochen und das PDF stattdessen vollständig auf Deutsch erstellt werden. Die App setzt dafür iOS 26 oder neuer voraus.

Das der App übergebene Originalbild wird unverändert im geschützten App-Verzeichnis abgelegt. Das PDF enthält das Bild, dessen vollständige SHA-256-Prüfsumme, Importzeitpunkt, verfügbare EXIF-Aufnahmezeit samt Zeitzonenhinweis und die bestätigte lokale Auswertung. Der fachliche Umfang steht in [docs/MVP.md](docs/MVP.md), die Leitlinien zum Beweiswert in [docs/EVIDENCE.md](docs/EVIDENCE.md).

## Technische Struktur

```text
.
├── Package.swift
├── Sources/HVMeldeCore
├── Tests/HVMeldeCoreTests
├── ios-app/App
├── project.yml
└── .github/workflows
```

- `HVMeldeCore`: Datenmodell und Validierung ohne UI-Abhängigkeiten
- `ios-app/App`: SwiftUI-Oberfläche und PDF-Ausgabe mit iOS-Frameworks
- `LocalImageAnalyzer`: lokale Apple-Vision-Klassifizierung und Kennzeichen-OCR
- lokale Stammdaten als JSON im geschützten App-Verzeichnis
- XcodeGen erzeugt das Xcode-Projekt aus `project.yml`; das generierte Projekt wird nicht eingecheckt
- `.github/workflows/testflight.yml`: manueller, signierter Upload zu TestFlight

## Lokale Entwicklung

Voraussetzungen auf macOS: aktuelles Xcode, Swift und XcodeGen. Das App-Ziel benötigt iOS 26 oder neuer.

```sh
swift test
xcodegen generate
open HVMeldeApp.xcodeproj
```

Die Entwicklung kann unter Windows erfolgen. GitHub Actions übernimmt Pakettests und den iOS-Simulator-Build auf einem macOS-Runner.

## Noch nicht enthalten

- vollständige nachvollziehbare Versions- und Änderungshistorie bereits gespeicherter Protokolleinträge
- automatische CloudKit-Synchronisierung großer Originalvideos
- endgültige App-Store-Veröffentlichung
- rechtliche Prüfung des Dokumentationsprozesses
