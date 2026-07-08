# Changelog

All notable changes to Medic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.3.0]

### Added
- **Debuff base durations (timed backstop)**: Packet-detected debuffs that a Medic ability can remove now record a base duration so a missed removal packet can't keep the tracked status alive forever. Any erasable debuff defaults to 120s (Poison/Paralyze/Blind/Silence/Dia/Bio); the explicit table covers only what that misses — Sleep 90s, Petrify 60s, Doom 30s (non-erasable but removable), Bind 60s / Gravity 90s / Slow 180s (accurate non-120 durations), and Curse/Bane/Disease/Plague (never time out). Debuffs nothing strips (Stun/Amnesia/Addle/Terror) are excluded — no remover, no loop to guard.
- **Timed expiry now covers alliance members & the pet**: `expire_timed_buffs` previously ran only for Trusts and tracked targets. Alliance members and the pet are also read from the packet-tracked `trust_buffs` (never from memory), so they now get the same timer backstop for both buffs and debuffs. Regular party members (read from memory) are still skipped.
- **Timed buff expiry for Trusts & tracked targets**: Trusts and tracked targets get no reliable wear-off packets, so tracked buffs now record a start time and base duration on application and are dropped by timer once elapsed (generalizing the BST Reward `reapply_interval` idea). Base durations: Haste/Flurry 180s, Refresh 150s, Regen 75s / II–III 60s, Phalanx II 120s, Protect/Shell all tiers 1800s, all bard songs 120s. Buffs without a known duration keep the old packet-only behavior; re-application refreshes the timer.
- **Per-caster song slot eviction**: Song slots are tracked per caster (2 per bard per target, mirroring FFXI). Each tracked buff records its caster (from the 0x028 action packet). When a new song lands from a caster who already has 2 songs on that target, that caster's oldest-start-time song is evicted; songs from a different bard sit in their own slot bucket and are never affected. Applies to any tracked ally (Trusts, tracked players, alliance members); skipped when the caster is unknown (0x029 packets carry no caster).

### Fixed
- **Removal spells no longer loop on Trusts/tracked/alliance targets**: These targets give no reliable wear-off packet, so after Medic cast e.g. Poisona the tracked Poison lingered and the cure re-fired every tick. On casting a na-/Erase spell, Medic now optimistically drops one matching status from the target's tracked list (`common.drop_removed_debuff`); each removal spell clears one status per cast, and the debuff base-duration timer catches anything guessed wrong.

## [2.2.0] - 2026-07-06

Adds three pet-support jobs (Beastmaster, Dragoon, Puppetmaster) with consumable-ammo auto-equip and packet-based pet status tracking, alongside a repo-wide dead-code sweep and UI polish.

### Added
- **Beastmaster (BST) support**: Pet-only automation. Pet healing via **Reward** (gated on a **Pet Food** biscuit worn in the ammo slot), a **Reward (Regen)** buff variant using a **Pet Poultice**, **Reward (Erase)** pet debuff removal using a **Pet Roborant**, and party AOE heal **Wild Carrot** from a rabbit jug pet (Lucky Lulush / Rabbit), gated on 2 spare Ready charges (its cost). Only one ammo can be worn at a time, so the biscuit / poultice / roborant Rewards never contend for the slot on the same tick.
- **Dragoon (DRG) support**: Pet-only automation. Pet (wyvern) healing via **Spirit Link** (transfers the master's HP), plus self-buffs **Ancient Circle** and **Spirit Bond**.
- **Puppetmaster (PUP) support**: Pet-only automation. Automaton healing via **Repair** and automaton debuff removal via **Maintenance**, both gated on an **Automaton Oil** worn in the ammo slot (higher tiers heal more). Oils can only be equipped with PUP as **main** job (`ammo_main_job_only`), so auto-equip is skipped when PUP is the subjob.
- **Consumable-Ammo Gating & Auto-Equip**: Abilities can require a consumable equipped in the ammo slot (`requires_equipped_ammo`). When a usable tier is owned but not worn, Medic issues a `/equip ammo` for the best tier the player's **main** level allows — searching main inventory and all eight Mog Wardrobes — the tick before the ability fires. If none are owned the ability is gated out (effectively disabled). New `common` helpers: `count_equippable_items`, `get_equipped_item_id`, `is_ammo_equipped`, `find_equippable_item`, `select_ammo_equip_command`, `ammo_equip_command`.
- **Pet Status Tracking (packet-based)**: The client keeps no pet buff memory, so a pet's buffs/debuffs are now inferred from the same 0x028/0x029 packets used for Trusts and routed into `trust_buffs`, keyed by the pet's server id (refreshed each tick). Exposed as `game_state.pet_debuffs`; the tracked list is dropped when the pet is swapped or released so no stale status lingers. New helpers `common.is_pet`, `common.apply_pet_buff`. As with Trusts, this tracking is inferred and not perfectly reliable.
- **Pet Debuff Removal**: New `pet_debuff_removal` action type (`status_removal.execute_pet_debuff_removal`) strips status ailments from the pet — BST Reward + Pet Roborant, PUP Maintenance + Oil — using the packet-tracked `game_state.pet_debuffs` list. Rendered as its own collapsible config section with an inline ammo count and an *"unreliable tracking"* warning tooltip.
- **Beastmaster Ready Charges**: Ready is a charge system (recast id 102; 3 charges, 30s each) like Scholar stratagems. The stratagem charge math was generalized into a shared `charges_from_recast` helper now driving both. Surfaced as `game_state.ready_charges` and shown in the `/med panel` header next to the stratagem counter. Abilities gate on it via `requires_ready_charge`, with `ready_charge_cost` (default 1) for multi-charge moves like Wild Carrot (2).
- **`requires_pet_name` (generalized pet-type gate)**: Replaces Summoner's `requires_carbuncle` with a list of acceptable pet names (`common.pet_type_ok`), shared by job validators and the config UI. Used by SMN (Carbuncle blood pacts) and BST (rabbit-only Wild Carrot). The UI grays such rows and tooltips the required pet when the wrong pet is out.
- **Buff `reapply_interval`**: For buffs we can't detect on the target (e.g. pet Regen from Reward, which pet tracking can't see), the buff is reapplied on a fixed time interval since the last cast instead of every recast, so consumables aren't wasted.
- **CLAUDE.md**: Contributor / AI-assistant guidance doc (architecture map, in-game verification notes, conventions).

