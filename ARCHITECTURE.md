# Medic Architecture

Technical overview of the Medic support-automation addon for Ashita v4 (CatsEyeXI).

## Design Philosophy

1. **Support-Only Focus** – Healing, buffing, debuff removal, and resource recovery. No offensive automation.
2. **Configuration over Code** – Job-specific details are data-driven tables, not hard-coded logic.
3. **Extensibility** – New jobs/actions can be added without touching core modules.
4. **DRY Utilities** – Shared helpers (`action_core`, `common`) eliminate boilerplate.
5. **Safety** – Multiple validation layers (resource, cooldown, status ailment, range) prevent errors.

---

## Directory Layout

```
Medic.lua                   Main addon entry point
lib/
  core/
    action_core.lua         Shared ability infrastructure (resource, cooldowns, buff-ID utils, candidacy helpers)
    automation.lua          Priority-based action selection engine
    common.lua              Shared utilities (logging, party, buffs, commands)
    parse_packets.lua       Raw-packet parsing (action packet 0x028)
    targets.lua             FFXI target-resolution helpers (from Ashita)
  actions/
    buff.lua                Buff maintenance (self + party, groups, Pianissimo)
    geo.lua                 Full Circle automation & Entrust management
    heal.lua                All healing (single-target, AOE, pet)
    item.lua                Consumable-based status removal (Echo Drops, Holy Water)
    recover.lua             MP/TP recovery abilities
    rest.lua                Automatic resting (/heal) with follow-target awareness
    revive.lua              Raise dead party/tracked/alliance members
    status_removal.lua      Debuff removal & sleep wake (single + AOE)
  jobs/
    bard.lua                BRD job definition
    dancer.lua              DNC job definition
    geomancer.lua           GEO job definition
    paladin.lua             PLD job definition
    red_mage.lua            RDM job definition
    rune_fencer.lua         RUN job definition
    scholar.lua             SCH job definition
    summoner.lua            SMN job definition
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
│  Medic.lua                                    │
│  • Job/level detection & change handling      │
│  • Event loop (d3d_present)                   │
│  • /medic command handler                     │
│  • Settings load/save/merge                   │
└──────┬─────────────────────────┬──────────────┘
       │ loads                   │ loads
       ▼                         ▼
┌──────────────┐         ┌──────────────────┐
│ Job Def      │         │ config.lua       │
│ (jobs/*.lua) │         │  orchestration   │
└──────┬───────┘         └──────┬───────────┘
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
│  • Command throttling (1 s default)           │
│  • pcall error isolation per module           │
└──────────┬────────────────────────────────────┘
           │ calls .execute() on each module
           ▼
┌───────────────────────────────────────────────┐
│  Action Modules  (actions/*.lua)              │
│  heal → status_removal → item → recover       │
│  → revive → geo → buff → rest                 │
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
1. Guard checks: addon loaded? automation enabled? mounted? in event/cutscene?
2. Refresh game_state (party HP, buffs, server IDs, pet info)
3. Check job/level change → reload job definition if needed
4. Iterate priority_order (defined per job)
5. For each action type → pcall action_module.execute(settings, job_def, ...)
6. First module to return {command, description} wins
7. Throttle check → QueueCommand → wait for next tick
```

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
| `is_ability_ready(id)` | Ability recast timer = 0 (with 0.5s post-delay) |
| `is_spell_ready(id)` | Spell recast timer = 0 (with 0.5s post-delay) |
| `get_ability_recast(id)` | Remaining ability recast |
| `get_spell_recast(id)` | Remaining spell recast |
| `set/is/get/clear_custom_recast(key)` | Manual recast tracking for shared cooldowns |

**Buff-ID Utilities** (formerly `buff_utils.lua`):

| Function | Purpose |
|---|---|
| `normalize_ids(ids)` | Coerce `number \| table \| nil` → flat table |
| `has_any_buff(active, check_ids)` | True if any active buff matches any check ID |
| `needs_buff(active, check_ids)` | True if none of the check IDs are active (nil = always needed) |

**Ability Candidacy**:

| Function | Purpose |
|---|---|
| `is_usable(ability, job_def)` | Returns `ok, reason` after checking status ailments, resource, and cooldown |
| `filter_usable(abilities, job_def, tag)` | Filters a list down to usable abilities, debug-logs skipped ones |
| `first_command(abilities, job_def, settings, tag, party_index, desc_fn)` | Returns the first usable ability as `{command, description}` or nil |
| `try_use(ability, job_def, settings, party_index, desc, game_state)` | Single-ability execution with optional Trust buff registration |

### common.lua

Shared utility module (~1,700 lines). Key areas:

