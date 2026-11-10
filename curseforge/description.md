# CurseForge project page

Text to paste into the CurseForge project form. Not shipped with the addon.

## Project name

GrudgeForever

## Summary

Mark players you never want to group with again and enemies to kill on sight, get warned when they show up, and share both lists with your guild.

## Category

Chat & Communication (secondary: PvP)

## Description

**GrudgeForever** keeps two lists of players for World of Warcraft: Forever and warns you the moment one of them shows up.

- **Blacklist** for your own faction: players you never want to group with again.
- **KOS** for the enemy faction: players to attack on sight.

Every entry has a reason, and your guildmates who run GrudgeForever see your entries too. GrudgeForever only warns. It never declines invites, ignores or kicks anyone on its own.

### Features

- **Alerts** with banner, sound and a colored chat line:
  - own faction: when a listed player whispers you, invites you or is in your group
  - enemy faction: on sight via nameplate, target or mouseover
  - sound, icon and text per list, with a cooldown per player
- **Guild sync**: entries are shared with guildmates automatically, manually or not at all. Entries belong to the player, not to a single character.
- **Right-click menu** on target, party and raid frames, chat names and the guild roster to add, edit or mute players.
- **Tooltip** with the reason and who added the entry.
- **Ignore integration**: players you ignore are added to your Blacklist automatically.
- **Main window** (`/gf`) with search, filters and a guild tab that shows which members run the addon and which version.
- **Mute** other people's entries just for yourself, **adopt** them into your own list, **export and import** your own entries.
- **Minimap button**, which you can turn off in the settings.
- English and German.

### Commands

- `/gf` opens the main window
- `/gf add First Last reason` adds a player (without a name: your target)
- `/gf sync` syncs with your guild now
- `/gf config` opens the settings

### Good to know

- Turn on enemy nameplates (Ctrl+V) for reliable on-sight alerts.
- In instances the game hides player names from addons, so GrudgeForever cannot check them there.

Source code and issue tracker: https://github.com/git-flexi/grudge-forever
