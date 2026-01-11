# Changelog

All notable changes to Sidekick will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.9.0] - 2026-01-08

### Added
- **Roll Automation System (roll.lua)**
  - New action module for Corsair Phantom Roll and Double-Up automation
  - Automatic roll casting: Roll 1 first, then Roll 2 (if Corsair is main job)
  - Smart Double-Up logic: automatically doubles up until lucky number or hit threshold reached
  - Configurable hit threshold (5-9, default 5): stops doubling when total reaches threshold
  - Lucky number detection: immediately stops doubling when lucky number is hit
  - Safety limit: prevents doubling at 11+ (would bust at 12)
  - Real-time packet-based roll total tracking (action packet 0x028, category 0x23)
  - Roll state tracking: monitors totals, expecting_double_up flags, and stability per roll
  - Intelligent packet attribution: uses last_roll_action to assign packets to correct roll
  - Cooldown management: 1 second after initial roll, 6 seconds between double-ups
  - UI integration: displays current roll totals with color coding (green for lucky, yellow for threshold)
  - Roll selection dropdowns with lucky/unlucky number display
  - Automatic state reset when roll selection changes in config UI
  - Bust detection: automatically adjusts to 1 roll slot when busted
  - Works alongside Quick Draw shots and other Corsair abilities
  - Priority positioning: executes before buffs and attacks for consistent roll maintenance

- **Ammunition Check System**
  - New `ammo_required` flag for abilities that require ammunition
  - `common.has_ammo()` function checks equipped ammo slot and validates item ID
  - Prevents execution of ranged attacks and Quick Draw shots without ammo
  - Automatically applied to Corsair Quick Draw shots and Ranger abilities
  - Config UI displays abilities requiring ammo with proper validation

### Changed
- **Corsair Job Enhancement**
  - Reorganized ability priority: roll → buff → weaponskill → attack
  - All Quick Draw shots now marked with `ammo_required = true`
  - Added Ranged Attack to attack abilities with ammo requirement
  - Roll abilities organized by level with buff_id, lucky, and unlucky values
  - Default settings include roll1_name, roll2_name, and roll_hit_threshold

### Technical Details
- Roll state persists across roll changes and bust conditions
- Packet handler extracts roll value from byte offset 0x0F (divided by 8)
- Roll totals accumulate: initial roll + sum of all double-ups
- State machine tracks: roll1/roll2 totals, expecting_double_up, is_stable, last_roll_action
- Mark stable: when roll hits lucky number OR threshold, prevents further double-ups
- Config UI receives roll module reference for state reset callbacks
- Ammo checking uses inventory manager to validate equipped item in slot 3
- Roll selection mutual exclusivity: changing Roll1 clears Roll2 if duplicate (and vice versa)

## [2.8.0] - 2026-01-05

### Fixed
- **Scholar Job Ability Buffs Visibility**
  - Fixed duplicate `buff` array definition causing job abilities to be overwritten by magic buffs
  - Merged job abilities (Light Arts, Dark Arts, Sublimation, etc.) with magic buffs into single array
  - All Scholar job abilities now properly appear in configuration UI
  - Resolved issue where only magic buffs were visible, hiding critical job abilities

### Added
- **Multiple Buff ID Support**
  - Added support for arrays of buff_id values in ability definitions
  - Light Arts now checks for both buff_id 358 (Light Arts) or 401 (Addendum: White)
  - Dark Arts now checks for both buff_id 359 (Dark Arts) or 402 (Addendum: Black)
  - Buff checking logic enhanced to handle both single values and arrays
  - Prevents redundant buff casting when enhanced versions are active

- **Scholar Spell Addendum Requirements**
  - Added `addendum = 'black'` to tier IV nukes requiring Addendum: Black:
    - Stone IV (70), Water IV (71), Aero IV (72), Fire IV (73), Blizzard IV (74), Thunder IV (75)
    - Sleep (30), Sleep II (65), Dispel (32)
  - Added `addendum = 'white'` to debuff removal spells requiring Addendum: White:
    - Poisona (10), Paralyna (12), Blindna (17), Silena (22)
    - Reraise (35), Erase (39), Viruna (46), Stona (50)
    - Reraise II (70), Raise II (70)
  - Will be used eventually but currently just data

### Changed
- **Scholar Job Definition Cleanup**
  - Removed redundant `art` properties from all abilities
  - Simplified ability definitions for better maintainability
  - Storm spells changed from `combat_only = false` to `combat_only = true`
  - All storm spells (Aurorastorm, Voidstorm, Thunderstorm, Hailstorm, Firestorm, Windstorm, Rainstorm, Sandstorm) now only cast during combat

### Technical Details
- Enhanced `buff.lua` to check arrays of buff_id values
- Modified ability filtering to handle both `buff_id = 358` and `buff_id = {358, 401}` formats
- Iterates through all buff_id values when checking for active buffs
- Scholar job definition reorganized for clarity and correctness
- Fixed Lua table key collision that was silently overwriting abilities

## [2.7.0] - 2026-01-04

### Added
- **Geo Action Module**
  - New `geo` action module for automatic Full Circle execution
  - Monitors pet distance in real-time using `common.get_pet_distance()`
  - Configurable distance threshold (7-30 yalms, default 10) via slider control
  - Automatically uses Full Circle when pet luopan exceeds distance threshold
  - Requires active pet and geo abilities enabled in configuration
  - Integrated into priority order for all jobs with geo abilities

- **Geomancer Spell Enhancements**
  - Added `buff_id` fields to all Indi and Geo spells mapping to status effect IDs
  - Status effect mappings use geo_ prefixed effects from status_effects.sql
  - Both Indi and Geo versions of same spells share identical buff_id values
  - Enables proper buff tracking and prevents redundant spell casting

### Changed
- **Geomancer Geo Spells Targeting**
  - Changed all Geo spells to target `<me>` instead of `<t>`
  - Geo spells now apply buffs to the caster rather than target
  - Consistent with FFXI mechanics where Geo spells create luopan effects on caster

