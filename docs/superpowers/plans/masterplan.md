# Sidekick v3 masterplan

First presented in chat on 2026-10-14. Updated 2026-10-15 to match the decisions and progress since then. Specs for single features live in [../specs/](../specs/) and refer back to the phases here.

## Status (2026-10-15)

| Phase | State |
|---|---|
| 0 | Done: `/sk3 dump` |
| 1 | Done: catalog and knowledge table, parity clean on 475 v2 entries |
| 2a | Done, untested in game: game snapshot (`/sk3 state`) |
| 2b | Done, untested in game: engine, heal/remove/buff/revive (`/sk3 plan`, `start`, `buff`, `focus`) |
| 2c | Done, untested in game: settings window (`ui/model.lua` pure, `ui/window.lua` thin) |
| 2d | Done, untested in game: [healing overhaul](../specs/2026-10-15-healing-design.md) (bands, area heals, Regen, boosts, learned potency); the in-game check of the area priors is left |
| 3–5 | Not started |

The dev command is `/sk3`, because v2 is still loaded and owns `/sk`. v3 takes `/sk` at cutover.

## Verdict

Keep the engine idea. Throw away the data model.

v2 is about 27k lines of Lua (jobs 8.1k, UI 6.3k, core 5.9k, actions 5.2k, main 1.4k), plus a 1,209-line ARCHITECTURE.md. Most of the weight comes from three root causes:

