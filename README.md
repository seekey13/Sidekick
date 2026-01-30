# **Medic** - Support Job Automation Framework

A focused, support-oriented addon for Ashita v4 that automates healing, buffing, and debuff removal for select support jobs in Final Fantasy XI.  Tuned specifically for [CatsEyeXI private server](https://www.catseyexi.com/).

## New Collapsable and Party Scaling UI
<img width="1044" height="1011" alt="Screenshot" src="https://github.com/user-attachments/assets/562dc45e-2f86-41ff-934e-26c13c81004c" />


## ⚠️ Important: This is NOT a Full Automation Tool

**Medic is a support-only addon.** It provides healing, buffing, debuff removal, and basic pet management. It does **NOT** automate:
- Combat/attacking
- Tanking/enmity management
- Magic bursting/nuking
- Weaponskills
- Movement/positioning
- Full job automation

## Latest Updates

### [1.3.0] - 2026-01-22
- **Pianissimo Support for Bard**: Bard songs can now be cast on party members using Pianissimo ability (level 20+), automatically integrated into party buff system
- **Song Limit Enforcement**: Bard songs limited to 2 per party member (main job) or 1 per party member (sub job) to match game mechanics
- **Party Buff Persistence**: Party buff selections (song assignments, etc.) now persist through addon reloads and zone changes
- **Target Modifier System**: New `target_modifier` ability category for abilities that redirect self-targeted spells to party members (Pianissimo, Entrust)
- **Smart UI Feedback**: Party buttons automatically disabled with grayed-out text when Pianissimo unavailable (below level 20), matching unlearned spell style


## Features

### Core Support Actions
- **PL Mode (Power Leveling Mode)**: Heal players outside your party via `/mst` command relay with automatic connection detection, entity-based distance tracking, and Trust exclusion logic (Requires [Multisend](https://github.com/ThornyFFXI/Multisend))
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
- **Geomancer Support**: Automatic Full Circle execution when luopan exceeds distance threshold

### User Interface
- **ImGui Configuration UI**: User-friendly settings interface with collapsible sections and PL Mode toggle with adaptive UI
- **Group Dropdown Selectors**: Multiple abilities in a group (e.g., Cure I-V) consolidated into dropdown menus
- **Per-Ability Toggles**: Enable/disable individual abilities
- **Button-Based Party Buff Targeting**: Single-target buffs display ME/P1-P5 buttons for precise control over who receives each buff
- **Trust Buff Support**: Can track and cast buffs on Trusts using packet-based detection
- **Subjob Duplicate Filtering**: Automatically hides duplicate abilities from subjob when they exist in main job
- **Threshold Configuration**: Customize HP/TP/MP thresholds
- **Focus Target Support**: Prioritize specific party members
- **Level-Based Filtering**: Shows only abilities available at your current level
- **Collapsible Sections**: All major features (Healing, Buffs, Debuff Removal, etc.) are collapsible for cleaner organization
- **Auto-Refresh**: UI updates automatically when jobs or levels change

### Core System Features
- **PL Mode Support**: Cross-party healing via `/mst` commands with automatic connection handling, entity tracking, and Trust exclusion
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

- **Geomancer** (GEO)
  - AOE healing with job abilities (Mending Halation)
  - Pet healing with job abilities (Life Cycle)
  - Buff with geomancy spells (Geo & Indi)
  - Entrust system: Select target party member and Indi spell to automatically cast via Entrust ability
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
  - Critical HP abilities (Apogee)
  - Single-target healing with blood pacts (Healing Ruby - requires Carbuncle)
  - AOE healing with blood pacts (Healing Ruby II - requires Carbuncle)
  - Buff with blood pacts (Avatar's Favor, Shining Ruby)
  - Smart pet validation: Carbuncle-specific abilities only execute when Carbuncle is summoned; avatar-agnostic abilities work with any avatar

- **White Mage** (WHM)
  - Critical HP abilities (Divine Seal, Martyr)
  - Single-target healing with white magic (Cure I-V)
  - AOE healing with white magic (Curaga I-IV)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona, Esuna)
  - Buff with white magic (Protectra I-V, Shellra I-V, Protect I-IV, Shell I-IV, Haste, Regen I-III, Reraise, Reraise II, Reraise III, Auspice, Aquaveil, Blink, Stoneskin, Enlight, Barfira, Barblizzara, Baraera, Barstonra, Barthundra, Barwatera, Barsleepra, Barpoisonra, Barparalyzra, Barblindra, Barsilencera, Barvira, Barpetra, Baramnesra)

## Installation

1. Place the entire `Medic` folder in your Ashita `addons` directory
2. Load the addon in-game: `/addon load medic`
3. Configure settings: `/medic config`
4. Start automation: `/medic start`

## Commands

- `/medic start` or `/med start` - Start automation
- `/medic stop` or `/med stop` - Stop automation
- `/medic toggle` or `/med toggle` - Toggle automation on/off
- `/medic config` or `/med config` - Show/hide configuration UI
- `/medic focus <index>` - Set focus target (0-5, party member index)
- `/medic focus clear` - Clear focus target
- `/medic debug` or `/med debug` - Toggle debug mode
- `/medic recast` or `/med recast` - Show all active ability recast timers
- `/medic status` or `/med status` - Show current status and settings
- `/medic help` or `/med help` - Show command help

**Note**: `/med` is a shorthand alias for `/medic`

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
├── Medic.lua              # Main addon file
├── lib/
│   ├── core/
│   │   ├── common.lua        # Shared utilities
│   │   ├── automation.lua    # Action selection engine
│   │   ├── resource.lua      # Resource/cooldown tracking
│   │   └── parse_packets.lua # Packet parsing for casting state
│   ├── actions/
│   │   ├── heal.lua          # Single-target healing
│   │   ├── heal_aoe.lua      # AOE healing
│   │   ├── heal_pet.lua      # Pet healing
│   │   ├── wake.lua          # Sleep removal
│   │   ├── debuff_removal.lua # Debuff removal
│   │   ├── recover.lua       # MP/TP recovery
│   │   ├── buff.lua          # Buff maintenance
│   │   └── geo.lua           # Geo Full Circle management
│   ├── jobs/
│   │   ├── bard.lua          # Bard abilities
│   │   ├── dancer.lua        # Dancer abilities
│   │   ├── geomancer.lua     # Geomancer abilities
│   │   ├── paladin.lua       # Paladin abilities
│   │   ├── red_mage.lua      # Red Mage abilities
│   │   ├── rune_fencer.lua   # Rune Fencer abilities
│   │   ├── scholar.lua       # Scholar abilities
│   │   ├── summoner.lua      # Summoner abilities
│   │   └── white_mage.lua    # White Mage abilities
│   └── config_ui.lua         # ImGui configuration interface
```

## Configuration

Settings are saved per job in JSON format in the Ashita config directory:
- `settings_white_mage.json`
- `settings_summoner.json`
- `settings_dancer.json`
- etc.

### Common Settings

- `automation_enabled` (boolean): Automation on/off
- `pl_mode_enabled` (boolean): Enable PL Mode for cross-party healing
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
- `geo_enabled` (boolean): Enable geo management
- `geo_distance_threshold` (number): Distance threshold for Full Circle

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

- Party only (no alliance support)
- Designed to work on [CatsEyeXI private server](https://www.catseyexi.com/)
- To use attack range and PL Mode requires [Multisend](https://github.com/ThornyFFXI/Multisend)
- Requires Ashita v4

## License

See [LICENSE file for details.](https://github.com/seekey13/Medic/blob/main/LICENSE)
