# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sidekick is an **Ashita v4 addon** (Lua) for the CatsEyeXI FFXI private server. It automates
support only — healing, buffing, debuff removal, resource recovery, revive, and pet support
(healing, buffs, and debuff removal for GEO / BST / DRG / PUP pets, including auto-equipping
the consumable a pet ability needs). It deliberately does **not** automate combat, tanking,
nuking, weaponskills, or movement. Entry point is `Sidekick.lua`; everything else lives under
`lib/`.

## Build / lint / test

There is **none**. This is a game client addon, not a standalone project — no package
manager, no build step, no test suite, no linter config. The Lua runs inside Ashita's
embedded interpreter (LuaJIT + Ashita's `AshitaCore` FFI bindings), which does not exist in
this dev environment, so **you cannot run or import the code here**. `require('common')`,
`imgui`, `AshitaCore:...`, `T{}` etc. only resolve in-game.

Verification is **in-game only**:
- Reload after edits: `/addon reload sidekick` (or `/addon load sidekick` first time).
- Open UI: `/sidekick` (alias `/sk`). Toggle automation: `/sidekick start` | `stop` | `toggle`.
- Inspect live state: `/sidekick panel` (debug game-state panel), `/sidekick debug` (verbose log),
  `/sidekick recast` (recast timers), `/sidekick status`.

Because the code can't execute outside the client, treat changes as unverified until the
user confirms in-game. Prefer edits that are obviously correct by inspection; call out
anything that needs a live check.

## Architecture (big picture)

Read `ARCHITECTURE.md` and `README.md` for the full map — they are kept current. The parts
that matter for editing:

**Tick loop.** `Sidekick.lua`'s `d3d_present` handler runs every frame: refreshes
`common.game_state` (one snapshot of player/party/alliance/pet HP, MP, buffs, server IDs —
read this instead of re-querying `AshitaCore` per module), guards (loading / mounted / dead /
casting / can't-attack), detects job/level change and reloads the job def, then calls
`automation.execute_priority_actions`.

**Priority engine** (`lib/core/automation.lua`). Iterates the job's `priority_order`, calls
each `action_module.execute(...)` inside `pcall` (a throwing module is logged, not fatal).
**First module to return a truthy result wins the tick.** Results may be a
`{command, description}` table or a raw command string. A **1-second throttle** gates all
commands. Resting (`/heal`) is broken automatically before urgent actions fire. Scholar
stratagems use a follow-up lock so the paired spell fires the tick after the stratagem JA.

**Action modules** (`lib/actions/*.lua`). Uniform contract:
```lua
function module.execute(settings, job_def, main_level, sub_level, player_resource)
    -- return {command=..., description=...} | command string | nil
end
```
`heal.lua` also exports `execute_aoe` and `execute_pet`; `status_removal.lua` exports
`execute_wake`, `execute_debuff_removal`, and `execute_pet_debuff_removal`. These are wired
to action-type names in the `action_modules` table in `Sidekick.lua`.

**Core helpers.** `lib/core/action_core.lua` is the shared ability pipeline (resource/MP-TP
check → cooldown/recast → status-ailment gate → build command): use `is_usable`,
`filter_usable`, `first_command`, `try_use` instead of re-implementing gating.
`lib/core/common.lua` (~1900 lines) holds everything else: logging (`printf`/`debugf`/
`errorf`/`warnf`), player/party/alliance state, buff tracking (incl. packet-based pet
status via `is_pet`/`apply_pet_buff` into `game_state.pet_debuffs`), consumable-ammo
equip helpers (`is_ammo_equipped`/`ammo_equip_command`/`count_equippable_items`),
`pet_type_ok`, `refresh_game_state`, charge math (Scholar stratagems + BST Ready share
`charges_from_recast`), packet handlers.

**Jobs are data** (`lib/jobs/*.lua`). Each returns a table: `job_id`, `job_name`,
`resource_type` (`'mp'`/`'tp'`), an `abilities` table keyed by action type
(`heal`, `buff`, `heal_aoe`, `heal_pet`, `pet_debuff_removal`, `recover_mp`, `geo`,
`revive`, …), `default_settings`, `priority_order`, and optional `validate_ability`. No
control flow belongs here beyond a `command` closure and an optional validator. See
`paladin.lua` for the minimal shape, `beastmaster.lua` for the pet/consumable-ammo shape,
and `ARCHITECTURE.md` for every ability field (`level`, `cost`, `value`, `id` = recast id,
`buff_id`, `debuff_id`, `group`, `idle_only`, `combat_only`, `requires_buff`,
`target_outside`, `main_job_only`, `target_modifier`, and the pet/ammo fields
`pet_required`, `requires_pet_name`, `requires_equipped_ammo`, `ammo_label`,
`ammo_main_job_only`, `requires_ready_charge`, `ready_charge_cost`, `reapply_interval`, …).

**UI** (`lib/ui/`). `config.lua` orchestrates the ImGui config window and delegates rendering
to `components.lua`; `panel.lua` is the debug panel; `tooltips.lua` is hover help. Settings
persist per job as `settings_<job_name>.json` via Ashita's `settings` module; some UI state
(group/AOE heal target selection, alliance/tracked buff toggles) is intentionally
**session-only** and never written to disk.

## Adding or changing things

- **New supported job:** add `lib/jobs/<job>.lua` (data only) and register its FFXI job id in
  the `job_map` in `load_single_job_definition` (`Sidekick.lua`). Main/sub abilities are merged
  automatically with subjob-duplicate filtering; the master `priority_order` in
  `load_job_definition` defines execution order across both jobs.
- **New action type:** add `lib/actions/<x>.lua` following the `execute` contract, wire it
  into the `action_modules` table in `Sidekick.lua`, and add its name to the master
  `priority_order` and to each job's `priority_order`.
- Keep job files pure data and lean; put shared logic in `action_core`/`common`, not in job
  or UI files. Some buff IDs are server-specific to CatsEyeXI.

## Conventions

- Ashita uses `T{}` for tracked tables — match surrounding usage.
- Match the existing comment density and naming; job files are heavily commented with FFXI
  spell/recast ids, keep that.
- Commits/PRs are made only when the user asks (they commit manually). Default branch `main`.
