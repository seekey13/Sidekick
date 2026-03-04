# Changelog

All notable changes to Medic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-03-03

### BREAKING CHANGES
- **PL Mode Removed**: All PL Mode functionality (`pl_mode_active`, `setup_pl_mode_job`, `clear_player_data`, `restore_normal_mode`, and related settings) has been removed. Users should clear any legacy `pl_*` settings keys from their configuration files.
- **Module Consolidation**: `heal_aoe.lua`, `heal_pet.lua`, `debuff_removal.lua`, and `wake.lua` have been merged into `heal.lua` and `status_removal.lua` respectively. Direct imports of the old modules will fail.
- **Config UI Renamed**: `config_ui.lua` renamed to `ui_config.lua`. Any external references must be updated.

### Added
- **Centralized Game State**: New `common.game_state` snapshot refreshed once per automation tick provides a consistent view of player/party HP, MP, buffs, and positions.
- **Action Core Module**: New `lib/core/action_core.lua` consolidates resource management, cooldown tracking, buff-ID utilities, and ability candidacy helpers (replacing deleted `lib/core/resource.lua`).
- **Packet-Based Buff Tracking**: Buff gain/loss tracking via 0x028 and 0x029 packets for Trusts and tracked (out-of-party) targets.
- **Tracked Targets**: Session-scoped tracking of out-of-party players for heal, buff, and status removal automation.
- **Debug Panel**: New `lib/ui/panel.lua` debug info panel showing party game_state snapshot (toggle with `/medic panel`).
- **Status Removal Module**: New combined `lib/actions/status_removal.lua` with `execute_debuff_removal` and `execute_wake` entry points.

### Changed
- **Heal AOE**: Merged into `heal.lua` as `execute_aoe`; requires at least 2 members below threshold before firing (hardcoded, previously configurable via slider).
- **Heal Pet**: Merged into `heal.lua` as `execute_pet`.
- **Recovery Priority**: Recovery actions (Convert, Manafont, etc.) execute before critical heals to ensure MP is available for subsequent healing.
- **Curaga II**: Fixed MP cost from 60 to 120 (White Mage).
- **Bar Spells**: Converted from dynamic-target functions to static self-target `<me>` commands (White Mage).

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
- **Conditional Ability Flags**: Three mutually exclusive flags for conditional ability usage with color-coded UI indicators:
  - `idle_only` (green) - Only usable when not in combat (checks `is_idle()`)
  - `combat_only` (yellow) - Only usable when in combat with a battle target nearby (checks `is_combat()`)
  - `engaged_only` (red) - Only usable when actively engaged/locked on to a target (checks `is_engaged()`)
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
- `filter_abilities_by_level()` now checks `idle_only`, `combat_only`, and `engaged_only` flags to conditionally filter abilities
- All UI components updated to display three conditional flags with color coding: idle_only (green), combat_only (yellow), engaged_only (red)
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