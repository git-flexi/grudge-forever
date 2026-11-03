# GrudgeForever

Addon für WoW: Forever. Du markierst Spieler, mit denen du nie wieder spielen willst (Blacklist, eigene Fraktion) oder die du sofort angreifen willst (KOS, gegnerische Fraktion). Die Markierungen werden mit Gildenmitgliedern geteilt, die das Addon ebenfalls haben. GrudgeForever warnt dich nur, es lehnt nichts ab, ignoriert niemanden und kickt niemanden.

## Installation

1. `make package` ausführen. Das erzeugt `dist/GrudgeForever-<Version>.zip`.
2. Die ZIP-Datei in den Ordner `Interface/AddOns` der WoW-Forever-Installation entpacken, sodass `Interface/AddOns/GrudgeForever/GrudgeForever.toc` existiert.
3. Der Ordnername der Forever-Installation kann anders heißen als bei Retail oder Classic. Suche den Ordner, der `Interface/AddOns` für Forever enthält (nicht den von Retail/Classic). Wenn dort schon andere Forever-Addons liegen, ist es der richtige.
4. Spiel starten. In der Addon-Liste muss GrudgeForever aktiv sein.

## Befehle

`/gf` oder `/grudgeforever`:

| Befehl | Wirkung |
|---|---|
| `/gf` | Hauptfenster öffnen oder schließen |
| `/gf add [Vorname Nachname] [Grund]` | Spieler hinzufügen. Ohne Namen wird dein Ziel genommen, seine Fraktion wählt die Liste vor. Es öffnet sich der Bearbeiten-Dialog. |
| `/gf remove [Vorname Nachname]` | Deinen eigenen Eintrag löschen (ohne Namen: dein Ziel) |
| `/gf sync` | Jetzt mit der Gilde abgleichen |
| `/gf export` | Eigene Einträge als Text zum Kopieren anzeigen |
| `/gf import` | Exportierten Text einfügen |
| `/gf debug` | Diagnosemodus an/aus (siehe unten) |
| `/gf config` | Einstellungen öffnen |

Namen immer mit Vor- und Nachname angeben (der volle Name ist der Listen-Schlüssel). Der Grund darf höchstens 80 Zeichen lang sein.

## Rechtsklick-Menü

Im Rechtsklick-Menü eines Spielers (Zielrahmen, Gruppe, Chat usw.) gibt es "Zu GrudgeForever hinzufügen...", bei bereits gelisteten Spielern "GrudgeForever-Eintrag bearbeiten..." sowie "Stumm schalten" / "Stumm aufheben" für Einträge anderer. Stummschalten gilt nur für dich und wird nicht geteilt.

## Hauptfenster

Zwei Reiter: "Eigene Fraktion" (Blacklist) und "Gegnerische Fraktion" (KOS). Pro Spieler eine Zeile mit Grund, Ersteller, Datum und Status. Filter "Alle Einträge" / "Nur meine". Buttons: Hinzufügen, Bearbeiten, Löschen, Übernehmen (Eintrag eines anderen in deinen Bestand kopieren, auch "Alle von X übernehmen"), Export, Import, "Jetzt abgleichen". Bearbeiten und Löschen kannst du nur deine eigenen Einträge.

## Einstellungen

Spiel-Menü, Einstellungen, Addons, GrudgeForever (oder `/gf config`). Dort:

- Abgleich-Modus: Automatisch, Manuell oder Aus
- Banner entsperren/verschieben und Position zurücksetzen
- Diagnosemodus
- Pro Liste: Aktiviert, Sound (inkl. "Kein Sound" und "Minimap-Ping", mit "Vorschau"-Knopf), Symbol, Nachrichtentext mit den Platzhaltern `{name}` `{grund}` `{von}` `{anlass}`, Banner an/aus, Chat an/aus, Wartezeit zwischen Warnungen (Standard 300 s)

## Gildenabgleich

- Automatisch: Abgleich bei Gildenaktivität, nach dem Login ohne dein Zutun.
- Manuell: nur über `/gf sync` oder den Button "Jetzt abgleichen".
- Aus: kein Abgleich.

"Jetzt abgleichen" hat eine Abklingzeit von 5 Minuten (der Button zeigt die Restzeit). Zusätzlich beantworten die Empfänger Abgleich-Anfragen desselben Absenders höchstens alle 5 Minuten. Das ist gewollt.

Verlässt ein Ersteller die Gilde (kein Charakter von ihm mehr in der Gildenliste), verschwinden seine Einträge bei allen. Übernommene Einträge bleiben. Einträge gehören einem Spieler (Account), nicht einem Charakter. Gelöschte Einträge bleiben 90 Tage als Grabstein erhalten, damit die Löschung sich verbreiten kann.

## Feindliche Namensplaketten

Die KOS-Warnung bei Sicht läuft über Namensplaketten, Ziel und Mouseover. Damit sie zuverlässig auslöst, müssen feindliche Namensplaketten im Spiel eingeschaltet sein. Sind sie aus, weist GrudgeForever einmalig im Chat darauf hin.

## Export / Import

Es werden nur deine eigenen Einträge exportiert (inkl. übernommener). Import fügt sie deinem Bestand hinzu, die Einträge gehören dann dir, der ursprüngliche Ersteller bleibt als Herkunft sichtbar. Taugt für Backup und Umzug auf einen anderen Rechner.

## Erster Test im Spiel: `/gf debug`

Der Client war beim Entwickeln nicht verfügbar, daher ist offen, in welchem Format das Spiel Namen liefert. Das prüfst du so:

1. `/gf debug` eingeben. Ab jetzt schreibt das Addon die Namen aus Ereignissen in den Chat (`[GrudgeForever Diagnose] <Ereignis>: <Name> -> <Ergebnis>`).
2. Lass dir flüstern, lass dich in eine Gruppe einladen, tritt einer Gruppe bei, nimm jemanden ins Ziel oder fahr mit der Maus über Spieler.
3. Prüfe pro Ereignis: Sieht der Name aus wie `Vorname Nachname` (oder `Vorname-Nachname`, evtl. mit Realm-Anhang)? Steht am Ende `match` bzw. `no match` (Name wurde ausgewertet) oder `ignored` (Name nicht auswertbar)? Ein Eintrag, den du selbst angelegt hast, muss bei seinem Namen `match` ergeben.
4. Gildenliste: Sobald die Gildenliste geladen ist, kommt eine Zeile `Gildenliste: X Mitglieder, Y Namen gelesen, erste: ...`. X und Y sollten gleich sein. Weichen sie ab oder stehen nur geheime/leere Namen da, funktioniert die Namenserkennung für die Gilde nicht.
5. Gib die Ausgabe zurück (Chat-Zeilen kopieren), vor allem Whisper, Einladung und die Gildenlisten-Zeile.

Danach `/gf debug` wieder ausschalten.

## Bekannte Grenzen

- Instanzen: Spielernamen sind für Addons dort weitgehend geheim. Sicht- und Tooltip-Erkennung geht daher vor allem in der offenen Welt.
- Kampf und Bossbegegnungen: Whisper-Absender sind geheim, es kommt keine Warnung. Addon-Nachrichten sind gesperrt, der Abgleich wartet.
- Der Abgleich funktioniert nur mit Gildenmitgliedern, die das Addon installiert haben und gleichzeitig online sind.
- Testaccounts können keine Addon-Nachrichten senden, dort geht kein Abgleich.
- Derselbe Account auf zwei Rechnern: Änderungen, die du auf beiden offline machst, werden nicht zusammengeführt.
- Ohne Gilde funktionieren die Listen normal, nur ohne Abgleich.