- **Logging**: `printf`, `debugf`, `errorf`, `warnf` – unified via internal `log()` helper
- **Player state**: `get_player_level/job/mp/tp`, `is_idle/engaged/in_event`, `is_casting`, `is_player_moving`, `is_resting` (cached from entity status 33), `is_mounted` (entity status 5 or buff 252)
- **Party**: `get_party_size`, `get_party_member_name/zone/distance`, `get_party_server_ids`
- **Alliance**: `is_alliance_member`, `find_alliance_member`, `get_alliance_count`, `sorted_alliance_members`, `apply_alliance_member_buff`, `apply_external_buff`
- **Buffs**: `has_buff`, `get_player_buffs`, `get_party_buffs`, `get_trust_buffs`
- **Trust buff tracking**: `register_pending_buff`, `handle_buff_application`, `handle_buff_removal`, `clear_trust_buffs`
- **Status ailments**: `has_silence`, `has_amnesia`, `is_command_blocked`
- **Ability helpers**: `has_spell_learned(ability)`, `filter_abilities_by_level`, `build_ability_command`, `check_target_modifier`
- **Game state**: `refresh_game_state` – populates a shared table with party HP%, buffs, server IDs, pet info, and alliance sub-party snapshots every tick
- **Tracked target level resolution**: `handle_check_packet` – parses 0x0C9 check-response packet to store level and seed estimated max HP via `AVERAGE_HP_BY_LEVEL`
- **Outside-target helpers**: `resolve_focus_target`, `find_alliance_member`, `outside_abilities`, `build_ability_command_for_target`

### automation.lua

Priority-based action engine with 1-second command throttle. Calls each action module's `.execute()` via `pcall`, accepts both `{command, description}` tables and raw command strings.

### parse_packets.lua

Parses raw packet bytes for action packet 0x028 into structured Lua tables (actor, type, targets, actions). Used by Medic.lua's packet_in handler for casting-state detection and Trust buff tracking.

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

**Pet healing** (`execute_pet`): Monitors pet HP via game state. Uses `action_core.first_command()`.

### status_removal.lua – Debuff Removal & Sleep Wake

**Debuff removal** (`execute_debuff_removal`):
- Priority: self → focus target → party member with most debuffs.
- Matches abilities to specific debuff IDs they can cure.
- Uses `action_core.try_use()`.

**Wake from sleep** (`execute_wake`):
- Scans party buffs for sleep IDs (2, 19).
- 1 sleeping → cheapest single-target ability; 2+ → cheapest AOE ability.
- Uses `action_core.try_use()` for resource/cooldown/command pipeline.

### buff.lua – Buff Maintenance

- **Self buffs**: ON/OFF toggle, grouped or single.
- **Party buffs**: Per-member `<ME> <P1>–<P5>` selection stored in `settings.party_buffs`.
- **Groups**: Mutually exclusive (e.g., "Arts", "Storm", "Spikes"); dropdown selects active member.
- **Target modifier** (Pianissimo, etc.): If `ability.target_modifier = true`, sends modifier command first; next tick casts the buff.
- **Trust buff registration**: Calls `common.register_pending_buff()` for Trusts after cast.
- **Condition flags**: `idle_only`, `requires_pet`, `requires_buff`; combat-only gating is controlled by settings (`combat_only_<name>` / `combat_only_group_<group>`).
- Uses `action_core.try_use()`.

### item.lua – Consumable Status Removal

Data-driven via `ITEM_REMOVALS` table (priority-ordered):

| Priority | Item | Removes | Buff ID |
|---|---|---|---|
| 1 | Holy Water | Doom | 15 |
| 2 | Echo Drops | Silence | 6 |

4-second cooldown between uses. Inventory count validated per-tick. Returns `{command, description}`.

### recover.lua – Resource Recovery

MP and TP recovery. Monitors percentage thresholds. Uses `action_core.first_command()` and `filter_usable()`. Supports `requires_buff` prerequisites.

### geo.lua – Geomancer Automation

- **Geo buffs**: `<me>` Geo spells (`group = 'Geo'`, `exclusive_target = true`) cast on a single selected party member via the same ME/P1-P5 button targeting as other buffs. Single-select: choosing a target deselects the others.
- **Geo debuffs (Geo-bt)**: `<bt>` enemy debuffs (`group = 'Geo-bt'`) cast on the player's battle target. Combat-only (inherently, via `is_ability_combat_only`); the single selected debuff is chosen from a dropdown and cast through `geo.lua` (not `buff.lua`). A module-local `geo_bt_pending` flag tracks whether the current luopan belongs to the debuff.
- **Full Circle**: Monitors luopan distance from the selected Geo target (`get_pet_distance_from_member`); fires Full Circle when the pet exceeds the configurable yalm threshold, then recasts. Skipped when no Geo target is selected.
- **Luopan lifecycle**: Only one luopan exists at a time. In combat the selected Geo debuff takes over the luopan (Full Circle a non-debuff luopan, then cast); the distance-based Full Circle is suppressed while a debuff luopan is active so it isn't dismissed mid-fight. When combat ends, Full Circle frees the luopan for Geo buffs.
- **Entrust**: Name-based target + spell selection from UI dropdowns; fires Entrust → Indi spell on configured party member. Indi does not use a luopan, so it never conflicts with the Geo luopan.
- All Geo spells have `main_job_only = true`.