1. **The job files copy data the game already has.** There are 550 ability entries with about 10 fields each. Level, cost, spell_id, recast_id, range, element, magic type, "can target outside party" and "self only" are all in the client DATs, and the server-sent learned lists cover what the player has actually unlocked. 204 copies of `command = function(target) return '/ma "X" '..target end`. `tools/gen_resources.lua` exists only to test the copies against server SQL, which shows they drift.
2. **No single model of a "target".** Party, trusts, tracked targets, alliance and pet each get their own scan loop: 36 scan sites across the action modules ([heal.lua:167](../../../../Sidekick/lib/actions/heal.lua#L167), [heal.lua:193](../../../../Sidekick/lib/actions/heal.lua#L193)). The packet handler fans out through 4 parallel buff stores using repeated if-chains.
3. **Settings have two sources of truth.** The UI keeps shadow copies and re-syncs `disabled_*` from `party_buffs` every frame ([config.lua:953](../../../../Sidekick/lib/ui/config.lua#L953)). Action modules `require('lib.ui.config')` to read state ([buff.lua:843](../../../../Sidekick/lib/actions/buff.lua#L843), plus heal, geo, status_removal). The UI also writes settings based on game state, which is why the zoning bug wiped every cure.

Smaller issues:
- [common.lua](../../../../Sidekick/lib/core/common.lua) is a 4,072-line grab-bag.
- `buff.lua` (1.5k lines) has the Bard song logic inlined.
- [common.lua:2541](../../../../Sidekick/lib/core/common.lua#L2541) calls the command builder just to find out whether something is a spell.
- Japanese support re-parses finished command strings.
- Job-change detection is written twice ([Sidekick.lua:422](../../../../Sidekick/Sidekick.lua#L422) and [Sidekick.lua:559](../../../../Sidekick/Sidekick.lua#L559)).

**Worth keeping:** the fixed priority list, the cast lock from packet 0x028, throttling from the action-finish packet instead of from the send, the 10 Hz snapshot, and the fake-client test harness.

## Verified: what the game gives for free

From the install's SDK header [Ashita.h](../../../../../plugins/sdk/Ashita.h):

| Need | Source |
|---|---|
| Learned spells | `Player:HasSpell(id)` (from the server's 0x0AA list) |
| JA unlocked (covers level, merits and sub) | `Player:HasAbility(512+id)` (from the server's 0x0AC list) |
| Spell level per job | `ISpell.LevelRequired[24]` |
| MP, TP, recast, cast time | `ISpell.ManaCost / RecastDelay / CastTime`, `IAbility.TPCost / RecastTimerId` |
| Who it can target | `.Targets` flags: self-only, party, outside party, enemy, corpse |
| AoE, range, element, skill, type | `.AreaRange / Range / Element / Skill / Type` |
| Japanese name | `.Name[2]`, so `lang.lua` goes away |
| Tooltips | `.Description[]` |
| Status names | `GetString('buffs.names', id)` |

**What the DATs don't have:** what a spell *does*. That means which status it grants, which statuses a "-na" spell removes, heal potency, and the Corsair lucky/unlucky numbers. That knowledge goes into one small table keyed by spell family (Cure, not Cure IV) and not by job. A family is then the same for WHM, RDM, SCH and PLD.

## Architecture: three layers, the UI only views

```
GAME (read-only)          BRAIN (decide)               HANDS (act)
game.lua   snapshot   ->  engine.lua  priority loop -> QueueCommand, throttle
units[]    one list        behaviors/*  want()->intent           modifier chain
catalog    from DATs       jobs/*     real state machines only
buffs.lua  packet store                                  UI reads/writes settings only
```

### 1. Catalog, built from the game (replaces `lib/jobs/*`)

Rebuilt on job, level or 0x0AA/0x0AC change, and only when the player data is stable. It never writes settings.

```lua
for id = 1, 1023 do
    local s = res:GetSpellById(id)
    if s and me:HasSpell(id) and castable_now(s.LevelRequired, main, mlvl, sub, slvl) then
        add('ma', s)                       -- family/tier parsed from name: "Cure IV" -> Cure, 4
    end
end
for id = 512, 1023 do if me:HasAbility(id) then add('ja', res:GetAbilityById(id)) end end
```

Record: `{kind, id, en, jp, family, tier, mp, tp, recast, range, targets, area, skill, element, from='main'|'sub'}`. Families missing from the knowledge table are not automated. `/sk3 catalog unknown` lists them, so gaps are visible instead of silent.

### 2. Knowledge table (pure data)

```lua
Cure      = { role='heal', potency={30,90,200,400,700}, wakes=true },
Curaga    = { role='heal', potency={60,130,270,450}, wakes=true },   -- area from the DAT
Cursna    = { role='remove', removes=CURSE },
Protect   = { role='buff' },                         -- status found by name: "Protect" -> 40
Protectra = { role='buff', status='Protect' },
Barfira   = { role='buff', status='Barfire', pick_one='barelement' },
Raise     = { role='revive' },
['Divine Seal'] = { role='emergency' },
Accession = { role='emergency', boost={'healing', area=10, mp=2, tiers=4} },  -- healing fires it
Pianissimo= { role='modifier', applies=is_song },
```

**The client DAT is authoritative** for levels and costs, over CatsEyeXI's server SQL: the client blocks a cast by its own cost. No server-value overrides. Mismatches found so far (Arise, Geo-Haste, Triumphant Roar, Carcharian Verve) were reported to the CatsEyeXI devs as server bugs.

### 3. One unit model

`game.units` is a flat list: `{sid, tidx, name, kind, slot, hpp, mpp, tp, buffs=set, dist, alive}`.

Buffs come from the best source per kind, hidden behind one call:
- **You:** `GetBuffs`
- **Party PCs:** status icons (keep the existing 20-line memory read, since `GetStatusIcons` loses the high bits)
- **Trust, alliance, tracked, pet:** one packet-fed store

Behaviors filter the list (`units:where{hurt=75, reach=action}`) and never care where a unit came from.

### 4. Engine plus behaviors

```lua
if not g:can_act() then return end            -- dead/mount/cast/incap/throttle: one place
for _, b in ipairs(PRIORITY) do
    local intent = b.want(g, cfg)             -- {action, target, mods} | nil | {hold=true}
    if intent and intent.action then return send(plan(intent)) end
    if intent and intent.hold then hold = true end
end
```

`plan()` handles modifiers generically. If a modifier is wanted and its status isn't up, it sends the JA and sets a 2-second `expect = {status, action}` window. The next tick fires the spell.

That one mechanism replaces:
- the `pending_stratagem` lock
- the per-feature Nether Void, Diffusion, Embolden, Enlightenment, Unbridled Learning, Accession, Pianissimo and Entrust plumbing
- the 6 near-duplicate UI button renderers

The generic behaviors (one file each, about 50–300 lines): heal (single and area heals, Regen, emergencies), remove (spells and items), wake, revive, buff, recover, rest, follow, pet_heal, pet_send.

Healing (2d) is the one behavior that scores instead of following a list: every usable heal aimed at every reachable unit is a candidate covering the units in its area, and the band (critical, danger, efficient) picks who counts and how candidates rank. `core/observed.lua` learns each heal's real potency from 0x028 and tracks your ticking Regens, and the snapshot carries both, so the engine still decides from the snapshot alone. Healing fires Accession itself; the generic modifier chain is still for the rest.

### 5. Job modules, only where real state machines exist

`sch` (arts, stratagem charges), `brd` (song slots and timers, the hardest one), `cor` (double-up strategy, lucky table), `geo` (luopan, Full Circle, Entrust), `run` (runes), `pup` (maneuvers), `bst` (ready charges, ammo), `nin` (tools), `blu` (set-spell read), `dnc` (stance blocks).

WHM, PLD, RDM, WAR, MNK, THF, SAM, DRK, DRG, BLM and RNG need **no file at all**.

### 6. Settings: one schema, keyed by family

```lua
rows = { Cure = { on = true }, Protect = { on = true, pick = 'Protect IV', targets = { [0] = true, [1] = true } } }
```

- One file per job pair under `config/addons/sidekick3/<character>/`. The new folder means v2's files are never read.
- **No v2 migrator.** Everyone starts fresh on v3.
- The UI edits this table directly. Nothing mirrors it, and nothing writes it from game state.
- This removes `disabled_*`, `ungrouped_*`, the `party_buffs` sync and the zoning-wipe class of bug.
- Open question: `ui` (layout and size) is stored per job pair; it may belong in one global file.

### 7. UI generated from the catalog

- **Sections:** one per role present, shown as headers, tabs or pages.
- **One row widget:** toggle, tier dropdown (when there is more than one tier), target chips (when not self-only), modifier chips (from the knowledge table).
- **Tooltips:** from the DAT descriptions.
- **Window size:** auto-fit or custom (dragged).
- `ui/model.lua` builds the view and owns the only setting writers; `ui/window.lua` only draws it. A user-written UI can replace the window (`custom-ui` branch).

## Features kept

Everything v2 does stays, including the three display modes (headers/tabs/groups), Multisend attack-range follow alongside native follow, and both window-size modes. New coverage the DATs reveal is welcome (PLD gets Raise; v2 never offered it).

## Layout and size target

```
Sidekick3.lua  core/{game,buffs,packets,observed,can,catalog,knowledge,resources,engine,settings}.lua
behaviors/*.lua  jobs/{sch,brd,cor,geo,run,pup,bst,nin,blu,dnc}.lua  ui/{model,window}.lua  tests/  tools/
```

Target: 8k lines or less, a cut of about 70%. The architecture doc becomes one page. At the end of phase 2c the tracked code (without `tests/data`) is about 3.4k lines; after 2d, about 3.9k.

## Phases

| # | Deliverable | Exit check |
|---|---|---|
| 0 | `/sk3 dump` writes spell, ability and status data from the DATs into `tests/data`, replacing the SQL fixtures | Fixtures committed |
| 1 | **Parity oracle:** [tools/parity.lua](../../../tools/parity.lua) loads every old job file, runs the new catalog and knowledge table against the same fixture, and diffs name, level, cost, status, removes and role. Run from the v2 root: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`. Kept until cutover as a regression guard, then deleted with v2 | Zero diffs for all 22 jobs at levels 75/37 and a few low levels |
| 2a | Game snapshot: party, trusts, buffs, target, flags (`/sk3 state`) | Snapshot matches the game |
| 2b | Engine plus heal, remove, buff and revive (`/sk3 plan`, `start`, `buff`, `focus`) | WHM/RDM/PLD play-test |
| 2c | Settings window: generic rows, sections, display modes, window size | Play-test |
| 2d | Healing overhaul: candidates by band (Critical/Danger/Efficient), Regen as a heal-over-time candidate, learned potency from 0x028 | Spec approved, then play-test |
| 3 | The rest of the generic behaviors (wake, recover, rest, follow, items, pet_heal, pet_send), focus, tracked targets, alliance (area heals then score per party), hold-AOE gather, profiles, Japanese | Fake-client scenario tests |
| 4 | Job modules (BRD last, with the most time budgeted) | Per-job play-test against the README feature list |
| 5 | Panel, widget, party_share, docs, take over `/sk`, release | v2 frozen |

## Risks

- **CatsEyeXI changes the DATs don't show.** Covered for JAs, since `HasAbility` comes from the server. Spell levels and costs follow the client DAT by decision; server mismatches go to the CatsEyeXI devs.
- **`HasSpell` reads false while zoning.** The catalog only rebuilds from stable state and never touches settings.
- **Finding a buff's status by name.** Phase 1 verified every family.
- **Bard song parity** is the largest unknown. Port the behavior, not the code: write the scenarios as tests first.
