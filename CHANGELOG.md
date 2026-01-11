# Changelog

All notable changes to Medic will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-11

### Summary

**Initial support-only release.** This version represents a complete refocus from a full automation framework to a dedicated support-only healer addon. All combat automation, offensive abilities, and non-support features have been removed.

### Scope

**Supported Modules:**
- buff
- debuff_removal
- geo
- heal
- heal_aoe
- heal_pet
- recover
- wake

**Supported Jobs:**
- Bard (BRD)
- Dancer (DNC)
- Geomancer (GEO)
- Paladin (PLD)
- Red Mage (RDM)
- Rune Fencer (RUN)
- Scholar (SCH)
- Summoner (SMN)
- White Mage (WHM)

### Added
- Initial support-only release
- Complete rewrite of README.md to reflect support-only scope
- Clearer documentation of intended use and limitations

### Changed
- Refocused entire codebase on support actions only
- Updated all documentation to reflect support-only nature

### Removed
- All references to full automation or unsupported features
- All documentation for non-support jobs (Monk, Warrior, Dark Knight, Black Mage, Ranger, Samurai, Dragoon, Corsair, Ninja, Puppetmaster, Beastmaster, Thief, Blue Mage)
- All documentation for combat automation systems (attack, tank, counter, nuke, debuff application, steps, weaponskill, go, roll, pet summoning)

### Fixed
- **Critical**: heal_pet module now properly loaded in action_modules table
- **Critical**: Fixed master priority naming inconsistency (aoe_heal → heal_aoe)
- Updated header comments in core modules

### Technical Details
- Fixed master_priority list to match actual action module names
- Added heal_pet to action_modules and master_priority (was missing)
- Attack range management: Off, Melee, Ranged/Caster distance options
- Ammunition checking for ranged abilities via has_ammo() function

