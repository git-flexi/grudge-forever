# GrudgeForever

A grudge list for **World of Warcraft: Forever** that you share with your guild.

Mark players you never want to group with again (*Blacklist*, your own faction) or want to attack on sight (*KOS*, enemy faction). The marks are shared with guildmates who also run the addon, and GrudgeForever warns you when one of those players shows up. It only warns: it never declines invites, ignores or kicks anyone.

> [!WARNING]
> **Alpha.** The logic is covered by automated tests, but the addon has not been played in-game yet. Please report bugs together with the output of `/gf debug` (see *First in-game test* below).

🇩🇪 **Deutsche Anleitung:** ganz unten zum Aufklappen.

## 📦 Installation

1. Download the latest `GrudgeForever-<version>.zip` from [Releases](https://github.com/git-flexi/grudge-forever/releases).
2. Unzip it into the `_forever_/Interface/AddOns` folder of your WoW installation (not `_retail_` or `_classic_`), so that `_forever_/Interface/AddOns/GrudgeForever/GrudgeForever.toc` exists. Watch out for a doubled folder such as `AddOns/GrudgeForever-<version>/GrudgeForever/`: then the game does not list the addon.
3. Start the game and make sure GrudgeForever is enabled in the AddOns list.
4. Turn on **enemy nameplates** (`Ctrl+V`) — on-sight alerts rely on them. If they are off, GrudgeForever tells you once in chat.

## ⌨️ Commands

`/gf` or `/grudgeforever`:

| Command | What it does |
|---|---|
| `/gf` | Open or close the main window |
| `/gf add [First Last] [reason]` | Add a player. Without a name your target is used and its faction preselects the list. Opens the edit dialog. |
| `/gf remove [First Last]` | Delete your own entry (without a name: your target) |
| `/gf sync` | Sync with the guild now |
| `/gf export` | Show your own entries as text to copy |
| `/gf import` | Paste exported text |
| `/gf debug` | Toggle diagnostic mode (see below) |
| `/gf config` | Open the settings |

Always use first **and** last name — the full name is the list key. A reason can be at most 80 characters long.

## 🖱️ Right-click menu

Right-click a player (target frame, party/raid frames, chat names, guild roster) for **Add to GrudgeForever...**. For players already on a list you get **Edit GrudgeForever entry...** (your own entries) or **Mute** / **Unmute** (other people's entries). Muting only affects you and is not shared.

For a player of your own faction the dialog offers only the Blacklist. When you edit one of your entries, the dialog also has a **Delete** button.

When you ignore a player (right-click menu, `/ignore` or the friends window), GrudgeForever puts them on your Blacklist with the reason *IgnoreList Import* and tells you in chat. Players that are already on your Blacklist keep their entry. Your existing ignore list cannot be imported, because the game only shows Battle.net accounts there, not character names.

## 📋 Main window

Tabs **Own faction** (Blacklist) and **Enemy faction** (KOS). One row per player with reason, author, date and status; players listed by several people expand to show every entry. Filter **All entries** / **Only mine** and a name search. The gear button next to Export opens the settings.

A third tab, **Guild**, lists every guild member with online state, whether they run GrudgeForever, their addon version and when their addon last reported. Below the list you see how many members run the addon. GrudgeForever learns this from the short hello every copy sends on login, so members with sync set to *Manual* only show up after their own manual sync. Without a guild the tab is disabled.

Buttons: **Add**, **Edit**, **Delete** (own entries only), **Adopt** (copy someone else's entry into your own list) and **Adopt all from …**, **Export**, **Import**, **Sync now**.

## ⚙️ Settings

Game menu → Options → AddOns → GrudgeForever (or `/gf config`, or right-click the minimap button):

- **General:** sync mode (Automatic / Manual / Off), unlock and move the alert banner, reset its position, diagnostic mode, minimap button on/off
- **Per list:** enabled, sound (None, Raid warning, Minimap ping or any LibSharedMedia sound — with a **Preview** button), icon (skull, cross, exclamation mark or a custom texture path), message text with the placeholders `{list}` `{name}` `{reason}` `{by}` `{trigger}`, banner on/off, chat on/off (the chat line starts with a red WARNING and shows name, reason and creator in color), warning cooldown (default 300 s)

**When you get warned**

| List | Trigger |
|---|---|
| Blacklist (own faction) | the player whispers you, invites you, or is in your group |
| KOS (enemy faction) | the player is seen via nameplate, target or mouseover |

Each player warns at most once per cooldown; a group warning appears once per group.

## 🔄 Guild sync

- **Automatic:** syncs on guild activity, right after login, without you doing anything
- **Manual:** only via `/gf sync` or the **Sync now** button
- **Off:** no sync at all

**Sync now** has a 5-minute cooldown (the button shows the time left). Other clients also answer requests from the same sender at most every 5 minutes — that's on purpose, so nobody can flood the guild.

How entries are shared:

- Entries belong to a **player** (account), not a single character — you can edit them from any of your characters.
- Your own entries go to every guild you have a character in. A guild only ever learns about your characters that are in *that* guild, so your alts in other guilds stay private.
- When an author leaves the guild (none of their characters is in the roster any more), their entries disappear for everyone. Entries you adopted stay, because they are yours.
- Deleted entries are kept as tombstones for 90 days so the deletion can spread.

## 💾 Export / import

Only **your own** entries are exported (including adopted ones). Import adds them to your list: they belong to you afterwards, and the original author stays visible as the source. Good for backups and moving to another PC.

## 🧪 First in-game test: `/gf debug`

The game client wasn't available while developing, so the exact name format the game delivers still needs checking:

1. Type `/gf debug`. From now on the addon prints names from game events to chat: `[GrudgeForever debug] <event>: <name> -> <result>`.
2. Have someone whisper you, invite you to a group, join a group, target someone, or hover over players.
3. For each event check: does the name look like `First Last` (or `First-Last`)? Does the line end in `match` / `no match` (the name was evaluated) or `ignored` (the name couldn't be read)? An entry you added yourself must give `match` for that name.
4. Guild roster: once the roster has loaded you get `guild roster: X members, Y names read, first: ...`. X and Y should be equal. If they differ, or only secret/empty names show up, guild name detection doesn't work.
5. Send back the output (copy the chat lines), especially whisper, invite and the guild roster line.

Turn `/gf debug` off again afterwards.

## ⚠️ Known limitations

- **Instances:** player names are mostly hidden from addons there ("secret values"), so on-sight and tooltip detection works mainly in the open world.
- **Combat and boss encounters:** whisper senders are hidden, so no warning; addon messages are blocked, so sync waits.
- Sync only works with guildmates who have the addon installed and are online at the same time.
- Trial accounts can't send addon messages, so they can't sync.
- Same account on two PCs: changes made on both while offline are not merged — one PC may miss an edit (the guild still has it).
- Without a guild the lists work normally, just without sync.

## 🛠 Development

Requirements: LuaJIT, [busted](https://lunarmodules.github.io/busted/) and [luacheck](https://github.com/lunarmodules/luacheck) (e.g. via LuaRocks with `--lua-version=5.1`).

```bash
make test      # run the test suite
make lint      # luacheck
make package   # build dist/GrudgeForever-<version>.zip
```

Bundled libraries and their sources are listed in [`Libs/README.md`](Libs/README.md).

---

<details>
<summary><h2>🇩🇪 Deutsch</h2></summary>

Eine Grudge-Liste für **World of Warcraft: Forever**, die du mit deiner Gilde teilst.

Du markierst Spieler, mit denen du nie wieder spielen willst (*Blacklist*, eigene Fraktion) oder die du sofort angreifen willst (*KOS*, gegnerische Fraktion). Die Markierungen werden mit Gildenmitgliedern geteilt, die das Addon ebenfalls haben, und GrudgeForever warnt dich, sobald einer dieser Spieler auftaucht. Das Addon warnt nur: Es lehnt keine Einladungen ab, ignoriert niemanden und kickt niemanden.

> **Alpha:** Die Logik ist automatisch getestet, im Spiel aber noch nicht erprobt. Bitte Fehler zusammen mit der Ausgabe von `/gf debug` melden.

### 📦 Installation

1. Die neueste `GrudgeForever-<Version>.zip` unter [Releases](https://github.com/git-flexi/grudge-forever/releases) herunterladen.
2. In den Ordner `_forever_/Interface/AddOns` der WoW-Installation entpacken (nicht `_retail_` oder `_classic_`), sodass `_forever_/Interface/AddOns/GrudgeForever/GrudgeForever.toc` existiert. Achtung bei doppelten Ordnern wie `AddOns/GrudgeForever-<version>/GrudgeForever/`: Dann zeigt das Spiel das Addon nicht an.
3. Spiel starten und prüfen, dass GrudgeForever in der Addon-Liste aktiv ist.
4. **Feindliche Namensplaketten** einschalten (`Strg+V`) – die Sicht-Warnung braucht sie. Sind sie aus, weist GrudgeForever einmalig im Chat darauf hin.

### ⌨️ Befehle

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

Namen immer mit Vor- **und** Nachname angeben – der volle Name ist der Listen-Schlüssel. Der Grund darf höchstens 80 Zeichen lang sein.

### 🖱️ Rechtsklick-Menü

Im Rechtsklick-Menü eines Spielers (Zielrahmen, Gruppen-/Raidrahmen, Chatnamen, Gildenliste) gibt es **Zu GrudgeForever hinzufügen...**. Bei bereits gelisteten Spielern stattdessen **GrudgeForever-Eintrag bearbeiten...** (eigene Einträge) oder **Stumm schalten** / **Stumm aufheben** (Einträge anderer). Stummschalten gilt nur für dich und wird nicht geteilt.

Bei Spielern der eigenen Fraktion bietet der Dialog nur die Blacklist an. Beim Bearbeiten eines eigenen Eintrags gibt es im Dialog zusätzlich einen **Löschen**-Knopf.

Wenn du einen Spieler ignorierst (Rechtsklick-Menü, `/ignore` oder Freundesfenster), setzt GrudgeForever ihn mit dem Grund *IgnoreList Import* auf deine Blacklist und meldet das im Chat. Steht er schon auf deiner Blacklist, bleibt der Eintrag unverändert. Die bestehende Ignore-Liste lässt sich nicht übernehmen, weil das Spiel dort nur Battle.net-Konten zeigt, keine Charakternamen.

### 📋 Hauptfenster

Zwei Reiter: **Eigene Fraktion** (Blacklist) und **Gegnerische Fraktion** (KOS). Pro Spieler eine Zeile mit Grund, Ersteller, Datum und Status; steht ein Spieler bei mehreren Leuten auf der Liste, lässt sich die Zeile aufklappen. Filter **Alle Einträge** / **Nur meine** und eine Namenssuche. Das Zahnrad neben „Export“ öffnet die Einstellungen.

Ein dritter Reiter, **Gilde**, zeigt jedes Gildenmitglied mit Online-Status, ob es GrudgeForever nutzt, die Addon-Version und wann sich sein Addon zuletzt gemeldet hat. Unter der Liste steht, wie viele Mitglieder das Addon haben. GrudgeForever erfährt das aus der kurzen Begrüßung, die jedes Addon beim Einloggen schickt. Mitglieder mit Abgleich auf *Manuell* erscheinen deshalb erst nach ihrem eigenen manuellen Abgleich. Ohne Gilde ist der Reiter ausgegraut.

Buttons: **Hinzufügen**, **Bearbeiten**, **Löschen** (nur eigene Einträge), **Übernehmen** (Eintrag eines anderen in deinen Bestand kopieren) und **Alle von … übernehmen**, **Export**, **Import**, **Jetzt abgleichen**.

### ⚙️ Einstellungen

Spielmenü → Optionen → AddOns → GrudgeForever (oder `/gf config` oder Rechtsklick auf den Minimap-Button):

- **Allgemein:** Abgleich-Modus (Automatisch / Manuell / Aus), Banner entsperren und verschieben, Position zurücksetzen, Diagnosemodus, Minimap-Button an/aus
- **Pro Liste:** aktiviert, Sound (Kein Sound, Schlachtzugswarnung, Minimap-Ping oder jeder LibSharedMedia-Sound – mit **Vorschau**-Knopf), Symbol (Totenkopf, Kreuz, Ausrufezeichen oder eigener Texturpfad), Nachrichtentext mit den Platzhaltern `{liste}` `{name}` `{grund}` `{von}` `{anlass}`, Banner an/aus, Chat an/aus (die Chatzeile beginnt mit einem roten WARNUNG und zeigt Name, Grund und Ersteller farbig), Wartezeit zwischen Warnungen (Standard 300 s)

**Wann gewarnt wird**

| Liste | Anlass |
|---|---|
| Blacklist (eigene Fraktion) | der Spieler flüstert dir, lädt dich ein oder ist in deiner Gruppe |
| KOS (gegnerische Fraktion) | der Spieler ist in Sicht (Namensplakette, Ziel, Mouseover) |

Jeder Spieler warnt höchstens einmal pro Wartezeit; die Gruppenwarnung kommt einmal pro Gruppe.

### 🔄 Gildenabgleich

- **Automatisch:** Abgleich bei Gildenaktivität, direkt nach dem Login ohne dein Zutun
- **Manuell:** nur über `/gf sync` oder den Button **Jetzt abgleichen**
- **Aus:** kein Abgleich

**Jetzt abgleichen** hat eine Abklingzeit von 5 Minuten (der Button zeigt die Restzeit). Zusätzlich beantworten die anderen Addons Anfragen desselben Absenders höchstens alle 5 Minuten – das ist gewollt, damit niemand die Gilde fluten kann.

So werden Einträge geteilt:

- Einträge gehören einem **Spieler** (Account), nicht einem Charakter – du kannst sie mit jedem deiner Charaktere bearbeiten.
- Deine eigenen Einträge gehen in jede Gilde, in der du einen Charakter hast. Eine Gilde erfährt nur deine Charaktere, die in *dieser* Gilde sind – Twinks in anderen Gilden bleiben privat.
- Verlässt ein Ersteller die Gilde (kein Charakter von ihm mehr in der Gildenliste), verschwinden seine Einträge bei allen. Übernommene Einträge bleiben, denn sie gehören dir.
- Gelöschte Einträge bleiben 90 Tage als Grabstein erhalten, damit sich die Löschung verbreiten kann.

### 💾 Export / Import

Es werden nur **deine eigenen** Einträge exportiert (inkl. übernommener). Import fügt sie deinem Bestand hinzu: Sie gehören dann dir, der ursprüngliche Ersteller bleibt als Herkunft sichtbar. Taugt für Backup und Umzug auf einen anderen Rechner.

### 🧪 Erster Test im Spiel: `/gf debug`

Der Client war beim Entwickeln nicht verfügbar, daher ist offen, in welchem Format das Spiel Namen liefert. Das prüfst du so:

1. `/gf debug` eingeben. Ab jetzt schreibt das Addon die Namen aus Ereignissen in den Chat: `[GrudgeForever Diagnose] <Ereignis>: <Name> -> <Ergebnis>`.
2. Lass dir flüstern, lass dich in eine Gruppe einladen, tritt einer Gruppe bei, nimm jemanden ins Ziel oder fahr mit der Maus über Spieler.
3. Prüfe pro Ereignis: Sieht der Name aus wie `Vorname Nachname` (oder `Vorname-Nachname`)? Steht am Ende `match` bzw. `no match` (Name wurde ausgewertet) oder `ignored` (Name nicht auswertbar)? Ein Eintrag, den du selbst angelegt hast, muss bei seinem Namen `match` ergeben.
4. Gildenliste: Sobald sie geladen ist, kommt eine Zeile `Gildenliste: X Mitglieder, Y Namen gelesen, erste: ...`. X und Y sollten gleich sein. Weichen sie ab oder stehen nur geheime/leere Namen da, funktioniert die Namenserkennung für die Gilde nicht.
5. Gib die Ausgabe zurück (Chat-Zeilen kopieren), vor allem Whisper, Einladung und die Gildenlisten-Zeile.

Danach `/gf debug` wieder ausschalten.

### ⚠️ Bekannte Grenzen

- **Instanzen:** Spielernamen sind für Addons dort weitgehend geheim, Sicht- und Tooltip-Erkennung geht daher vor allem in der offenen Welt.
- **Kampf und Bossbegegnungen:** Whisper-Absender sind geheim, es kommt keine Warnung; Addon-Nachrichten sind gesperrt, der Abgleich wartet.
- Der Abgleich funktioniert nur mit Gildenmitgliedern, die das Addon installiert haben und gleichzeitig online sind.
- Testaccounts können keine Addon-Nachrichten senden, dort geht kein Abgleich.
- Derselbe Account auf zwei Rechnern: Änderungen, die du auf beiden offline machst, werden nicht zusammengeführt – einem Rechner kann eine Änderung fehlen (die Gilde hat sie trotzdem).
- Ohne Gilde funktionieren die Listen normal, nur ohne Abgleich.

### 🛠 Entwicklung

Voraussetzungen: LuaJIT, busted und luacheck (z. B. über LuaRocks mit `--lua-version=5.1`). Befehle: `make test`, `make lint`, `make package` (erzeugt `dist/GrudgeForever-<Version>.zip`). Die eingebetteten Bibliotheken und ihre Quellen stehen in [`Libs/README.md`](Libs/README.md).

</details>
