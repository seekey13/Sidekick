# **Medic** - Support Job Automation Framework

A focused, support-oriented addon for Ashita v4 that automates healing, buffing, debuff removal, resource recovery, and reviving for select support jobs in Final Fantasy XI.  Tuned specifically for [CatsEyeXI private server](https://www.catseyexi.com/).

# Quick Start Guide
<img width="1450" height="910" alt="image" src="https://github.com/user-attachments/assets/e6b15b0a-35ad-4182-98f1-c1488c3f08f2" />

### Header
<img width="1453" height="555" alt="image" src="https://github.com/user-attachments/assets/c5dd8d6b-a8b8-4ae1-968a-4f7af5978de1" />

### Focus Healing
<img width="1449" height="386" alt="image" src="https://github.com/user-attachments/assets/41492d8c-0dd8-4715-94de-cd5abb89c04f" />

### Group Healing
<img width="1454" height="643" alt="image" src="https://github.com/user-attachments/assets/4759be51-5d4d-42d5-849f-e86b96c63b75" />

### AOE Healing
<img width="1453" height="465" alt="image" src="https://github.com/user-attachments/assets/2de2b4ff-9aff-4012-b2bf-53f6746fd451" />

### Pet Healing
<img width="1454" height="353" alt="image" src="https://github.com/user-attachments/assets/560b3be2-055c-47f2-a1f4-711cfc6d4f7b" />

### Sleep Removal
<img width="1360" height="294" alt="image" src="https://github.com/user-attachments/assets/8496c23a-9ec3-4408-a339-84cdf99cc7fe" />

### Debuff Removal
<img width="1449" height="549" alt="image" src="https://github.com/user-attachments/assets/8676c0cd-561b-41bb-911e-7c48e72f4073" />

### Item Debuff Removal
<img width="1453" height="496" alt="image" src="https://github.com/user-attachments/assets/8c3e08b4-7827-44ae-bd0a-8872d8ffb8c8" />

### Resting
<img width="1453" height="581" alt="image" src="https://github.com/user-attachments/assets/9d3b6642-9ed8-49cb-9749-f10a259ffbba" />

### Recource Recovery
<img width="1450" height="469" alt="image" src="https://github.com/user-attachments/assets/7ca740b2-3ed2-4bbf-83d5-18bcc7d80837" />

### Buffs
<img width="1449" height="1075" alt="image" src="https://github.com/user-attachments/assets/27ebedaf-ffa7-4432-80c6-de90cb8c4a37" />

### Revive
<img width="1453" height="378" alt="image" src="https://github.com/user-attachments/assets/2afff4a6-9538-4f07-b7db-5c47cbeda4e1" />

## ⚠️ Important: This is NOT a Full Automation Tool

**Medic is a support-only addon.** It provides healing, buffing, debuff removal, and basic pet management. It does **NOT** automate:
- Combat/attacking
- Tanking/enmity management
- Magic bursting/nuking
- Weaponskills
- Movement/positioning
- Full job automation

## Latest Updates

### [2.3.0] - 2026-07-09

Adds **Chakra** to Monk — a self-cure that recovers HP and clears its own Poison / Blindness.

### Added
- **Monk Chakra**: Monk now self-casts **Chakra** to recover HP and to remove its own **Poison** and **Blindness**. Wired as both a self-heal and a self debuff removal (see [Supported Jobs](#supported-jobs)).

### [2.2.0] - 2026-07-06

Adds three pet-support jobs (Beastmaster, Dragoon, Puppetmaster) with consumable-ammo auto-equip and packet-based pet status tracking, plus three self-support jobs (Monk, Samurai, Ninja) and a right-click **Idle Only** ability toggle; also makes packet-tracked buffs/debuffs (Trusts, tracked players, alliance, pets) expire on a timer so a missed wear-off packet no longer leaves a stale status stuck forever; also reworks debuff-removal priority (targeted cures before Erase, group Esuna) — alongside internal dead-code cleanup and UI polish.

### Added
- **Timed Status Expiry**: Every packet-tracked buff/debuff records a base duration and falls off on its own once elapsed, instead of waiting for a wear-off packet that may never arrive. Covers Trusts, tracked players, alliance members, and the pet.
- **Debuff Backstop Durations**: Removable debuffs (Poison, Paralysis, Silence, Sleep, Petrify, Doom, Bind, Gravity, Slow, etc.) get a fall-off timer so a missed cure-detection can't spam the na-/Erase spell forever. Curse, Bane, Disease, and Plague are treated as "until removed."
- **Per-Caster Bard Song Slots**: Song tracking now mirrors FFXI's 2-songs-per-bard limit per target, so a second bard's songs no longer evict yours.
- **Beastmaster / Dragoon / Puppetmaster**: Three new pet-support jobs (see [Supported Jobs](#supported-jobs)).
- **Monk / Samurai / Ninja**: Three new self-support jobs — Monk self-buffs Boost, Dodge, Focus, Counterstance, Footwork; Samurai self-buffs Warding Circle, Third Eye, and the Hasso/Seigan stance plus TP recovery via Meditate; Ninja maintains its Ninjutsu stances and Utsusemi/Tonko/Monomi utility spells plus Sange (see [Supported Jobs](#supported-jobs)).
- **Inventory-Tool Gating**: Ninjutsu spells need a **tool held in the bag** (not worn), so a new `requires_item` gate counts the spell's own tool plus Shikanofuda (the universal substitute) and grays/locks the spell at zero — separate from the ammo-slot auto-equip used by Sange and pet consumables.
- **Idle Only Toggle**: Right-click any ability and pick **Idle Only** (next to Combat Only) to fire it only out of combat — e.g. Monk Boost on cooldown while idle. The two are mutually exclusive.
- **Consumable-Ammo Auto-Equip**: Abilities that need a consumable worn in the ammo slot (BST Pet Food, PUP Automaton Oil) auto-equip the best owned tier for your level — from inventory or any Mog Wardrobe — before firing. The config UI shows a live count, green when equipped and red when not.
- **Pet Status Tracking**: A pet's buffs/debuffs are inferred from packets (the client keeps no pet buff memory) so BST/PUP can strip the pet's status ailments. As with Trusts, this tracking is not perfectly reliable.
- **Beastmaster Ready Charges**: Ready-move charges are tracked like Scholar stratagems and shown in the `/med panel` header.
- **Expanded Item-Based Removal**: The item-cure feature grows from 2 items to 9 (Antidote, Eye/Echo Drops, Holy/Hallowed Water, Tincture, Remedy Ointment, Remedy, Panacea), grouped under one collapsing **Item Debuff Removal** header with a master toggle. Only reliably-cured ailments are listed per item (Remedy skips Disease, Panacea skips Amnesia) so it can't loop the stack on something it won't clear.

### Changed
- **Item Removal Matched by ID**: Inventory counts and the `/item` command now key off item ID rather than the English name, so custom-server items (Remedy Ointment, Hallowed Water, Tincture) resolve correctly instead of showing `?`. Items are never used while moving, and the whole section stays hidden until inventory is readable.
- **Cursna Curse List**: Cursna and Holy/Hallowed Water share `common.CURSE_DEBUFFS` (Curse, Doom, Bane) so the curable set is defined once.
- **UI Section Order & Colors**: Status-removal sections now read Sleep → Debuff → Pet Debuff → Item; the ammo-count `(n)` reuses the current-job green when equipped and the automation-stopped red when not.
- **Targeted Cure Before Erase**: Debuff removal now uses a targeted na-spell (Poisona, Paralyna, etc.) before generic Erase, so the exact ailment is stripped first and Erase mops up the rest.
- **Group Esuna (AOE)**: Esuna now fires when 2+ members within 10 yalms (you + party + alliance) share an Esuna-removable ailment, clearing them in one cast; a single affected target uses the cheaper na-spell instead. Pets and Trusts aren't in the AOE.
- **Party Button Tooltips**: Hovering a target button (**ME** / **P1–P5**) now shows that member's character name; on Trust/tracked buttons the reliability caveat is appended below the name.
- **"Not Learned" Tooltip**: Unlearned abilities show a *Not Learned* hover tooltip instead of a `(Not Learned)` label suffix.
- **Debug Scalars Moved**: The Zone / Target / Moving / Casting readout moved from the configuration window to the `/med panel` header (shown while Debug Mode is on).

### Fixed
- **Removal Spells Looping on Trusts/Alliance/Pet**: After curing a status (e.g. Poisona on a Trust, or a Reward/Maintenance strip on a pet), Medic now drops that status from tracking immediately instead of re-casting every tick until it detects the removal.
- **Cure-Wake on Trusts/Alliance**: Waking a Trust or alliance member with a Cure now clears Sleep from tracking right away, so it stops re-curing them.
- **Afflatus Solace**: Corrected recast id (245 → 29) so its cooldown is tracked correctly (White Mage).

### [2.1.0] - 2026-07-05

### Added
- **Group / AOE Heal Target Selection**: Group and AOE healing now have per-target selection buttons (**Group Targets** / **AOE Targets**) so you choose who is managed. Deselecting a member excludes them from single-target Group scanning or the AOE below-threshold average. Party and tracked members are ON by default; alliance (B/C) members are OFF by default. AOE selection lists ME + party only. Selections are per-session and reset each load.
- **Bard Area Songs (`[A]` button)**: An **A** button to the left of the target buttons sings a song without Pianissimo so everyone within range (10 yalms) gets it. The area recast only tracks in-range party members who aren't assigned a specific ME/P button, so single-target songs coexist with area songs.
- **Bard Self Songs via Pianissimo**: The **ME** button now uses Pianissimo, letting a Bard single-target buff themselves the same as any other party member.
- **Stacking Same-Buff Songs (Ungroup)**: Right-click a grouped buff and choose **Ungroup** to cast every tier independently instead of only the selected one — e.g. Mage's Ballad + Mage's Ballad II on the same target.
- **Hold for Stratagem**: A checkbox in the Scholar stratagem popup. ON = skip the spell until the stratagem can fire; OFF (default) = cast the spell without the stratagem when no charge is available.

### Changed
- **Automatic Window Sizing**: The configuration window auto-resizes to fit its content and force-expands when reopened (no more empty title bar from a collapsed state). Collapsing no longer closes it — only the `[X]` does.
- **Debug Mode Moved**: The Debug Mode checkbox moved from the configuration window to the `/med panel` header.

### Fixed
- **`HasSpell` Check**: Unlearned spells are no longer treated as learned.
- **Stratagem Stuck from High-Level SCH**: Stratagems assigned on a high-level Scholar are pruned when switching to a lower level or `???/SCH`, so the configuration is no longer stuck.
- **Geo-bt UI Alignment**: Geo-bt debuff rows no longer show an unwanted stratagem indent.
- **Song 2-Limit**: The per-member song limit (2 main / 1 sub) is enforced correctly across grouped and ungrouped songs.

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
- **Item-Based Status Removal**: Automatically use consumable items to cure status ailments — Antidote (Poison), Eye Drops (Blind), Echo Drops (Silence), Holy Water / Hallowed Water (Curse/Doom/Bane), Tincture (Plague/Disease), Remedy Ointment & Remedy (Poison/Paralyze/Blind/Silence), Panacea (stat-downs). Grouped under one collapsing header with a live per-item count; matched by item ID (not name, so custom-server items work), never fired while moving, and the section hides until inventory loads
- **Critical HP Response**: Emergency abilities (e.g., Divine Seal, Martyr, Contradance) automatically trigger when party members drop below critical threshold (default 30%)
- **Single-Target Healing**: Intelligent HP deficit-based heal selection with priority system (Critical HP → Focus target → Regular lowest HP)
- **Group / AOE Heal Target Selection**: Per-target ME/P1-P5 (plus alliance and tracked for Group) buttons choose who Group and AOE healing manage; party/tracked default ON, alliance default OFF, selections per-session
- **AOE Healing**: Party-wide healing when multiple members need HP
- **Pet Healing & Support**: Automated healing for pets — GEO luopan, DRG wyvern, BST jug pets, PUP automaton — plus pet buff/debuff removal for jobs whose pet-heal ability needs a consumable equipped in the ammo slot (auto-equipped from inventory or a Mog Wardrobe)
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

- **Beastmaster** (BST) — *pet-only support*
  - Pet healing with **Reward** (requires a **Pet Food** biscuit in the ammo slot; auto-equips the best tier for your level)
  - Pet Regen with **Reward (Regen)** using a **Pet Poultice** (reapplied on a timer since pet buffs can't be read)
  - Pet debuff removal with **Reward (Erase)** using a **Pet Roborant**
  - Party AOE healing with **Wild Carrot** from a rabbit jug pet (KeenearedSteffi / Rabbit), gated on a Ready charge
  - Only one ammo can be worn at a time, so the three Reward variants never contend for the ammo slot

- **Dragoon** (DRG) — *pet-only support*
  - Pet (wyvern) healing with **Spirit Link** (no item — transfers the master's HP)
  - Self-buffs: **Ancient Circle**, **Spirit Bond**

- **Puppetmaster** (PUP) — *pet-only support*
  - Automaton healing with **Repair** (requires an **Automaton Oil** in the ammo slot; higher tiers heal more; PUP-main only)
  - Automaton debuff removal with **Maintenance** (same Oil ammo)

- **Bard** (BRD)
  - Buff with songs on self or party members using Pianissimo (level 20+) — the ME button self-buffs via Pianissimo too
  - Area songs: an `[A]` button (left of the target buttons) sings without Pianissimo so everyone in range (10 yalms) gets it
  - Songs: Minuet, Minne, Paeon, Madrigal, Prelude, March, Ballad, Etude, Carol, Mambo, Mazurka, Scherzo, Threnody, etc.
  - Song limits: 2 songs per party member (main job) or 1 song per party member (sub job)
  - Stack same-buff tiers: right-click → Ungroup to cast each tier independently (e.g. Mage's Ballad + Mage's Ballad II)
  - Party button targeting with automatic Pianissimo usage
  - Settings persist through reloads

- **Blue Mage** (BLU)
  - Self-heal with **Pollen**; party healing with **Wild Carrot** and **Magic Fruit** (blue magic cures can't target outside the party)
  - AOE healing with **Healing Breeze**
  - Self-buffs with blue magic (Cocoon, Metallic Body, Refueling, Feather Barrier, Memento Mori, Zephyr Mantle, Warm-Up, Amplification, Saline Coat, Reactor Cool, Plasma Charge)
  - **Unbridled Learning** spells (level 75: Battery Charge, Animating Wail, Magic Barrier, Occultation, Orcish Counterstance, Barrier Tusk, Harden Shell, Pyric Bulwark, Carcharian Verve) — the Unbridled Learning JA is popped automatically right before the spell, and the spell is held while the JA is on cooldown
  - **Diffusion** (level 75 merit, BLU main): a **D** button on every blue buff row opens a popup — **Enable** fires Diffusion before the buff to spread it to the whole party; **Hold for Diffusion** skips the buff until Diffusion is ready (off by default: the buff still casts self-only when Diffusion is on cooldown)

- **Dancer** (DNC)
  - Critical HP abilities (Contradance)
  - Single-target healing with waltzes (Curing Waltz I/II/III)
  - AOE healing with waltzes (Divine Waltz, Divine Waltz II)
  - Debuff removal with waltz (Healing Waltz)
  - Buff with sambas (Drain Samba I/II/III, Aspir Samba, Haste Samba)
  - Buff with jigs (Spectral Jig)
  - Buff with level-75 job abilities (Saber Dance, Fan Dance, No Foot Rise, Presto)

- **Dark Knight** (DRK) — *self-only support*
  - Self-buffs with job abilities (Arcane Circle, Last Resort, Souleater, Consume Mana, Diabolic Eye, Scarlet Delirium)
  - Self-buff with dark magic (Dread Spikes)
  - Absorb spells on your battle target (Absorb-Attri, Absorb-ACC, Absorb-TP, Absorb-STR/DEX/INT/AGI/VIT/CHR/MND) — combat-only, single spell selectable via dropdown
  - **Nether Void** (level 75, DRK main): an **N** button on the Absorb row opens a popup — **Enable** fires Nether Void before the selected Absorb to boost it; **Hold for Nether Void** skips the Absorb until Nether Void is ready (off by default: the Absorb still casts without it when Nether Void is on cooldown)

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

- **Monk** (MNK) — *self-only support*
  - Self-heal with Chakra (HP recovery)
  - Self debuff removal with Chakra (Poison, Blindness)
  - Self-buffs with job abilities (Boost, Dodge, Focus, Counterstance, Footwork)

- **Ninja** (NIN) — *self-only support*
  - Ninjutsu stances (Yonin / Innin — mutually exclusive)
  - Utsusemi (shadows, Ichi/Ni), and the idle-only Tonko (movement) / Monomi (Sneak) utility spells
  - Sange (throws a shuriken — auto-equips the best owned tier in the ammo slot)
  - Ninjutsu spells need their **tool in inventory** (family tool or Shikanofuda); a spell with zero tools is grayed and never cast

- **Paladin** (PLD)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with white magic (Protect I-IV, Shell I-IV)

- **Ranger** (RNG) — *self-only support*
  - Self-buffs with job abilities (Sharpshot, Scavenge, Velocity Shot (RNG-main only), Unlimited Shot, Flashy Shot, Stealth Shot)
  - Bounty Shot on your battle target — combat-only

- **Red Mage** (RDM)
  - Single-target healing with white magic (Cure I-IV)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Haste, Refresh, Phalanx, Phalanx II, Enfire, Enblizzard, Enaero, Enstone, Enthunder, Enwater, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)
  - Revive with white magic (Raise)

- **Samurai** (SAM) — *self-only support*
  - Self-buffs with job abilities (Warding Circle, Third Eye, Hasso/Seigan stance — Hasso and Seigan grouped as mutually exclusive)
  - TP recovery with **Meditate**

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

- **Warrior** (WAR) — *self-only support*
  - Self-buffs with job abilities (Berserk, Defender, Warcry, Blood Rage, Aggressor, Retaliation, Warrior's Charge)
  - Note: Berserk cancels Defender and Warcry removes Blood Rage (and vice versa) — enable only one of each pair

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
│   │   └── geo.lua           # Geo buff/debuff targeting & Full Circle / luopan management
│   ├── jobs/
│   │   ├── bard.lua          # Bard abilities
│   │   ├── beastmaster.lua   # Beastmaster abilities (pet-only)
│   │   ├── blue_mage.lua     # Blue Mage abilities
│   │   ├── dancer.lua        # Dancer abilities
│   │   ├── dark_knight.lua   # Dark Knight abilities (self-only)
│   │   ├── dragoon.lua       # Dragoon abilities (pet-only)
│   │   ├── geomancer.lua     # Geomancer abilities
│   │   ├── monk.lua          # Monk abilities (self-only)
│   │   ├── ninja.lua         # Ninja abilities (self-only)
│   │   ├── paladin.lua       # Paladin abilities
│   │   ├── puppetmaster.lua  # Puppetmaster abilities (pet-only)
│   │   ├── ranger.lua        # Ranger abilities (self-only)
│   │   ├── red_mage.lua      # Red Mage abilities
│   │   ├── rune_fencer.lua   # Rune Fencer abilities
│   │   ├── samurai.lua       # Samurai abilities (self-only)
│   │   ├── scholar.lua       # Scholar abilities
│   │   ├── summoner.lua      # Summoner abilities
│   │   ├── warrior.lua       # Warrior abilities (self-only)
│   │   └── white_mage.lua    # White Mage abilities
│   └── ui_config.lua         # ImGui configuration interface
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
- `pet_debuff_removal_enabled` (boolean): Enable pet debuff removal (BST/PUP)
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
- `ungrouped_<group>` (boolean): When true, casts every tier in the group independently instead of only the selected tier (right-click → Ungroup)
- `stratagem_hold[<key>]` (boolean): When true, hold the spell until its assigned stratagem can fire; when false (default), cast without the stratagem if no charge is available

**Note**: Group/AOE heal target selection is per-session (not persisted). Debug Mode toggles from the `/med panel` header.

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
