# Medic - Support-Only Healer Addon for FFXI

A focused, support-oriented addon for Ashita v4 that automates healing, buffing, and debuff removal for select support jobs in Final Fantasy XI.

## ⚠️ Important: This is NOT a Full Automation Tool

**Medic is a support-only addon.** It provides healing, buffing, debuff removal, and basic pet management. It does **NOT** automate:
- Combat/attacking
- Tanking/enmity management
- Magic bursting/nuking
- Weaponskills
- Movement/positioning
- Full job automation

## Version 0.1.0 - Initial Support Release

This is the first official release focusing purely on support functionality.

## Features

### Core Support Actions
- **Single-Target Healing**: Intelligent HP deficit-based heal selection
- **AOE Healing**: Party-wide healing when multiple members need HP
- **Pet Healing**: Automated healing for job pets (wyverns, avatars, luopans, etc.)
- **Sleep Removal (Wake)**: Automatically wake sleeping party members
- **Debuff Removal**: Remove poison, paralysis, silence, and other negative status effects
- **Buff Maintenance**: Auto-apply and maintain self-buffs and party buffs
- **Resource Recovery**: Automated MP and TP recovery abilities
- **Geomancer Support**: Automatic Full Circle execution when luopan exceeds distance threshold

### User Interface
- **ImGui Configuration UI**: User-friendly settings interface
- **Per-Ability Toggles**: Enable/disable individual abilities
- **Threshold Configuration**: Customize HP/TP/MP thresholds
- **Focus Target Support**: Prioritize specific party members
- **Level-Based Filtering**: Shows only abilities available at your current level
- **Auto-Refresh**: UI updates automatically when jobs or levels change

### Core System Features
- **Smart Resource Management**: Automatic MP/TP checking and cooldown tracking
- **Focus Target Support**: Prioritize specific party members for healing/support
- **Main/Sub Job Support**: Automatically loads and merges abilities from both jobs
- **Priority-Based Actions**: Configurable action priority order per job
- **Settings Persistence**: Settings saved per job in JSON format

## Supported Jobs

Currently implemented support jobs:

- **Bard** (BRD)
  - Songs (Ballad, Minne, Paeon, Madrigal, Prelude, March, etc.)
  - Buff maintenance and debuff abilities

- **Dancer** (DNC)
  - Waltzes (Curing Waltz I/II/III, Divine Waltz, Healing Waltz)
  - Sambas (Drain Samba, Aspir Samba, Haste Samba)
  - Jigs (Spectral Jig for sneak/invis)

- **Geomancer** (GEO)
  - Geomancy spells (Indi- and Geo-)
  - Automatic Full Circle execution
  - Healing and buff maintenance

- **Paladin** (PLD)
  - Single-target healing (Cure I-IV)
  - Party buffs (Protect/Shell)
  - Defensive abilities

- **Red Mage** (RDM)
  - Healing (Cure I-IV)
  - Enhancing magic (Refresh, Haste, Phalanx, etc.)
  - Debuff removal (Erase, Viruna, Paralyna, etc.)

- **Rune Fencer** (RUN)
  - Rune effects (Ignis, Gelus, Flabra, Tellus, Sulpor, Unda, Lux, Tenebrae)
  - Magic and Vivacious Pulse healing

- **Scholar** (SCH)
  - Light Arts/Dark Arts
  - Stratagems (Penury, Celerity, Rapture, Accession, etc.)
  - Healing and buff maintenance

- **Summoner** (SMN)
  - Blood Pacts: Healing Ruby, Healing Ruby II
  - Pet management and healing

- **White Mage** (WHM)
  - Single-target healing (Cure I-V)
  - AOE healing (Curaga I-IV)
  - Debuff removal (Erase, Viruna, Paralyna, Blindna, Silena, Poisona, Cursna)
  - Buff maintenance (Protectra, Shellra, Haste, Regen, etc.)

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
2. Open config: `/medic config`
3. Enable desired features (healing, buffs, etc.)
4. Adjust thresholds as needed
5. Start automation: `/medic start`

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
- Cooldown tracking
- Event/cutscene blocking

### Performance
- Efficient party checking algorithms
- 1-second command throttle to prevent spam
- Early returns for disabled states

## Known Limitations

- Party only (no alliance support)
- Buffing limited to Self targeting
- Some buff IDs may vary by private server
- Requires Ashita v4

## License

See LICENSE file for details.