### Fixed
- **Healing Spells UI Visibility**
  - Fixed healing spells not hiding when Party Healing is disabled
  - Changed condition from `settings.heal_enabled or settings.focus_enabled` to `settings.heal_enabled`
  - Healing ability list now only shows when Party Healing is specifically enabled
- **Pet Healing**
  - Fixed issue with `heal_pet` that was preventing it from displaying in the Config UI.

### Technical Details
- Geo module uses `common.has_pet()` and `common.get_pet_distance()` for pet validation
- Distance threshold setting: `geo_distance_threshold` (default 10 yalms)
- Buff ID mappings: Indi-Haste/Geo-Haste = 580, Indi-Regen/Geo-Regen = 539, etc.
- All 46 Geomancer spells now have proper buff_id fields for status tracking
- Config UI properly hides healing abilities when only Focus Healing is enabled

## [2.6.0] - 2026-01-02

### Added
- **Weaponskill Automation**
  - New `weaponskill` action module for automated weaponskill execution
  - User-configurable weaponskill name via text input field
  - Adjustable TP threshold (1000-3000) with slider control
  - Requires being engaged with valid target
  - Command format: `/ws "WeaponskillName" <t>` (with quotes for multi-word names)
  - No recast checking (trusts user input)
  - Global setting available for all jobs in configuration UI
  - Added to master_priority after 'stun', before 'nuke'
  - Integrated into all 22 job priority_order lists

- **Pet Attack on Engagement (Go)**
  - New `go` action module for automated pet attack commands
  - Automatically sends pet to attack when player engages a new enemy
  - Tracks last target to detect new engagements (one-shot per target)
  - Requires having an active pet
  - Leverages attack.lua validation logic for range and combat checks
  - Enable/disable toggle in configuration UI
  - Works for all pet jobs (BST, SMN, DRG, PUP)

### Changed
- **Geomancer Spell Organization**
  - Reorganized buff list: Indi spells first (highest level to lowest), then Geo spells
  - Added `group = 'Indi'` to all Indi- spells for mutual exclusivity
  - Added `group = 'Geo'` to all Geo- spells for mutual exclusivity
  - Verified all spell IDs match spell_list.sql database (768-827 range)
  - Improved UI organization for easier spell selection

### Technical Details
- Weaponskill settings: `weaponskill_enabled`, `weaponskill_name`, `weaponskill_tp_threshold`
- Go settings: `go_enabled`
- Both actions respect combat state and automation enabled flag
- Weaponskill positioned early in priority for consistent TP usage
- Go action reuses attack.lua validation to maintain code consistency

## [2.5.0] - 2026-01-02

### Added
- **Job Support Expansion**
  - Added basic support for 10 additional jobs using existing feature set, expanding coverage from 12 to 22 supported jobs
  - **Geomancer** (GEO): Geomancy spells (Indi-/Geo-), Job Abilities, Healing and MP Recovery.
  - **Runefencer** (RUN): Magic & Vivacious Pulse
  - **Bard** (BRD): Songs (Ballad, Minne, Paeon, Madrigal, etc.), buff and debuff abilities
  - **Ninja** (NIN): Utsusemi shadows, ninjutsu debuffs (Kurayami, Hojo, etc.) & nukes.
  - **Corsair** (COR): Quick Draw shots.
  - **Scholar** (SCH): Light/Dark Arts, Stratagems, Helix spells, Klimaform, & Magic.
  - **Puppetmaster** (PUP): Activate, Deus Ex Automata, & Repair
  - **Beastmaster** (BST): Beast summoning, Reward, and Killer Instinct
  - **Thief** (THF): Steal, Mug, Despoil, Bully, Assassin's Charge, Feint
  - **Blue Mage** (BLU): Only Burst Affinity.

- **UI Spell/Song Filtering**
  - Automatic disabling of unlearned magic/songs in configuration UI
  - Checks job level and spell availability to prevent invalid selections
  - Improves user experience by hiding unusable abilities
  - Applies to all magic-using jobs (BLM, WHM, RDM, SCH, GEO, BRD, BLU, etc.)

### Changed
- **Job Coverage**: Expanded supported jobs list from 12 to 22, covering all of FFXI jobs

## [2.4.0] - 2025-12-28

### Added
- **Samurai job support**
  - Buff maintenance: Hasso (Lv25, attack speed/accuracy), Seigan (Lv35, counter stance)
  - Stance buffs are mutually exclusive via `group = 'stance'`
  - Stun abilities: Blade Bash (Lv75, melee-range interrupt), Third Eye (Lv15, anticipate)
  - Resource recovery: Meditate (Lv30, TP recovery)
  - Default TP threshold: 300 TP
  - Job definition (`lib/jobs/samurai.lua`) with job_id 12

- **Resource Recovery System (recover.lua)**
  - New action module for automated MP and TP recovery
  - MP recovery: Monitors `GetMemberMPPercent(0)`, triggers when below `recover_mp_threshold`
  - TP recovery: Monitors `GetMemberTP(0)`, triggers when below `recover_tp_threshold`
  - Prioritizes MP recovery over TP recovery when both are needed
  - Uses `resource.has_resource()` and `resource.is_ability_ready()` for validation
  - Respects `combat_only` and `idle_only` flags for situational abilities
  - Config UI section with MP% slider (1-100) and TP slider (0-3000)
  - Per-ability enable/disable toggles
  - Integrated into Red Mage (Convert at 30% MP) and Samurai (Meditate at 300 TP)
  - Added to default priority_order in Sidekick.lua master list

### Changed
- **Code Refactoring - DRY Principles Applied**
  - All action modules now use shared `common.filter_abilities_by_level()` helper function
  - Eliminated ~100+ lines of duplicate filtering code across 7 action modules
  - Consistent behavior across all ability filtering
  - Modules refactored: attack.lua, buff.lua, debuff_removal.lua, debuff.lua, pet.lua, step.lua, stun.lua
  - Removed manual level checking, disabled setting checks, and goto statements
  - Single source of truth for ability filtering logic

