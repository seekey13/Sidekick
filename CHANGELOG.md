# Changelog

All notable changes to Medic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-16

### Added
- **Button-Based Party Buff Targeting**: Single-target buffs now display ME/P1-P5 buttons for precise control over who receives each buff (e.g., Haste, Refresh, Protect, Shell, Enspells, etc.)
- **Trust Detection**: Party member buttons automatically disable for Trusts (server_id >= 0x1000000) since buffs cannot be cast on them
- **Single-Target Buff Support**: Jobs can now cast single-target buffs on party members with intelligent uptime tracking and range validation (20 yalms)
- **Movement Blocking**: Casting is now prevented while the player is moving to avoid interrupted spells

### Changed
- **Buff UI**: Single-target buffs (function commands) now use button-based targeting instead of checkboxes
- **Buff Logic**: Abilities are automatically enabled when any ME/P1-P5 button is selected, and disabled when all buttons are deselected
- **Party Buff Validation**: Added zone matching and range checking before casting buffs on party members

### Fixed
- Button-based buffs now properly check if the ability is enabled before attempting to cast
- Party buff state correctly syncs with settings on button toggle

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