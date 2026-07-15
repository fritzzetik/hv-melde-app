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

## MVP-Ablauf

1. Persönliche Absenderdaten einmalig lokal hinterlegen.
2. Hausverwaltungen und mehrere verwaltete Objekte anlegen.
3. Pro Objekt eine Melde-E-Mail festlegen.
4. Objekt wählen und Pflichtangaben zum Vorfall erfassen.
5. Eingaben lokal validieren und das PDF auf dem Gerät erzeugen.
6. Empfänger im Mailfenster vorausfüllen und das PDF anhängen.
7. Versand ausdrücklich bestätigen oder das PDF anderweitig teilen.

## Datenschutzgrenze

- kein Backend
- keine Anmeldung
- keine Telemetrie
- keine automatische Übertragung
- temporäre PDF-Dateien werden nur im App-eigenen Verzeichnis erzeugt
- Profil-, Objekt- und Verwaltungsdaten werden ausschließlich im App-Verzeichnis gespeichert

## Abnahmekriterien der ersten Iteration

- Leere Pflichtfelder verhindern die PDF-Erzeugung und werden verständlich benannt.
- Sonderzeichen und mehrzeilige Texte erscheinen korrekt im PDF.
- Die Meldungs-ID und beide Zeitpunkte sind im PDF sichtbar.
- Das PDF lässt sich über das System-Teilen-Menü weitergeben.
- Die Kernvalidierung wird automatisiert getestet.

## Spätere Iterationen

- Originalfotos importieren oder aufnehmen
- Metadaten und SHA-256-Prüfsummen dokumentieren
- lokale, verschlüsselte Entwürfe
- Vorlagen für verschiedene Hausverwaltungen
- optional qualifizierte Signatur oder vertrauenswürdiger Zeitstempel nach rechtlicher Prüfung
