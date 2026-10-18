# Sidekick v3 masterplan

First presented in chat on 2026-10-14. Updated 2026-10-18 to match the decisions and progress since then. Specs for single features live in [../specs/](../specs/) and refer back to the phases here.

## Status (2026-10-18)

| Phase | State |
|---|---|
| 0 | Done: `/sk3 dump` |
| 1 | Done: catalog and knowledge table, parity clean on 475 v2 entries |
| 2a | Done, untested in game: game snapshot (`/sk3 state`) |
| 2b | Done, untested in game: engine, heal/remove/buff/revive (`/sk3 plan`, `start`, `buff`, `focus`) |
| 2c | Done, untested in game: settings window (`ui/model.lua` pure, `ui/window.lua` thin) |
| 2d | Done, untested in game: healing overhaul (bands, area heals, Regen, boosts, learned potency); the in-game check of the area priors is left |
| 3a | Done (PR #3 with its review fixes), untested in game: wake, recover, pet care and pet send, follow, rest (`/sk3 follow`, `rest`) |
| 3b | Done, untested in game: items (status removal from your inventory, under Debuffs), tracked players (`/sk3 track`, players outside the party looked after with what reaches them) and the alliance (party slots 6-17, each party scored on its own by area heals; healing them opt-in) |
| UI | Done (PR #5), untested in game: the window became a HUD of the party's HP and MP (an arrow at the next action's member) plus SK Settings under collapsing headers; the display and size modes are gone, and `cfg.ui` is its own file shared by every job pair |
| 3c | Done: Hold-AOE gather done, untested in game (`buff.hold_aoe`: an area buff spell waits while a player in your party who lacks it is out of reach, and `/p Gather together for <spell>` goes out every 5s while it does); profiles done, untested in game (`core/profiles.lua`, Profiles in SK Settings, `/sk3 profile`); Japanese done, untested in game (names from the DATs' Japanese column, the setting shared by every job pair, a warning per name sent in English, `/sk3 buff` by Japanese name) |
| 4 | In progress: SCH done, untested in game (`jobs/sch.lua`: the stratagem charge pool, and stratagems as modifiers through the engine's modifier chain: chips on buff rows, Accession spreading a buff, Enlightenment for an Addendum spell); COR done, untested in game (`jobs/cor.lua`: two rolls kept up, the last Double-Upped by v2's risk rules from the totals in 0x028, Snake Eye as a modifier, Fold on a Bust); GEO done, untested in game (`jobs/geo.lua`: the luopan's slot, the Geo row's on its target and the Geo debuff's on your battle target in combat, Full Circle on drift and after combat, Blaze of Glory and Entrust as modifiers, Radial Arcana's sequence) |
| Boxing | In progress: HUD step done, untested in game (run and the cog moved from the title row onto your own card's HP bar; the HP % and MP % text gone from cards and alliance rows, kept in their tooltips); session files and auto-track done, untested in game (`core/share.lua`); remote control done, untested in game (a session's run icon and cog on its card in another, its SK Settings drawn there from the view it publishes, changes sent back as numbered `act` calls). Left: `/sk3 start|stop <name|all>`, docs |
| 5 | Not started |

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

The generic behaviors (one file each, about 50–300 lines): heal (single and area heals, Regen, emergencies), remove (spells and items), wake, revive, buff, recover, rest, follow, pet (care: heal and cleanse; send).

Behaviors that aren't a spell or ability (rest's `/heal`, follow's `/follow`) return the command itself. While you rest only the rest behavior runs, as in v2: it alone decides when to stand.

Healing (2d) is the one behavior that scores instead of following a list: every usable heal aimed at every reachable unit is a candidate covering the units in its area, and the band (critical, danger, efficient) picks who counts and how candidates rank. `core/observed.lua` learns each heal's real potency from 0x028 and tracks your ticking Regens, and the snapshot carries both, so the engine still decides from the snapshot alone. Healing fires Accession itself; the generic modifier chain is still for the rest.

### 5. Job modules, only where real state machines exist

`sch` (arts, stratagem charges), `brd` (song slots and timers, the hardest one), `cor` (double-up strategy, lucky table), `geo` (luopan, Full Circle, Entrust, Radial Arcana), `run` (runes), `pup` (maneuvers), `bst` (ready charges, ammo), `nin` (tools), `blu` (set-spell read), `dnc` (stance blocks).

WHM, PLD, RDM, WAR, MNK, THF, SAM, DRK, DRG, BLM and RNG need **no file at all**.

### 6. Settings: one schema, keyed by family

```lua
rows = { Cure = { on = true }, Protect = { on = true, pick = 'Protect IV', targets = { [0] = true, [1] = true } } }
```

- One file per job pair under `config/addons/sidekick3/<character>/`. The new folder means v2's files are never read.
- **No v2 migrator.** Everyone starts fresh on v3.
- The UI edits this table directly. Nothing mirrors it, and nothing writes it from game state.
- This removes `disabled_*`, `ungrouped_*`, the `party_buffs` sync and the zoning-wipe class of bug.
- `ui` (the HUD's sizes, opacity and lock) is the exception: one file, `ui.lua`, shared by every job pair.

### 7. UI generated from the catalog

- **Sections:** one per role present, under collapsing headers in SK Settings.
- **One row widget:** toggle, tier dropdown (when there is more than one tier), target chips (when not self-only), modifier chips (from the knowledge table).
- **Tooltips:** from the DAT descriptions.
- **The HUD:** the party's HP and MP bars, with an arrow at whoever the next action is for; its cog opens SK Settings, which fits itself to its contents.
- `ui/model.lua` builds the view and owns the only setting writers; `ui/window.lua` only draws it. A user's own `ui/custom.lua` replaces the window; [ui/README.md](../../../ui/README.md) is its contract.

## Features kept

Everything v2 does stays. The exceptions: the three display modes (headers/tabs/groups) and both window-size modes were dropped for the HUD (2026-10-16), and Multisend attack-range follow was dropped (2026-10-17); native follow stays. New coverage the DATs reveal is welcome (PLD gets Raise; v2 never offered it).

## Layout and size target

```
Sidekick3.lua  core/{game,buffs,packets,observed,can,catalog,knowledge,resources,engine,settings}.lua
behaviors/*.lua  jobs/{sch,brd,cor,geo,run,pup,bst,nin,blu,dnc}.lua  ui/{model,window}.lua  tests/  tools/
```

Target: 8k lines or less, a cut of about 70%. The architecture doc becomes one page. At the end of phase 2c the tracked code (without `tests/data`) is about 3.4k lines; after 2d, about 3.9k; after 3a and its review, about 4.75k; with 3b's items, about 4.9k (Lua only, as every count here); after the HUD, about 5.85k; with tracked players and their review, about 6.25k; with the alliance and its review, about 6.8k; with Hold-AOE gather, about 6.9k; with profiles, about 7.3k; with Japanese, about 7.5k; with SCH, about 7.9k; with COR, about 8.6k (past the target, with BRD and seven more modules to come); with GEO and its review, about 9.3k; with session files and auto-track, about 9.45k; with remote control, about 10.6k (counting every tracked Lua file but `tests/data`, tests included).

## Phases

| # | Deliverable | Exit check |
|---|---|---|
| 0 | `/sk3 dump` writes spell, ability and status data from the DATs into `tests/data`, replacing the SQL fixtures | Fixtures committed |
| 1 | **Parity oracle:** [tools/parity.lua](../../../tools/parity.lua) loads every old job file, runs the new catalog and knowledge table against the same fixture, and diffs name, level, cost, status, removes and role. Run from the v2 root: `cd ../Sidekick && luajit ../Sidekick3/tools/parity.lua`. Kept until cutover as a regression guard, then deleted with v2 | Zero diffs for all 22 jobs at levels 75/37 and a few low levels |
| 2a | Game snapshot: party, trusts, buffs, target, flags (`/sk3 state`) | Snapshot matches the game |
| 2b | Engine plus heal, remove, buff and revive (`/sk3 plan`, `start`, `buff`, `focus`) | WHM/RDM/PLD play-test |
| 2c | Settings window: generic rows, sections, display modes, window size | Play-test |
| 2d | Healing overhaul: candidates by band (Critical/Danger/Efficient), Regen as a heal-over-time candidate, learned potency from 0x028 | Spec approved, then play-test |
| 3a | The generic behaviors that need nothing new from the game but the ammo slot, the pet's statuses and when you last moved: wake, recover, pet care (heal, cleanse) and pet send, follow, rest | Fake-client scenario tests, then play-test |
| 3b | Items (status removal from the inventory), tracked targets, alliance (area heals then score per party) | Fake-client scenario tests |
| 3c | Hold-AOE gather, profiles, Japanese | Fake-client scenario tests |
| 4 | Job modules (BRD last, with the most time budgeted) | Per-job play-test against the README feature list |
| Boxing | Sessions on one PC see and control each other (below): 1. HUD icons onto the cards; 2. `core/share.lua`, session files and auto-track (v2's party_share, moved up from phase 5); 3. remote control: a session's run icon and SK Settings drawn on its card in another session; 4. `/sk3 start|stop <name|all>`, docs | Fake-client scenario tests, then play-test with two boxes |
| 5 | Panel, widget, docs, take over `/sk`, release | v2 frozen |

## Risks

- **CatsEyeXI changes the DATs don't show.** Covered for JAs, since `HasAbility` comes from the server. Spell levels and costs follow the client DAT by decision; server mismatches go to the CatsEyeXI devs.
- **`HasSpell` reads false while zoning.** The catalog only rebuilds from stable state and never touches settings.
- **Finding a buff's status by name.** Phase 1 verified every family.
- **Ammo the pet abilities need** (pet food for Reward, oils for Repair and Maintenance) is only checked in 3a: it's worn by hand until the BST and PUP modules equip it. CatsEyeXI's Reward takes pet food only, so v2's Pet Poultice (Regen) and Pet Roborant (Erase) rows are gone.
- **Statuses on trusts and your pet** come from packets: gains and enfeebles in 0x028 (area variants included), wear-offs in 0x029. A death clears statuses with no message, so a dead trust's or a gone pet's are forgotten.
- **Items** are named from the client's item resource, since `/item` needs its spelling (CatsEyeXI's custom items differ). What each medicine clears follows the server's item scripts: Panacea's list differs from v2's. The server drops a use of a locked or bazaar-priced stack with no reply, so an unanswered `/item` holds items back 4s; not counting such stacks waits on checking in game that Ashita's item flags show the lock.
- **Tracked players** (`core/tracked.lua`, session only as in v2) are units of kind `tracked`: the DAT's "ally" target bit (8) says what reaches outside the party (Cure, Protect, Haste, the -na spells, Raise; not Regen, Erase, Curaga), and the server's area effects land on the target's own party, so no area spell cast from you or a member counts them (a Cure aimed at them and spread by Majesty or Accession counts them alone; Accession is never fired for them). Only their HP % is readable: max HP comes from the level a `/check` gives (packet 0x0C9, matched by server id), as v2's average-HP table (a straight line), else your own, until party_share (phase 5) gives the real one; heals on them teach no potency. Decided 2026-10-16: healing ranks them by urgency alone, like members (not party first); a buff row's name key never applies while they're in your party. The `/check` tells them they were examined, as in v2.
- **The alliance** (party slots 6-17) are units of kind `alliance`, B0-B5 and C0-C5: their HP and MP read as a member's, their statuses from packets as a trust's (forgotten when they leave, so one back starts clean). They come after tracked players in the unit list, as in v2, and one the client isn't drawing is out of reach (any member's entity read needs it drawn). The DAT's ally bit says what reaches them, as for tracked players. An area effect lands on its target's party alone (server targetfind), so `can.together` scores each party on its own: Curaga, Esuna and Protectra from you never count them, and a Cure spread by Majesty or Accession aimed at one of them covers their party, so Accession may be fired for them (v2 did too). Healing them is opt-in (`heal.alliance`, off as in v2) but for the focus member; raising, waking, removal and buff chips need no switch. Decided 2026-10-17: with it on, healing ranks them by urgency alone, like members and tracked players; each can then be unticked under Heal (a line per party); the HUD shows them as thin HP rows under the cards, which the arrow can point at. A mob another party claimed has no client `<bt>`: as in v2, the nearest live mob within 21 yalms claimed by anyone in the alliance is the battle target (`claimed`, so commands aim at its server id), looked for at most every 0.5s; checking ClaimStatus in game is left.
- **Hold-AOE gather** (`buff.hold_aoe`, off by default as in v2) holds area buff spells only (Protectra, Shellra, bar-elements, songs; as v2, never a heal), within the 10 yalms buffs already count as near you. Only players in your party who lack it hold it: trusts follow, and the alliance and tracked players are never reached by your area spells. One not drawn holds it (fail closed, as v2); v2 also skipped a charmed member, which waits on reading charm. Blue magic the DAT gives an area (15) though it lands on you alone (Battery Charge, Occultation...) has `area = 0` in the knowledge table, so it's neither held nor recast for others. The held row is skipped and the rows after it still go. Decided 2026-10-17: the gather line (`buff.gather`, on) goes only when someone near you lacks it too, so a puller who stays away is waited for quietly (v2 asked only when you lacked it); a rest started while one is held keeps going as any rest does. It goes only while running, in Japanese on a Japanese client. Songs get it again when the BRD module takes them over (phase 4); rolls have it from the COR module.
- **Profiles** (as v2: named snapshots per job pair, the live settings staying the auto-saving working copy) live in the job pair's own file, so they need no key per job pair as v2's did: `profiles`, `profile` (the one loaded, `''` for Default) and `parked` (the working copy put aside by a load from Default, which Default restores). Kept out of every snapshot, as in v2: the HUD (`ui`), the Japanese client, following, the focus member, and, new, who healing skips (names, like the focus) and who Entrust goes on (GEO). A profile saved before a newer setting existed gets its default on load. Decided 2026-10-17: Save never lands on another profile's name, renaming or adding (v2's did, silently); only Save as replaces one. A name is drawn over a blank row, so one with `##` or `###` shows whole and keeps its own id.
- **Japanese** (`ui.japanese`, off, as v2's opt-in: Ashita's boot config doesn't reliably say the client's language) sends each name from the DAT's Japanese column (`.Name[2]`, already in the client's Shift-JIS) instead of v2's re-parsing of finished commands: `/ma`, `/ja`, `/pet` and `/item`, and the gather line. The setting is the install's, not a job's, so it lives in the shared `ui.lua` as v2's was global (a job pair's own from before is carried over when on and saved away on load). A name with no Japanese one goes in English, warned once a session per name, and is sent again each time it's picked, as v2 (decided 2026-10-17: not skipped, in case the client takes it); `/sk3 buff` takes a spell's Japanese name too. The HUD and SK Settings stay in English (as v2's panel). Phase 4's `/equip` (ammo) is to take the Japanese name the same way.
- **SCH** (`jobs/sch.lua`) holds the stratagem charge pool (timer 231 counts down to every charge back) and which spells each stratagem fits; the rest is the generic modifier chain. A modifier intent goes before its spell, alone, and its status is then taken as on you for 2s (`engine.EXPECT`) so the next decision sends the spell, which replaces v2's `pending_stratagem` lock (healing's own Accession and boosts are expected the same way; the expected statuses live in a copy of the snapshot for the decision, so the HUD and `/sk3 state` show only what the game says): a more urgent decision in between (a cure) takes the stratagem instead. A buff row's chips (`rows[key].mods`) turn them on: Penury and Celerity for white magic, Perpetuance for white enhancing, Parsimony and Alacrity for black, each needing its Arts (as v2). Accession on a row casts the spell on you to spread it to the row's targets in your party within 10 yalms, at twice the MP, and is held for the group like Protectra (a self-only row such as Stoneskin too: you and one far member lacking it hold it); what it spreads follows the server's AOE flag (v2's list). Decided 2026-10-17: it spreads whenever one of the row's targets near you lacks it, as v2. Enlightenment has no chip: an Addendum spell you lack the Addendum for is usable while Enlightenment is (`a.via`, under Dark Arts as v2) and the engine fires it first, for any behavior (revive, remove, buff, heal). Healing keeps firing Accession and Rapture itself. Decided 2026-10-17: Enlightenment only under Dark Arts, as v2; v2's charge reserve is ported, opt-in (`heal.reserve`, Keep a stratagem for healing under Heal, shown for a job with stratagems): buff rows (their stratagems and the Addendum rows) never spend the last charge, counted from the pool timer in the snapshot (`g.stratagems`).
- **COR** (`jobs/cor.lua`) ports v2's rolls: Roll 1 and Roll 2 (`cfg.roll.first`, `second`; the second on a COR main job only, as v2) are kept up on you, and the risk (`cfg.roll.risk`: lowest, medium, highest, v2's rules as `cor.decide`) says when to Double-Up. The totals come from your own 0x028 job ability packets (420/421 a roll, 424 a Double-Up, which names the roll doubled, 426/427 a Bust), the snapshot carrying the last (`g.roll`). Unlike v2, only the last roll rolled is ever doubled (the Double-Up Chance is its alone), a roll or Double-Up sent waits for its total and is left as it is if none comes in 5s (never doubled off a stale total), and a new roll waits until the last is settled, no total older than the last send is doubled, and resting waits while a Double-Up is due (`mem.busy_until`). A Bust takes a roll's place (a COR subjob, with one, then rolls none) until Fold, fired whenever it's ready, as v2. Snake Eye is a modifier: the Double-Up's intent lists it and the engine fires it first, so its status, read or expected, says the forced die is waiting (v2's armed flag). Double-Ups stay 6s apart (v2, proven in game), counted from the send and from the Double-Up's total, as v2 stamped both. Hold-AOE holds a roll as an area buff spell, within the DAT's area (8.4 yalms, v2 used 10); the Double-Ups are never held. Rows aren't used: Rolls (under Buff) picks each roll and the risk. Decided 2026-10-17: nothing rolls while you're Invisible (new: v2 rolled anyway, breaking it; buffs and pet abilities already wait); a roll is held within the DAT's area, not v2's 10 yalms (Luzaf's Ring would double it, so it may hold more than needed with one); no roll is picked at first (opt-in like buffs; v2 picked Corsair's and Ninja). `tools/parity.lua` checks every roll's status, lucky and unlucky against v2's.
- **GEO** (`jobs/geo.lua`) ports v2's luopan handling. The Geo- spells and the luopan's abilities (Full Circle, Blaze of Glory, Entrust) are their own role, `geo`, under **Geomancy** (under Buff, for a GEO main job, `cfg.geo`); Indi- spells on you stay buff rows. One luopan at a time, the snapshot's pet: its spell and who it went on are remembered from the send (`mem.geo`); one out after a reload is known only as up. The Geo row's luopan goes on the first of its targets (slot order) in reach who lacks its aura while the slot is free, waiting while they move (new: `u.moving`, any unit's position changed in the last 0.5s, as v2's sampling); Full Circle recalls it once they're past `geo.distance` (10, as v2) from it or gone, measured from the row's first target for one not sent here (a reload, or one that came while nothing decided: the snapshot's `pet.since` says when the pet was first seen), and it goes down again on the row's first target who lacks it. In combat the Geo debuff row's luopan goes on your battle target (waiting while it moves), Full Circle first taking the slot from any other while the debuff could follow (in range, off recast, not silenced; short of MP by no more than Full Circle's refund, taken as half the luopan's cost at its HP %, to check in game); it's recalled `geo.linger` seconds (5, v2's timer) after the last battle target, and a new one in that time keeps it. Blaze of Glory and Entrust are modifiers (`engine.EXPECT`), so Blaze of Glory goes only when the luopan can, as v2's precast; Entrust puts the Indi- picked on the member picked within 20 yalms whenever they lack its aura (v2 recast it on Entrust's recast alone). Radial Arcana is a recover row that `geo.arcana` drives, as v2: under the MP line, a luopan that's cheap (75 MP), nearly spent (5% HP) or a Geo-Voidance put down for it is spent once you're within 10 yalms; a dearer one (or one not sent here) is recalled when a Geo-Voidance can follow, which is put down on you, then spent, the sequence keeping the slot for 20s whatever the MP does (let go when Recover or the row is turned off); once Radial Arcana is sent, the luopan going is left alone. A spare Voidance left when it runs out is recalled for the Geo row. A luopan's auras end with it, with no message: the snapshot forgets them on trusts when it goes (v2). The Geo rows are opt-in like buffs (new: v2 cast the dearest Geo debuff in combat by default). `tools/parity.lua` checks v2's geo entries as the `geo` role. Decided 2026-10-17: a debuff takes the slot only while your MP and that refund cover it; a dear luopan is left as it is when no Geo-Voidance can follow (not spent at a loss); a luopan sent here that no longer fits the Geo row's pick or targets is recalled, so a settings change applies at once (new: v2 waited for it to go); who Entrust goes on stays out of profiles, as the focus member.
- **Boxing** (decided 2026-10-17): every Sidekick session on one PC (as v2's party_share: files under `config/addons/sidekick3/`, no network) publishes a session file (server id, name, jobs, running, real HP, MP and max HP, an `os.time()` heartbeat, stale after about 5s; and its SK Settings view while another session watches it) and reads the others'. It's symmetric: any session controls any other, "main" being the one you look at. Auto-track as v2: each session tracks the other session's whole party (trusts left out) when not in a party with it, with no `/check` (the level and max HP come from the file), and drops those `auto` entries when the file goes stale or lists them no more; hand-tracked players are never touched. Remote control sends `act` calls (numbered commands, applied by the target through its own `model.actions` and acknowledged in its file); the controller draws the target's own view, since only the target can build its catalog. Not sent: `act.close`, `act.log` and `ui.*` (the HUD is each box's), and track by target. Step 2 as built (`core/share.lua`): `session_<Name>.txt`, a version line, the heartbeat and running, then one line per player (you first, your party's players after, trusts left out): server id, jobs and levels, HP %, HP, max HP (0 until seen at full; yours from the client), MP % and MP, whether in the owner's zone, name; an `end` line last (a file without it was cut short). Players not filled in yet (no id or name) are left out. Written every second through a temp file, as v2, read and synced every second; a file caught mid-write keeps the last one read, and the heartbeat alone says a session is gone (a zone keeps the last roster written, so it isn't taken for one), and your file is deleted on unload. Anyone a live file lists is tracked as `auto` (its owner's name) unless in your party or alliance; what a file says (levels, max HP, HP % while your client doesn't draw them and they're in its owner's zone) fills in any tracked player it lists, hand-tracked too, and is cleared once no file lists them; a player several files list is taken from their own session's file, else the first owner by name; an auto entry dropped for joining your party or alliance keeps the statuses seen on them; and a hand track of one a file lists sends no `/check` (and finds them by name out of sight). Tracking one by hand makes them your own (never dropped); untracking an auto entry by hand declines them for the session, until tracked by hand again. Decided 2026-10-18: a loading session (a zone, the title screen after a logout) keeps its last roster up for 60s at most, then deletes its file; an auto entry no file lists is kept 15s before it's dropped (at once, statuses kept, when they join your party or alliance), so a hitch or a short roster doesn't forget a party's statuses; `/sk3 untrack all` declines the auto entries too and names them; writes stay every second, and a reader deletes a file no one has written for an hour (a crashed session's). Left to check in game: whether a minimized window keeps drawing frames, as the heartbeat comes from `d3d_present`. The HUD's run icon and cog sit on the HP bar of each card that is a session; the HP % and MP % text is gone (kept in tooltips), from alliance rows too. Step 3 as built (2026-10-18): the session file (version 2) also carries the load's epoch on its heartbeat line, a `watch <Name>` line per session whose SK Settings are open there, a `do <Name> <its epoch> <n> <call>` line per call not yet acknowledged, and an `ack <Sender> <their epoch> <n>` line per sender, the last call applied. A call is an `act` call packed as one line by `share.pack` (plain data, read back by a parser of its own, never run as Lua). The target applies each call once, in order, through its own `model.actions`, if `model.apply` lets it: not `close`, `log`, `watch`, `ui.*` or `japanese` (the HUD is each box's), not `track` with no name, and `set` only on a setting that exists, with a value of its type. A sender's reload (a new epoch) starts its numbering again; a target's reload drops the calls sent to its old epoch, never applied twice. A slider's drag sends its latest value only (consecutive `set`s of one path merge). The view goes in a file of its own, `view_<Name>.txt`, written while watched (`model.published`: without the HUD's pointer and sizes) and deleted when not; while one session watches or calls another, both publish and read every 0.25s instead of every second. The cards that get the icons are party members and tracked players (alliance rows are thin, so not them); a remote SK Settings window shows that session's job and Running/Stopped, and its UI / Log section only its recent actions. A remote `run` is printed in the target's chat. Review fixes (2026-10-18): `model.apply` checks every argument's type (optional ones too), `n` against them and passes only those; no number that isn't finite is packed or taken, and a `do` line that won't read is skipped rather than the whole file; a remote window that errors stops watching, so the HUD reopens; sessions are watched only while the HUD is open; a view file gone is forgotten, not shown as current, and one unchanged isn't parsed again; a target whose view fails says so once in its chat.
- **Bard song parity** is the largest unknown. Port the behavior, not the code: write the scenarios as tests first.
