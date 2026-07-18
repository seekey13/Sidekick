# Sidekick Architecture

Technical overview of the Sidekick support-automation addon for Ashita v4 (CatsEyeXI).

## Design Philosophy

1. **Support-Only Focus** – Healing, buffing, debuff removal, and resource recovery. No offensive automation.
2. **Configuration over Code** – Job-specific details are data-driven tables, not hard-coded logic.
3. **Extensibility** – New jobs/actions can be added without touching core modules.
4. **DRY Utilities** – Shared helpers (`action_core`, `common`) eliminate boilerplate.
5. **Safety** – Multiple validation layers (resource, cooldown, status ailment, range) prevent errors.

---

## Directory Layout

```
Sidekick.lua                   Main addon entry point
lib/
  core/
    action_core.lua         Shared ability infrastructure (resource, cooldowns, buff-ID utils, candidacy helpers)
    afk.lua                 AFK Sleep dead-man's switch (gates the tick after a stillness timeout)
    automation.lua          Priority-based action selection engine
    common.lua              Shared utilities (logging, party, buffs, commands)
    parse_packets.lua       Raw-packet parsing (action packet 0x028)
    targets.lua             FFXI target-resolution helpers (from Ashita)
  actions/
    buff.lua                Buff maintenance (self + party, groups, Pianissimo)
    follow.lua              Opt-in leader following (/follow past follow_distance)
    geo.lua                 Full Circle automation & Entrust management
    heal.lua                All healing (single-target, AOE, pet)
    item.lua                Consumable-based status removal (Antidote, Eye/Echo Drops, Holy/Hallowed Water, Remedy, Panacea, Remedy Ointment, Tincture)
    recover.lua             MP/TP recovery abilities
    rest.lua                Automatic resting (/heal) with follow-target awareness
    revive.lua              Raise dead party/tracked/alliance members
    status_removal.lua      Debuff removal & sleep wake (single + AOE)
  jobs/
    bard.lua                BRD job definition
    beastmaster.lua         BST job definition (pet-only)
    black_mage.lua          BLM job definition (self-only)
    blue_mage.lua           BLU job definition
    dancer.lua              DNC job definition
    dark_knight.lua         DRK job definition (self-only)
    dragoon.lua             DRG job definition
    geomancer.lua           GEO job definition
    monk.lua                MNK job definition (self-only)
    ninja.lua               NIN job definition (self-only)
    paladin.lua             PLD job definition
    puppetmaster.lua        PUP job definition (pet-only)
    ranger.lua              RNG job definition (self-only)
    red_mage.lua            RDM job definition
    rune_fencer.lua         RUN job definition
    samurai.lua             SAM job definition (self-only)
    scholar.lua             SCH job definition
    summoner.lua            SMN job definition
    thief.lua               THF job definition (self-only)
    warrior.lua             WAR job definition (self-only)
    white_mage.lua          WHM job definition
  ui/
    components.lua          Reusable imgui components & constants
    config.lua              Configuration window orchestration
    panel.lua               Debug info panel
    tooltips.lua            Contextual hover-help text for config UI
```

---

## Component Architecture

```
┌───────────────────────────────────────────────┐
│  Sidekick.lua                                 │
│  • Job/level detection & change handling      │
│  • Event loop (d3d_present)                   │
│  • /sidekick command handler                  │
│  • Settings load/save/merge                   │
└──────┬─────────────────────────┬──────────────┘
       │ loads                   │ loads
       ▼                         ▼
┌──────────────┐         ┌──────────────────┐
│ Job Def      │         │ config.lua       │
│ (jobs/*.lua) │         │  orchestration   │
└──────┬───────┘         └───────┬──────────┘
       │ provides                │ delegates to
       │ abilities               ▼
       │                 ┌──────────────────┐
       │                 │ components.lua   │
       │                 │  render helpers  │
       │                 │  constants       │
       │                 └──────────────────┘
       ▼
┌───────────────────────────────────────────────┐
│  automation.lua                               │
│  • Priority-ordered action evaluation         │
│  • Command throttling (1.1 s, from an         │
│    action's completion — see notify_action_   │
│    finished)                                  │
│  • pcall error isolation per module           │
└──────────┬────────────────────────────────────┘
           │ calls .execute() on each module
           ▼
┌───────────────────────────────────────────────┐
│  Action Modules  (actions/*.lua)              │
│  master_priority (Sidekick.lua) order:        │
│  item → recover → critical → heal_aoe → heal  │
│  → debuff_removal → heal_pet →                │
│  pet_debuff_removal → wake → geo → buff →     │
│  revive → follow → rest                       │
└──────────┬────────────────────────────────────┘
           │ uses
           ▼
┌─────────────────────┐  ┌────────────────┐
│ action_core.lua     │  │ common.lua     │
│ Resource management │  │ party, buffs,  │
│ Cooldown tracking   │  │ logging, cmds  │
│ Buff-ID utilities   │  └────────────────┘
│ is_usable()         │
│ filter_usable()     │
│ first_command()     │
│ try_use()           │
└─────────────────────┘
```

---

## Data Flow

### Automation Tick (every frame via `d3d_present`)

```
1. Guard: addon loaded? automation enabled? job_def loaded?
2. Refresh game_state (party HP, buffs, server IDs, pet info)
   -- must precede the mount guard, else is_mounted would never clear
3. Guard: is_loading()
4. afk.update() → Guard: afk.is_sleeping() -- AFK Sleep dead-man's switch; after
   is_loading so zone garbage is never sampled, before the guards below so the
   timer keeps running (and can wake) while mounted/dead/casting
5. process_scheduled_removal() -- fires a queued mid-cast /debuff; must
   precede the is_casting() guard or it could never send during a cast
6. Guards: is_mounted / is_dead / can_attack / is_casting
7. Multisend range management (only in multisend_follow mode)
8. Check job/level change → reload job definition, skip the frame
9. Iterate priority_order (merged per job from master_priority)
10. For each action type → pcall action_module.execute(settings, job_def, ...)
11. First module to return a truthy result wins
12. Throttle check (1.1 s, or 3.1 s after a spell finish; re-stamped from the action's
    own 0x028 finish/interrupt packet) → QueueCommand → wait for next tick
```

