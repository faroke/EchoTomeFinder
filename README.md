# EchoTomeFinder

A World of Warcraft 3.3.5 addon for **Project Ebonhold** (Rogue-Lite realm).

It spots the **Echo Tomes** in your bags and in group loot rolls, and tells you which of your characters still need them for one of their saved Echo builds.

## Features

- **Bag highlight**: tomes wanted by one of your builds get a pulsing border in your bags. Works with ElvUI bags and the default Blizzard bags.
- **Loot roll alert**: when a wanted tome shows up in a Need / Greed roll, you get a chat message, an on-screen warning and a sound, and its icon is highlighted. Works with ElvUI roll bars and the default Blizzard roll frames.
- **Multi-character**: every character records its builds when it logs in. Tomes wanted by your alts are highlighted too.
- **Stock across characters and banks**: every character also records the tomes in its bags and, each time you open it, in its bank. The window shows your whole stock: which character holds each tome, in bags or bank, and who wants it.
- **Your character first**: a tome wanted by the logged-in character gets a bright pulsing border and a star icon. A tome wanted only by your other characters gets a faint, still border, and only a chat line instead of the sound and on-screen warning.
- **Per-character colors**: the border uses the color of the first character who wants the tome (the logged-in one first). A small number shows how many characters want it. Colors default to class colors and can be changed.
- **Tooltip**: hovering a tome lists every character who wants it and the matching builds.
- **Window and minimap button**: click the book icon on the minimap (drag it to move it) to open a window with three tabs:
  - **Tomes**: every tome held by your characters (bags and banks), where it is and who wants it (shift-click links one in chat);
  - **Characters**: recorded characters, click a color square to change its color, or remove a character;
  - **Options**: sound, chat messages, other characters, Echo Wishlists, minimap button, language.
- Tomes a character has **already learned** are not counted for that character.

Builds come from the Echo Journal's **Loadouts** tab. By default only your saved builds (server snapshots) count. **Echo Wishlists** (designed builds) and the local loadout library can be included with the *Include Echo Wishlists* option; their names then show with a *(wishlist)* tag.

## Installation

1. Download the zip for your language from the [Releases](https://github.com/faroke/EchoTomeFinder/releases) page: `EchoTomeFinder-<version>-en.zip` (English) or `EchoTomeFinder-<version>-fr.zip` (French). You can switch language later with `/etf lang`.
2. Extract it into `Interface/AddOns/` of your Ebonhold client, so you get `Interface/AddOns/EchoTomeFinder/`.
3. Restart the game and enable **EchoTomeFinder** in the AddOns list.
4. Log in once on each character you want to track, so its builds and bags get recorded, and open its bank once so the bank is recorded too.

## Commands

| Command | Description |
|---|---|
| `/etf` | Open or close the window |
| `/etf list` | List your tomes (all characters, bags and banks) and who wants them in chat |
| `/etf chars` | List recorded characters, their color and last update |
| `/etf color <Name> <rrggbb>` | Set a character's color (`reset` restores the class color) |
| `/etf forget <Name>` | Remove a character (e.g. a deleted one) |
| `/etf alts` | Include or ignore other characters' builds |
| `/etf builds` | List the logged-in character's builds |
| `/etf sound` | Toggle the alert sound |
| `/etf wishlists` | Include or ignore Echo Wishlists (off by default) |
| `/etf classes` | Include local loadouts made for other classes |
| `/etf lang <en\|fr>` | Change the language (English or French) |

`/tomes` works as an alias for `/etf`.

## How it works

On Ebonhold, an Echo Tome item ID is the unlocked echo's spell ID plus 100000. The addon reads the echo data and the saved builds from the official `ProjectEbonhold` addon that ships with the client, and matches build echoes by spell ID or by name (the same echo can have several spell IDs, one per quality).

Settings and recorded characters are stored account-wide in `EchoTomeFinderDB`.

## Building

```
python build.py
```

Creates one zip per language in `dist/`. The builds only differ by their default language and the description shown in the AddOns list.

GitHub Actions runs the same build on every push (zips available as a workflow artifact). To publish a release, bump `## Version:` in `EchoTomeFinder.toc`, commit, then push a matching tag:

```
git tag v2.4.0
git push origin v2.4.0
```

The workflow checks that the tag matches the `.toc` version and publishes the release with both zips.

## License

[MIT](LICENSE)
