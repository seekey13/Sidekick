<div align="center">

# Sidekick

**Support-job automation for Ashita v4 on [CatsEyeXI](https://www.catseyexi.com/).**

Heals, cures, buffs, raises and recovers for you, your party, your alliance and anyone you track.

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Ashita v4](https://img.shields.io/badge/Ashita-v4-8a2be2.svg)
![Status](https://img.shields.io/badge/status-in%20development-orange.svg)

</div>

---

Sidekick v3 is a ground-up rewrite of Sidekick v2. Instead of hand-written job files, it reads your spells and abilities straight from the game client and server, so it knows exactly what your character can do at any level, on any job pair.

## Features

- **Urgency-based healing**: the most HP per MP when someone is hurt, the fastest cure when they're in danger, a boost (Divine Seal, Accession, Majesty) when they're critical. Weighs area cures and Regen against single-target, and learns what your cures actually heal.
- **Status removal**: -na spells, Erase, Esuna, waltzes and (opt-in) items, with per-player, per-debuff control.
- **Wake, raise and buff**: wakes sleepers, raises the KO'd and keeps up the buffs you choose on the targets you choose.
- **Recovery**: MP and TP through Convert, Devotion, Aspir, Chivalry, Meditate, resting and more.
- **Pet care**: Repair, Spirit Link, Reward, sending your pet in, and auto-equipping oils and pet food.
- **Follow, rest and AFK sleep**: follows a leader, rests when MP runs low, and pauses itself if the party goes quiet.
- **Alliance and tracked players**: looks after all three parties, plus players outside your alliance.
- **Multiboxing**: every Sidekick session on one PC sees the others (your alts) and can start, stop and configure them.
- **Profiles**: named settings snapshots per job pair (Dynamis, EXP...).
- **Japanese client support**: commands go out in Japanese and the whole UI can be shown in Japanese.

## Installation

1. Download or clone this repository into `Ashita/addons/sidekick`.
2. In game: `/addon load sidekick`
3. Configure with `/sk`, open the HUD with `/sk hud`, and press run on your card (or `/sk start`).

Automation starts **off** after a load; turn off **Always load stopped** (Sidekick Settings, UI / Log) to have it come back as you left it, running or stopped. **After zone stop** there stops it each time you zone, and keeps it off when you log in. Healing, removal, waking, raising, recovery and pet care are on by default; buffs, items, following and resting are opt-in. Following, once on, works with automation stopped too, and stays on through a load: it follows again at once.

> [!NOTE]
> v3 replaces Sidekick v2: both answer `/sk` and `/sidekick`, so don't load them together. Installing over v2? Delete its folder first (v2's `lib/` would otherwise stay behind). v2's settings in `config/addons/sidekick/` are left as they are and never read.

## Commands

`/sidekick` works anywhere `/sk` does (`/sidekick hud`, `/sidekick start`...).

| Command | Description |
| --- | --- |
| `/sk` | Open or close Sidekick Settings |
| `/sk hud` | Show or hide the HUD |
| `/sk alt` `[Name\|all]` | Open or close your alts' Sidekick Settings: the one named, or every alt's (closing them all while any is open) |
| `/sk alt start` \| `stop` `[Name\|all]` | Your alts' automation on/off: the one named, or every alt's |
| `/sk start` \| `stop` `[Name\|all]` | Automation on/off, for this or another session on this PC |
| `/sk toggle` | Automation on if it's off, off if it's on (this session only) |
| `/sk plan` | Show what it would do right now, without doing it |
| `/sk buff <spell> <targets>` | Keep a buff up (`me`, `p1`–`p5`, `b0`–`c5`, a tracked name); `off` to stop |
| `/sk focus <Name>` \| `off` | Heal this member first |
| `/sk follow` `[Name\|on\|off]` | Follow on or off (toggled with nothing after it); with a name, follow that leader: anyone in your party, alliance or tracked (a name not there yet is kept, with a warning). Follow goes on mounted, in town and while automation is stopped |
| `/sk rest` / `afk` `[on\|off]` | Rest when MP runs low / AFK sleep |
| `/sk track` / `untrack` `[Name]` | Look after a player outside your alliance |
| `/sk profile [Name]` | Load a profile, or list them |
| `/sk widget` | Toggle the compact status widget |
| `/sk catalog` | What it can automate for your job |
| `/sk help` | Full command list |

## Interface

- **HUD**: a card per party member and pet with HP/MP/TP bars, the alliance below, and a label showing the next action and who it's for. Target a player outside your alliance and an **Add Tracked** pill at your card tracks them in one click.
- **Widget**: a compact pill per character with run/stop and settings, handy beside another party list, and the same Add Tracked pill.
- **Sidekick Settings** (`/sk`, or the cog on your card or the widget): one page per behavior (Heal, Remove, Buff, Pet, Recover, Follow, AFK...), with on/off switches per section. Point at a spell or ability to limit it to **Combat** (only while there's a battle target, and a few seconds after) or **Idle** (only out of combat); the one picked stays shown beside its name. Some come that way already, like Berserk (Combat) or Spectral Jig and Sneak (Idle).

The UI is a single replaceable file; see [ui/README.md](ui/README.md) to build your own.

## Job logic

Every job gets healing, removal, buffs and recovery from what it knows. These jobs also have logic of their own.

<details>
<summary><b>Bard</b></summary>

Keeps the songs you pick up, as **Area** songs on everyone nearby or per-slot songs through Pianissimo. Tracks each song's age to re-sing the oldest first, re-sings before expiry with **Song Duration**, and handles Nightingale/Troubadour and optional Pianissimo fast casting.
</details>

<details>
<summary><b>Beastmaster</b></summary>

A rabbit's **Wild Carrot** joins your heals once two Ready charges are banked, used only when someone is in danger so chip damage leaves charges for attacks.
</details>

<details>
<summary><b>Blue Mage</b></summary>

Casts only the blue magic you have set. **Unbridled Learning** fires for the spells that need it, and a **Diffusion** chip spreads self-buffs to the party when they need it.
</details>

<details>
<summary><b>Corsair</b></summary>

Keeps your chosen rolls up and **Double-Ups** by your chosen risk, using Snake Eye and Fold to land lucky numbers and undo Busts. `/sk "Bolter's Roll"` rolls one on demand.
</details>

<details>
<summary><b>Dancer</b></summary>

Heals with waltzes, with free waltzes under **Trance**, and keeps sambas and Saber/Fan Dance up as buffs, working around the moves each one blocks. Uses No Foot Rise and Reverse Flourish to manage finishing moves.
</details>

<details>
<summary><b>Geomancer</b></summary>

Places your **Geo** luopan on the right target, or a debuff luopan on your battle target in combat, and recalls it with **Full Circle** when it's out of place. Supports Blaze of Glory, **Entrust**, and **Radial Arcana** for MP.
</details>

<details>
<summary><b>Ninja</b></summary>

Keeps **Utsusemi** shadows up with the tools you carry, and shows how many casts you have left. Can recast at one shadow, and equips shuriken for Sange.
</details>

<details>
<summary><b>Puppetmaster</b></summary>

Keeps your chosen **maneuvers** up while the automaton is out, skipping them under Overload. Equips the best oil for Repair and Maintenance.
</details>

<details>
<summary><b>Rune Fencer</b></summary>

Keeps your chosen **runes** up with separate sets for idle, **Vallation**, **Valiance** and **Pflug**, firing wards in combat. An **Embolden** chip boosts enhancing spells.
</details>

<details>
<summary><b>Scholar</b></summary>

Handles **Light/Dark Arts** and Addendum automatically, fires **stratagems** (Penury, Celerity, Perpetuance, Accession...) just before the spells you tag, and can save the last charge for emergency healing.
</details>

<details>
<summary><b>Other jobs</b></summary>

White Mage, Red Mage, Paladin, Summoner, Dragoon and the rest are handled by the shared engine: Divine Seal and Martyr, Convert, Majesty and Chivalry, Healing Ruby, Spirit Link and more, all read from the game.
</details>

## Configuration

Settings are saved per character and job pair in `config/addons/sidekick/<character>/`, profiles included. The HUD layout is shared across job pairs.

<details>
<summary><b>Japanese font on Ashita 4.16</b></summary>

Ashita 4.16 must load the Japanese font itself. Copy `meiryo.ttc` from `C:\Windows\Fonts` to `Ashita\resources\fonts\`, add this to your boot config, and restart the game:

```ini
[ashita.imgui.fonts]
font0.family = Agave
font0.size   = 18,24,32
font1.family = meiryo.ttc
font1.size   = 18
font1.is_jp  = true
```

Under VanaCore (ImGui 1.92) no setup is needed.
</details>

## Development

Requires `luajit` and `luacheck`.

```sh
luajit tests/run.lua   # unit tests (offline, no game needed)
luacheck .
```

See [docs/e2e.md](docs/e2e.md) for in-game end-to-end tests.

## License

Sidekick is released under the [GNU GPL v3 or later](LICENSE). Copyright © 2026 Seekey.

The UI kit (`ui/kit.lua`) and settings layout (`ui/window.lua`) are based on VanaCore's `/vana` window (Copyright © 2026 Vekien, GPL-3.0-or-later). Sidekick is not affiliated with or endorsed by VanaCore or Vekien. `tests/data/` is dumped from the game client and isn't covered by this license.