`follow_tick()` runs separately in `d3d_present` and deliberately bypasses the `can_attack` guard — see [follow.lua](#followlua--leader-following).

### Action Module Pattern

Every action module follows the same contract:

```lua
function module.execute(settings, job_def, main_level, sub_level, player_resource)
    -- 1. Check enabled in settings
    -- 2. Filter abilities by level
    -- 3. Evaluate conditions (HP thresholds, buffs, debuffs, pet status)
    -- 4. Select best ability via action_core helpers
    -- 5. Return {command = "...", description = "..."} or nil
end
```

---

## Core Modules

### action_core.lua

Consolidated ability infrastructure module. Combines resource management (MP/TP checking, cooldown tracking with post-recast delay), buff-ID utilities, and the **blocked → resource → cooldown → build-command** pipeline that every action module needs.

**Resource Management** (formerly `resource.lua`):

| Function | Purpose |
|---|---|
| `has_resource(type, amount)` | Check MP or TP ≥ amount |
| `get_resource(type)` | Current MP or TP |
| `is_ability_ready(recast_id)` | Ability recast timer = 0 (with 0.5s post-delay) — reads the JA recast table |
| `is_spell_ready(spell_id)` | Spell recast timer = 0 (with 0.5s post-delay) — reads the spell recast table |
| `get_spell_recast(spell_id)` | Remaining spell recast |

The two tables are distinct and take different ids, so an ability's `spell_id` / `recast_id`
field name must match its command (see the ability-field reference below).

**Buff-ID Utilities** (formerly `buff_utils.lua`):

| Function | Purpose |
|---|---|
| `normalize_ids(ids)` | Coerce `number \| table \| nil` → flat table |
| `has_any_buff(active, check_ids)` | True if any active buff matches any check ID |
| `needs_buff(active, check_ids)` | True if none of the check IDs are active (nil = always needed) |

**Ability Candidacy**:

| Function | Purpose |
|---|---|
| `is_usable(ability, job_def)` | Returns `ok, reason` after checking status ailments, resource, and cooldown. The cooldown check keys off the *field name*: `spell_id` → `is_spell_ready`, else `recast_id` → `is_ability_ready`, else unchecked |
| `filter_usable(abilities, job_def, tag)` | Filters a list down to usable abilities, debug-logs skipped ones |
| `first_command(abilities, job_def, settings, tag, party_index, desc_fn)` | Returns the first usable ability as `{command, description}` or nil |
| `try_use(ability, job_def, settings, party_index, desc, game_state)` | Single-ability execution with optional Trust buff registration |

### afk.lua – AFK Sleep

- **ADK switch** (`settings.afk_enabled`, default **on**, `afk_timeout` default 600s). After
  `afk_timeout` seconds with no party movement and no combat, automation sleeps until the player
  physically moves. **On by default**, unlike `follow_enabled`: sleeping only stops automation
  from *acting*, so the failure mode is benign.
- **A runtime gate, not a stop.** `automation_enabled` stays true and nothing is written to disk,
  so `/sk start` survives a sleep cycle. All state is module-local and does not survive
  `/addon reload`.
- **Two activity signals, both already sampled each tick** (no new memory reads): party movement
  (indices 0-5 — index 0 is the player in `game_state.player`, since `game_state.party` is 1-5
  only) and `common.is_combat()`. `<bt>` resolves on party *claim* rather than the player's own
  engagement, so combat already covers a healer standing back.
- **The wake asymmetry is deliberate**: six people plus a party claim can keep automation awake,
  but only the player's **own** movement (`common.is_player_moving()`) wakes it. A mob claim is
  not proof a human is present; movement is. Combat explicitly does *not* wake — an AFK player in
  a party that pulls should stay asleep.
- **Tick placement** (see Data Flow): after the `is_loading()` guard, so zone-transition garbage is
  never sampled — while loading the timer neither advances nor resets, and the first post-zone
  sample reads a wildly different position and resets naturally. Ahead of the
  mount/dead/can_attack/casting guards, so the timer keeps running and can still wake regardless
  of those states. Nothing is expected to be queued after minutes of stillness, so gating ahead of
  `process_scheduled_removal()` drops no in-flight work.
- `afk.reset()` clears the timer and wakes, silently (a deliberate state clear is not a
  movement-detected wake). Called on job change, on `/sk start` and the UI Start button
  (`toggle`), when the timeout changes, and when the feature is disabled — the last so automation
  is never left stuck asleep.
- **Bounds live in two places** and must agree: `/sidekick afk <seconds>` clamps 60-3600, the
  `/sk panel` **Timeout (minutes)** field clamps 1-60 and converts (`afk_timeout` is stored in
  **seconds**; the field reads `/60` and writes `*60`).
- `afk.seconds_remaining(settings)` is display-only, for the panel debug row. It returns 0 both
  when asleep and when disabled, so the panel branches on `afk_enabled` / `automation_enabled`
  first (`off` / `idle` / `asleep` / `awake (Ns)`) — the countdown only advances while the tick
  loop is actually reaching `afk.update()`.

### common.lua

Shared utility module (~3,200 lines). Key areas:

- **Logging**: `printf`, `debugf`, `errorf`, `warnf` – unified via internal `log()` helper
- **Player state**: `get_player_level/job/mp/tp`, `is_idle/engaged/in_event`, `is_casting` (locked by 0x028 category 8 `casting_begin`, released by 4 `spell_finish` or by an interrupt, via `handle_action_packet`; melee is dropped. `cast_timeout` = 16 s is a **backstop for a missed packet, not a mechanism** — interrupts (below) and zoning clear the lock explicitly, so nothing routine relies on it), `clear_casting_state` (drops the casting lock on zone change, where the cancelled cast never sends a finish packet), `get_last_action` (debug-panel label for the last 0x028 category seen), `is_player_moving`, `is_resting` (cached from entity status 33), `is_mounted` (entity status 5 or buff 252)
- **Interrupt detection** (`common.INTERRUPT_PARAM` = 28787 / `0x7073`): a cancelled action sends **no finish packet**. It repeats its own `*_begin` category (7 WS / 8 casting / 9 item / 12 ranged) carrying `INTERRUPT_PARAM` where the spell/ability id would be — no real id collides with it. Three readers: `handle_action_packet` ignores that second category 8 rather than re-arming the cast lock (which froze automation until `cast_timeout`); `is_action_finish` in `Sidekick.lua` restarts the command throttle from it (the server's lockout applies whether the action landed or was cancelled); `get_last_action` reports `interrupted (<category>)` instead of a bogus `casting_begin` plus a spell lookup on an id that isn't one.
- **Party**: `get_party_size`, `get_party_member_name/zone/distance`, `get_party_server_ids`
- **Alliance**: `is_alliance_member`, `find_alliance_member`, `get_alliance_count`, `sorted_alliance_members`, `apply_alliance_member_buff`, `apply_external_buff`
- **Buffs**: `has_buff`, `get_player_buffs`, `get_party_buffs`, `get_trust_buffs`
- **Trust buff tracking**: `register_pending_buff`, `handle_buff_application`, `handle_buff_removal`, `drop_removed_debuff(server_id, ability)` (marks one status a na-/Erase spell just fired at as **in-flight** for `REMOVAL_SUPPRESS_WINDOW` (~4s) on a Trust/tracked/alliance/pet target rather than deleting it — those give no reliable wear-off packet, so without suppression the removal spell re-fires every tick; a resisted cast, which sends no packet, lets the mark expire and retries instead of orphaning the status; no-op for memory-read party members), `removable_after_suppression(server_id, buffs)` (the removal selector's view of `buffs` with any still-in-flight id hidden and expired marks GC'd; the panel keeps reading the full list), `clear_trust_buffs`, `base_buff_duration` (buff durations + a debuff backstop: `BASE_DEBUFF_DURATION` gives packet-detected debuffs a timed fall-off, Curse/Bane/Disease/Plague never time out, other **removable** debuffs default to 120s — keyed off `REMOVABLE_SET`, built from the `PET_CLEANSE_DEBUFFS` superset rather than Erase's narrower share, since a debuff left out is tracked with no timer and loops its remover forever), `expire_timed_buffs` (timed expiry + Trust song slot eviction — see Trust Buff Tracking below)
- **Status ailments**: `has_silence`, `has_amnesia`, `is_command_blocked` (returns `'Moving'` for **any** command while the player is moving, then `'Silence'` for `/ma` and `'Amnesia'` for `/ja`)
- **Ability helpers**: `has_spell_learned(ability)` (spells: `HasSpell(spell_id)`; job abilities carrying `ability_id` — merit-unlocked JAs like Diabolic Eye — `HasAbility(ability_id + 512)`, the +512 converting the raw abilities.sql id to the client JA resource id; only a `pcall` error assumes known — an unlearned spell/JA is *not* treated as learned), `filter_abilities_by_level` (also filters out unlearned spells/merit JAs via `has_spell_learned`, blue magic not in the BLU set-spell list via `is_blue_magic_unequipped`, an ability whose `requires_equipped_ammo` isn't currently worn, or whose `requires_item` tool isn't owned), `build_ability_command`, `check_target_modifier`
- **Blue magic set-spell gate**: `get_equipped_blue_spells()` reads the client's BLU set-spell buffer (the signature-scanned memory the blusets addon uses; slot bytes are `spell_id - 512`, main-job list at `+0x04`, sub-job at `+0xA0`) into a `{ [spell_id] = true }` set, cached 0.5s; returns `nil` when unreadable. `is_blue_magic_unequipped(ability)` is true for a `magic = 'blue'` **/ma** ability missing from that set — automation skips it (`filter_abilities_by_level`), while the UI shows the row grayed with a *"Blue Magic not currently equipped"* tooltip but still selectable. Fails open (an unreadable buffer gates nothing), and Sidekick never equips spells itself — that's the user's job (e.g. via blusets).
- **Pet status tracking**: `is_pet(server_id)` (true for the current pet's server id, refreshed each tick), `apply_pet_buff` — pets have normal entity ids (< 0x1000000) so they miss the Trust guard; these route the pet's packet-detected buffs/debuffs into `trust_buffs` keyed by the pet's server id. `pet_type_ok(ability)` gates a `requires_pet_name` ability on the summoned pet's name (shared by job validators and the config UI so the name list lives only in the ability data).
- **Consumable-ammo equip**: `count_equippable_items(spec)` / `find_equippable_item(spec)` scan the equip-eligible containers (main inventory + all eight Mog Wardrobes); `get_equipped_item_id(slot)` and `is_ammo_equipped(spec)` read the worn ammo; `select_ammo_equip_command(spec, level)` builds a `/equip ammo "<name>" <container>` for the best owned tier at/below `level`; `ammo_equip_command(abilities, settings, player)` picks the first enabled, level-eligible, not-yet-worn ability needing ammo and returns that equip (respecting `ammo_main_job_only`). A "spec" is a single item id, a flat id list, or a list of `{ id, name, level }` tier entries.
- **Scholar stratagems & BST Ready**: `check_stratagem(job_def, settings, ability_key, ability)` returns the next stratagem JA to fire, `nil` (cast the spell), or `false` (skip). "Hold for Stratagem" (`settings.stratagem_hold[<key>]`) controls the can't-fire case: when held it returns `false` (skip until ready); otherwise `nil` (cast without the stratagem). `prune_unavailable_stratagems(job_def, settings)` drops assigned stratagems above the current SCH level on job/level change (bails on a transient level-0 read), fixing a high-level SCH assignment sticking after a downgrade to a lower level or `???/SCH`. Both stratagems and BST **Ready** are charge systems on one shared recast timer, so a single `charges_from_recast(recast_id, max, rate)` helper converts the remaining-until-full timer into available charges for both (`state.stratagems`, `state.ready_charges`). A stratagem entry with `recast_gate = true` (DRK **Nether Void** on the `absorb` group via the N button; BLU **Diffusion** per blue buff row via the D button; RUN **Embolden** per white enhancing row via the E button; SCH **Enlightenment** on the Addendum: White-gated rows via its own E button) names its button column with `column` and has no charge pool: it's gated on its own JA recast being ready and on `precast_permanently_usable` (on-level, meritted, not a main-job JA supplied by the subjob — so a de-level or a lost merit can't spam an unusable JA); when unavailable the spell casts without it (same hold-off rule). Job files list `recast_gate` strats **ahead of** the charge strats, so `missing[1]` being one means the tick spends no charge and any charge strat behind it is re-checked on a later tick.

  A `recast_gate` entry additionally flagged `precast_required = true` (SCH **Enlightenment**) is the JA its spell's `requires_buff` depends on, which changes three things. It **always holds** regardless of `stratagem_hold` — casting without the buff only fails — scoped to the strat firing this tick so an unrelated charge stratagem the user left un-held isn't silently held too. It is **skipped as redundant** (`precast_redundant`) when the spell's `requires_buff` is already met another way (Addendum: White up), so one assignment survives a stance change. And `common.precast_satisfies_prereq(job_def, settings, ability)` opens the action modules' own `requires_buff` gates (`buff.lua`, `revive.lua`) for a spell whose assigned precast would grant the missing buff — without it the spell never reaches `check_stratagem` and the JA never fires. That helper checks level / merit / main-job (permanent, and a JA that can never fire would hold the spell forever) plus the strat's own `requires_buff` (Enlightenment's Dark Arts), but deliberately **not** recast, which is momentary and handled by the hold. `check_required_precast(job_def, ability)` handles the always-mandatory variant (BLU **Unbridled Learning**, named by `ability.requires_precast`): never user-assigned — it returns `nil` when the JA's buff is already up (cast the spell), the JA command when it can fire now, or `false` (skip the spell) while the JA is unlearned/on cooldown/blocked, since the spell cannot function without it.
- **Game state**: `refresh_game_state` – populates a shared table with party HP%, buffs, server IDs, pet info (including `pet_debuffs` and `ready_charges`), and alliance sub-party snapshots every tick
- **Tracked target level resolution**: `handle_check_packet` – parses 0x0C9 check-response packet to store level and seed estimated max HP via `AVERAGE_HP_BY_LEVEL`
- **Outside-target helpers**: `resolve_focus_target`, `find_alliance_member`, `outside_abilities`, `build_ability_command_for_target`

### automation.lua

Priority-based action engine with a 1.1-second command throttle (3.1 s after a spell finish). Calls each action module's `.execute()` via `pcall`, accepts both `{command, description}` tables and raw command strings.

The throttle mirrors the game's post-action lockout. That lockout is server-side and runs from when the server **resolves** an action, but `execute_command` can only stamp the timer when the client **sends** — seconds early for a spell (the stamp expires before the cast even ends, so the next command fires into the lockout and is eaten) and half a round-trip early even for an instant job ability. So `automation.notify_action_finished()` re-stamps the timer from the player's own 0x028 finish packets, which is the server reporting when the action actually landed. `ACTION_FINISH_CATEGORIES` in Sidekick.lua lists the categories: 2/3/4/5 (ranged, WS, spell, item) and 6/14/15 (job abilities). The `*_begin` categories (7/8/9/12) are excluded — each has its own finish packet later — and melee (1) never gets that far, since `handle_action_packet` drops it. The one exception is an **interrupt**, which never sends a finish and locks out just the same: `is_action_finish` also accepts a `*_begin` category carrying `common.INTERRUPT_PARAM` (see common.lua).

**Spell finishes carry a longer lockout than other actions.** `notify_action_finished(is_spell_finish)` takes that flag from `actionPacket.Type == 4` (spell_finish) and stamps `spell_finish_throttle` (3.1 s) forward instead of the 1.1 s `command_throttle`; ranged / WS / item / JA finishes, and interrupted spells (which arrive as a `*_begin` category, not 4), keep the 1.1 s gap. Since the throttle check always subtracts `command_throttle`, the stamp is pushed only `(spell_finish_throttle − command_throttle)` into the future, which yields exactly the 3.1 s gap. Like the base re-stamp it can only move the timer later.

Re-stamping only ever moves the timer later, never earlier, so it cannot release a command early. It also picks up actions the **player** took by hand, which `execute_command` never sees.

- **Rest breaking**: `REST_BREAKING` (heal, recover, item, status_removal, debuff_removal, wake, revive) fires `/heal off` and returns before the action itself, which lands the next tick. `buff` and `geo` are low priority and never interrupt rest.
- **Stratagem follow-up lock**: a result flagged `is_stratagem` sets `pending_stratagem = {action_type, timestamp}`; the next tick runs **only** that module so nothing pre-empts the paired spell. Released when the module returns nil, or after `STRATAGEM_FOLLOWUP_TIMEOUT` (5 s).
- **Scheduled mid-cast removal**: a result carrying `scheduled_removal = {command, delay}` is handed to `common.schedule_command_removal`. See below.
- `master_priority` includes `'critical'` (and DNC lists it), but there is no `critical` entry in `action_modules` — the engine skips unknown action types, so it is inert. Critical-HP healing is handled inside `heal.lua` via `abilities.critical`.

### Scheduled Mid-Cast Removal

Two opt-in modes need a buff stripped *during* a cast, not before or after. The action module attaches `scheduled_removal` to its result; `common.schedule_command_removal(command, delay)` stores one pending entry (only one spell casts at a time) and `common.process_scheduled_removal()` fires it from the tick loop **ahead of the `is_casting()` guard**, so it lands mid-cast instead of being throttled out by the action pipeline.

| Mode | Setting | What it does |
|---|---|---|
| Bard **Pianissimo Fast Casting** | `pianissimo_fast_casting` | Raises Pianissimo on purpose for an area song (shorter cast time), then `/debuff 409` mid-cast so the song still lands as area. In this mode the area phase runs even while Pianissimo is up (it's ours), and always holds for Pianissimo rather than casting without it — but only raises it once the song itself is castable (see the song-ready gate under [buff.lua](#bufflua--buff-maintenance)). It also holds the whole single-target pass while any configured `[A]` song still needs recasting but is momentarily on recast, so area songs fully establish before single-target songs fire (prevents single-target casts the area recast would overwrite). |
| Ninja **Cast with 1 Shadow** | `cast_with_1_shadow` | Utsusemi normally blocks while any Copy Image buff (66/444/445/446) is up. This ignores the 1-shadow buff (`one_shadow_buff = 66`) so the spell recasts at 1 shadow, then `/debuff 66` mid-cast so the new shadows apply cleanly. |

Both toggles live in the `/sk panel` header row, are persisted per job, and require the Debuff addon by atom0s (`/debuff`).

### parse_packets.lua

Parses raw packet bytes for action packet 0x028 into structured Lua tables (actor, type, targets, actions). Used by Sidekick.lua's packet_in handler for casting-state detection and Trust buff tracking.

0x028 is **bit-packed, not byte-aligned** — `Type` (the 4-bit action category) sits at bit 82, not on any byte boundary, so it can only be read through this parser, never with `struct.unpack` offsets. Categories: `1` melee, `2` ranged_finish, `3` ws_finish, `4` spell_finish, `5` item_finish, `6` job_ability, `7` ws_begin, `8` casting_begin, `9` item_begin, `11` mob_tp_finish, `12` ranged_begin, `13` avatar_tp_finish, `14`/`15` job_ability (DNC/RUN). Layout matches [Windower's `fields.lua`](https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua) for incoming 0x028.

### targets.lua

FFI bindings for FFXI target resolution (battle target, scan target, last teller). Ashita utility module.

---

## Action Modules

### heal.lua – Healing (Single, AOE, Pet)

**Single-target priority**: Critical HP → Focus target → Lowest-HP party member

- **Deficit-based selection**: Calculates exact HP deficit, picks ability whose `value` best matches to minimise overheal.
- **Critical HP system**: Separate ability list (`abilities.critical`) with lower threshold (default 30%).
- Uses `action_core.filter_usable()` for resource/cooldown gating.

**AOE healing** (`execute_aoe`): Triggers when average party HP falls below threshold. Uses `action_core.first_command()`.

**Pet healing** (`execute_pet`): Monitors pet HP via game state. Uses `action_core.first_command()`. For jobs whose pet-heal needs a consumable in the ammo slot (BST **Reward** → Pet Food, PUP **Repair** → Automaton Oil), `execute_pet` calls `common.ammo_equip_command` and returns its `/equip` for the best owned tier when one isn't worn; the heal itself fires the following tick. If none are owned the ability stays gated out.

**Group / AOE target selection**: `make_group_filter(key_name)` reads session-only per-target state from `ui_config.get_party_buffs()[key_name]` (`heal_group` for single-target Group scanning, `heal_aoe_group` for the AOE average). Keys mirror the UI: numeric `0-5` (party), `tt_<sid>` (tracked), `al_<flat>` (alliance). Defaults are asymmetric — party/tracked are included unless explicitly set `false`; alliance members are excluded unless explicitly set `true` — so behavior is correct even when the config window was never opened.

### status_removal.lua – Debuff Removal & Sleep Wake

**Debuff removal** (`execute_debuff_removal`):
- The level-filtered removal list is ranked by `removal_rank` so the per-target loops reach for the most specific remover first: targeted na-spell (`0`, strips the *exact* ailment) < generic Erase / any wildcard remover (`1`, strips a *random* erasable status) < the self-centered AOE / Esuna (`2`). Erase is identified by table identity (WHM/SCH Erase share the one `common.ERASABLE_DEBUFFS` table; the pet cleanses carry `common.PET_CLEANSE_DEBUFFS` and are matched too, though they only reach `execute_pet_debuff_removal`, which does not sort).
- Priority: **AOE Esuna** → focus target → party member with most debuffs (then tracked / alliance). The AOE pass fires a self-centered removal (Esuna) when **2+ members inside its radius** (self + party + alliance, via `is_in_range`) share an ability-removable ailment — one cast beats a chain of na-casts. **Pets and tracked (Trust) targets are not in the AOE**, so they don't count toward the threshold and aren't dropped by it. Below the threshold, a single affected target falls through to its targeted na-spell; Esuna still trails the per-target loops as a last resort for an Esuna-only ailment nothing else covers.
- Matches abilities to specific debuff IDs they can cure. Uses `action_core.try_use()`.
- On firing a removal at a **packet-tracked** target (Trust / tracked / alliance / pet — including one Esuna-removable status per affected alliance member on the AOE cast), calls `common.drop_removed_debuff(server_id, ability)` to mark one matching status as **in-flight** for `REMOVAL_SUPPRESS_WINDOW` (~4s) rather than deleting it: `common.removable_after_suppression` hides it from the removal selector so the spell doesn't re-fire while the cast resolves. A landed cast's `0x028` msg-83 deletes it for real inside the window; a **rejected/resisted** cast sends no packet, so the mark expires and the status is retried instead of orphaned (gone from tracking but still on the target). No-op for memory-read party members (their sid isn't in `trust_buffs`, and their buffs aren't run through the suppression filter); the debuff base-duration timer is the ultimate fallback.

**Wake from sleep** (`execute_wake`):
- Scans party buffs for sleep IDs (2, 19).
- 1 sleeping → cheapest single-target ability; 2+ → cheapest AOE ability.
- Uses `action_core.try_use()` for resource/cooldown/command pipeline.
- Wake spells carry no `debuff_id`, so the Sleep drop is inferred in Sidekick.lua's 0x028 handler instead: a player Cure landing (HP messages 2/7/24) on any packet-tracked ally (Trust/tracked/alliance/pet) clears Sleep + Sleep II from tracking, so the wake doesn't re-cure until the timer would.

**Pet debuff removal** (`execute_pet_debuff_removal`):
- BST (Reward + Pet Roborant) and PUP (Maintenance + Oil) strip status ailments from the pet.
- Reads the packet-tracked `game_state.pet_debuffs` list (see [Pet Status Tracking](#pet-status-tracking)); only fires when the pet actually carries a debuff the ability can remove, matched against the ability's `debuff_id` list.
- Both carry `common.PET_CLEANSE_DEBUFFS`, **not** `ERASABLE_DEBUFFS` — neither ability is an Erase server-side. PUP **Maintenance** walks its own ailment list (petrification, silence, bane, curse I/II, paralysis, plague, poison, disease, blindness) and only *then* falls back to `eraseStatusEffect()`, making its real set a superset of Erase. BST **Reward** never calls Erase at all: its cleanse is gear-dependent (Beast Jackcoat → poison/paralysis/blindness, Monster Jackcoat → silence/weight/slow, the +1s → all six, no Jackcoat → nothing), so it over-claims against this list and simply no-ops on a status the worn body piece can't strip. `PET_CLEANSE_DEBUFFS` is `ERASABLE_DEBUFFS` plus the Na-spell ailments (3,4,5,6,8,9,31), and is also what the 120s debuff-expiry backstop keys off, since that must cover every debuff with *any* remover.
- Auto-equips the required consumable (`requires_equipped_ammo`) **only** when there is a matching debuff to cure, so the roborant/oil never fights the heal or Regen for the ammo slot while there's nothing to do.
- On firing, marks one matching status on the pet as in-flight (`common.drop_removed_debuff(pet.ServerId, ability)`), same suppression as Trust/alliance removal — a pet carrying several erasable statuses gets one suppressed per cast, more casts strip the rest; a cast that never lands lets the status become eligible again after the window.
- Because pet status is inferred from packets, this is best-effort (same caveat as Trust tracking) — surfaced in the UI as a warning tooltip.

### buff.lua – Buff Maintenance

Runs in two phases per tick:

- **Phase 1 – Area songs (`[A]`)**: Bard songs flagged for area (`party_buff_config[key]['A'] == true`) are cast **without** Pianissimo so everyone in range gets the song, checked *before* the single-target pass because an AoE song overwrites single-target songs on everyone it hits. `area_needs_recast()` scans in-range (`SONG_AOE_RANGE` = 10 yalms), same-zone party members who aren't already covered by a dedicated single-target song (`dedicated_targets()` counts per-member song slots against the `song_limit`). Trusts are skipped for recast timing (unreliable buff tracking) but covered by the cast. Phase 1 is skipped while Pianissimo is active (it would make the area cast single-target by mistake).
- **Phase 2 – Single-target buffs**: Per-member `<ME> <P1>–<P5>` (plus alliance/tracked) selection stored in `settings.party_buffs`. ME (`target_index 0`) now also routes through the target modifier so Bard self-songs use Pianissimo like P1-P5.
- **Groups**: Mutually exclusive by default (dropdown selects the active tier). A group the user **ungroups** (`settings['ungrouped_<group>'] == true`) casts every tier independently, keyed by ability name like a non-grouped ability.
- **Stacking same `buff_id`**: `count_instances()` / `wanted_instances()` / `song_needed()` count how many distinct selected tiers share a `buff_id` (e.g. Mage's Ballad + Mage's Ballad II both = buff 196) and treat a target as needing the song until it holds that many instances, instead of a plain presence check.
- **Target modifier** (Pianissimo, etc.): If `ability.target_modifier = true`, sends modifier command first; next tick casts the buff.
- **Song-ready gate on the modifier**: the modifier is only raised once the song it precedes is *itself* castable — `action_core.is_usable(ability, job_def, common.effective_ability_cost(ability, settings, job_def))`. Otherwise a song merely *due* for recast raises Pianissimo while still on its own recast or unaffordable, burning Pianissimo's recast before the song comes up. Applies to both the Phase 1 fast-casting hold and the Phase 2 `check_target_modifier` path; a song that isn't ready falls through to the next.
- **Trust buff registration**: Calls `common.register_pending_buff()` for Trusts after cast.
- **Ammo auto-equip**: When a pet is out and a buff needs a consumable in the ammo slot (BST **Reward (Regen)** → Pet Poultice), `common.ammo_equip_command` equips the best owned tier first (only reachable after the higher-priority pet-heal passed, so its biscuit and this poultice never contend for the slot).
- **`reapply_interval`**: For buffs whose presence can't be read on the target (pet Regen — pet buffs aren't in memory), the buff is reapplied only after `reapply_interval` seconds have elapsed since the module's last cast (tracked in a module-local `last_self_cast` table, cleared on reload), instead of every recast, so the consumable isn't wasted.
- **Condition flags**: `idle_only`, `requires_pet`, `requires_buff`, `blocked_by`; combat-only and idle-only gating are also controlled by settings (`combat_only_<name>`/`combat_only_group_<group>`, `idle_only_<name>`/`idle_only_group_<group>`) via `is_ability_combat_only`/`is_ability_idle_only`. The two are mutually exclusive.
- **Self-buff blocking (`blocked_by`)**: An ability is dropped while the player holds a buff listed in `blocked_by` — distinct from `buff_id` (the buff the ability *grants*). `action_core.is_self_blocked` tests one ability; `action_core.filter_self_buff_blocked` drops blocked ones from a candidate list, wired into `buff.lua`, `heal.lua` (`execute` + `execute_aoe`), and `status_removal.lua` (debuff removal). DNC: **Saber Dance** (410) blocks Waltzes, **Fan Dance** (411) blocks Sambas.
- Uses `action_core.try_use()`.

### item.lua – Consumable Status Removal

Data-driven via `ITEM_REMOVALS` (priority-ordered; each row is `setting_key`,
`item_id`, `item_name`, `debuff_name`, `buff_ids`). Dedicated single-cures come
first so a cheap item wins over a premium multi-cure (Antidote before Remedy for
Poison). `buff_ids` lists every status the item **reliably** removes; hedged
("potentially") cures are omitted so the item can't loop the stack on a debuff it
won't clear — Remedy skips Disease, Panacea skips Amnesia.

| # | Item | ID | Removes (`buff_ids`) |
|---|---|---|---|
| 1 | Antidote | 4148 | Poison (3) |
| 2 | Eye Drops | 4150 | Blindness (5) |
| 3 | Echo Drops | 4151 | Silence (6) |
| 4 | Holy Water | 4154 | `common.CURSE_DEBUFFS` = Curse/Doom/Bane (9,15,20,30) |
| 5 | Hallowed Water | 5306 | `common.CURSE_DEBUFFS` |
| 6 | Tincture | 5418 | Plague/Disease (31, 8) |
| 7 | Remedy Ointment | 5356 | Poison/Paralyze/Blind/Silence (3,4,5,6) |
| 8 | Remedy | 4155 | Poison/Paralyze/Blind/Silence (3,4,5,6) |
| 9 | Panacea | 4149 | stat-down family (the ≥128 tail of `ERASABLE_DEBUFFS`) |

Gated by a master `item_removal_enabled` toggle plus a per-item `setting_key`;
skipped while the player is moving (`common.is_player_moving()`, same rule as
casting). 4-second cooldown between uses. Inventory is matched by **item ID**
(`get_item_count(item_id)` scans container 0), not name — custom-server items
(Remedy Ointment, etc.) have resource names that don't match the English string
`GetItemByName` expects, so a name lookup returns `nil`. The `/item` command name
is resolved from the resource by ID (`GetItemById(id).Name[1]`, falling back to
the label). Returns `{command, description}`.

### recover.lua – Resource Recovery

MP and TP recovery. Monitors percentage thresholds. Uses `action_core.first_command()` and `filter_usable()`. Supports `requires_buff` prerequisites.

### geo.lua – Geomancer Automation

- **Geo buffs**: `<me>` Geo spells (`group = 'Geo'`, `exclusive_target = true`) cast on a single selected party member via the same ME/P1-P5 button targeting as other buffs. Single-select: choosing a target deselects the others.
- **Geo debuffs (Geo-bt)**: `<bt>` enemy debuffs (`group = 'Geo-bt'`) cast on the player's battle target. Combat-only (inherently, via `is_ability_combat_only`); the single selected debuff is chosen from a dropdown and cast through `geo.lua` (not `buff.lua`). A module-local `geo_bt_pending` flag tracks whether the current luopan belongs to the debuff.
- **Full Circle**: Monitors luopan distance from the selected Geo target (`get_pet_distance_from_member`); fires Full Circle when the pet exceeds the configurable yalm threshold, then recasts. Skipped when no Geo target is selected.
- **Luopan lifecycle**: Only one luopan exists at a time. In combat the selected Geo debuff takes over the luopan (Full Circle a non-debuff luopan, then cast); the distance-based Full Circle is suppressed while a debuff luopan is active so it isn't dismissed mid-fight. When combat ends, Full Circle frees the luopan for Geo buffs.
- **Entrust**: Name-based target + spell selection from UI dropdowns; fires Entrust → Indi spell on configured party member. Indi does not use a luopan, so it never conflicts with the Geo luopan.
- All Geo spells have `main_job_only = true`.

### follow.lua – Leader Following

- **Opt-in** (`settings.follow_enabled`, default off) job-independent leader following — the
  only non-combat movement Sidekick performs. Returns `{command = '/follow <pN>'}` when the
  configured `follow_target` is beyond `follow_distance` (default 5), else `nil`.
- Reuses existing primitives: finds the target in `game_state.party` (0-based indices map
  directly to FFXI's zero-based `<pN>`, `<p0>` = player), gates in-zone on `GetSpawnFlags > 0`
  (a zoned-out member keeps a slot with a garbage position), and measures range via
  `common.get_party_member_distance`.
- Wired **low** in `master_priority` (just above `rest`) so healing and every other support
  action preempt following. Injected into the merged `available_actions` **once** in
  `load_job_definition` rather than added to all 21 job files.
- **Runs even when the priority engine won't.** The engine (`automation_tick`) only reaches the
  follow action when automation is **enabled *and* `can_attack`** is true, so on its own follow
  would die whenever automation is stopped *or* the tick is "paused" (automation on but
  `can_attack` blocked — safe zone, cutscene, just-zoned). A standalone `follow_tick()` in
  `d3d_present` covers exactly those cases: it bails when `automation_enabled and can_attack`
  (engine handles follow there, preserving healing-over-follow priority) and otherwise runs the
  follow module directly. Unlike combat actions, follow is deliberately **not** gated on
  `can_attack`, so it works in towns/safe zones. Guards it keeps: zoning / mounted / dead /
  casting. Reuses the shared throttle via `automation.execute_command`; in the states it runs,
  the engine issues nothing, so the shared throttle never delays a heal.
- Follow survives the server's position syncs via the **autorun-cancel packet guard** in
  `Sidekick.lua`'s `packet_in` handler (see Event System); without it `/follow` breaks on every
  sync. The guard is gated on `follow_enabled and not multisend_follow`, so behavior is unchanged
  when following is off.
- **Movement mode switch** (`multisend_follow`, checkbox in `/sk panel`, default off): when on,
  Sidekick uses the legacy Multisend attack-range follow instead — the config window shows the
  **Attack Range** combo and hides the Follow section, `follow.execute` returns `nil`, the packet
  guard is suppressed, and the Multisend range logic in `automation_tick` runs. When off, native
  Follow is used and the Multisend range logic is suppressed. The two are mutually exclusive so
  they never both drive movement.
- Changing `follow_target` in the UI calls `common.reset_autofollow()` (`GetAutoFollow()` →
  `SetIsAutoRunning(0)` / `SetFollowTargetIndex(0)` / `SetFollowTargetServerId(0)`) so the client
  stops running at the old leader before the module retargets the new one.

### rest.lua – Automatic Resting

- Two-phase timer: conditions become favourable → wait N seconds → `/heal on`.
- Stops at 100% MP or when follow-target distance exceeds threshold.

### revive.lua – Raise Dead Members

- Scans party (indices 1–5), tracked targets, and alliance sub-parties 2 & 3 for members with `entity_status == 3`.
- Filters abilities by level, recast readiness, **and** `requires_buff` prerequisites (e.g., Scholar needs Addendum: White buff 401).
- Validates range (`common.is_in_range`) before building each command.
- **Pending-raise guard**: a target with `common.has_pending_raise(server_id)` is skipped. The flag is set from the 0x029 handler — the server answers a raise cast on an already-raised body with a rejection param, and without the flag the spell re-fires every tick.
- Runs `common.check_stratagem` before each cast like the other modules, so Scholar can fire Penury to halve the Raise MP cost.
- Falls back through all usable abilities if the first spell's command build fails.
- All raise spells use `idle_only = true` and `target_outside = true`.
- Controlled by `settings.revive_enabled`.

---

## Job Definitions

Each job file returns a configuration table:

```lua
return {
    job_id          = 3,
    job_name        = 'White Mage',
    resource_type   = 'mp',           -- 'mp' or 'tp'

    abilities = {
        heal               = { ... },
        heal_aoe           = { ... },
        heal_pet           = { ... },
        critical           = { ... },
        buff               = { ... },
        debuff_removal     = { ... },
        pet_debuff_removal = { ... },  -- strip pet status ailments (BST/PUP)
        wake               = { ... },
        recover_mp         = { ... },
        recover_tp         = { ... },
        recover_party_mp   = { ... },
        geo                = { ... },
        target_modifier    = { ... },
        revive             = { ... },  -- raise spells (WHM/SCH/RDM)
        precast            = { ... },  -- JAs fired just before a paired spell (SCH stratagems /
                                       --   Enlightenment, DRK Nether Void, BLU Diffusion /
                                       --   Unbridled Learning, RUN Embolden)
    },

    default_settings = { heal_enabled = true, heal_threshold = 75, ... },

    priority_order = { 'heal_aoe', 'heal', 'debuff_removal', 'wake', ... },

    -- Optional: custom validator called by filter_abilities_by_level()
    validate_ability = function(ability, common) return true end,
}
```

### Ability Definition

```lua
{
    name            = 'Cure IV',
    level           = 48,
    cost            = 88,
    value           = 400,          -- HP restored (deficit selection)
    spell_id        = 1,            -- /ma only: spell_list.sql `spellid` (spell recast + HasSpell)
    recast_id       = 0,            -- everything else (/ja, /item, /pet, /ws): abilities.sql `recastId`
                                    --   Exactly one of the two per ability -- the field name selects
                                    --   which recast table is_usable reads.
    ability_id      = 160,          -- JA only: raw abilities.sql `abilityId` for merit-unlocked JAs
                                    --   (has_spell_learned checks HasAbility(ability_id + 512))
    command         = function(idx) return '/ma "Cure IV" <p' .. idx .. '>' end,
    -- or: command = '/ja "Divine Seal" <me>',
    buff_id         = 43,           -- number or table of buff IDs to track
    debuff_id       = 3,            -- debuff ID(s) this ability removes
    idle_only       = false,        -- green  – is_idle()  (static field or user-toggleable via right-click)
    combat_only     = false,        -- yellow – is_combat() (user-toggleable via right-click)
    requires_pet    = false,
    requires_buff   = 401,          -- prerequisite buff ID(s)
    blocked_by      = 410,          -- buff ID(s) that block this ability while active
                                    --   (DNC Saber Dance 410 blocks Waltzes, Fan Dance 411 blocks Sambas)
    priority        = 100,          -- ability ordering: higher = evaluated before lower-priority abilities
                                    --   (Composure first so later self-buffs inherit its bonus). Unset = 0.
                                    --   filter_abilities_by_level sorts priority desc, then cost desc.
                                    --   Applies to any type routed through it (buff, heal, heal_pet...).
                                    --   Do NOT set on a grouped tier -- breaks tier auto-select.
    group           = 'regen',      -- mutually exclusive group
    self_only       = false,
    main_job_only   = false,        -- hidden when job is subjob
    target_modifier = false,        -- needs Pianissimo / similar before party cast
    wakes           = true,         -- can remove sleep
    removal_rank    = 0,            -- removal only: 0 = targeted na-spell, 1 = generic Erase /
                                    --   wildcard remover, 2 = self-centered AOE (Esuna)
    exclusive_target = false,       -- GEO: single-select targeting (choosing one deselects others)
    magic           = 'blue',       -- marks a spell for magic-specific gating (BLU set-spell list,
                                    --   arts-stance matching, Diffusion/Embolden button rows)
    magic_type      = 'enhancing',  -- magic school within the colour ('enhancing' | 'healing' |
                                    --   'raise' | ...): matched against a stratagem's magic_types,
                                    --   and required alongside magic = 'white' for the Embolden [E]
                                    --   button (the black-magic Spikes are 'enhancing' too)
    magic_types     = { 'enhancing' },  -- precast entries only: the magic_types this stratagem applies
                                    --   to (SCH Perpetuance); no field = every type of its colour
    requires_stratagem_charge = true,  -- SCH: gate on a spare stratagem charge instead of a recast.
                                    --   The pool (recast 231) counts down per charge rather than to
                                    --   zero, so a plain recast_id passes only at full charges.
                                    --   Enforced by the job's validate_ability.
    column          = 'embolden',   -- recast_gate precast entries only: names the button column that
                                    --   owns this JA ('nether_void' | 'diffusion' | 'embolden' |
                                    --   'enlightenment'). A UI key, never a magic colour.
    one_shadow_buff = 66,           -- NIN: buff id ignored/stripped by "Cast with 1 Shadow"
    range           = 20,
    is_main_job     = true,         -- false for subjob-sourced abilities
    resource_type   = nil,          -- override job resource_type ('mp'/'tp')
    target_outside  = false,        -- true for abilities that can target non-party members

    -- Pet / consumable-ammo fields (BST, DRG, PUP)
    pet_required           = true,              -- gated on a pet being out
    requires_pet_name      = { 'Carbuncle' },   -- list of acceptable pet names (pet_type_ok)
    requires_equipped_ammo = OILS,              -- consumable spec that must be worn in the ammo slot;
                                                --   auto-equipped from the best owned tier, else gated out
    ammo_label             = 'Oils',            -- UI label for the inline (count) display
    ammo_main_job_only     = true,              -- only equip the ammo when this job is MAIN (e.g. PUP oils)
    requires_item          = TOOLS,             -- consumable held IN INVENTORY (not worn) — NIN Ninjutsu tools;
                                                --   list of {id,name}; count_equippable_items sums them, spell
                                                --   gated out (find_equippable_item nil) when none owned
    item_label             = 'Shihei',          -- UI label for the requires_item tooltip
    requires_ready_charge  = true,              -- gated on a spare BST Ready charge (game_state.ready_charges)
    ready_charge_cost      = 2,                 -- Ready charges the move burns (default 1; Wild Carrot = 2)
    reapply_interval       = 300,               -- buff: reapply after N seconds instead of every recast
                                                --   (for buffs whose target we can't read, e.g. pet Regen)
    requires_precast       = 'Unbridled Learning',  -- names an abilities.precast entry that MUST be fired
                                                    --   right before this spell (check_required_precast);
                                                    --   the spell is skipped while the JA can't fire
    precast_required       = true,              -- precast entries only (SCH Enlightenment): the JA grants a
                                                --   buff its paired spell's requires_buff needs, so
                                                --   check_stratagem always holds the spell for it (no Hold
                                                --   option) and skips it once the prerequisite is met
                                                --   another way. precast_satisfies_prereq opens the action
                                                --   modules' requires_buff gate so the spell can reach it.
}
```

#### Id fields and their SQL sources

Every id in a job file comes straight from the CatsEyeXI server SQL, and the numbers are
only meaningful against the table they were taken from:

| Field | Source | Applies to |
|---|---|---|
| `spell_id` | [`spell_list.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/spell_list.sql) `spellid` | `/ma` abilities (spell recast + `HasSpell`) |
| `recast_id` | [`abilities.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/abilities.sql) `recastId` | everything else (`/ja`, `/item`, `/pet`, `/ws`) |
| `ability_id` | [`abilities.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/abilities.sql) `abilityId` | merit-unlocked JAs only (`HasAbility(ability_id + 512)`) |
| `buff_id` / `debuff_id` | [`status_effects.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/status_effects.sql) `id` | status tracked / removed |

`cost` is `spell_list.sql` `mpCost` and `level` is the per-job level packed into the `jobs`
blob (byte index = job id - 1), except for JAs, where `level` is `abilities.sql` `level`.
The exception is retail-era content the 75-cap server grants early: those rows keep their
retail `level` in SQL (Presto 77, Conspirator 87, the Unbridled Learning spells 79-98, …)
while the job file clamps them to a reachable level. Don't "fix" those against SQL — but a
level *below* the SQL value on ordinary content is a bug.

Two rules are easy to get wrong:

- **`recastId` and `abilityId` are different columns of the same `abilities.sql` row** — do
  not conflate them. An ability carries exactly one *cooldown* id (`spell_id` **or**
  `recast_id`), and `ability_id` is an extra, only for merit JAs.
- **The field name, not the command text, picks the recast table.** `is_usable` no longer
  sniffs the command for `/ma`, so a `/ma` ability given a `recast_id` will silently read
  the wrong timer, and one given neither id is never cooldown-gated at all.

Item/ammo tier-spec tables (BST `PET_FOOD`, NIN `SHURIKENS`, PUP `OILS`, …) are not
abilities — their entries keep a bare `id`, which is an item id.

Ninjutsu is a special case worth knowing: in `spell_list.sql` the `mpCost` column holds the
**tool item id** rather than an MP cost, which is why NIN spells carry `cost = 0` and gate on
`requires_item` instead.

---

## UI System

### config.lua – Orchestration

- Builds a **context object** (`ctx`) containing settings, callbacks, job_def, filter functions, and party_buffs.
- Delegates all rendering to `components.lua`.
- **Window sizing**: Uses imgui `AlwaysAutoResize` (no manually computed fixed width). A `force_expand` flag un-collapses the window once when reopened so a collapsed `imgui.ini` state doesn't leave an empty title bar. `imgui.Begin` returning `false` on collapse is treated as "still open, skip content"; only the `[X]` (is_open → false) closes it, and `End()` is always called.
- **Group/AOE heal targets**: Calls `render_heal_group_selection(ctx, 'heal_group', true)` and `(ctx, 'heal_aoe_group', false)` under the respective threshold sliders.
- **DRY helpers**:
  - `render_party_dropdown(label, key, include_player, names, settings, cb)` – reusable for Focus/Follow/Recovery/Entrust Target dropdowns.
  - `has_usable_abilities(abilities)` – quick check for any level-appropriate abilities.
- **Pet Debuff Removal section**: A collapsing checkbox header (`pet_debuff_removal_enabled`) shown only when the job has usable `pet_debuff_removal` abilities. Sets `ctx.show_pet_debuff_warning` while rendering its rows so `ability_checkbox` surfaces the *"Pet Tracked Removal is not totally reliable"* tooltip.
- **Inline ammo count**: In the pet-heal, pet-debuff-removal, and buff sections, an ability with `requires_equipped_ammo` draws a `(<count>)` after its row via `common.count_equippable_items` — **green** when a matching item is worn (`is_ammo_equipped`), **red** when not. The buff section passes `render_ammo_count(ability, true)` so the count also names the currently equipped tier (NIN Sange shuriken). An ability with `requires_item` (NIN Ninjutsu tool) instead draws a `(<count>)` that is green when any tool is owned, red at zero.

### components.lua – Render Components

**Constants** exported for config.lua:
`ABILITY_LIST_INDENT`, `PARTY_BUTTON_WIDTH`, `SPACE_BETWEEN_BUTTONS`, `DROPDOWN_WIDTH`, `AUTOMATION_BUTTON_WIDTH`, colour tables (`LIGHT_RED/GREEN/BLUE/YELLOW/GRAY`).

**Render functions**:

| Function | Layout |
|---|---|
| `render_ability(ctx, ability, job_def, suffix)` | Dispatcher – picks correct renderer below |
| `self_single_ability(ctx, ability, job_def, suffix)` | `[ON/OFF] Ability Name` |
| `self_grouped_ability(ctx, ability, job_def)` | `[ON/OFF] [Dropdown]` |
| `party_single_ability(ctx, ability, job_def)` | `[<ME>] [<P1>]… Ability Name` |
| `party_grouped_ability(ctx, ability, job_def)` | `[<ME>] [<P1>]… [Dropdown]` |
| `ability_checkbox(ctx, ability, job_def, suffix)` | Simple checkbox with spell-learned check |
| `render_party_buttons(ctx, key, has_spell, ability, is_group)` | ME/P1-P5 (+ alliance/tracked) buttons; for songs also draws the leading `[A]` area button and gates ME on Pianissimo |
| `render_heal_group_selection(ctx, key, show_outside)` | Group/AOE heal target buttons — **session-only**, asymmetric defaults (party/tracked ON, alliance OFF); `show_outside` draws alliance+tracked (Group=true, AOE=false) |
| `item_removal_checkboxes(ctx)` | One checkbox per `item.REMOVALS` row (via `render_item_removal_checkbox`); label shows live count, or `(?)` while inventory loads |
| `item_inventory_loaded()` | True once inventory is readable; config hides the whole Item Removal section while counts are still `?` (nil), shows it once loaded even if every count is 0 |

**Ability graying** (`self_single_ability`, `self_grouped_ability`, `group_dropdown`, `party_single_ability`, `ability_checkbox`): in addition to unlearned spells, a row is grayed (and given a matching tooltip) when it's blue magic not in the BLU set-spell list — `blue_unequipped` via `common.is_blue_magic_unequipped`, tooltip *"Blue Magic not currently equipped"*, row stays selectable since equipping is the user's job (`self_single_ability` and `ability_checkbox` only — the paths BLU rows render through) — when it's ammo-gated with none of the consumable owned — `no_ammo`, tooltip *"No `<ammo_label>` found in storage."* — when its `requires_item` tool isn't owned — `no_item`, tooltip *"No `<item_label>` or Shikanofuda in inventory."*, which also locks the ON/OFF toggle off — or when it needs a specific pet that isn't out — `wrong_pet` via `pet_type_unmet`/`common.pet_type_ok`, tooltip *"Requires pet `<name / name>`"*. `ability_checkbox` additionally renders unchecked **and** swallows clicks while `no_ammo`, so a consumable-gated row can't be enabled while unusable (the saved setting is left intact and restores when the item returns).

**Right-click context menu** (`render_combat_only_context_menu`): mutually-exclusive **Combat Only** / **Idle Only** toggles (checking one clears the other) plus, for grouped buffs, an **Ungroup** checkbox (`ungrouped_<group>`). Suppressed for statically `idle_only` and `<bt>` abilities. Popup ids are per-ability (not per-group) so an ungrouped group's per-tier rows don't collide.

**Scholar stratagem button** (`render_scholar_stratagem_button`): Assign stratagems per spell, plus a **Hold for Stratagem** checkbox (`stratagem_hold[<key>]`). The alignment spacer is skipped for Geo-bt rows (no S-button column) and Bard song rows (the `[A]` button already indents them), preventing a double indent.

**Recast-gate buttons** (`render_recast_gate_button`, shared by `render_nether_void_button`, `render_diffusion_button`, `render_embolden_button` and `render_enlightenment_button`): a one-letter button in the row's leading slot — DRK **N** on the Absorb group row, BLU **D** on every `magic = 'blue'` buff row, RUN **E** on every `magic = 'white'` + `magic_type = 'enhancing'` row (both keys needed: `magic_type` keeps it off the white non-enhancing rows, `magic` off the black-magic Spikes, which are `'enhancing'` too) — drawn when the main job meets the JA's level (`recast_gate_column_strat(ctx, column)` matches the JA's `column` field: `'nether_void'`, `'diffusion'`, `'embolden'` or `'enlightenment'`); while the merit is not unlocked it renders disabled (grayed, click-locked, *"Not Learned"* tooltip), like an unlearned spell row. While either column is on-screen, every other buff row draws one alignment spacer via `render_leading_slot` (single self rows reach it through `onoff_button`), following the same exactly-one-indent rule as the S/[A] columns (on e.g. DRK/SCH in Light Arts the N button or the scholar spacer fills the slot, never both). Both JAs are excluded from the Scholar S popup (`get_available_stratagems` skips `recast_gate` strats; Unbridled Learning is excluded by its `magic = 'blue'` mismatch). Clicking opens a popup with **Enable** (`stratagem_settings[<key>][<JA name>]` — the automation fires the JA before the paired ability; key is `'absorb'` for DRK, the buff/spell name for BLU and RUN) and **Hold for `<JA>`** (`stratagem_hold[<key>]`, the same hold key Scholar uses — ON skips the paired ability until the JA is ready; OFF, the default, fires it without the JA when on cooldown, which for Diffusion means the buff lands self-only and for Embolden an unboosted cast). Lit when enabled. `has_any_stratagem` matches only the names the calling button offers, since these JAs share the per-ability `stratagem_settings` table with the Scholar stratagems — otherwise one button's assignment would light another's.

**Enlightenment button** (`render_enlightenment_button`): SCH **E**, on every row Addendum: White gates — those whose `requires_buff` the JA's own `buff_id` (416) satisfies, which the job data writes as `requires_buff = {401, 416}`. Rows gated on an arts stance instead (`{358, 401}`, e.g. Tranquility) carry no 416 and get no button, since Enlightenment frees the next spell from the addenda rather than changing the stance. Drawn only while in Dark Arts / Addendum: Black on a level-75 SCH main (`enlightenment_column_strat`, keyed `column = 'enlightenment'`). It takes the **scholar column** rather than adding one of its own (see below). It reuses `render_recast_gate_button` in **toggle** mode: passing no `hold_tip` drops the popup, so the button itself is the Enable switch. Hold is implicit — the spell cannot be cast without the JA's buff — which `precast_required` enforces in `check_stratagem`. The strat's own `requires_buff = {359, 402}` keeps a persisted assignment from firing in Light Arts, where the button isn't drawn to turn it off.

**The recast-gate buttons share the scholar column.** `render_leading_slot` is **one column wide in every case but one**. The S button only draws a *real* button on a `/ma` row whose magic colour matches the arts stance — `get_available_stratagems` matches `strat.magic` against `ability.magic`, and every stratagem is `'white'` or `'black'`. Everywhere else it draws an alignment spacer, which a recast-gate button can take instead. So it comes down to the colour of the rows each button appears on:

| Button | Its rows | Contests the S button? |
|---|---|---|
| **N** Nether Void | the `absorb` group — carries **no** `magic` colour, so `get_available_stratagems` returns `{}` and S draws *nothing* | never, either stance |
| **D** Diffusion | blue rows — not white/black, so S only ever spacers them | never, either stance |
| **E** Enlightenment | white rows, and only drawn in Dark Arts to begin with | never |
| **E** Embolden | white *enhancing* rows | **only in Light Arts** |

RUN/SCH in Light Arts is therefore the sole two-column case (`embolden_needs_own_column`), reading `[E][S]` on Protect and `[ ][S]` on Cure. Everything else is one slot: DRK/SCH shows `[N]` on Absorb and `[S]` on Protect in Light Arts, `[N]` and a spacer in Dark Arts; BLU/SCH shows `[D]` on a blue row and `[S]` on Protect. The decision is deliberately **per-stance, not per-row** — every row in a section has to agree on the column count or they stop lining up. `scholar_claims_row` backstops the handoff: if a stance-coloured row ever did want both, the S button keeps the slot. (The `nether_void` black rows — Drain/Drain II/Aspir — would be exactly that case, but they render through `ability_checkbox`, not this path, where they legitimately show `[S][N]` in Dark Arts.)

`is_song_config_key()` recognizes both grouped (group name) and ungrouped (ability name) song config keys so the per-member song limit counts them together. `is_persisted_target_key()` gates which party-buff keys persist to disk — numeric ME/P1-P5 (0-5) and the area key `'A'` persist; `al_`/`tt_` keys are session-only.

**UI creators** (settings-bound):
`checkbox`, `collapsing_checkbox_header`, `slider_int`, `combo`.

**Context object**:
```lua
{
    settings            = current_settings,
    save_callback       = save_callback,
    party_buffs         = party_buffs,
    job_def             = job_def,
    filter_func = {
        can_use_ability    = ...,  -- level check
    },
}
```

**Spell-learned checks** use `common.has_spell_learned(ability)` throughout.

### panel.lua – Debug Panel

Read-only display of game state, party buffs, server IDs, target indices. Shown when Debug Mode is enabled. The **Debug Mode** checkbox now lives in the panel header row (next to the Stratagems counter), moved out of the configuration window. The header also shows **BST Ready charges** (`gs.ready_charges`, cyan / red-when-low) next to the stratagem counter. Entity status values are rendered as human-readable labels (`Idle`, `Engaged`, `Dead`, `Resting`, `Mounted`, etc.) via a `STATUS_LABELS` lookup table.

The header row also holds the toggles that don't belong to any ability row: **AFK Sleep** (`afk_enabled` plus a **Timeout (minutes)** field shown only while enabled, see [afk.lua](#afklua--afk-sleep)), **Multisend Follow** (`multisend_follow`, see follow.lua), and the two job-conditional mid-cast modes — Bard **Pianissimo Fast Casting** (`pianissimo_fast_casting`) and Ninja **Cast with 1 Shadow** (`cast_with_1_shadow`), both described under [Scheduled Mid-Cast Removal](#scheduled-mid-cast-removal).

The debug row shows AFK state beside Moving/Action: `off` (disabled), `idle` (automation stopped), `asleep`, or `awake (Ns)` with the live countdown.

**Action** (`common.get_last_action()`) replaces the old `Casting: true/false` boolean: it names the last 0x028 category detected from the player — `casting_begin: Cure IV`, `spell_finish: Cure IV`, `job_ability`, `ws_finish`, … — so a cast can be watched start-to-finish instead of inferred from a flag. Melee rounds aren't recorded (they'd drown everything else while engaged), and the spell name is resolved only for the two magic categories (4/8), where `Param` is known to be a spell id. A cancelled action reuses its `*_begin` category, so `INTERRUPT_PARAM` is reported as `interrupted (casting_begin)` rather than as a fresh cast. Reads `none` before the first action, after the stuck-cast timeout fires, and after a zone change.

---

## Event System

| Event | Handler | Purpose |
|---|---|---|
| `load` | Sidekick.lua | Set initialisation flag |
| `unload` | Sidekick.lua | Save settings |
| `d3d_present` | Sidekick.lua | Automation tick + UI render |
| `packet_in` | Sidekick.lua | Casting state (0x028), Trust/pet buffs (0x028, 0x029), check response (0x0C9), zone change (0x0A), autorun-cancel guard (0x0D byte 0x42 / 0x37 byte 0x58, only while `follow_enabled`) |
| `command` | Sidekick.lua | `/sidekick` command handler |

### Trust Buff Tracking

Regular party members: buffs read directly from game memory.
Trusts (server_id ≥ 0x1000000): tracked via packets.

1. `register_pending_buff(server_id, buff_id, spell_name)` – on cast initiation
2. `handle_buff_application()` – packet 0x028, category 4 (spell_finish), player is the actor, `Param ~= common.INTERRUPT_PARAM` (a guard, in case an interrupt ever lands on category 4). An interrupt normally sends **no** category 4 at all, so the entry registered at cast start is never popped and a later unrelated `spell_finish` would claim it and record a buff the target never got — `handle_buff_application` therefore drops a pending entry older than `PENDING_BUFF_TIMEOUT` (10 s)
3. `handle_buff_removal(server_id, buff_id)` – packet 0x029
4. `clear_trust_buffs()` – on zone change

**0x029 is gated on the battle-message id.** A 0x029 (`GP_SERV_COMMAND_BATTLE_MESSAGE`) carries damage, misses, no-effect, synth results and skill-ups as well as status changes, and `param` (0x0C) is only a status id on the status messages — treating every 0x029 `param` as a buff id injected phantom statuses (a synth whose param happened to equal Sleep 2 / Terror 28…). `parse_message_packet` now also reads `message` (`MessageNum` @ 0x18, masked to its low 15 bits), and the handler acts only on `STATUS_GAIN_MESSAGES` (gain → `apply_*_buff`) and `STATUS_LOSE_MESSAGES` (loss → `handle_buff_removal`) — the latter is the wear-off path, since `EffectWearsOff` (206) is broadcast in-range on every status expiry and was previously mis-read as a *gain*. Message ids are listed in `Sidekick.lua`, verified against the server enums `msg_std.h` / `msg_basic.h`.

**Timed expiry.** Every packet-tracked target (Trusts, tracked targets, alliance members, the pet — all read from `trust_buffs`, never from memory) gets no reliable wear-off packet, so every buff application also records a start time and, when known, a base duration (`buff_timestamps` in `common.lua`, resolved by `common.base_buff_duration(buff_id, spell_name)`). The duration table covers Haste/Flurry/Refresh/Regen tiers/Phalanx II/Protect/Shell tiers, every bard song buff (ids 195–222) at a flat 120 s, and a **debuff backstop** (`BASE_DEBUFF_DURATION`): removable debuffs get a timed fall-off so a missed removal packet can't loop a cure spell forever. Any **removable** debuff defaults to a flat 120 s (covers Poison/Paralyze/Blind/Silence/Dia/Bio); "removable" is `REMOVABLE_SET`, built from the `PET_CLEANSE_DEBUFFS` superset rather than Erase's narrower list, since this backstop must cover every debuff with *any* remover. The explicit table only lists what that default misses — non-erasable statuses that still have a remover (Sleep 90 s, Petrify 60 s, Doom 30 s), more-accurate non-120 durations (Bind 60 s, Gravity 90 s, Slow 180 s), and the until-removed group (Curse/Bane/Disease/Plague, which never time out). Debuffs nothing can strip (Stun/Amnesia/Addle/Terror) are intentionally left out — no remover means no loop to guard against. `expire_timed_buffs()` runs each `refresh_game_state` tick and drops elapsed entries from `trust_buffs` for those packet-tracked targets so action modules see the effect as missing and recast; regular party members read from memory and are skipped. Buffs/debuffs matching no known duration fall back to `UNKNOWN_BUFF_DURATION` (300 s), so a status whose wear-off packet never arrives can't linger until zone; Sidekick never re-applies unknown statuses, so an early drop just clears tracking and re-adds on the next detection. Re-application refreshes the start time.

**Song slots are per-caster.** Each bard holds 2 song slots (`TRUST_SONG_SLOTS`) on a given target — song accounting is scoped by caster, not by target. Every tracked buff records its `src` (caster server id, from the 0x028 action packet's `UserId`, or our own player id for Sidekick's casts). When a new song lands from caster S on a target that already holds 2 of *S's* songs, S's oldest-start-time song is evicted; songs from other bards sit in their own bucket and never count. Applies to any ally target tracked in `trust_buffs` (Trusts, tracked players, alliance members). Skipped when the caster is unknown (0x029 carries no `UserId`; 0x028 is the reliable song path). No range check is needed: songs are only applied to targets the action packet reports as hit.

### Pet Status Tracking

The client keeps no pet buff memory, so a pet's buffs and debuffs are inferred from the same packets and stored in `trust_buffs`, keyed by the pet's server id (`pet_server_id`, refreshed each tick in `refresh_game_state`). Pets have normal entity ids (< 0x1000000), so the packet handlers also route through the `common.is_pet()` guard (alongside the Trust / tracked / alliance guards):

- **0x028** effect gain/loss (message 82 gain → `apply_pet_buff`; 83 loss → `handle_buff_removal`).
- **0x029** effect gain/loss, gated on the battle-message id (see [Trust Buff Tracking](#trust-buff-tracking)): gain → `apply_pet_buff` (a mob debuff landing on the pet arrives here as an out-of-party target gaining an effect); loss → `handle_buff_removal`.

The current pet's list is surfaced as `game_state.pet_debuffs` and consumed by `status_removal.execute_pet_debuff_removal`. When the pet changes or leaves (swap / release), the previous pet's entry is dropped so no stale status lingers. Because this is inferred rather than read from memory, it is best-effort — the same reliability caveat as Trust tracking, surfaced to the user via a warning tooltip.

---

## Settings System

JSON persistence via Ashita's settings module.

- **File naming**: `settings_white_mage.json`, `settings_geomancer.json`, etc.
- **Load flow**: Detect job → load job definition → load settings file → merge with `default_settings` → save merged result.
- **Auto-save**: On every UI change and addon unload.
- **Addon-wide defaults**: `default_settings` in `Sidekick.lua` holds the job-independent keys — focus, follow (`follow_enabled`/`follow_distance`/`multisend_follow`), `attack_range`, AFK Sleep (`afk_enabled`/`afk_timeout`), and resting (`rest_enabled`/`rest_timer`/`rest_distance`, inert unless the job is MP-based and lists `rest`). Job files supply the rest.
- **Start-button right-click menu** (both opt-in, default off): `load_stopped` ignores the saved `automation_enabled` state and loads stopped; `stop_after_zone` stops automation on zone change.
- **Party buffs**: `settings.party_buffs[ability_name][party_index] = true/false`. Persisted keys are numeric ME/P1-P5 (0-5) and the Bard area key `'A'`; alliance (`al_`) and tracked (`tt_`) keys are session-only.
- **Ungroup**: `settings.ungrouped_<group> = true` casts every tier in a group independently.
- **Stratagem hold**: `settings.stratagem_hold[<key>] = true` holds a spell until its assigned stratagem can fire.
- **Session-only**: Group/AOE heal target selection (`ctx.party_buffs['heal_group' / 'heal_aoe_group']`) is never written to disk — it resets each load.

---

## Error Handling

- **Module isolation**: `pcall` wraps every action module call in `automation.lua`.
- **Resource validation**: `action_core.is_usable()` gates every ability before execution.
- **Nil safety**: Guard checks (`if not player then return end`) throughout.
- **Inventory safety**: `item.lua` returns `nil` during zone transitions when inventory is unloaded.

---

## Known Limitations

- Alliance automation is limited to abilities with `target_outside = true` (spells and abilities that can target non-party members)
- Some buff IDs may vary by private server.
- Trust buff tracking has slight packet-based delay.
- Requires Ashita v4.
- Attack Range feature requires [Multisend](https://github.com/ThornyFFXI/Multisend).
- Bard Pianissimo Fast Casting and Ninja Cast with 1 Shadow require the Debuff addon by atom0s (`/debuff`).