### Changed
- **Party Button Tooltips**: Hovering a party target button (**ME** / **P1–P5**) now shows that member's character name. On Trust/tracked buttons the reliability caveat (*"...Removal / Buff tracking is not totally reliable"*) is appended **below** the name instead of replacing it. Driven by `common.get_party_member_name()`.
- **"Not Learned" as Tooltip**: The inline ` (Not Learned)` label suffix on unlearned abilities was removed. Unlearned abilities now surface a **Not Learned** hover tooltip instead, alongside the existing Combat Only / Idle Only tooltips, for cleaner ability rows. Applies to `self_single_ability`, `party_single_ability`, and `ability_checkbox`.
- **Debug Scalars Moved to Panel**: The debug scalar readout (Zone / Target / Moving / Casting, plus the target's party slot + target index when the target is a party member) moved out of the configuration window into the `/med panel` debug header row. Shown only while Debug Mode is on.
- **Bard Area-Column Alignment**: Row leading-slot rendering unified behind a new `job_def.has_songs` flag (set during job load when either job carries song magic) and a single `render_leading_slot` helper. A BRD/SCH combo now draws exactly **one** indent instead of stacking the Scholar S-button spacer and the Bard `[A]` area-column indent.

### Fixed
- **Afflatus Solace Recast ID**: Corrected recast id from `245` to `29` (White Mage) so its cooldown gate reads the right timer.

### Removed
- **`medic_heartbeat.log`**: Stray committed log file removed from the repo.

### Internal / Maintenance
- Repo-wide dead-code sweep across `common.lua`, `action_core.lua`, `automation.lua`, `parse_packets.lua`, `config.lua`, `components.lua`, and every `lib/jobs/*.lua`: removed unused functions, write-only state, dead fallbacks, commented-out blocks, and unused exports/fields (~480 lines net removed). No functional change intended.
  - Deleted the unused custom-recast subsystem (`get_ability_recast`, `set/is/get/clear_custom_recast`) from `action_core`.
  - Dropped the dead throttle API and a duplicate require/table from `automation`.
  - Replaced hand-rolled buff scans with `action_core.has_any_buff` in the action modules.
  - Dropped unused `UserIndex` / `SpellGroup` / message fields from `parse_packets`.
- `ARCHITECTURE.md` updated to drop the removed `action_core` recast helpers.

## [2.1.0] - 2026-07-05

### Added
- **Group / AOE Heal Target Selection**: Group healing and AOE healing now have per-target selection buttons (ME / P1-P5, plus alliance B/C and tracked targets for Group healing) rendered under the threshold slider as **Group Targets** / **AOE Targets**. Deselecting a member excludes them from the scan (single-target Group healing) or from the below-threshold average (AOE). Defaults are asymmetric so behavior is correct even when the config window is never opened: party and tracked members are **ON** by default; alliance (B/C) members are **OFF** by default. AOE selection lists ME and party members only (Curaga-style AOE is party-scoped). Selections are **per-session** and reset on each load. Backed by session-only state in `ctx.party_buffs['heal_group' / 'heal_aoe_group']`, read by `heal.lua` via `make_group_filter()`.
- **Bard Area Songs (`[A]` button)**: Every Bard song now has an **A** button in the leading slot, left of the ME/P1-P5 target buttons. It sings the song **without Pianissimo** so everyone within the song's AoE (10 yalms) receives it. The area recast tracks only in-range, same-zone party members who are **not** given a specific ME/P button, so dedicated single-target songs don't trigger an endless area recast. Trusts are skipped for recast timing (their buff tracking is unreliable) but are still covered by the AoE cast. Mazurka (no Pianissimo) is always area.
- **Single-Target Self Songs via Pianissimo**: The **ME** button for Bard songs now uses Pianissimo, so a Bard can single-target buff themselves the same way as P1-P5. The ME button requires Pianissimo to be available (below its level the `[A]` area button still works).
- **Stacking Same-`buff_id` Songs (Ungroup)**: A grouped buff can be **ungrouped** via right-click, casting every tier in the group independently instead of only the single selected tier. Enables e.g. Mage's Ballad + Mage's Ballad II (both `buff_id` 196) on the same target simultaneously. Song-needed logic counts active buff instances (`count_instances` / `wanted_instances`) so stacked tiers each demand their own instance. Persisted per group as `ungrouped_<group>` (off / grouped by default).
- **Hold for Stratagem**: New checkbox in the Scholar stratagem assignment popup. When **ON**, the spell is skipped until an assigned stratagem can fire (enough charges, correct Arts, not status-blocked). When **OFF** (default), a stratagem that can't fire falls through and the spell casts **without** it, rather than blocking the cast. Persisted per ability/group key as `stratagem_hold[<key>]`.
- **Debug Mode in Panel Header**: The **Debug Mode** checkbox now lives in the debug panel header row (next to the Stratagems counter), moved out of the configuration window.

### Changed
- **Automatic Config Window Sizing**: The configuration window now uses imgui `AlwaysAutoResize` instead of a manually computed fixed width, so it grows/shrinks to fit its content (party size, alliance, tracked targets, new buttons). Opening the window force-expands it once, so a collapsed `imgui.ini` state no longer leaves the user staring at an empty title bar. A mere collapse now keeps the window open; only the `[X]` closes it.
- **Debug Mode Location**: The Debug Mode toggle moved from the bottom of the configuration window to the `/med panel` header.
- **Stratagem Tooltips**: Added hover help for the Scholar stratagem button and the Hold for Stratagem checkbox.
- **Trust Buff-Tracking Warning**: Trust/tracked buttons in the Buff section now show a *"Trust/Tracked Buff tracking is not totally reliable"* tooltip (distinct from the removal-section warning), driven by a new `ctx.show_buff_warning` flag.
- **Focus / Group threshold labels**: Slider labels shortened (`Focus Healing (HP%)` → `Focus (HP%)`).

### Fixed
- **`HasSpell` Check**: `common.has_spell_learned()` no longer treats an unlearned spell as learned. Previously `ok and known or true` returned `true` whenever `known` was `false` (unlearned), so unavailable spells were wrongly considered known. Now only a `pcall` **error** assumes known.
- **Stratagem Stuck from High-Level SCH**: A stratagem assigned on a high-level Scholar main job carried over into `stratagem_settings` when the player switched to a lower level or `???/SCH`, leaving automation trying to fire a JA the player couldn't use and the config un-removable. `common.prune_unavailable_stratagems()` (called on job/level change from `Medic.lua`) now drops any assigned stratagem above the current SCH level, bailing on a transient level-0 read so config is never wiped during zoning.
- **Geo-bt UI Alignment**: Geo-bt debuff rows no longer receive the Scholar stratagem spacer indent (the Geo section has no S-button rows to align with). Bard song rows likewise skip the stratagem spacer because the `[A]` button already supplies the leading indent, preventing a double indent.
- **Song 2-Limit**: Song-slot counting now keys on `magic == 'song'` (recognizing both grouped and ungrouped song config keys via `is_song_config_key`) instead of `target_modifier`, so the per-member song limit (2 main / 1 sub) is enforced correctly, including Mazurka (which has no Pianissimo).

## [2.0.0] - 2026-03-04

### BREAKING CHANGES
- **PL Mode Removed**: All PL Mode functionality (`pl_mode_active`, `setup_pl_mode_job`, `clear_player_data`, `restore_normal_mode`, and related settings) has been removed. Users should clear any legacy `pl_*` settings keys from their configuration files.
- **Module Consolidation**: `heal_aoe.lua`, `heal_pet.lua`, `debuff_removal.lua`, and `wake.lua` have been merged into `heal.lua` and `status_removal.lua` respectively. Direct imports of the old modules will fail.
- **Config UI Renamed**: `config_ui.lua` renamed to `ui_config.lua`. Any external references must be updated.

### Added
- **Revive / Raise System**: New `lib/actions/revive.lua` action module automatically raises dead party members, tracked targets, and alliance sub-party members. Filters abilities by level, recast readiness, `requires_buff` prerequisites (e.g., Scholar's Raise spells require Addendum: White), and range before casting. Falls back through all usable abilities if the preferred spell cannot be built. Controlled by `settings.revive_enabled`. Job definitions for White Mage (Raise/Raise II/Arise), Scholar (Raise/Raise II), and Red Mage (Raise) include `revive` ability blocks.
- **Mount Detection**: `common.is_mounted()` returns `true` when the player is riding a mount, detected via entity status 5 OR buff 252 (Mounted) as a dual safeguard. Synced once per tick inside `refresh_game_state()` from the player snapshot. `automation_tick()` returns early when mounted, suppressing all automation while riding.
- **Alliance Support**: Healing, debuff removal, wake, and buff automation extended to alliance sub-parties B and C (flat indices 6–17). Requires abilities with `target_outside = true`. `game_state.alliance[2|3]` snapshots are built each tick alongside `alliance_leaders` and `alliance_member_sids` for packet-based buff tracking. Alliance members dropped from the roster have their stale `trust_buffs` entries purged automatically.
- **Alliance UI**: Per-member buff-toggle buttons (`<B0>`–`<B5>`, `<C0>`–`<C5>`) rendered in the configuration window; alliance sub-parties displayed in the debug panel with HP, MP, TP, job, buffs, party leader (`^`), and Trust NPC (`*`) indicators. Alliance members are excluded from the tracked-target add list.
- **HP Estimation for Tracked Targets**: On add, a `/check <name>` command is issued; the 0x0C9 check-response packet resolves the target's level. A built-in `AVERAGE_HP_BY_LEVEL` table (levels 1–75) is used to seed `max_hp` before the target is ever seen at 100%, enabling accurate deficit-based healing from the first heal.
- **`requires_no_buff` Ability Flag**: Buff abilities can specify `requires_no_buff = <id or table>`. The ability is skipped while any of the listed buffs are active on the player. Used for mutually exclusive stances (e.g., Saber Dance vs. Fan Dance).
- **Dancer Level-75 Abilities**: Added Saber Dance, Fan Dance, No Foot Rise, and Presto to the Dancer job definition. Saber Dance and Fan Dance share a `dance` group and use `requires_no_buff` to prevent both being active simultaneously.
- **`common.get_alliance_count()`**: Centralized helper returning the total number of active alliance members across sub-parties B and C.
- **`common.sorted_alliance_members(sub_party)`**: Returns sub-party members sorted by local slot index (0–5). Replaces inline sort logic previously duplicated across `panel.lua`, `config.lua`, and `components.lua`.
- **`common.apply_external_buff(server_id, buff_id)`**: Shared dedup-insert helper used by both `apply_alliance_member_buff` and `apply_tracked_target_buff`, replacing duplicated implementations.
- **`game_state.alliance_size`**: Separate counter for active alliance members only; `party_size` now counts main-party members (indices 0–5) only.
- **Centralized Game State**: New `common.game_state` snapshot refreshed once per automation tick provides a consistent view of player/party HP, MP, buffs, and positions.
- **Action Core Module**: New `lib/core/action_core.lua` consolidates resource management, cooldown tracking, buff-ID utilities, and ability candidacy helpers (replacing deleted `lib/core/resource.lua`).
- **Packet-Based Buff Tracking**: Buff gain/loss tracking via 0x028 and 0x029 packets for Trusts and tracked (out-of-party) targets.
- **Tracked Targets**: Session-scoped tracking of out-of-party players for heal, buff, and status removal automation.
- **Debug Panel**: New `lib/ui/panel.lua` debug info panel showing party game_state snapshot (toggle with `/medic panel`).
- **Status Removal Module**: New combined `lib/actions/status_removal.lua` with `execute_debuff_removal` and `execute_wake` entry points.
- **Geomancer Geo Targeting**: The `<me>` Geo buff spells now target a single party member (`group = 'Geo'`, `exclusive_target = true`), cast through the same ME/P1-P5 button targeting as other party buffs. Selecting a target deselects the others (single-select, handled by `toggle_group_party_buff` in `components.lua`). `common.get_pet_distance_from_member(party_index)` measures luopan drift from the selected target; distance-based Full Circle is skipped when no Geo target is selected.
- **Geomancer Geo Debuffs (Geo-bt)**: New `<bt>` enemy-target debuff spells (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) in `abilities.geo` with `group = 'Geo-bt'`. Combat-only (enforced by `common.is_ability_combat_only` for any `<bt>` ability; the right-click Combat Only toggle is suppressed). Rendered under **Enable Geo** as an ON/OFF + dropdown (`selected_Geo-bt`). Casting and luopan lifecycle live in `geo.lua`, not `buff.lua`.
- **Single Luopan Lifecycle**: `geo.lua` tracks luopan ownership with a `geo_bt_pending` flag. In combat the selected Geo debuff takes over the single luopan (Full Circle a non-debuff luopan, then cast); the distance-based Full Circle is suppressed while a debuff luopan is active so it isn't dismissed mid-fight. When combat ends, Full Circle frees the luopan so Geo buffs can be re-placed. Indi/Entrust do not use a luopan and are unaffected.
- **Configuration Tooltips**: Comprehensive contextual tooltips added across the configuration UI (`lib/ui/tooltips.lua`), explaining each section, slider, dropdown, button, and checkbox. Wired in via `ui.item_tooltip()` in `config.lua`/`components.lua`.

### Changed
- **`is_resting()` now cached**: `common.is_resting()` no longer calls `GetPlayerEntity()` on every invocation. The value is synced once per tick inside `refresh_game_state()` from the player's entity status (33 = resting), eliminating per-call overhead in the hot automation loop. Transient entity read failures do not clobber the cached value.
- **Revive priority above Buff**: In the `priority_order` for White Mage, Scholar, and Red Mage, `revive` is now listed before `buff`. Dead members are raised before living members receive buffs out-of-combat. No in-combat effect since all raise spells are `idle_only = true`.
- **Status labels in debug panel**: `fmt_status()` in `panel.lua` now maps common entity status integers to human-readable strings (`Idle`, `Engaged`, `Dead`, `Resting`, `Mounted`, `Sitting`) via a `STATUS_LABELS` table. Unknown codes still fall back to `tostring()`.
- **Config UI mounted state**: When `common.is_mounted()` is true the configuration window shows `Paused` button text and `Automation paused (mounted).` status text, distinct from the normal paused/resting states.
- **Heal AOE**: Merged into `heal.lua` as `execute_aoe`; requires at least 2 members below threshold before firing (hardcoded, previously configurable via slider).
- **Heal Pet**: Merged into `heal.lua` as `execute_pet`.
- **Recovery Priority**: Recovery actions (Convert, Manafont, etc.) execute before critical heals to ensure MP is available for subsequent healing.
- **Curaga II**: Fixed MP cost from 60 to 120 (White Mage).
- **Bar Spells**: Converted from dynamic-target functions to static self-target `<me>` commands (White Mage).
- **Attack Range Labels**: Attack Range options now display explicit distances — `Off`, `Melee (3 yalms)`, `Ranged (15 yalms)` (previously `Off`/`Melee`/`Ranged`).
- **Tracked Target Button**: The "Add Tracked Target" button is relabeled "Track Target".

### Removed
- **PL Mode**: All PL Mode functionality and UI elements.
- **lib/core/resource.lua**: Replaced by `action_core.lua`.
- **lib/actions/heal_aoe.lua**: Merged into `heal.lua`.
- **lib/actions/heal_pet.lua**: Merged into `heal.lua`.
- **lib/actions/debuff_removal.lua**: Merged into `status_removal.lua`.
- **lib/actions/wake.lua**: Merged into `status_removal.lua`.

## [1.3.0] - 2026-01-22

### Added
- **Contradance for Dancer**: Added Contradance to Dancer's critical abilities category for emergency situations
- **Pianissimo Support for Bard**: Bard songs can now be cast on party members using the Pianissimo ability (level 20+):
  - New `target_modifier` ability category for abilities that redirect self-targeted spells to party members
  - All Bard songs (except Mazurkas) flagged with `target_modifier = true` to indicate Pianissimo compatibility
  - Bard songs converted to function-based commands for dynamic targeting: `function(target) return '/ma "Song Name" '..target end`
  - Party buttons (P1-P5) automatically disabled when Pianissimo unavailable (below level 20 main/sub)
  - Grayed-out text and "(Pianissimo Lv20)" suffix displayed for songs requiring unavailable Pianissimo
  - Common `check_target_modifier()` helper function validates modifier availability (level, settings, blocks, resources, cooldown)
  - Integrated into buff.lua: checks `ability.target_modifier`, calls helper, uses modifier before casting party-targeted buff
- **Song Limit Enforcement**: Bard songs per party member limited based on job type to match game mechanics:
  - **Bard Main Job**: Maximum 2 songs per party member (including self)
  - **Bard Sub Job**: Maximum 1 song per party member (including self)
  - Auto-deselects existing song when limit reached before enabling new selection
  - Only applies to abilities with `target_modifier = true` flag
- **Party Buff Settings Persistence**: Party buff selections (song targets, etc.) now persist through addon reloads:
  - Settings saved to `settings.party_buffs[ability_name][party_index]` structure
  - Loaded on first UI render, similar to Entrust and Focus target persistence
  - Prevents loss of song configurations when reloading addon or changing zones

### Changed
- **Entrust Logic Refactored**: Geomancer Entrust now uses common `check_target_modifier()` helper for DRY code:
  - Removed ~40 lines of duplicated validation logic (level, settings, blocks, resources, cooldown)
  - Creates temporary job_def structure to present Entrust in target_modifier format
  - Calls centralized validation helper, maintains original dedicated UI for 10-minute cooldown
  - Preserves spell selection dropdown + target dropdown UX for infrequent single-use ability

### Technical
- Created `check_target_modifier()` in common.lua: validates target modifier ability availability and returns command to use it
- Function checks: buff already active, level requirement, disabled setting, status blocks, resource cost, ability cooldown
- Added `combat_only` check to `check_target_modifier()` validation flow
- Party buff toggle now saves selections to `settings.party_buffs` for persistence across sessions
- Config UI loads `settings.party_buffs` on first render to restore saved party buff selections
- Song limit logic in `toggle_party_buff()`: counts active songs with `target_modifier = true`, deselects when at limit
- Helper function `find_ability_by_name()` added to ui_components.lua for ability lookups
- Modified `render_party_buttons()` to accept ability object, check target_modifier availability, disable P1-P5 buttons when modifier unavailable
- Party buff rendering pushes LIGHT_GRAY text color for disabled modifier buttons (4 colors total vs 3 for normal disabled)

## [1.2.0] - 2026-01-18

### Added
- **Automatic Resting**: New rest action module for MP-based jobs automatically triggers `/heal on` when idle to recover MP:
  - **Two-Phase Timer**: Conditions become favorable → wait configurable timer duration (1-20s, default 5s) → start resting
  - **HP Threshold Safety**: Stops resting if any party member drops below threshold (1-99%, default 70%)
  - **Follow Target System**: Optional follow target selection (P1-P5) with distance monitoring (1-15 yalms, default 7)
  - **Smart Blocking**: Prevents resting when engaged, moving, casting, or when MP is full
  - **Priority**: Executes last in action priority order to allow healing/buffing to take precedence
  - Available for: White Mage, Scholar, Red Mage, Paladin, Geomancer, Bard, Rune Fencer, Summoner
- **Conditional Ability Conditions**: Two mutually exclusive conditions for conditional ability usage with color-coded UI indicators:
  - `idle_only` (green) - Only usable when not in combat (checks `is_idle()`)
  - `combat_only` (yellow) - Only usable when in combat with a battle target nearby (checks `is_combat()`); user-toggleable per ability/group via right-click
- **Item-Based Status Removal**: New item action module automatically uses consumables to remove debuffs:
  - **Echo Drops** for Silence (buff_id 6)
  - **Holy Water** for Doom (buff_id 15)
  - UI displays inventory count with checkboxes to enable/disable each item
  - Shows "(?)" during zone loading to preserve settings; only auto-disables on genuine 0 count
  - 4-second cooldown between item uses to avoid recast issues
  - Doom removal has higher priority than Silence
- **Pet Entity Consolidation**: New `get_pet_entity()` function provides single source of truth for pet entity access across all pet-related operations
- **Job-Specific Ability Validation**: Jobs can now define custom `validate_ability` functions for fine-grained control over when abilities can be used
- **Summoner Pet Name Validation**: Carbuncle-specific abilities (Healing Ruby, Healing Ruby II, Shining Ruby) now automatically check if Carbuncle is summoned before attempting to use
- **Avatar-Agnostic Abilities**: Summoner abilities like Avatar's Favor work with any summoned avatar, not just Carbuncle
- **Summoner Critical Ability**: Added Apogee to Summoner's critical abilities category
- **UI Component Extraction**: Created new `ui_components.lua` module (835 lines) consolidating all reusable UI rendering functions and constants for better code organization
- **Subjob Level Filtering**: Config UI now properly filters subjob abilities by subjob level, ensuring only abilities available at current subjob level are displayed
- **Geomancer Main Job Restriction**: Geo spells now restricted to main job only via `main_job_only=true` flag; hidden from UI when GEO is subjob
- **Entrust System**: Name-based Entrust target and spell selection with dynamic party member dropdowns; settings persist across sessions

### Changed
- **Pet Functions Refactored**: `has_pet()`, `get_pet_hp_percent()`, and `get_pet_distance()` now use consolidated `get_pet_entity()` for improved code maintainability
- **Filter Abilities Enhanced**: `filter_abilities_by_level()` now accepts optional `job_def` parameter to enable job-specific validation hooks
- **Config UI Refactored**: Reduced `ui_config.lua` from 1,758 lines to 876 lines (52% reduction) by extracting all rendering logic to `ui_components.lua`
- **Context Object Pattern**: UI components now use a context object `{settings, save_callback, party_buffs, job_def, ...}` for cleaner function signatures

### Technical
- Added `is_combat()` function to check for combat state (has battle target nearby)
- Updated `is_engaged()` function to check player status for active engagement (status == 1)
- `filter_abilities_by_level()` now checks `idle_only` and user-configured combat-only settings (`combat_only_*`) to conditionally filter abilities
- All UI components updated to display conditional flags with color coding: idle_only (green), combat_only (yellow)
- Introduced `requires_carbuncle` flag for Summoner abilities to distinguish Carbuncle-specific abilities from avatar-agnostic ones
- Job definition merging now copies `validate_ability` function when present
- All action modules updated to pass `job_def` to `filter_abilities_by_level()`
- All UI rendering sections now call `can_use_ability()` before displaying each ability to ensure proper level filtering
- Added `main_job_only` flag to ability definitions; `can_use_ability()` checks this flag and returns false when ability is marked main job only but `is_main_job=false`
- Geomancer Geo spells now have `main_job_only=true` flag to prevent casting when GEO is subjob
- Entrust target and spell stored as character names in settings (`entrust_target`, `entrust_spell`); validated against current party on each render
- Created centralized constants in `ui_components.lua`: colors (COMBAT_ONLY, IDLE_ONLY, button states), widths (DROPDOWN_WIDTH=300, SLIDER_WIDTH=250), and spacing values
- Implemented reusable render functions: `onoff_button`, `group_dropdown`, `party_single_ability`, `party_grouped_ability`, `ability_checkbox`, `render_ability` (dispatcher)

## [1.1.0] - 2026-01-17

### Added
- **Critical HP Abilities**: New critical ability category triggers emergency abilities (e.g., Divine Seal, Martyr) when party members drop below critical threshold (default 30%, configurable 1-50%) before attempting regular heals
- **Button-Based Party Buff Targeting**: Single-target buffs now display ME/P1-P5 buttons for precise control over who receives each buff (e.g., Haste, Refresh, Protect, Shell, Enspells, etc.)
- **Trust Buff Tracking**: Buffs can now be tracked and cast on Trusts using packet-based detection (packets 0x028 for application, 0x029 for removal)
- **Group Dropdown Consolidation**: When multiple abilities exist in a group (e.g., Cure I-V), they are now consolidated into a dropdown selector for cleaner UI
- **Enhanced Casting State Detection**: Improved packet-based casting detection using offset 0x0F state byte (0x00 = casting started, 0x01+ = casting complete)
- **Subjob Duplicate Filtering**: Config UI now automatically hides duplicate abilities from subjob when they exist in main job (e.g., Cure spells)
- **Single-Target Buff Support**: Jobs can now cast single-target buffs on party members with intelligent uptime tracking and range validation (20 yalms)
- **Movement Blocking**: Casting is now prevented while the player is moving to avoid interrupted spells
- **Grouped Ability Management**: Only the currently visible ability in a dropdown group can be enabled; all others in the group are automatically disabled when dropdown selection changes
- **New Ability Default State**: All newly discovered abilities now default to OFF (disabled) until explicitly enabled by the player
- **Unknown Spell Button Protection**: ON/OFF buttons and party target buttons (ME/P1-P5) are now fully disabled (grayed out and unclickable) when a spell is not yet learned

### Changed
- **Healing Priority**: Updated healing priority to: Critical lowest HP (if below critical threshold) → Focus target → Regular lowest HP
- **Collapsible UI Sections**: All major feature sections (Healing, Buffs, Debuff Removal, etc.) are now collapsible headers with checkboxes for cleaner organization
- **Buff UI**: Single-target buffs (function commands) now use button-based targeting instead of checkboxes
- **Buff Logic**: Abilities are automatically enabled when any ME/P1-P5 button is selected, and disabled when all buttons are deselected
- **Party Buff Validation**: Added zone matching and range checking before casting buffs on party members
- **Casting State Logic**: Simplified casting detection to use action state byte only, not action ID, for more reliable state tracking
- **Party Buff Buttons**: Trust members now show disabled (dark gray) buttons in party buff UI to indicate buffs cannot be cast
- **Job Detection**: Moved job change detection from packet handler to automation loop for simpler, more reliable code (no longer uses packets 0x1B, 0x44, 0x1A)
- **Ability Default State**: Changed from enabled-by-default to disabled-by-default for all newly discovered abilities
- **Grouped Abilities**: Dropdown selection change now enforces single-enabled-ability constraint by disabling all other group members

### Fixed
- Button-based buffs now properly check if the ability is enabled before attempting to cast
- Party buff state correctly syncs with settings on button toggle
- Casting state now properly detects spell casting regardless of action ID changes between start and completion packets
- UI no longer shows duplicate abilities when same spell exists in both main job and subjob
- Grouped abilities now correctly maintain single-enabled constraint when dropdown selection changes
- Unknown spell buttons are now properly disabled and unclickable until spell is learned

## [1.0.0] - 2026-01-11

This is the first official release.

## Features

### Core Support Actions
- **Single-Target Healing**: Intelligent HP deficit-based heal selection
- **AOE Healing**: Party-wide healing when multiple members need HP
- **Pet Healing**: Automated healing for luopan pets
- **Sleep Removal (Wake)**: Automatically wake sleeping party members
- **Debuff Removal**: Remove poison, paralysis, silence, and other negative status effects
- **Buff Maintenance**: Auto-apply and maintain self-buffs and party buffs
- **Resource Recovery**: Automated MP and TP recovery abilities
- **Geomancer Support**: Automatic Full Circle execution when luopan exceeds distance threshold

### User Interface
- **ImGui Configuration UI**: User-friendly settings interface
- **Per-Ability Toggles**: Enable/disable individual abilities
- **Party Buff Configuration**: Per-party-member buttons to control which buffs to cast on each member (P1-P5)
- **Threshold Configuration**: Customize HP/TP/MP thresholds
- **Focus Target Support**: Prioritize specific party members
- **Level-Based Filtering**: Shows only abilities available at your current level
- **Auto-Refresh**: UI updates automatically when jobs or levels change

### Core System Features
- **Smart Resource Management**: Automatic MP/TP checking and cooldown tracking
- **Status Ailment Detection**: Automatically detects and prevents casting when Silenced (magic) or Amnesiac (job abilities)
- **Party Buff Management**: Per-party-member buff configuration with intelligent uptime tracking
- **Focus Target Support**: Prioritize specific party members for healing/support
- **Main/Sub Job Support**: Automatically loads and merges abilities from both supported jobs
- **Priority-Based Actions**: Configurable action priority order per job
- **Settings Persistence**: Settings saved per job in JSON format

## Supported Jobs

Currently implemented support jobs:

- **Bard** (BRD)
  - Buff with songs (Minuet, Minne, Paeon, Madrigal, Prelude, March, Ballad, Etude, Carol, Mambo, Mazurka, Scherzo, Threnody, etc.)

- **Dancer** (DNC)
  - Single-target healing with waltzes (Curing Waltz I/II/III)
  - AOE healing with waltzes (Divine Waltz, Divine Waltz II)
  - Debuff removal with waltz (Healing Waltz)
  - Buff with sambas (Drain Samba I/II/III, Aspir Samba, Haste Samba)
  - Buff with jigs (Spectral Jig)

- **Geomancer** (GEO)
  - AOE healing with job abilities (Mending Halation)
  - Pet healing with job abilities (Life Cycle)
  - Buff with geomancy spells (Indi-Haste, Indi-STR, Indi-DEX, Indi-VIT, Indi-AGI, Indi-INT, Indi-MND, Indi-CHR, Indi-Acumen, Indi-Fury, Indi-Barrier, etc.)
  - Buff with job abilities (Lasting Emanation, Ecliptic Attrition, Collimated Fervor, Blaze of Glory, Dematerialize)
  - MP recovery with job abilities (Radial Arcana)
  - Geomancy management (automatic Full Circle execution)

- **Paladin** (PLD)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with white magic (Protect I-IV, Shell I-IV)

- **Red Mage** (RDM)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Haste, Refresh, Phalanx, Phalanx II, Enfire, Enblizzard, Enaero, Enstone, Enthunder, Enwater, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)

- **Rune Fencer** (RUN)
  - AOE healing with job abilities (Vivacious Pulse)
  - Buff with enhancing magic (Protect I-III, Shell I-IV, Regen I-III, Refresh, Barfire, Barblizzard, Baraero, Barstone, Barthunder, Barwater, etc.)

- **Scholar** (SCH)
  - Single-target healing with white magic (Cure I-IV)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Regen I-III, Reraise, Reraise II, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)
  - Buff with geomancy spells (Sandstorm, Rainstorm, Windstorm, Firestorm, Hailstorm, Thunderstorm, Voidstorm, Aurorastorm, Klimaform)
  - Buff with elemental magic (Blaze Spikes, Ice Spikes, Shock Spikes)
  - Buff with job abilities (Light Arts, Dark Arts, Addendum: White, Addendum: Black, Sublimation)
  - MP recovery with job abilities (Sublimation)

- **Summoner** (SMN)
  - Single-target healing with blood pacts (Healing Ruby)
  - AOE healing with blood pacts (Healing Ruby II)
  - Buff with blood pacts (Shining Ruby)

- **White Mage** (WHM)
  - Single-target healing with white magic (Cure I-V)
  - AOE healing with white magic (Curaga I-IV)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona, Esuna)
  - Buff with white magic (Protectra I-V, Shellra I-V, Protect I-IV, Shell I-IV, Haste, Regen I-III, Reraise, Reraise II, Reraise III, Auspice, Aquaveil, Blink, Stoneskin, Enlight, Barfira, Barblizzara, Baraera, Barstonra, Barthundra, Barwatera, Barsleepra, Barpoisonra, Barparalyzra, Barblindra, Barsilencera, Barvira, Barpetra, Baramnesra)