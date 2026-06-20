# **Medic** - Support Job Automation Framework

A focused, support-oriented addon for Ashita v4 that automates healing, buffing, and debuff removal for select support jobs in Final Fantasy XI.  Tuned specifically for [CatsEyeXI private server](https://www.catseyexi.com/).

<img width="3840" height="2160" alt="Screenshot 2026-03-03 191208" src="https://github.com/user-attachments/assets/4b9165e3-8ced-4af2-b765-105d846c2ee1" />
<img width="3840" height="2160" alt="Screenshot 2026-03-03 191222" src="https://github.com/user-attachments/assets/da087926-c7f6-48f5-8e02-0db4c6bfb5c5" />
<img width="3840" height="2160" alt="Screenshot 2026-03-03 191254" src="https://github.com/user-attachments/assets/5bae06cf-5268-4b69-8480-0c53a7b0e7e3" />
<img width="3840" height="2160" alt="Screenshot 2026-03-03 191314" src="https://github.com/user-attachments/assets/f0857b76-c773-4ea9-b8ee-6629de331609" />

## ⚠️ Important: This is NOT a Full Automation Tool

**Medic is a support-only addon.** It provides healing, buffing, debuff removal, and basic pet management. It does **NOT** automate:
- Combat/attacking
- Tanking/enmity management
- Magic bursting/nuking
- Weaponskills
- Movement/positioning
- Full job automation

## Latest Updates

### [2.1.0] - 2026-06-19

Internal refactor release (~1,180 lines removed, behavior unchanged) plus a job-data
simplification and one Geomancer fix.

#### Added
- **Derived ability commands**: A job ability's `command` is now optional — when omitted it is derived as `'/<cast> "<spell|name>" <server_id>'`. New optional fields: `cast` (verb, default `ma`; `ja`/`pet` for abilities/blood pacts), `spell` (cast name when it differs from the display name), and `note` (display-only effect hint shown in parens).

#### Changed
- **Job files are now pure data** — all command closures removed from the nine job definitions; commands derive from the ability's name. Adding a spell is a flat data row.
- **Bard song labels** now come from `name` + `note` (e.g. `Knight's Minne IV` + `++++DEF`) and display identically. ⚠️ Saved Bard song selections reset once on upgrade (the song identity changed); re-toggle your songs.

#### Fixed
- **Geomancer Geo-bt**: fixed a luopan-timing race where a Geo debuff could trigger Full Circle on its own freshly-cast luopan mid-combat. Added a short grace window after casting.

### [2.0.0] - 2026-03-03

### BREAKING CHANGES
- **PL Mode Removed**: All PL Mode functionality (`pl_mode_active`, `setup_pl_mode_job`, `clear_player_data`, `restore_normal_mode`, and related settings) has been removed. Users should clear any legacy `pl_*` settings keys from their configuration files.
- **Module Consolidation**: `heal_aoe.lua`, `heal_pet.lua`, `debuff_removal.lua`, and `wake.lua` have been merged into `heal.lua` and `status_removal.lua` respectively. Direct imports of the old modules will fail.
- **Config UI Renamed**: `config_ui.lua` renamed to `ui_config.lua`. Any external references must be updated.

### Added
- **Alliance Support**: Healing, debuff removal, wake, and buff automation now extend to alliance sub-parties B and C. Alliance members require abilities with `target_outside = true`. Focus target, lowest-HP priority, and HP deficit selection all work across alliance members.
- **Alliance UI**: Per-member buff-toggle buttons (`<B0>`–`<B5>`, `<C0>`–`<C5>`) in the configuration window; alliance members displayed in the debug panel with HP, MP, job, and buff data; party leader marked with `^`.
- **HP Estimation for Tracked Targets**: When a tracked target is first added, a `/check` command is issued to resolve their level via the 0x0C9 packet. The resulting level is used to estimate max HP from a built-in level-average table, enabling accurate deficit-based healing before the target is seen at full HP.
- **Centralized Game State**: New `common.game_state` snapshot refreshed once per automation tick provides a consistent view of player/party HP, MP, buffs, and positions.
- **Action Core Module**: New `lib/core/action_core.lua` consolidates resource management, cooldown tracking, buff-ID utilities, and ability candidacy helpers (replacing deleted `lib/core/resource.lua`).
- **Packet-Based Buff Tracking**: Buff gain/loss tracking via 0x028 and 0x029 packets for Trusts and tracked (out-of-party) targets.
- **Tracked Targets**: Session-scoped tracking of out-of-party players for heal, buff, and status removal automation. (Power Leveling)
- **Debug Panel**: New `lib/ui/panel.lua` debug info panel showing party game_state snapshot (toggle with `/medic panel`).
- **Status Removal Module**: New combined `lib/actions/status_removal.lua` with `execute_debuff_removal` and `execute_wake` entry points.
- **Dancer Level-75 Abilities**: Added Saber Dance, Fan Dance, No Foot Rise, and Presto to the Dancer job definition.
- **Geomancer Geo Targeting**: `<me>` Geo buff spells now target party members via single-select ME/P1-P5 buttons (like other party buffs), with Full Circle distance measured from the selected Geo target.
- **Geomancer Geo Debuffs**: New `<bt>` Geo debuff spells (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) cast on your battle target. These are combat-only and selected via a dropdown under Enable Geo. In combat the selected debuff takes over the single luopan; Full Circle frees it for Geo buffs once combat ends.

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


## Features

### Core Support Actions
- **Revive / Raise**: Automatically raises dead party members, tracked targets, and alliance members using Raise, Raise II, or Arise. Respects prerequisite buffs (Scholar requires Addendum: White), validates range, and falls back to the next available raise spell. Out-of-combat only (`idle_only`).
- **Mount Detection**: Automation is fully suppressed while riding a mount (detected via entity status 5 or buff 252). Configuration panel shows "Automation paused (mounted)" in this state.
- **Alliance Support**: Automatically heals, removes debuffs, wakes, and applies buffs to alliance sub-party members (parties B and C) using abilities flagged with `target_outside = true`.
- **Tracked Targets**: Session-scoped tracking of out-of-party players for heal, buff, and status removal automation. (Power Leveling)
- **Item-Based Status Removal**: Automatically use consumable items to remove critical debuffs (Echo Drops for Silence, Holy Water for Doom) with inventory tracking and smart zone-load handling
- **Critical HP Response**: Emergency abilities (e.g., Divine Seal, Martyr, Contradance) automatically trigger when party members drop below critical threshold (default 30%)
- **Single-Target Healing**: Intelligent HP deficit-based heal selection with priority system (Critical HP → Focus target → Regular lowest HP)
- **AOE Healing**: Party-wide healing when multiple members need HP
- **Pet Healing**: Automated healing for luopan pets
- **Sleep Removal (Wake)**: Automatically wake sleeping party members
- **Debuff Removal**: Remove poison, paralysis, silence, and other negative status effects
- **Buff Maintenance**: Auto-apply and maintain self-buffs with single-target party buff support
- **Resource Recovery**: Automated MP and TP recovery abilities
- **Automatic Resting**: MP-based jobs automatically rest when idle to recover MP with configurable timer, HP threshold safety, and optional follow target distance monitoring
- **Geomancer Support**: Single-target Geo buffs on party members, target-cast Geo debuffs in combat, and automatic Full Circle / luopan management (recalls and recasts when the luopan drifts beyond the distance threshold from the selected Geo target)

### User Interface
- **ImGui Configuration UI**: User-friendly settings interface with collapsible sections
- **Alliance Member Buttons**: Per-member buff-toggle buttons (`<B0>`–`<B5>`, `<C0>`–`<C5>`) for alliance sub-parties B and C, shown only when an alliance is detected
- **Group Dropdown Selectors**: Multiple abilities in a group (e.g., Cure I-V) consolidated into dropdown menus
- **Per-Ability Toggles**: Enable/disable individual abilities
- **Button-Based Party Buff Targeting**: Single-target buffs display ME/P1-P5 buttons for precise control over who receives each buff
- **Trust Buff Support**: Can track and cast buffs on Trusts using packet-based detection
- **Subjob Duplicate Filtering**: Automatically hides duplicate abilities from subjob when they exist in main job
- **Threshold Configuration**: Customize HP/TP/MP thresholds
- **Focus Target Support**: Prioritize specific party members
- **Level-Based Filtering**: Shows only abilities available at your current level
- **Collapsible Sections**: All major features (Healing, Buffs, Debuff Removal, etc.) are collapsible for cleaner organization
- **Contextual Tooltips**: Hover help across the configuration UI explaining what each section, slider, dropdown, button, and checkbox does
- **Attack Range Selector**: Choose `Off`, `Melee (3 yalms)`, or `Ranged (15 yalms)` to set how close a follow target must be (requires [Multisend](https://github.com/ThornyFFXI/Multisend))
- **Auto-Refresh**: UI updates automatically when jobs or levels change

### Core System Features
- **Smart Resource Management**: Automatic MP/TP checking and cooldown tracking
- **Status Ailment Detection**: Automatically detects and prevents casting when Silenced (magic) or Amnesiac (job abilities)
- **Job-Specific Ability Validation**: Jobs can implement custom validators for fine-grained ability control (e.g., checking pet type, buff requirements, etc.)
- **Pet Entity Management**: Consolidated pet entity access with `get_pet_entity()` for consistent pet checking across all features
- **Enhanced Casting State Detection**: Packet-based casting detection using offset 0x0F state byte for accurate spell tracking
- **Movement Detection**: Prevents casting while moving to avoid interrupted spells
- **Trust Buff Tracking**: Packet-based buff tracking for Trusts (0x028 for application, 0x029 for removal)
- **Single-Target Party Buffs**: Cast buffs on specific party members with button-based targeting (Haste, Refresh, Protect, Shell, etc.)
- **Party Buff Management**: Per-party-member buff configuration with intelligent uptime tracking and range validation (20 yalms)
- **Focus Target Support**: Prioritize specific party members for healing/support
- **Main/Sub Job Support**: Automatically loads and merges abilities from both supported jobs with duplicate filtering
- **Priority-Based Actions**: Configurable action priority order per job
- **Settings Persistence**: Settings saved per job in JSON format

## Supported Jobs

Currently implemented support jobs:

- **Bard** (BRD)
  - Buff with songs on self or party members using Pianissimo (level 20+)
  - Songs: Minuet, Minne, Paeon, Madrigal, Prelude, March, Ballad, Etude, Carol, Mambo, Mazurka, Scherzo, Threnody, etc.
  - Song limits: 2 songs per party member (main job) or 1 song per party member (sub job)
  - Party button targeting with automatic Pianissimo usage
  - Settings persist through reloads

- **Dancer** (DNC)
  - Critical HP abilities (Contradance)
  - Single-target healing with waltzes (Curing Waltz I/II/III)
  - AOE healing with waltzes (Divine Waltz, Divine Waltz II)
  - Debuff removal with waltz (Healing Waltz)
  - Buff with sambas (Drain Samba I/II/III, Aspir Samba, Haste Samba)
  - Buff with jigs (Spectral Jig)
  - Buff with level-75 job abilities (Saber Dance, Fan Dance, No Foot Rise, Presto)

- **Geomancer** (GEO)
  - AOE healing with job abilities (Mending Halation)
  - Pet healing with job abilities (Life Cycle)
  - Buff with Geo geomancy spells, single-target party member selection (ME/P1-P5 buttons, single-select)
  - Buff with Indi geomancy spells (self)
  - Debuff with Geo geomancy spells on your battle target (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) — combat-only, single debuff selectable via dropdown
  - Entrust system: Select target party member and Indi spell to automatically cast via Entrust ability
  - Buff with job abilities (Lasting Emanation, Ecliptic Attrition, Collimated Fervor, Blaze of Glory, Dematerialize)
  - MP recovery with job abilities (Radial Arcana)
  - Geomancy/luopan management (automatic Full Circle execution)

- **Paladin** (PLD)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with white magic (Protect I-IV, Shell I-IV)

- **Red Mage** (RDM)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Haste, Refresh, Phalanx, Phalanx II, Enfire, Enblizzard, Enaero, Enstone, Enthunder, Enwater, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)
  - Revive with white magic (Raise)

- **Rune Fencer** (RUN)
  - AOE healing with job abilities (Vivacious Pulse)
  - Buff with enhancing magic (Protect I-III, Shell I-IV, Regen I-III, Refresh, Barfire, Barblizzard, Baraero, Barstone, Barthunder, Barwater, etc.)

- **Scholar** (SCH)
  - Single-target healing with white magic (Cure I-IV)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
  - Revive with white magic (Raise, Raise II — requires Addendum: White)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Regen I-III, Reraise, Reraise II, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)
  - Buff with geomancy spells (Sandstorm, Rainstorm, Windstorm, Firestorm, Hailstorm, Thunderstorm, Voidstorm, Aurorastorm, Klimaform)
  - Buff with elemental magic (Blaze Spikes, Ice Spikes, Shock Spikes)
  - Buff with job abilities (Light Arts, Dark Arts, Addendum: White, Addendum: Black, Sublimation)
  - MP recovery with job abilities (Sublimation)

- **Summoner** (SMN)
  - Critical HP abilities (Apogee)
  - Single-target healing with blood pacts (Healing Ruby - requires Carbuncle)
  - AOE healing with blood pacts (Healing Ruby II - requires Carbuncle)
  - Buff with blood pacts (Avatar's Favor, Shining Ruby)
  - Smart pet validation: Carbuncle-specific abilities only execute when Carbuncle is summoned; avatar-agnostic abilities work with any avatar

- **White Mage** (WHM)
  - Critical HP abilities (Divine Seal, Martyr)
  - Single-target healing with white magic (Cure I-V)
  - Revive with white magic (Raise, Raise II, Arise)
  - AOE healing with white magic (Curaga I-IV)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona, Esuna)
  - Buff with white magic (Protectra I-V, Shellra I-V, Protect I-IV, Shell I-IV, Haste, Regen I-III, Reraise, Reraise II, Reraise III, Auspice, Aquaveil, Blink, Stoneskin, Enlight, Barfira, Barblizzara, Baraera, Barstonra, Barthundra, Barwatera, Barsleepra, Barpoisonra, Barparalyzra, Barblindra, Barsilencera, Barvira, Barpetra, Baramnesra)

## Installation

1. Place the entire `Medic` folder in your Ashita `addons` directory
2. Load the addon in-game: `/addon load medic`
3. Configure settings: `/medic` (opens the configuration UI)
4. Start automation: `/medic start`

## Commands

- `/medic` or `/med` - Show/hide configuration UI (default action)
- `/medic help` or `/med help` - Show command help
- `/medic start` or `/med start` - Start automation
- `/medic stop` or `/med stop` - Stop automation
- `/medic toggle` or `/med toggle` - Toggle automation on/off
- `/medic config` or `/med config` - Show/hide configuration UI
- `/medic focus <index>` - Set focus target (0-5, party member index)
- `/medic focus clear` - Clear focus target
- `/medic debug` or `/med debug` - Toggle debug mode
- `/medic recast` or `/med recast` - Show all active ability recast timers
- `/medic status` or `/med status` - Show current status and settings

**Note**: `/med` is a shorthand alias for `/medic`. Running `/medic` with no arguments opens the configuration UI; use `/medic help` to list commands.

## Usage

### Basic Setup

1. Load the addon: `/addon load medic`
2. Open config: `/med config`
3. Enable desired features (healing, buffs, etc.)
4. Adjust thresholds as needed
5. Start automation: `/med start`

### Focus Target

Focus targets are prioritized for healing and debuff removal:

```
/medic focus 1  # Set party member 1 as focus
/medic focus clear  # Clear focus
```

Party indices:
- 0 = You
- 1-5 = Other party members

### Debug Mode

Enable debug logging to troubleshoot issues:

```
/medic debug
```

This will show detailed information about ability selection, cooldowns, and action execution.

## Architecture

```
Medic/
├── Medic.lua                  # Main addon file
├── lib/
│   ├── core/
│   │   ├── common.lua         # Shared utilities (party, buffs, commands, game_state)
│   │   ├── action_core.lua    # Resource/cooldown tracking, ability candidacy helpers
│   │   ├── automation.lua     # Priority-based action selection engine
│   │   ├── parse_packets.lua  # Packet parsing for casting state / buff tracking
│   │   └── targets.lua        # FFXI target-resolution helpers (from Ashita)
│   ├── actions/
│   │   ├── heal.lua           # Healing (single-target, AOE, pet)
│   │   ├── status_removal.lua # Debuff removal & sleep wake
│   │   ├── recover.lua        # MP/TP recovery
│   │   ├── buff.lua           # Buff maintenance
│   │   ├── geo.lua            # Geo buff/debuff targeting & Full Circle / luopan management
│   │   ├── item.lua           # Consumable-based status removal
│   │   ├── rest.lua           # Automatic resting (/heal)
│   │   └── revive.lua         # Raise dead party/tracked/alliance members
│   ├── jobs/                  # Per-job ability data tables (BRD, DNC, GEO, PLD, RDM, RUN, SCH, SMN, WHM)
│   │   └── *.lua
│   └── ui/
│       ├── config.lua         # ImGui configuration orchestration
│       ├── components.lua     # Reusable imgui render components & constants
│       ├── panel.lua          # Debug game-state panel (/medic panel)
│       └── tooltips.lua       # Contextual hover-help text
```

## Configuration

Settings are saved per job in JSON format in the Ashita config directory:
- `settings_white_mage.json`
- `settings_summoner.json`
- `settings_dancer.json`
- etc.

### Common Settings

- `automation_enabled` (boolean): Automation on/off
- `focus_enabled` (boolean): Use focus target
- `focus_target_index` (number): Focus target party index
- `heal_enabled` (boolean): Enable healing
- `heal_threshold` (number): HP% threshold for healing
- `heal_aoe_enabled` (boolean): Enable AOE healing
- `heal_aoe_threshold` (number): HP% threshold for AOE
- `heal_aoe_count_threshold` (number): Min members needing heal for AOE
- `heal_pet_enabled` (boolean): Enable pet healing
- `heal_pet_threshold` (number): Pet HP% threshold for healing
- `wake_enabled` (boolean): Enable sleep removal
- `buff_enabled` (boolean): Enable buff maintenance
- `debuff_removal_enabled` (boolean): Enable debuff removal
- `recover_enabled` (boolean): Enable MP/TP recovery
- `rest_enabled` (boolean): Enable automatic resting (MP-based jobs only)
- `rest_timer` (number): Timer duration in seconds before resting starts (1-20, default 5)
- `rest_threshold` (number): HP% threshold - stops resting if any party member below this (1-99, default 70)
- `rest_distance` (number): Distance in yalms to follow target - stops resting if exceeded (1-15, default 7)
- `follow_target` (string): Character name of party member to follow for distance checking (P1-P5, optional)
- `geo_enabled` (boolean): Enable geo management (Geo buffs, Geo debuffs, and Full Circle / luopan handling)
- `geo_distance_threshold` (number): Distance (yalms) the luopan may drift from the selected Geo target before Full Circle recalls and recasts it (7-30)
- `selected_Geo-bt` (string): Selected Geo debuff spell to cast on your battle target (combat-only)
- `disabled_group_Geo-bt` (boolean): Disables casting the selected Geo debuff

## Design Principles

### Support-Only Focus
- No combat automation
- No tanking/enmity management
- No magic bursting or offensive spells
- Only healing, buffing, debuff removal, recovering, and basic Geo pet management

### Configuration Over Code
- Jobs defined via configuration files
- No hard-coded ability names in core logic
- Easy to adjust per-job settings

### Safety First
- Multiple validation layers
- Automatic resource checking
- Status ailment detection (Silence/Amnesia)
- Cooldown tracking
- Event/cutscene blocking

### Performance
- Efficient party checking algorithms
- 1-second command throttle to prevent spam
- Early returns for disabled states

## Known Limitations

- Alliance automation is limited to abilities with `target_outside = true` (spells/abilities that can be cast on non-party targets)
- Designed to work on [CatsEyeXI private server](https://www.catseyexi.com/)
- To use attack range requires [Multisend](https://github.com/ThornyFFXI/Multisend)
- Requires Ashita v4

## License

See [LICENSE file for details.](https://github.com/seekey13/Medic/blob/main/LICENSE)
