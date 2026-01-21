# Changelog

All notable changes to Medic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-01-18

### Added
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
- **Config UI Refactored**: Reduced `config_ui.lua` from 1,758 lines to 876 lines (52% reduction) by extracting all rendering logic to `ui_components.lua`
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