- **Magic Burst (Nuke) System Enhancements**
  - Skillchain state now persists for the full 8-second window (retry behavior)
  - Added busy state checks: `common.is_casting()` and `common.is_in_event()`
  - System automatically retries casting if player is busy when skillchain detected
  - Only clears skillchain when: window expires OR spell successfully queued
  - Prevents lost magic burst opportunities due to timing issues
  - Better debug output showing remaining window time
  - Now uses common helpers: `common.get_target_index()`, `common.get_entity_manager()`, `common.build_ability_command()`
  - Simplified spell selection using `common.filter_abilities_by_level()`

- **Priority Order Master List System**
  - Changed from main job priority → append sub job priorities to consistent master list approach
  - `load_job_definition()` now uses master priority list defined in Sidekick.lua
  - Master list defines execution order: stun, aoe_heal, heal, heal_pet, debuff_removal, wake, step, debuff, buff, recover
  - Collects available actions from both main and sub jobs
  - Builds merged priority_order by iterating master list and including available actions
  - Ensures consistent priority regardless of which job is main vs sub
  - Example: Dragoon/Warrior and Warrior/Dragoon now have identical priority order
  - Predictable execution order across all job combinations

### Fixed
- **Magic Burst Timing**: No longer loses skillchain opportunities when player is busy
  - Previously cleared skillchain immediately, causing failed attempts
  - Now retries every automation tick until successful or window expires
  - Respects casting state to prevent spam attempts during spell animation

### Technical Details
- `common.filter_abilities_by_level()` handles: level requirements, disabled settings, pet requirements, combat state checking
- Returned abilities sorted by cost descending (higher cost = stronger/better)
- Two-stage filtering pattern for special cases (e.g., pet.lua filters by requires_pet after level filtering)
- Magic burst window management: 8-second detection window with automatic expiration
- Nuke module now follows same pattern as other action modules for consistency
- All modules benefit from future improvements to shared filtering logic

### Benefits
- **Maintainability**: Bug fixes to helpers benefit all modules automatically
- **Consistency**: All modules filter abilities the same way
- **Readability**: Less duplicate code, clearer intent
- **Reliability**: Magic burst no longer misses opportunities due to busy state

## [2.3.0] - 2025-12-27

### Added
- **Ranger job support**
  - Buff maintenance: Velocity Shot, Barrage, Camouflage, Scavenge, Sharpshot
  - Attack abilities: Flashy Shot, Stealth Shot, Bounty Shot, Shadowbind
  - All abilities properly organized by level (highest first)
  - Full integration with config UI and automation system
  - Job definition (`lib/jobs/ranger.lua`) with job_id 11

- **Attack Range Management**
  - Global setting for automated distance control during engaged combat
  - Config UI dropdown with three options: Off (disabled), Melee (3 yalms), Ranged (15 yalms)
  - Automatically manages multisend follow commands to maintain desired range
  - When engaged and within range: `/ms follow off` (stop movement)
  - When engaged and beyond range: `/ms follow on` (chase target)
  - When disengaged: `/ms follow on` (return to party formation)
  - State tracking prevents command spam
  - Works with `common.is_in_range()` for accurate distance measurement

### Fixed
- **Main/Sub Job Priority Order Merging**
  - Fixed `load_job_definition()` to properly merge priority_order from both jobs
  - Sub job priority actions now appended to main job's priority order
  - Unique actions only (no duplicates)
  - Fixes issue where sub job abilities weren't executing (e.g., Warrior's Provoke on Dragoon/Warrior)
  - Example: Dragoon/Warrior now has priority: defense, heal_pet, attack, debuff, buff, pet, **tank**

- **Pet Summoning (pet.lua)**
  - Now checks `combat_only` flag before attempting to summon pet
  - Respects `idle_only` flag for abilities that require being out of combat
  - Matches behavior of buff.lua for consistent combat state checking

