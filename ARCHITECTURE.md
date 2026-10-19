# Sidekick3 architecture

One page on how the addon fits together, for anyone changing it. What it does for players is in the [README](README.md); the UI contract is in [ui/README.md](ui/README.md); why it is built this way, and what's left to do, is in the [masterplan](docs/superpowers/plans/masterplan.md).

## Three layers, the UI only views

```
GAME (read)                    BRAIN (decide)                    HANDS (act)
core/game.lua   snapshot   ->  core/engine.lua  priority list -> QueueCommand, one per throttle
core/catalog    from DATs      behaviors/*.lua  want() -> intent   modifiers first (EXPECT)
core/packets    packet stores  jobs/*.lua       real state machines only
                                                                  UI: shows `view`, changes through `act`
```

- **The game is read, never guessed.** What an action costs, reaches and needs comes from the client DATs (`core/resources.lua`) and the server's learned lists (`HasSpell`, `HasAbility`). Only what an action is *for* is written by hand, once per family, in `core/knowledge.lua`. The client DAT wins over the server's SQL.
- **The engine decides from one snapshot alone.** `game.read` gathers everything a decision needs into a plain table (`g`), so tests hand the engine a fake one and no behavior touches `AshitaCore`.
- **Nothing writes settings from game state.** Settings change only when you change them: through a UI's `act` (`ui/model.lua`), a `/sk3` command, a profile load, or another session's remote call that `model.apply` accepts.

## One frame

`Sidekick3.lua` wires the events; everything it calls is a module below.

1. **`d3d_present`** → `refresh`: at most 10 times a second, `game.read` takes a new snapshot. Once the game is loaded it rebuilds the catalog when your jobs, levels or Blue Mage set change, loads the settings when the job pair changes, and updates AFK sleep (`core/afk.lua`).
2. **`tick`** on a new snapshot: `engine.cancel` (a status to cancel mid-cast, packet 0x0F1), then `engine.ready` (running, and past the throttle since the last send and the last action to finish) and `engine.decide`. The intent goes out with `QueueCommand`, and `engine.sent` and `game.sent` remember it. While the window is open it decides even when stopped, to show what it would do.
3. **`share.tick`** writes this session's file and reads the others' (boxing, `core/share.lua`).
4. **Draw**: `model.build(g, catalog, cfg, status)` makes the `view`, `model.actions` the `act`, and `ui.render(view, act)` draws them (`ui/window.lua`, or your `ui/custom.lua`). An error closes the UI instead of the game.
5. **Save** what the UI changed once no widget is held, so a dragged slider saves when let go.

**`packet_in`** goes to `core/packets.lua`, which feeds the cast lock and throttle, the packet-fed statuses (`core/buffs.lua`), learned heal potency (`core/observed.lua`), `/check` answers (`core/tracked.lua`) and the job modules' packets (rolls, songs, the automaton's name, the blue magic set). **`command`** handles `/sk3`.

## The decision

`engine.decide` checks the gates that stop everything once (loading, dead, mounted, safe zone, AFK asleep, incapacitated, casting, moving), then asks each behavior in `engine.BEHAVIORS`' order for an intent:

```lua
{ action = catalog record, target = unit or nil, why = 'Kupipi at 62%', mods = {...}, cancel = status id }
{ command = '/heal', action = { name = 'Rest' }, why = ... }   -- what isn't a spell or ability
{ hold = true }                                                 -- a cure nearly off recast: only `quick` behaviors may go first
```

The first intent wins. Shared rules live in `core/can.lua` (`can.use`, `can.reach`, `can.together`, `can.command`), so no behavior re-implements cost, recast, range or targeting. A modifier the intent lists (a stratagem, Pianissimo, Embolden, Snake Eye, Blaze of Glory, Entrust, Diffusion) or the action's `via` (Enlightenment, Unbridled Learning) goes first, alone; its status is then taken as on you for `engine.EXPECT` seconds, so the next decision sends the spell. Healing is the one behavior that scores rather than walks a list: every usable heal aimed at every reachable unit, ranked by band (critical, danger, efficient).

## The modules

| Where | What |
|---|---|
| `core/game.lua` | The snapshot: you, your party and trusts, tracked players, the alliance, as one list of units; battle target, pet, flags, charges |
| `core/resources.lua`, `core/catalog.lua` | The client's spells, abilities and statuses as plain tables, and the catalog: every action you can use now, each with its family's knowledge row |
| `core/knowledge.lua` | One row per spell family: its role (heal, remove, buff...), the status it gives or clears, potency, gates |
| `core/can.lua` | The rules every behavior shares |
| `core/engine.lua` | Gates, priority order, modifiers, the gather call, mid-cast cancels |
| `core/packets.lua`, `core/buffs.lua`, `core/observed.lua` | What only packets say: casts starting and finishing, statuses on units with no readable list, what your heals really did |
| `core/settings.lua`, `core/profiles.lua` | One file per job pair, rows keyed by family; named snapshots of it |
| `core/tracked.lua`, `core/share.lua` | Players outside your alliance; sessions on one PC (session files, auto-track, remote control) |
| `core/afk.lua`, `core/ammo.lua` | AFK sleep; equipping the ammo an action needs |
| `behaviors/*.lua` | One generic behavior each: heal, remove, wake, recover, pet (care and send), revive, buff, follow, rest |
| `jobs/*.lua` | Only where a job has a real state machine: `sch` stratagems, `cor` rolls, `geo` the luopan, `run` runes, `pup` maneuvers, `bst` Ready charges, `nin` tools and shadows, `blu` set spells, `dnc` stances, `brd` songs. The other jobs need no file |
| `ui/model.lua`, `ui/window.lua` | The `view` and `act` any UI is given (pure, tested); the standard UI that draws them (ImGui only, decides nothing) |
| `tools/dump.lua`, `tools/parity.lua` | `/sk3 dump` writes the DATs to `tests/data`; the parity check against v2's job files (deleted with v2) |

## Changing it

- **A spell family it doesn't automate** (`/sk3 catalog unknown` lists them): a row in `core/knowledge.lua`. Level, cost, range and targets come from the DATs; a test in `tests/catalog_test.lua`.
- **A new kind of action**: a behavior file returning intents, and its place in `engine.BEHAVIORS`. Read the snapshot, decide, return; keep state in `mem`, the engine's memory, never in the snapshot.
- **A job mechanic the generic roles can't carry**: a file in `jobs/`, called from the behavior or the snapshot that needs it.
- **Something new to show or set**: a field in `model.build` or a call in `model.actions`, documented in [ui/README.md](ui/README.md) in the same change, then drawn in `ui/window.lua`.

## Tests

`luajit tests/run.lua` runs every `tests/*_test.lua` with no game client: `tests/fake.lua` builds a real catalog from the dumped DATs in `tests/data` and fake snapshots shaped like `game.read`'s, and `tests/ui_window_test.lua` fakes ImGui. `luacheck .` must stay clean. Rerun `/sk3 dump` after a client update; `tools/parity.lua` (from a v2 checkout: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`) guards the catalog against v2's job files until cutover.
