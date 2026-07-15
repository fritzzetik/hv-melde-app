# MVP: PDF-Meldung ohne Server

## Ziel

Eine Person dokumentiert einen konkreten Vorfall in einer Garage und erzeugt daraus ein lesbares PDF. Die App überträgt selbst keine Daten. Erst die ausdrückliche Auswahl im iOS-Teilen-Menü gibt das PDF an Mail, Dateien oder eine andere App weiter.

## Angaben pro Meldung

- Objekt oder Liegenschaft
- genauer Bereich, Stellplatz oder Garagenebene
- Datum und Uhrzeit des beobachteten Vorfalls
- Kennzeichen
- optionale Fahrzeugbeschreibung
- Art des Verstoßes
- sachliche Beschreibung
- optionale Zeugenangabe
- automatisch: Erstellungszeitpunkt und eindeutige Meldungs-ID
- optionales Beweisfoto mit getrennter Aufnahme- und Importzeit

## MVP-Ablauf

1. Persönliche Absenderdaten einmalig lokal hinterlegen.
2. Hausverwaltungen und mehrere verwaltete Objekte anlegen.
3. Pro Objekt eine Melde-E-Mail festlegen.
4. Objekt wählen und Pflichtangaben zum Vorfall erfassen.
5. Meldekategorie wählen und Foto importieren oder direkt aufnehmen.
6. Foto lokal klassifizieren und mögliche Kennzeichen, Fahrzeugdetails sowie relevante Nebenobjekte erkennen lassen.
7. KI-Vorschläge am Originalfoto prüfen und ausdrücklich bestätigen.
8. Eingaben lokal validieren und das PDF auf dem Gerät erzeugen.
9. Fall und PDF dauerhaft lokal speichern.
10. Empfänger im Mailfenster vorausfüllen und das PDF anhängen.
11. Versand ausdrücklich bestätigen oder das PDF anderweitig teilen.
12. Fall später als erledigt markieren oder wieder öffnen.

## Datenschutzgrenze

- kein Backend
- keine Anmeldung
- keine Telemetrie
- keine automatische Übertragung
- temporäre PDF-Dateien werden nur im App-eigenen Verzeichnis erzeugt
- Profil-, Objekt- und Verwaltungsdaten werden ausschließlich im App-Verzeichnis gespeichert
- Beweisfoto und zugehörige Metadaten werden geschützt im App-Verzeichnis gespeichert
- Fallarchiv und dauerhafte PDF-Dateien werden ausschließlich im App-Verzeichnis gespeichert

## Abnahmekriterien der ersten Iteration

- Leere Pflichtfelder verhindern die PDF-Erzeugung und werden verständlich benannt.
- Sonderzeichen und mehrzeilige Texte erscheinen korrekt im PDF.
- Die Meldungs-ID und beide Zeitpunkte sind im PDF sichtbar.
- Ein ausgewähltes Foto wird ausschließlich lokal analysiert.
- Kennzeichen- und Fahrzeugvorschläge werden nie ohne Bestätigung übernommen.
- Foto, vollständige SHA-256-Prüfsumme und verfügbare EXIF-Aufnahmezeit erscheinen im PDF.
- Fehlende EXIF-Aufnahmezeit oder Zeitzone wird sichtbar als solche gekennzeichnet.
- Das PDF lässt sich über das System-Teilen-Menü weitergeben.
- Gespeicherte Fälle lassen sich als offen oder erledigt verwalten.
- Die Kernvalidierung wird automatisiert getestet.

## Spätere Iterationen

- lokale, verschlüsselte Entwürfe
- Änderungshistorie und Prüfsumme der strukturierten Meldungsdaten
- Vorlagen für verschiedene Hausverwaltungen
- optional qualifizierte Signatur oder vertrauenswürdiger Zeitstempel nach rechtlicher Prüfung
