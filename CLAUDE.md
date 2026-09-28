# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sidekick is an **Ashita v4 addon** (Lua) for the CatsEyeXI FFXI private server. It automates
support only — healing, buffing, debuff removal, resource recovery, revive, and pet support
(healing, buffs, and debuff removal for GEO / BST / DRG / PUP pets, including auto-equipping
the consumable a pet ability needs). It deliberately does **not** automate combat, tanking,
nuking, weaponskills, or combat movement/positioning. The one movement it will do is **opt-in
leader following** (`follow_enabled`, off by default): `/follow` a chosen party member when they
walk beyond `follow_distance`. A second, narrower exception is the **opt-in send-pet-at-target
toggle** in the **Pet Control** section (Puppetmaster/Summoner/Beastmaster, `pet_control_enabled`,
off by default, see `lib/actions/pet.lua`): sends the *pet*, not the player, at the mob picked by
`pet_control_target` — `<t>`, the player's own cursor target and only while engaged, or `<bt>`, the
battle target, with no engaged check. It is labelled in the UI with the job's own ability (PUP Deploy / SMN Assault /
BST Fight) — "Deploy" is one job's ability name, never the feature's name. Entry point is
`Sidekick.lua`; everything else lives under `lib/`.

## Build / lint / test

No build step and no package manager. The addon runs inside Ashita's embedded interpreter
(LuaJIT + Ashita's `AshitaCore` FFI bindings), which does not exist here. Outside the game
there are **offline tests and a lint**, which need only `luajit` and `luacheck`
(`apt-get install luajit lua-check`), run from the repo root:

- `make check` runs both; `make test` / `make lint` run one; `make test FILE=jobs_test`
  runs one file. Without `make`: `luajit tests/run.lua` and `luacheck .`.
- `tests/ashita.lua` is a fake client (`T{}`, `AshitaCore`, `GetEntity`, the chat, settings
  and imgui modules) that reads from one `fake.state` table, so the real `lib/` modules
  load unchanged. `tests/README.md` shows how to add a test.
- `tests/jobs_test.lua` checks every job file against the CatsEyeXI SQL in `tests/data/`:
  `spell_id` / `recast_id` / `ability_id` resolve to the row the command names, `cost`
  matches the server MP cost, buff/debuff ids exist, every `default_settings` key is read by
  the engine, and every job is in `job_map`. **Run it after any job-file edit**; a failure
  there is a wrong id in the job file, not a test bug.
- `tests/data/*.lua` is generated (`tools/gen_resources.lua`, `make resources
  CATSEYE=../catseyexi`) — never edit it by hand. The weekly `server-data` workflow
  regenerates it and opens a PR when the server's rows change.
- CI (`.github/workflows/ci.yml`) runs lint and tests on every push to `main` and every PR.
  Lint ignores the warning classes already present in `lib/` (see `.luacheckrc`); don't add
  new warnings.

A passing test proves the logic against the fake client, not the real one. Behavior still
needs **in-game verification**:
- Reload after edits: `/addon reload sidekick` (or `/addon load sidekick` first time).
- Open UI: `/sidekick` (alias `/sk`). Toggle automation: `/sidekick start` | `stop` | `toggle`.
- Inspect live state: `/sidekick panel` (debug game-state panel), `/sidekick debug` (verbose log),
  `/sidekick recast` (recast timers), `/sidekick status`.

Run the tests and lint before handing back a change, and still treat it as unverified until
the user confirms in-game. Prefer edits that are obviously correct by inspection; call out
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
`{command, description}` table or a raw command string. A **1.1-second throttle** gates all
commands, matching the game's server-side post-action lockout: it is stamped on send, then
re-stamped by `automation.notify_action_finished()` from the player's own 0x028 finish
packets (`ACTION_FINISH_CATEGORIES` in `Sidekick.lua`), so the timer runs from when the
server resolved the action rather than from the send that preceded it — a whole cast time
earlier for a spell. Re-stamping only moves the timer later, never earlier. While resting (`/heal`), the loop runs **only** the `rest` module — no action interrupts a rest;
it ends at full MP or when the follow target passes `rest_distance`. Scholar
stratagems use a follow-up lock so the paired spell fires the tick after the stratagem JA.
A result carrying `scheduled_removal` queues a mid-cast `/debuff` (Bard Pianissimo fast
casting, Ninja 1-shadow Utsusemi) — that one fires from the tick loop ahead of the
`is_casting` guard, not through the throttled pipeline.

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
`lib/core/common.lua` (~3200 lines) holds everything else: logging (`printf`/`debugf`/
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
and `ARCHITECTURE.md` for every ability field (`level`, `cost`, `value`, `spell_id` /
`recast_id` (see below), `buff_id`, `debuff_id`, `group`, `idle_only`, `combat_only`,
`requires_buff`, `blocked_by`, `target_outside`, `main_job_only`, `target_modifier`,
`requires_item`, `requires_precast`, and the pet/ammo fields `pet_required`,
`requires_pet_name`, `requires_equipped_ammo`, `ammo_label`, `ammo_main_job_only`,
`requires_ready_charge`, `ready_charge_cost`, `reapply_interval`, …).

**Ability id fields map 1:1 onto CatsEyeXI server SQL.** An ability carries exactly one
cooldown id, and the *field name* — not the command text — selects which recast table
`action_core.is_usable` reads, so it must match the command:

| Field | Source | Applies to |
|---|---|---|
| `spell_id` | [`spell_list.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/spell_list.sql) `spellid` | `/ma` abilities (spell recast + `HasSpell`) |
| `recast_id` | [`abilities.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/abilities.sql) `recastId` | everything else (`/ja`, `/item`, `/pet`, `/ws`) |
| `ability_id` | [`abilities.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/abilities.sql) `abilityId` | merit-unlocked JAs only (`HasAbility(ability_id + 512)`) |
| `buff_id` / `debuff_id` | [`status_effects.sql`](https://github.com/CatsAndBoats/catseyexi/blob/base/sql/status_effects.sql) `id` | status tracked / removed |

Note `recastId` and `abilityId` are different columns of the same row — do not conflate them.
Item/ammo tier-spec tables (BST `PET_FOOD`, NIN `SHURIKENS`, PUP `OILS`, …) use a plain `id`
= item id; those are not abilities and keep the bare `id`.

**UI** (`lib/ui/`). `config.lua` orchestrates the ImGui config window and delegates rendering
to `components.lua`; `panel.lua` is the debug panel; `tooltips.lua` is hover help. Settings
persist **per character** (not per job) via Ashita's `settings` module, in
`config/addons/sidekick/<Name>_<ServerId>/settings.lua` — one file, default alias
`'settings'`, shared by every job. Save with a bare `settings.save()`: the API is
`save([alias])`, so `settings.save(tbl, filename)` is a silent no-op that returns `false`.
Some UI state (group/AOE heal target selection, alliance/tracked buff toggles) is
intentionally **session-only** and never written to disk.

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
- **Bug fixes and new logic in `lib/core` or `lib/actions`:** add a `tests/<module>_test.lua`
  case that fails without the change. If the module calls something the fake client lacks,
  add that one method to `tests/ashita.lua`, reading from `fake.state`.
- **A spell the job file keeps although the server has no row for it** goes in
  `missing_on_server` at the top of `tests/jobs_test.lua`, with the job file's note as the reason.

## Conventions

- Ashita uses `T{}` for tracked tables — match surrounding usage.
- Match the existing comment density and naming; job files are heavily commented with FFXI
  spell/recast ids, keep that.
- Commits/PRs are made only when the user asks (they commit manually). Default branch `main`.
- **`README.md`'s "Latest Updates" section shows only the current release**, written as a
  brief, user-facing summary (bullets, no implementation detail) — not the full history.
  `CHANGELOG.md` is the durable, detailed record and keeps every past version. When a new
  version ships, replace the README's "Latest Updates" entry with the new version's brief
  notes rather than appending to it, and add the full entry to `CHANGELOG.md` as usual.
- **One line per item in the README, no exceptions.** Every bullet under Added / Changed /
  Fixed is a single line: bolded feature or fix name, then one sentence of what it does or
  what it stopped doing. No sub-bullets, no second paragraph, no rationale, no walkthrough of
  the settings involved, no before/after story. The whole 2.7.0 section fits in ~3KB; if a
  release's notes are running past that, the bullets are too long, not too many. Anything
  that needs a paragraph to explain belongs in `CHANGELOG.md` and nowhere else. Mention a
  setting or command by name (**Song Duration (s)**, `/sk widget`) when the reader needs it
  to find the feature — but never explain how to use it.
- **Credit in the README is the person's name in bold at the end of the line**, after an em
  dash, and nothing else — `... — **Toranko**`, or `— **Atsumu**, **Pax**` for two. No
  "Thanks to", no "for reporting the bug", no separate sentence; the prose form stays in
  `CHANGELOG.md`, which is the permanent record and must carry the credit before the README
  does. A bullet nobody reported or asked for gets no name.
