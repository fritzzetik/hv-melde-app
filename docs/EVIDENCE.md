# Leitlinien zum Beweiswert

Die App kann eine konsistente Dokumentation unterstützen, aber nicht allein garantieren, dass ein Dokument vor Gericht als vollständig, unverändert oder beweiskräftig anerkannt wird.

## Technische Ziele

- Beobachtungen und automatisch ermittelte technische Daten klar unterscheiden.
- Originaldateien nicht stillschweigend verändern.
- Zeitzone und Quelle eines Zeitpunkts kenntlich machen.
- Jede Meldung mit einer stabilen UUID versehen.
- Das der App übergebene Originalfoto geschützt und ohne nachträgliche Bildbearbeitung speichern.
- SHA-256-Prüfsumme des gespeicherten Fotos vollständig im PDF ausgeben.
- Aufnahmezeit aus EXIF, Übernahmezeit in die App und Erstellungszeit der Meldung getrennt dokumentieren.
- Fehlende EXIF-Zeitzonen ausdrücklich kennzeichnen; bei direkter Kameraaufnahme die Geräteuhr als Quelle nennen.
- Automatische Erkennung und anschließend bestätigte Angaben getrennt dokumentieren.
- In einer späteren Ausbaustufe zusätzlich Prüfsummen für die strukturierten Meldungsdaten erzeugen.
- Korrekturen sichtbar machen, statt frühere Angaben unbemerkt zu überschreiben.

## Grenzen

- Die Geräteuhr kann durch die Gerätehalterin oder den Gerätehalter verändert worden sein.
- EXIF-Daten und Standortangaben sind technische Indizien, keine unabhängige Bestätigung.
- Ein Foto aus der Mediathek kann keine EXIF-Aufnahmezeit enthalten; die App ersetzt diesen fehlenden Wert nicht durch die spätere Import- oder Meldezeit.
- Ein lokal berechneter Hash belegt nur dann etwas, wenn sein Erstellungszeitpunkt und seine Aufbewahrung nachvollziehbar sind.
- Versand per E-Mail ersetzt keinen vertrauenswürdigen Zeitstempel und keine qualifizierte elektronische Signatur.

Vor einem produktiven Einsatz sollte die konkrete Dokumentations- und Aufbewahrungskette mit der Hausverwaltung und deren Rechtsberatung abgestimmt werden.
