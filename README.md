# HV Melde App

Serverlose iPhone-App zur strukturierten Dokumentation von Vorfällen in verwalteten Objekten. Die erste Ausbaustufe erzeugt auf dem Gerät ein PDF, das die Nutzerin oder der Nutzer anschließend über das iOS-Teilen-Menü, zum Beispiel per E-Mail, versendet.

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

Über das Zahnrad lassen sich persönliche Absenderdaten, mehrere Objekte und wiederverwendbare Hausverwaltungen lokal hinterlegen. Jedes Objekt besitzt eine eigene Melde-E-Mail-Adresse.

Fotos, Prüfsummen und eine nachvollziehbare Änderungshistorie folgen in einem eigenen Umsetzungsschritt. Der fachliche Umfang steht in [docs/MVP.md](docs/MVP.md), die Leitlinien zum Beweiswert in [docs/EVIDENCE.md](docs/EVIDENCE.md).

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
- lokale Stammdaten als JSON im geschützten App-Verzeichnis
- XcodeGen erzeugt das Xcode-Projekt aus `project.yml`; das generierte Projekt wird nicht eingecheckt
- `.github/workflows/testflight.yml`: manueller, signierter Upload zu TestFlight

## Lokale Entwicklung

Voraussetzungen auf macOS: aktuelles Xcode, Swift und XcodeGen.

```sh
swift test
xcodegen generate
open HVMeldeApp.xcodeproj
```

Die Entwicklung kann unter Windows erfolgen. GitHub Actions übernimmt Pakettests und den iOS-Simulator-Build auf einem macOS-Runner.

## Noch nicht enthalten

- Fotoaufnahme und Import aus der Mediathek
- lokale Ablage unfertiger Meldungen
- kryptografische Prüfsummen
- TestFlight- und App-Store-Veröffentlichung
- rechtliche Prüfung des Dokumentationsprozesses
