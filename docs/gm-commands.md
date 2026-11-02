# GM commands for in-game tests

Researched on 2026-11-02 for [issue #56](https://github.com/seekey13/Sidekick3/issues/56): the commands a session needs to drive the dev server through the VanaCore MCP, setting up each scene a Sidekick3 test needs. On the dev server `Test` and `Dev` are GMs. [tools/gm.lua](../tools/gm.lua) sends these commands for you.

**The source is the server's own `scripts/commands/*.lua`** (the CatsEyeXI server, a LandSandBoat fork). The DSPT wiki's GM Commands page (archived 2026-03-26) dates from DSP and has drifted. Its `!addeffect` doesn't take a player's name. `!reset`, `!raise`, `!immortal`, `!geteffects` and `!deleffect` aren't there at all. Each command's file says its GM level (`cmdprops.permission`), its arguments and whom it acts on, and the notes below come from reading them.

## How the server takes a command

- **A chat line starting with `!`, in any chat mode.** The server reads it before anyone hears it. A GM's `!` line is never sent on as chat, even a mistyped one (`src/map/packets/c2s/0x0b5_chat_std.cpp`). Commands don't work from jail.
- **Typed lines are rate-limited by the client, packets aren't.** The client's chat box drops a line sent within about 1.5 s of the last ("...A command error occurred."), and shows your own line in your chat log. `tools/gm.lua` doesn't type: it injects the say packet (0x0B5) itself, so a scene's lines go out together, in one frame if need be.
- **Failures are silent.** If a command doesn't exist, or is above your GM level, you get no answer: only the server's log notes it. Many commands that work say nothing either, such as `!hp` on yourself or `!deleffect` on yourself. So a test checks the result, not the chat.
- **Arguments split on spaces, and numbers are read with `atoi`.** A word that isn't a number becomes 0, so `!hp abc Test` sets Test's HP to 0. A command whose one argument is text takes the rest of the line (`!exec`, `!immortal`).
- **128 bytes a line.** That is the packet's `Str[128]`. `tools/gm.lua` keeps lines to 120 bytes.
- **GM levels.** Level 1 covers nearly everything a test needs. `!getenmity` needs 2, `!stun` 3 and `!exec` 4. Level 5 holds the server-wide commands under Never send. `gm.probe()` tells you yours.

## Whom a command acts on

| Rule | Commands |
|---|---|
| A name; else your cursor target unless it's an NPC (so a player **or a mob**); else you | `hp`, `mp`, `tp`, `immortal`; `geteffects` also takes a mob's id |
| A name; else your cursor target if it's a player; else you | `checkvar`, `setskill` |
| A name, else your cursor target unless it's an NPC; never you by default | `setmod` |
| A name, else you | `addeffect`, `deleffect`, `raise`, `reset`, `setplayerlevel`, `homepoint`, `addspell`, `addallspells`, `addalltrusts`, `delitem`, `pos`, `masterjob`, `release` |
| A name only | `goto`, `bring`, `giveitem` |
| You only | `changejob`, `changesjob`, `godmode`, `additem`, `capallskills`, `speed`, `zone`, `where` |
| Your cursor only | `stun` (a player or a mob), `setmoblevel`, `getenmity` (a mob), `getid`, `getstats` |
| A mob's id, else your cursor's mob | `despawnmob`, `mobhere`, `getmobaction`, `mobskill` |

Names match in any case (`strcmpi`), and the player can be in any zone.

**The cursor race.** `/target` doesn't tell the server your target. The server takes it from your position packet (0x015, `facetarget` at byte 0x16), which goes out a few times a second. So `/target Tracked` followed at once by `!hp 0` sets the HP of whoever the server last heard you target, and that's you when nothing was. Therefore:

- Always name the player, yourself included: `!hp 0 Tracked`. `tools/gm.lua` always does.
- A mob has no name the server looks up. `gm.mob_hp` and `gm.mob_level` read the target index in your last 0x015, and go only once the server has the mob as your target (`gm.cursor().ready`).
- `!hp 0 <t>` also works for a player: the client writes the target's name into the line as it sends it.

## The commands a Sidekick3 test needs

Columns: the line, its GM level, then notes, with the `tools/gm.lua` call in bold.

**Vitals and death**

| Line | GM | Notes |
|---|---|---|
| `!hp <n> [name]`, `!mp`, `!tp` | 1 | Sets the amount outright, and more than the max gives the max. Does nothing to a dead player ("X is currently dead"). `!hp 0` kills. `!tp` sets their pet's TP too. **`gm.hp`, `mp`, `tp`, `kill`, `full`, `hp_pct`, `mp_pct`** |
| `!raise [1-3] [name]` | 1 | The raise menu, on a dead player only, who still has to take it. **`gm.raise`** |
| `!immortal [name]` | 1 | A toggle: HP never falls below 1. For a punching bag that still takes damage to heal. Its state is the char var `Immortal` (`!checkvar <name> Immortal`). **`gm.immortal`** |
| `!godmode [1]` | 1 | You only. Invincible, Perfect Dodge, Regen, Refresh and +1000% HP, which leaves nothing to heal, so keep it out of heal tests. Tier 1 is Regen, Refresh, Regain, Chainspell and Manafont. |
| `!homepoint [name]` | 1 | Sends them to their home point. **`gm.homepoint`** |

**Statuses**

| Line | GM | Notes |
|---|---|---|
| `!addeffect [name] <status> [power] [seconds]` | 1 | Given straight: no resist, no immunity. The status is its id or its `xi.effect` name (`POISON`, `SLEEP_I`). Power defaults to 1 and the time to 60 s. The area sees "gains the effect of". Trusts and mobs can't be named here; use `!exec` on your cursor's `target`. **`gm.effect`** |
| `!deleffect [name] <status>` | 1 | **With a name, the status must be its id.** It's read with `atoi`, so a status name becomes 0, which the server takes as 1 (Weakness). **`gm.uneffect`**, which always sends ids |
| `!geteffects [name or id]` | 0 | The server's own list of statuses, with each one's power, time left and flags (Song, Roll, Dispelable). Check what Sidekick3 reads against this. Refused for the dead. **`gm.effects`** |

`gm.EFFECTS` holds the status ids by their server names, lower case: what Sidekick3 removes, wakes from and keeps up.

**Recasts**

| Line | GM | Notes |
|---|---|---|
| `!reset [name]` | 1 | Sets their job ability and spell recasts to 0. It then clears **the sender's** debuffs, whoever you named: the erasable ones, plus Sleep, Silence, Paralysis, Poison, Doom, Curse and the others it lists. Don't send it from a character carrying a debuff the test needs. **`gm.reset`** |

**Jobs, levels and spells**

| Line | GM | Notes |
|---|---|---|
| `!changejob <job> [level]`, `!changesjob <job> [level]` | 1 | You only. The job by abbreviation or id. The server holds the sub job to its level cap. Sidekick3 rebuilds its catalog on the change. **`gm.job`**. For another player's job, run it on their own game, or use **`gm.job_of`** (`!exec`, GM 4). |
| `!setplayerlevel [name] <level>` | 1 | Their main job's level. **`gm.level`** |
| `!addallspells [name]`, `!addalltrusts [name]`, `!addspell <id> [name]` | 1 | Sidekick3 only offers the spells the client says are known (`HasSpell`). **`gm.spells`, `trusts`, `spell`** |
| `!capallskills` | 1 | You only. Caps every skill. |

**Moving people**

| Line | GM | Notes |
|---|---|---|
| `!bring <name>`, `!goto <name>` | 1 | Them to you, or you to them: same zone and spot. For follow, distance and range tests. **`gm.bring`, `go`** |
| `!pos [x y z [zone]] [name]` | 1 | With no coordinates, it prints their position. **`gm.pos`** |
| `!zone <id>` | 1 | You only. Ids are in `xi.zone` (`scripts/enum/zone.lua`). Zoning exercises Sidekick3's zoning hold. **`gm.zone`** |
| `!where` | 1 | Prints your position. |

**Items**

| Line | GM | Notes |
|---|---|---|
| `!additem <id> [qty]` | 1 | Into your own inventory; the id or the item's exact name. For item removal: Antidote 4148, Eye Drops 4150, Echo Drops 4151, Holy Water 4154, Remedy 4155 (`core/knowledge.lua`). **`gm.item`** |
| `!giveitem <name> <id> [qty]` | 1 | Into theirs. The server says when it's full. **`gm.give`** |
| `!delitem <id> [name]` | 1 | Takes one. |

**Mobs**

A mob's server id comes from the MCP's `entities` or `gm.mob(name).id` once it has spawned, and from the server's `sql/mob_spawn_points.sql` otherwise.

| Line | GM | Notes |
|---|---|---|
| `!spawnmob <id>` | 1 | Spawns it at its own spawn point. **`gm.spawn`** |
| `!mobhere [id]` | 1 | Spawns it if needed, then moves it to you. **`gm.mobhere`** |
| `!despawnmob [id]` | 1 | **`gm.despawn`** |
| `!hp <n>` with a mob targeted and no name | 1 | 0 kills it. **`gm.mob_hp`** |
| `!setmoblevel <level>` | 1 | Level 1 makes a harmless mob to claim for combat tests. **`gm.mob_level`** |
| `!getid` | 1 | Prints your target's server id. |
| `!getenmity` | 2 | Prints your target mob's enmity toward you (cumulative and volatile). |
| `!stun` | 3 | A toggle: an hour of Stun on your target, a player or a mob. |

**Server Lua**

| Line | GM | Notes |
|---|---|---|
| `!exec <lua>` | 4 | `player` (you) and `target` (your cursor's) are defined. One line, within 120 bytes, with no `<t>` in it, since the client would replace it. **`gm.exec`** |

## Never send

These are level 5 or disruptive, and `tools/gm.lua` sends none of them:

- `!crash` brings the map server down.
- `!sleep` stalls the server for a second.
- `!gc_full`, `!gc_step` and `!reload*` act on the whole server.
- `!addtime` changes the server's clock, and `!promote` changes GM levels.
- `!packetmod`, `!jail`, `!logoff`, `!delallinventory`, `!delcontaineritems`, `!rename`, `!racechange` and `!breaklinkshell` change or remove characters and their things.
- `!provokeall` puts every mob in the zone onto you at 3000 TP.

## tools/gm.lua

```
lua  addon = "Sidekick3"  code = "return require('tools.gm').hp_pct('Test', 40)"
```

It runs in Sidekick3's own state, which the MCP's `lua` tool reaches by the addon's name. Nothing in Sidekick3 loads it. Each call:
- returns the line or lines it sent;
- on a bad argument, raises an error before anything goes out;
- names the player in every line, with `'me'` meaning you.

- **Vitals:** `hp(who, n)`, `mp`, `tp`, `kill(who)`, `full(who)`, `hp_pct(who, %)`, `mp_pct`, `raise(who, tier)`, `immortal(who)`
- **Statuses:** `effect(who, status, power, seconds)`, `uneffect(who, status)`, `effects(who)`
- **Recasts, jobs and spells:** `reset(who)`, `job(main, lv, sub, sub_lv)`, `job_of(who, ...)`, `level(who, lv)`, `spells(who)`, `trusts(who)`, `spell(who, id)`
- **Items and moving:** `item(id, qty)`, `give(who, id, qty)`, `bring(who)`, `go(who)`, `zone(id)`, `homepoint(who)`, `pos(who, x, y, z, zone)`
- **Mobs:** `spawn(id)`, `mobhere(id)`, `despawn(id)`, `target(name or index)`, `cursor()`, `mob_hp(n)`, `mob_level(lv)`
- **Reading:** `me()`, `who(name)` (HP, MP and TP of a party or alliance member in points and %, or a nearby player's HP %), `mob(name)` (the nearest live mob of that name)
- **Server Lua and level:** `exec(code)`, `probe()`

`hp_pct` and `mp_pct` work from what the client reads. Yours are exact. A member's max is HP ÷ HP %, which is exact only at full. So call `gm.full` first, and `hp_pct` a moment later in a separate call, once the client has the server's answer. For a player outside your alliance, whose HP the client shows only as a %, they set it on the server from its own max, through `!exec` (GM 4).

## Setting a scene

These parts of a test aren't GM commands:

- **Which game is which.** Each game runs its own MCP server, on port 47800 or the next free port, and `game_state` names its character. A GM command from either GM's game reaches any player by name. `gm.job` and `gm.item` act only on the game that sends them.
- **The party.** Run `/pcmd add <name>` on the leader's game and `/join` on theirs; `/pcmd leave` to go. Use `run_command` for both. For trusts, run `/ma "Trust: <name>" <me>` after `gm.trusts`.
- **Sidekick3.** `/sk3 start` and `stop`, `/sk3 buff ...`, `/sk3 track <name>` and `/sk3 rest on` set it up. `/sk3 plan` says what it would do now, `/sk3 state` says what it reads, and `/sk3 log` prints each send. Their answers come back in `run_command`'s result.
- **Results.** Read them from:
  - `game_state` (HP, MP and statuses), `gm.who`, and `gm.effects` (the server's list);
  - `packets` (0x028: a cast's begin and finish);
  - `chat_log` (the server's replies).

  A spell's result line in the chat comes about 5 s after its finish packet, so never time anything from the chat.

`tools/e2e.lua` runs most of these as scenarios, with their cleanup ([e2e.md](e2e.md)). Item removal, combat and zoning have no scenario yet.

| Check | Scene | Expect |
|---|---|---|
| Heal band | `gm.full('Test')`, then a moment later `gm.hp_pct('Test', 40)` | A Cure on Test, and Test's HP back up |
| Death and Raise | `gm.kill('Test')` | A Raise on Test (Test's game takes the menu) |
| A -na spell | `gm.effect('Test', 'poison', 10, 120)` | Poisona, then `gm.effects('Test')` without Poison |
| Doom | `gm.effect('Test', 'doom', 1, 30)` | Cursna, whatever the Debuff switches say |
| Wake | `gm.effect('Test', 'sleep', 1, 60)` | A heal that wakes (Cure, Curaga) on Test |
| Buff upkeep | `/sk3 buff Protect p1` until it lands, then `gm.uneffect('Test', 'protect')` | Protect on Test again |
| Rest | `/sk3 rest on`, then `gm.mp_pct('me', 10)` out of combat, standing still | `/heal on` after 5 quiet seconds |
| Item removal | `gm.item(4151, 3)`, then `gm.effect('me', 'silence', 1, 120)` | Echo Drops on you |
| A tracked player | Test out of the party, `/sk3 track Test`, `gm.hp('Test', <points>)` | A Cure on Test |
| Combat | `gm.mobhere(id)`, `gm.target('<mob>')`, `gm.mob_level(1)`, then engage | The combat-gated actions |
| Zoning | `gm.zone(id)` | The zoning hold, then everything resumes |

**Afterwards:**
- `gm.full` everyone;
- `gm.uneffect` what was added;
- turn `gm.immortal` off (`!checkvar <name> Immortal` says whether it's on);
- `gm.despawn` the mobs;
- `/sk3 stop`.

## Checked in game

On 2026-11-02, through the MCP on `Dev`:

- `Dev` is GM level 4 or more: `gm.probe()` got both answers.
- `vana.game.set_target` works from Sidekick3's state. After `gm.target('Tracked')`, `gm.cursor().ready` turned true within a second: VanaCore raises Ashita's `packet_out` for 0x015, and the target index is at 0x16.
- Typed `/say !...` lines fail within about 1.5 s of each other; injected 0x0B5 packets don't, three in one frame.
- The exact `!exec` fallback set Tracked's HP from their server max.
- `!hp 0 Test` killed Test. `!homepoint Test` then revived Test at their home point, at full HP and MP (`charutils::HomePoint(PChar, PChar->isDead())`), and `!bring Test` brought them back. That's how a scenario's cleanup revives a character whose game has no MCP of its own to take the raise menu (0x01A, action 0x0D).

Still open:

- Whether `!hp 0` kills a player under `!immortal` (`setHP` sets 0 outright).