- **Buff Maintenance (buff.lua)**
  - Added `pet_required` flag checking (separate from `requires_pet`)
  - Abilities with `pet_required = true` now only execute when pet is active
  - Enables proper handling of pet-dependent buffs (e.g., Dragoon's Spirit Bond)

- **Summoner Default Settings**
  - Added missing `pet_enabled = true` to default_settings
  - Added missing `attack_enabled = true` to default_settings
  - Pet summoning now works correctly for Summoner job

- **Config UI Stability**
  - Added `tostring()` safety checks for all ability fields
  - Prevents crashes when ability fields contain unexpected types
  - More robust error handling for malformed ability definitions

- **Debuff Module Debug Output**
  - Removed excessive debug messages from packet handlers
  - Packet tracking now runs silently in background
  - Debug output only appears when debuff_enabled is true
  - Cleaner log output during normal operation

- **Casting Detection Debug Messages**
  - Simplified casting debug output to just `[CASTING STARTED]` and `[CASTING ENDED]`
  - Removed verbose packet details (categories, action IDs, etc.)
  - Cleaner debug logs for easier troubleshooting

### Technical Details
- Priority order merging now handles both main-only, sub-only, and main+sub job combinations
- All action modules benefit from consistent combat/pet state checking
- Ranger abilities use proper recast IDs and buff IDs from abilities.sql
- Config UI more resilient to malformed job definitions

### Supported Jobs
- Ranger (new in 2.3.0)
  - Ranged attack buffs and abilities
  - Enmity management (Flashy Shot, Stealth Shot)
  - Utility (Scavenge for ammo recovery)

- Samurai (new in 2.4.0)
  - Stance management (Hasso, Seigan)
  - Melee interrupt abilities (Blade Bash, Third Eye)
  - TP recovery (Meditate)

## [2.2.0] - 2025-12-26

### Added
- **Pet Healing System**
  - New `heal_pet` action module for automated pet healing
  - Monitors pet HP using `common.get_pet_hp_percent()` function
  - Configurable pet heal threshold (default 50%)
  - Always targets `<me>` for pet healing abilities
  - Priority positioned after player healing, before other actions
  - Config UI section with enable/disable toggle and threshold slider
  - Per-ability toggles for pet healing abilities

- **Dragoon job support**
  - Pet management: Call Wyvern (summon wyvern companion)
  - Pet healing: Spirit Link (transfer HP to heal wyvern)
  - Buff maintenance: Ancient Circle, Spirit Bond, Deep Breathing, Fly High
  - Attack abilities: Jump, High Jump (with enmity and damage)
  - Debuff abilities: Angon (defense down)
  - Priority order: heal_pet → attack → debuff → buff → pet

- **DRY Helper Functions in common.lua**
  - `common.filter_abilities_by_level()` - Shared ability filtering logic
    - Filters by level, disabled settings, pet requirements, combat state
    - Sorts by cost descending (higher cost = stronger/better)
    - Removes ~70 lines of duplicate code across action modules
  - `common.build_ability_command()` - Shared command building logic
    - Handles both function and string command formats
    - Removes duplicate command building across all action modules
  - `common.get_pet_hp_percent()` - Reads pet HP from entity using `HealthPercent`

### Refactored
- **heal.lua**: Replaced manual ability filtering and command building with DRY helpers
  - Now uses `common.filter_abilities_by_level()` instead of 50-line filtering loop
  - Now uses `common.build_ability_command()` instead of local `heal.build_command()`
  - Removed local `heal.build_command()` function (replaced by shared helper)
  - ~50 lines of duplicate code eliminated

- **heal_aoe.lua**: Replaced manual ability filtering and command building with DRY helpers
  - Now uses `common.filter_abilities_by_level()` instead of 20-line filtering loop
  - Now uses `common.build_ability_command()` instead of local `heal_aoe.build_command()`
  - Removed local `heal_aoe.build_command()` function (replaced by shared helper)
  - ~20 lines of duplicate code eliminated

- **heal_pet.lua**: Built from the ground up using DRY helpers
  - Uses shared filtering and command building from common.lua
  - Consistent behavior with heal.lua and heal_aoe.lua
  - Minimal code duplication

### Technical Details
- Pet HP reading uses Ashita API: `GetEntity(pet_index).HealthPercent`
- Pet healing abilities defined in job definitions under `heal_pet = {}` section
- Separate from pet summoning abilities in `pet = {}` section
- All three healing modules (heal, heal_aoe, heal_pet) now share common filtering/building logic
- DRY refactoring eliminates ~80 lines of duplicate code across the codebase
- Improved maintainability: bug fixes to helpers benefit all action modules
- Consistent behavior across all healing categories

### Supported Jobs
- Dragoon
  - Pet management (Call Wyvern)
  - Pet healing (Spirit Link - transfers HP to wyvern when below 50%)
  - Jump abilities (Jump, High Jump for damage/enmity)
  - Buff maintenance (Ancient Circle, Spirit Bond, Deep Breathing, Fly High)
  - Debuff abilities (Angon)

## [2.1.0] - 2025-12-25

### Added
- **Paladin job support**
  - Single-target healing (Cure I-IV)
  - Party buffs (Protect I-IV, Shell I-III)
  - Light-based nukes (Banish, Banish II, Banishga, Holy)
  - Tank abilities (Flash for AOE blind enmity generation)
  - Counter abilities (Shield Bash for melee-range interruption)
  - Defensive buffs (Sentinel, Rampart, Fealty, Majesty, Holy Circle, Reprisal)
  - Intelligent priority: Tank → Counter → Heal → Buff → Nuke
  - Full hybrid tank/healer/support role automation

### Technical Details
- Paladin job definition (`lib/jobs/paladin.lua`) with job_id 7
- Paladin abilities span healing, buffing, tanking, and offensive magic
- Proper spell IDs, MP costs, and level requirements for all abilities

### Supported Jobs
- Paladin
  - Healing (Cure I-IV for party support)
  - Tank abilities (Flash for enmity, Shield Bash for counters)
  - Buffs (Protect/Shell for party, defensive JAs for tanking)
  - Light nukes (Banish line and Holy for offensive magic)
  - Support (Cover, Chivalry)

## [2.0.0] - 2025-12-24

### Added
- **Main/Sub Job Support System**
  - System now loads and merges abilities from both main and sub jobs
  - Abilities are marked with `is_main_job` flag to distinguish their source
  - Sub job abilities are correctly filtered by sub job level (not main job level)
  - Config UI displays combined job name (e.g., "Dark Knight/Warrior")
  - Support for loading if only subjob is supported (not main job)
  - Error message shows both jobs when neither is supported

- **Enhanced Job Change Detection**
  - Detects main job changes
  - Detects sub job changes (gain, lose, or switch)
  - Detects level changes for automatic UI refresh
  - Improved nil/0 value handling to prevent spurious change messages during loading
  - Only triggers on valid job/level values (ignores 0 or nil)

- **Group-Based Mutual Exclusivity**
  - Generalized ability grouping system (not just Samba-specific)
  - Any ability with `group` field enforces mutual exclusivity
  - Enabling one ability in a group automatically disables others
  - Examples: `group = 'samba'`, `group = 'bio_dia'`
  - Works across all ability categories

- **Full Job Name Display**
  - All jobs now display full names instead of abbreviations
  - "Dragoon" instead of "DRG", "Samurai" instead of "SAM"
  - Consistent naming across UI and log messages

### Changed
- **Ability Merging System**
  - Deep copy of abilities during merge (prevents reference issues)
  - Abilities marked with source job flag
  - Sub job abilities appended to each category
  - Default settings merged (main job takes priority)

- **Config UI Improvements**
  - Level-based filtering now checks appropriate job level
  - Main job abilities checked against main level
  - Sub job abilities checked against sub level
  - Real-time refresh when jobs or levels change

- **Job Definition Structure**
  - `load_job_definition()` now accepts both main and sub job IDs
  - Creates merged job definition with combined abilities
  - Handles scenarios: both supported, only main, only sub, neither
  - Job name includes sub job when present

### Technical Details
- New state variables: `current_main_job_id`, `current_sub_job_id`, `main_job_def`, `sub_job_def`
- New tracking variables: `last_sub_job_id`, `last_level`
- `merge_abilities()` function creates deep copies with source flags
- `load_single_job_definition()` extracted for reusability
- `can_use_ability()` checks `is_main_job` flag for correct level validation
- `common.get_job_name()` uses `jobs.names` for full names with fallback to abbreviations
- Enhanced packet handler validates job_id, sub_job_id, and main_level
- Smart change detection: ignores 0→valid and valid→0 transitions during loading

### Breaking Changes
- Job definitions now return abilities with `is_main_job` flag added during merge
- State management refactored to track main/sub jobs separately
- Settings may need to be reconfigured after update (due to job-specific files)

## [1.7.0] - 2025-12-20

### Added
- **Red Mage job support**
  - Hybrid magic system combining white, black, and enfeebling magic
  - Single-target healing: Cure I-IV with HP deficit-based selection
  - Magic burst nuking: Elemental spells Fire-Thunder I-III (tier-restricted compared to BLM)
  - Enfeebling magic: Slow I-II, Paralyze I-II, Silence, Bind, Blind, Dia I-II
  - Enhancing buffs: Refresh I-II, Haste, Phalanx, Stoneskin, Aquaveil, Blink, Protect I-III, Shell I-III
  - Debuff removal: Erase, Viruna, Paralyna, Silena, Blindna, Poisona (comprehensive coverage)
  - Special abilities: Convert (HP/MP swap)
  - Intelligent priority system: healing → debuff removal → nuking → enfeebling → enhancing

### Changed
- **Magic Burst Integration**: Red Mage now supports automatic elemental nuking on skillchain detection
  - Uses same skillchain property detection system as Black Mage
  - Limited to tier III elemental spells (Fire III, Blizzard III, etc.)
  - Respects MP costs and level requirements for balanced hybrid gameplay
  - Integrated with existing nuke action system

### Technical Details
- New `lib/jobs/red_mage.lua` with full hybrid magic support
- Healing values optimized for RDM's moderate cure potency
- Enfeebling spells with appropriate MP costs and level requirements
- Enhanced buff system includes both self-buffs and party support spells
- Convert ability as special attack action for emergency MP recovery
- Priority order emphasizes support role: healing before offense
- All spells use proper recast IDs for accurate cooldown tracking

### Supported Jobs
- Red Mage
  - Single-target healing (Cure I-IV with deficit-aware selection)
  - Magic burst nuking (Fire-Thunder I-III, automatic on skillchains)
  - Enfeebling magic (Slow, Paralyze, Silence, Bind, Blind, Dia - weakening enemies)
  - Enhancing magic (Refresh, Haste, Phalanx, Protect, Shell - supporting party)
  - Debuff removal (Erase, Viruna, status cleansing - full coverage)
  - Resource management (Convert for MP recovery)

## [1.6.0] - 2025-12-19

### Added
- **Black Mage job support**
  - Magic Burst nuking with automatic skillchain detection
  - Elemental spells: Fire I-V, Blizzard I-V, Thunder I-V, Water I-V, Aero I-V, Stone I-V
  - Ancient Magic: Flare, Freeze, Tornado, Quake, Burst, Flood
  - Self-healing: Drain (combat-only)
  - Buff maintenance: Elemental Seal
  - Counter abilities: Stun spell (automatic enemy ability interruption)
- **New Magic Burst (Nuke) Action Category**
  - Real-time skillchain property detection from combat packets (0x028)
  - Detects all 16 skillchain properties from Additional Effect field
  - Property ID to name mapping: Light, Darkness, Gravitation, Fragmentation, Distortion, Fusion, Compression, Liquefaction, Induration, Reverberation, Transfixion, Scission, Detonation, Impaction, Radiance, Umbra
  - Intelligent element mapping per skillchain:
    - Single element: Liquefaction→Fire, Induration→Ice, Detonation→Wind, Scission→Earth, Impaction→Thunder, Reverberation→Water, Transfixion→Light, Compression→Dark
    - Dual element: Fragmentation→Wind/Thunder, Distortion→Ice/Water, Fusion→Light/Fire, Gravitation→Dark/Earth
    - Multi element: Light/Radiance→Light/Fire/Wind/Thunder, Darkness/Umbra→Dark/Earth/Ice/Water
  - Smart spell selection algorithm:
    - Filters by matching element for skillchain property
    - Respects level requirements and MP availability
    - Honors disabled spell settings from config_ui
    - Prioritizes highest tier spell available (Fire V over Fire IV)
  - 8-second magic burst window after skillchain detection
  - Works with party and alliance member skillchains
  - One-shot execution per skillchain (prevents spam)
  - Uses attack.lua command builder for consistency
  - Alliance member validation to filter enemy skillchains
  - Target ID matching to ensure correct mob
  - Configurable via `nuke_enabled` setting
  - UI support with nuke spell section in configuration

### Changed
- **Nuke Action Integration**: Uses attack.lua's `build_command()` function for command execution
  - Consistent with counter.lua and tank.lua patterns
  - Maintains same validation logic across all action modules
  - Supports both function and string command formats

### Fixed
- **Disabled Spell Checking**: Nuke action now properly respects config_ui disabled spell toggles
  - Checks `disabled_<spell_name>` settings before spell selection
  - Prevents casting of spells that user has disabled
  - Follows same pattern as heal/buff/debuff actions

### Supported Jobs
- Black Mage
  - Magic Burst: Automatic elemental nuking on skillchain detection (all 16 properties)
  - Elemental spells: Fire I-V, Blizzard I-V, Thunder I-V, Water I-V, Aero I-V, Stone I-V
  - Ancient Magic: Flare, Freeze, Tornado, Quake, Burst, Flood
  - Self-healing: Drain
  - Buff maintenance: Elemental Seal
  - Counter abilities: Stun spell

### Technical Details
- New `lib/actions/nuke.lua` module handles magic burst detection and spell casting
- Packet 0x028 parsing extracts skillchain property from Additional Effect field
- Property ID extraction: `bit.band(additionalEffect.Damage, 0x3F)`
- SkillPropNames table maps property IDs (1-16) to property names
- property_to_elements table defines valid burst elements per property
- select_best_nuke() filters by element, level, MP, disabled settings, and tier
- 8-second skillchain window stored in active_skillchain state table
- Packet handler registered in Sidekick.lua load event
- Integration with existing automation priority system
- Alliance checking via isPlayerInAlliance() and isPetInAlliance()
- Target validation ensures packet actor matches current target
- Uses resource.get_resource('mp') for MP checking
- Attack.build_command() generates final spell command


## [1.5.0] - 2025-12-18

### Added
- **Dark Knight job support**
  - Self-healing (Drain, Drain II with combat-only flag)
  - Counter abilities (Weapon Bash, Stun spell for enemy ability interruption)
  - Buff maintenance (Last Resort, Souleater, Arcane Circle, Dread Spikes, Diabolic Eye, Nether Void, Scarlet Delirium)
  - Debuff abilities (Bio, Bio II, Poison, Poison II)
- **New Counter Action Category**
  - Event-driven enemy ability interruption via packet detection
  - Monitors 0x028 action packets for enemy ability usage (action_id 0x58DC)
  - Automatic counter execution when enemy begins casting/using abilities
  - Priority-based counter ability selection (prefers low-cost abilities like Weapon Bash over spells)
  - Validates target match, enemy spawn flags, and combat state
  - Instant execution without command throttle for time-critical interrupts
  - Leverages attack.lua validation logic for ability execution
  - Configurable per-job with `counter_enabled` setting
  - UI support with counter abilities section in configuration
- **Combat-Only Ability Flag**: Added `combat_only` property for abilities that require engagement
  - Abilities with `combat_only = true` are only available while engaged in combat
  - Applied to Dark Knight's Drain/Drain II (must target enemy), buffs (Last Resort, Souleater, etc.), and counter abilities
  - Healing system checks combat state before attempting combat-only heals
  - Prevents attempting abilities that will fail when idle

### Changed
- **Spell Recast Checking**: Enhanced heal action module to properly differentiate between spells and job abilities
  - Now detects spells by command prefix (`/ma`) and uses `resource.is_spell_ready()` for recast checking
  - Job abilities continue using `resource.is_ability_ready()` for recast tracking
  - Fixes issue where spell recasts were not being checked correctly (e.g., Dark Knight's Drain)
  - Shows spell recast time in debug output for better troubleshooting
  - Applies to all spell-based healing (WHM cures, DRK drain, etc.)
- **Counter Integration**: Counter functionality now properly respects `/sk start` and `/sk stop` commands
  - Added `automation_enabled` check to counter packet handler
  - Counter only active when automation is explicitly started by user
  - Consistent behavior with other action modules

### Technical Details
- New `lib/actions/counter.lua` module handles enemy ability interruption
- Counter system is event-driven via packet handlers (no polling)
- Packet 0x028 parsing: actor_id (offset 0x05), category (offset 0x04), action_id (offset 0x0A)
- Enemy ability ready signal: category 35 or 45, action_id 0x58DC (22748)
- Validates server IDs match between packet actor and current target
- Checks enemy spawn flags (0x10 = monster) to ensure valid target
- Priority system: lower priority value = higher priority (Weapon Bash = 1, Stun spell = 2)
- Combat-only flag checked in heal ability filtering alongside other requirements
- Spell detection uses pattern matching on command strings for accurate categorization

### Supported Jobs
- Dark Knight
  - Self-healing (Drain, Drain II - combat only)
  - Counter abilities (Weapon Bash, Stun spell - automatic enemy interruption)
  - Buff maintenance (Last Resort, Souleater, Arcane Circle, Dread Spikes, Diabolic Eye, Nether Void, Scarlet Delirium - all combat only)
  - Debuff abilities (Bio, Bio II, Poison, Poison II - DoT spells)


## [1.4.0] - 2025-12-18

### Added
- **Warrior job support**
  - Buff maintenance (Berserk, Defender, Warcry, Aggressor, Retaliation, Restraint, Warriors Charge, Blood Rage, Brazen Rush)
  - Tank abilities (Provoke)
  - Debuff abilities (Tomahawk)
- **New Tank Action Category**
  - Dedicated action handler for enmity/threat management
  - Monitors target's current target to detect when player loses aggro
  - Automatically uses tank abilities when target is not focusing on player
  - Only executes when engaged in combat with a valid target
  - Leverages attack.lua validation logic for range, cooldown, and resource checks
  - Configurable per-job with `tank_enabled` setting
  - Priority position: First in action order for tank jobs
  - UI support with tank abilities section in configuration

### Changed
- **Action Priority System**: Jobs with tank abilities now prioritize tank actions first
  - Tank-capable jobs check threat status before other actions
  - Ensures aggro management takes precedence in combat
  - Non-tank jobs unaffected by this change

### Supported Jobs
- Warrior
  - Tank abilities (Provoke for enmity management)
  - Buff maintenance (Berserk, Defender, Warcry, Aggressor, Retaliation, Warriors Charge, Blood Rage)
  - Debuff abilities (Tomahawk)

### Technical Details
- New `lib/actions/tank.lua` module handles enmity management
- Tank actions check: engagement status, target validity, target's current target
- `is_target_claiming_player()` function monitors mob's focus
- Reuses attack.lua's validation logic for ability execution
- Tank abilities only trigger when player doesn't have mob's attention
- All buff/ability IDs confirmed accurate for Warrior abilities


## [1.3.0] - 2025-12-17

### Changed
- **Enhanced Healing Logic**: Intelligent heal selection based on HP deficit
  - Heal abilities now include a `value` field representing heal potency (HP restored)
  - Added HP deficit calculation to determine exact HP needed for target
  - Smart ability selection:
    - Calculates target's max HP from current HP and HP percentage
    - Determines exact HP deficit (max HP - current HP)
    - Selects largest heal that fits within deficit to minimize overheal
    - Falls back to smallest heal if all options would overheal
  - Special handling for low HP scenarios:
    - Detects unreliable HP percentage data (e.g., 1% with very low current HP)
    - Automatically uses strongest available heal when HP data is unreliable
  - Improved debug logging:
    - Shows calculated HP deficit and max HP values
    - Displays available heals sorted by value
    - Explains heal selection reasoning (efficiency vs emergency)
  - Benefits all healing jobs (White Mage, Summoner, Dancer, etc.)
  - Maximizes MP/TP efficiency by avoiding overheal waste
  - Maintains safety by using stronger heals when needed

### Technical Details
- Enhanced `heal.select_ability()` function with deficit-based selection
- Added HP calculation from party member data
- Heal value field added to all heal abilities in job definitions
- Unreliable data detection prevents heal selection errors at critical HP
- Comprehensive debug output for troubleshooting heal selection


## [1.2.0] - 2025-12-16

### Added
- **Monk job support**
  - Self-healing (Chakra)
  - Debuff removal (Chakra removes Poison/Blind)
  - Buff maintenance (Boost, Dodge, Focus, Counterstance, Footwork, Mantra, Formless Strikes, Impetus, Perfect Counter, Hundred Fists)
  - Attack abilities (Chi Blast)
- **New Attack Action Category**
  - Dedicated action handler for offensive abilities that require a target
  - Executes when engaged with a valid target in range
  - Does not check for buffs/debuffs, only cooldowns and resources
  - Configurable range checking (e.g., Chi Blast has 15 yalm range)
  - UI support with range display in configuration

### Changed
- **Debuff Removal Enhancement**: Added `self_only` support for abilities that only target the player
  - Self-only abilities are checked first before party member debuff removal
  - Enables abilities like Chakra to remove debuffs from self efficiently
- **Configuration UI**: Added Attack Abilities section
  - Toggle to enable/disable attack abilities
  - Individual ability toggles with level and range information
  - Positioned between Buffs and Debuffs sections

### Supported Jobs
- Monk
  - Self-healing (Chakra)
  - Debuff removal (Chakra - removes Poison and Blind from self)
  - Buff maintenance (Boost, Dodge, Focus, Counterstance, Footwork, Mantra, Formless Strikes, Impetus, Perfect Counter, Hundred Fists)
  - Attack abilities (Chi Blast)

### Technical Details
- New `lib/actions/attack.lua` module handles offensive abilities
- Attack actions check: engagement status, target validity, range, cooldowns
- All buff/ability IDs confirmed accurate for proper tracking
- Priority order updated: debuff_removal → heal → attack → debuff → buff


## [1.1.0] - 2025-12-15

### Added
- **White Mage job support**
  - Single-target healing (Cure, Cure II-V, Curaga II as single-target fallback)
  - AOE healing (Curaga, Curaga II-IV)
  - Debuff removal (Erase, Viruna, Paralyna, Blindna, Silena, Poisona, Cursna)
  - Buff maintenance (Protectra III-V, Shellra III-V, Protect IV-V, Shell IV-V, Haste, Regen I-IV, Aquaveil, Blink, Stoneskin)
  - Sleep removal (via cure spells)
  - Focus target support
- **Level-Based Ability Filtering**: Configuration UI now only displays abilities the player can currently use
  - Added `can_use_ability()` helper function that checks player's main job level
  - Abilities are filtered in real-time based on level requirements
  - Applies to all ability categories: heal, heal_aoe, debuff_removal, buff, and debuff
  - New abilities automatically appear in the UI as you level up

### Changed
- **Wake System Refactor**: Simplified sleep detection to match BackupDancer's proven approach
  - Now uses `get_party_buffs()` to read buff arrays directly (buff IDs 2 and 19)
  - Added `is_buff_sleep()` helper function from BackupDancer
  - Removed complex `check_sleeping_members()` and `has_status()` memory pointer navigation
  - More reliable sleep detection with clearer debug output
  - Logic: 0 sleeping → exit, 1 sleeping → single-target heal, 2+ sleeping → AOE heal
  - Matches BackupDancer behavior exactly (scans party indices 1-5, excludes player at 0)
- **Enhanced Player Information Functions**:
  - `common.get_player_level()` now returns both main job level and subjob level (previously only main level)
  - `common.get_player_job()` now returns both main job ID and subjob ID (previously only main job)
  - These functions maintain backward compatibility by returning multiple values

### Supported Jobs
  - White Mage 
  - Single-target healing (Cure I-V)
  - AOE healing (Curaga I-IV)
  - Debuff removal (Erase, Viruna, Paralyna, Blindna, Silena, Poisona, Cursna)
  - Buff maintenance (Protectra, Shellra, Aquaveil, Blink, Stoneskin)
  - Sleep removal

### Technical Details
- Config UI filtering uses direct level comparison: `main_level >= ability.level`
- Samba detection uses pattern matching: `ability_name:match('Samba')`
- All `toggle_ability()` calls now pass `job_def` parameter for context-aware toggling
- Subjob information available for future features (subjob ability support, etc.)


## [1.0.0] - 2025-12-14

### Added
- Initial release of generic job automation framework
- Core automation engine with priority-based action selection
- Modular action system (heal, heal_aoe, wake, debuff_removal, buff, debuff, attack)
- Job definition system for configuration-driven automation
- Summoner job support with blood pacts (Healing Ruby, Healing Ruby II, Shining Ruby)
- Dancer job support with waltzes, sambas, jigs, and steps
- Dynamic ImGui configuration UI that adapts to loaded job
- Focus target system for prioritizing specific party members
- Resource management (MP/TP checking, cooldown tracking)
- Party management utilities (HP checking, buff reading, range validation)
- Sleep removal with smart AOE/single-target selection
- Debuff removal with priority-based target selection
- Buff maintenance with uptime checking
- Step tracking via packet sniffing (Dancer-specific)
- Casting state to prevent spam
- Command throttling to prevent spam (1 second default)
- Debug mode for troubleshooting
- Settings persistence per job (JSON files)
- Comprehensive documentation:
  - README.md - User guide and quick start
  - ARCHITECTURE.md - Technical design documentation
  - TESTING.md - Testing procedures and validation
  - CONTRIBUTING.md - Guide for adding new jobs

### Core Features
- Generic action modules work for any job
- No hard-coded ability names in core logic
- Adding new jobs requires only a configuration file
- All existing timing, cooldown, and safety checks preserved
- Priority-based target selection (focus → lowest HP → most debuffs)
- Range checking (21 yalm default)
- Event system blocking (no actions during cutscenes)
- Error handling with pcall to prevent crashes
- Memory pointer access for accurate buff checking

### Commands
- `/sidekick start` or `/sk start` - Start automation
- `/sidekick stop` or `/sk stop` - Stop automation
- `/sidekick toggle` or `/sk toggle` - Toggle automation on/off
- `/sidekick config` or `/sk config` - Open configuration UI
- `/sidekick focus <index>` - Set focus target (0-5, party member index)
- `/sidekick focus clear` - Clear focus target
- `/sidekick debug` or `/sk debug` - Toggle debug mode
- `/sidekick status` or `/sk status` - Show current status and settings
- `/sidekick help` or `/sk help` - Show command help

### Supported Jobs
- Summoner 
  - Single-target healing (Healing Ruby)
  - AOE healing (Healing Ruby II)
  - Buff maintenance (Shining Ruby for Protect/Shell)
  - Sleep removal
  
- Dancer 
  - Single-target healing (Curing Waltz, Curing Waltz II, Curing Waltz III)
  - AOE healing (Divine Waltz)
  - Debuff removal (Healing Waltz)
  - Sleep removal
  - Buff maintenance (Drain/Aspir/Haste Samba, Spectral Jig)
  - Step stacking with packet tracking (Quickstep, Box Step)

### Technical Details
- Built for Ashita v4
- Compatible with CatsEyeXI
- No external dependencies (uses Ashita built-ins)
- Modular architecture with clear separation of concerns
- Event-driven automation loop (d3d_present)
- Packet sniffing for advanced features (step tracking)
- Memory pointer access for buff reading

### Known Limitations
- Party only (no alliance support)
- Fixed 21 yalm range for abilities
- Some buff IDs may vary by server
- Step tracking requires packet sniffing (Dancer-specific)
- No multi-step action chains



## Version History

- **2.8.0** (2026-01-05) - Scholar job ability fixes, multiple buff_id support for Arts/Addendum tracking, spell addendum requirements, storm spell combat restrictions
- **2.7.0** (2026-01-04) - Geo automation with Full Circle, Geomancer spell enhancements with buff_id fields, Geo spell targeting corrections, healing UI visibility fixes
- **2.4.0** (2025-12-28) - Samurai job support, resource recovery system (recover.lua for MP/TP), priority order master list, code refactoring using DRY principles, enhanced magic burst system with retry logic
- **2.3.0** (2025-12-27) - Ranger job support, main/sub job priority order merging fixes, attack range management system, pet summoning improvements
- **2.2.0** (2025-12-26) - Pet healing system with automated pet HP monitoring, Dragoon job support with wyvern management
- **2.1.0** (2025-12-25) - Paladin job support with hybrid tank/healer/support role, Black Mage job support with complete elemental magic arsenal (I-VI + Ancient Magic)
- **2.0.0** (2025-12-24) - Main/Sub job support system, job change detection, group-based mutual exclusivity, full job name display
- **1.7.0** (2025-12-20) - Red Mage job support with hybrid magic system, enfeebling debuffs, enhancing buffs, magic burst nuking, comprehensive debuff removal, and Convert ability
- **1.6.0** (2025-12-19) - Black Mage job support with magic burst nuking, automatic skillchain detection for all 16 properties, intelligent element mapping, and tier-based spell selection
- **1.5.0** (2025-12-18) - Dark Knight job support with Drain self-healing, automatic enemy ability interruption via counter detection, combat-only ability flag, and improved spell recast checking
- **1.4.0** (2025-12-18) - Warrior job support and new tank action category for enmity/threat management
- **1.3.0** (2025-12-17) - Enhanced healing logic with HP deficit-based ability selection for maximum efficiency
- **1.2.0** (2025-12-16) - Monk job support, new attack action category, self-only debuff removal, and config_ui filtering for Focus and Debuff removal
- **1.1.0** (2025-12-15) - White Mage support and wake system improvements, Level-based filtering, enhanced player info, Samba mutual exclusivity, and Casting state to prevent spam
- **1.0.0** (2025-12-14) - Initial release with Summoner and Dancer support

---

## How to Read This Changelog

### Version Format
`MAJOR.MINOR.PATCH`
- **MAJOR**: Breaking changes, major refactors
- **MINOR**: New features, new job support
- **PATCH**: Bug fixes, minor improvements

### Change Categories
- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Features marked for removal
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security fixes

## Support

For issues, questions, or contributions:
- GitHub: https://github.com/seekey13/Sidekick
- Check TESTING.md for troubleshooting
- Check ARCHITECTURE.md for technical details
- Check CONTRIBUTING.md for how to add jobs