### rest.lua – Automatic Resting

- Two-phase timer: conditions become favourable → wait N seconds → `/heal on`.
- Stops at 100% MP or when follow-target distance exceeds threshold.

### revive.lua – Raise Dead Members

- Scans party (indices 1–5), tracked targets, and alliance sub-parties 2 & 3 for members with `entity_status == 3`.
- Filters abilities by level, recast readiness, **and** `requires_buff` prerequisites (e.g., Scholar needs Addendum: White buff 401).
- Validates range (`common.is_in_range`) before building each command.
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
        heal            = { ... },
        heal_aoe        = { ... },
        heal_pet        = { ... },
        critical        = { ... },
        buff            = { ... },
        debuff_removal  = { ... },
        wake            = { ... },
        recover_mp      = { ... },
        recover_tp      = { ... },
        recover_party_mp= { ... },
        geo             = { ... },
        target_modifier = { ... },
        revive          = { ... },  -- raise spells (WHM/SCH/RDM)
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
    id              = 0,            -- Recast ID
    command         = function(idx) return '/ma "Cure IV" <p' .. idx .. '>' end,
    -- or: command = '/ja "Divine Seal" <me>',
    buff_id         = 43,           -- number or table of buff IDs to track
    debuff_id       = 3,            -- debuff ID(s) this ability removes
    idle_only       = false,        -- green  – is_idle()
    combat_only     = false,        -- yellow – is_combat() (user-toggleable via right-click)
    requires_pet    = false,
    requires_buff   = 401,          -- prerequisite buff ID(s)
    group           = 'regen',      -- mutually exclusive group
    self_only       = false,
    main_job_only   = false,        -- hidden when job is subjob
    target_modifier = false,        -- needs Pianissimo / similar before party cast
    wakes           = true,         -- can remove sleep
    range           = 20,
    is_main_job     = true,         -- false for subjob-sourced abilities
    resource_type   = nil,          -- override job resource_type ('mp'/'tp')
    target_outside  = false,        -- true for abilities that can target non-party members
}
```

---

## UI System

### config.lua – Orchestration

- Builds a **context object** (`ctx`) containing settings, callbacks, job_def, filter functions, and party_buffs.
- Delegates all rendering to `components.lua`.
- **DRY helpers**:
  - `render_party_dropdown(label, key, include_player, names, settings, cb)` – reusable for Focus/Follow/Recovery/Entrust Target dropdowns.
  - `has_usable_abilities(abilities)` – quick check for any level-appropriate abilities.

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
| `item_silence_removal_checkbox(ctx)` | Echo Drops checkbox (via `render_item_removal_checkbox`) |
| `item_doom_removal_checkbox(ctx)` | Holy Water checkbox (via `render_item_removal_checkbox`) |

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

Read-only display of game state, party buffs, server IDs, target indices. Shown when Debug Mode is enabled. Entity status values are rendered as human-readable labels (`Idle`, `Engaged`, `Dead`, `Resting`, `Mounted`, etc.) via a `STATUS_LABELS` lookup table.

---

## Event System

| Event | Handler | Purpose |
|---|---|---|
| `load` | Medic.lua | Set initialisation flag |
| `unload` | Medic.lua | Save settings |
| `d3d_present` | Medic.lua | Automation tick + UI render |
| `packet_in` | Medic.lua | Casting state (0x028), Trust buffs (0x028 completion, 0x029 removal) |
| `command` | Medic.lua | `/medic` command handler |

### Trust Buff Tracking

Regular party members: buffs read directly from game memory.
Trusts (server_id ≥ 0x1000000): tracked via packets.

1. `register_pending_buff(server_id, buff_id)` – on cast initiation
2. `handle_buff_application()` – packet 0x028 with completion flag
3. `handle_buff_removal(server_id, buff_id)` – packet 0x029
4. `clear_trust_buffs()` – on zone change

---

## Settings System

JSON persistence via Ashita's settings module.

- **File naming**: `settings_white_mage.json`, `settings_geomancer.json`, etc.
- **Load flow**: Detect job → load job definition → load settings file → merge with `default_settings` → save merged result.
- **Auto-save**: On every UI change and addon unload.
- **Party buffs**: `settings.party_buffs[ability_name][party_index] = true/false`.

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
