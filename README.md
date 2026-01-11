\# Medic - Healer automation addon for FFXI specifically tuned for CatsEyeXI



Sidekick is a generic, job-agnostic automation framework for FFXI (Ashita v4) that supports multiple jobs through configuration-driven automation. Instead of hard-coding job-specific abilities, Sidekick uses a modular architecture where jobs are defined via configuration files.



\## Version 2.9.0 - Corsair Roll Automation \& Ammo Checking



\*\*Latest Update\*\*: New roll automation system for Corsair with intelligent Double-Up logic, lucky number detection, and configurable hit thresholds! Added ammunition checking to prevent execution of abilities requiring ammo when none is equipped. Roll totals display in real-time in the config UI with color-coded status.



\## Features



\### Core Automation

\- \*\*Job-Agnostic Design\*\*: Core automation logic works for any job

\- \*\*Main/Sub Job Support\*\*: Automatically loads and merges abilities from both jobs

\- \*\*Configuration-Driven\*\*: Add new jobs by creating a job definition file

\- \*\*Priority-Based Actions\*\*: Configurable action priority order per job

\- \*\*Smart Resource Management\*\*: Automatic MP/TP checking and cooldown tracking

\- \*\*Intelligent Heal Selection\*\*: HP deficit-based healing to minimize overheal and maximize efficiency

\- \*\*Focus Target Support\*\*: Prioritize specific party members for healing/support

\- \*\*Attack Range Management\*\*: Automatically maintain optimal combat distance (Off/Melee/Ranged)

&nbsp; - Melee mode: Maintains 3 yalm distance from engaged target

&nbsp; - Ranged mode: Maintains 15 yalm distance from engaged target

&nbsp; - Uses multisend follow commands to control movement

&nbsp; - Automatically re-enables follow when disengaged

\- \*\*Dynamic UI Updates\*\*: Config UI refreshes automatically on job/level changes



\### Ability Categories

\- \*\*Single-Target Healing\*\*: HP threshold-based healing with intelligent deficit-aware ability selection

&nbsp; - Calculates exact HP deficit to select most efficient heal

&nbsp; - Minimizes overheal and resource waste

&nbsp; - Emergency mode for critically low HP situations

\- \*\*AOE Healing\*\*: Party-wide healing when multiple members need HP

\- \*\*Pet Healing\*\*: Automated healing for player pets (wyverns, avatars, etc.)

&nbsp; - Monitors pet HP percentage in real-time

&nbsp; - Configurable heal threshold (default 50%)

&nbsp; - Uses job-specific pet healing abilities (Spirit Link, Cure spells)

&nbsp; - Always targets `<me>` for pet healing commands

&nbsp; - Priority after player healing

\- \*\*Sleep Removal (Wake)\*\*: Automatically wake sleeping party members

\- \*\*Debuff Removal\*\*: Remove poison, paralysis, silence, and other negative status effects

\- \*\*Buff Maintenance\*\*: Auto-apply and maintain self-buffs (combat/idle aware)

\- \*\*Debuff Application\*\*: Apply stacking debuffs with intelligent balancing

&nbsp; - Packet-based tracking for accurate debuff level detection

&nbsp; - Automatic alternation between multiple debuffs for balanced stacks

&nbsp; - Expiration tracking via game packets

\- \*\*Tank/Enmity Management\*\*: Automatic threat generation and aggro control

&nbsp; - Monitors target's focus to detect when player loses aggro

&nbsp; - Automatically uses enmity abilities to regain mob's attention

&nbsp; - Only active when engaged in combat with valid target

&nbsp; - Configurable per-job basis

\- \*\*Attack Abilities\*\*: Offensive abilities that require a target

&nbsp; - Executes when engaged with valid target in range

&nbsp; - Range and cooldown validation

\- \*\*Weaponskill Automation\*\*: User-configured weaponskill execution at TP threshold

&nbsp; - Configurable weaponskill name via text input (e.g., "Fast Blade", "Savage Blade")

&nbsp; - Adjustable TP threshold (1000-3000) with slider control

&nbsp; - Automatic execution when engaged and TP threshold reached

&nbsp; - Global setting available for all jobs

\- \*\*Pet Attack on Engagement (Go)\*\*: Automatic pet attack commands

&nbsp; - Sends pet to attack when player engages a new enemy

&nbsp; - One-shot per target (tracks last engagement)

&nbsp; - Works for all pet jobs (BST, SMN, DRG, PUP)

&nbsp; - Leverages attack.lua validation for range and combat checks

\- \*\*Resource Recovery\*\*: Automated MP and TP recovery

&nbsp; - Monitors MP percentage and TP levels in real-time

&nbsp; - Configurable thresholds for MP% (1-100) and TP (0-3000)

&nbsp; - Supports MP recovery abilities (Convert, etc.)

&nbsp; - Supports TP recovery abilities (Meditate, etc.)

&nbsp; - Prioritizes MP recovery over TP recovery

&nbsp; - Per-ability toggles in configuration UI

\- \*\*Enemy Ability Interruption (Counter)\*\*: Automatic ability interruption via packet detection

&nbsp; - Real-time detection of enemy ability usage via packet analysis (0x028)

&nbsp; - Automatic counter execution when enemy begins casting/using abilities

&nbsp; - Supports both job abilities and spells (Weapon Bash, Stun spell)

&nbsp; - Priority-based ability selection (prefer low-cost abilities when available)

&nbsp; - Only active while engaged in combat and automation is enabled

&nbsp; - Event-driven system for instant response to threats

\- \*\*Magic Burst (Nuke)\*\*: Automatic elemental spell casting for skillchain magic bursts

&nbsp; - Real-time skillchain property detection from combat packets (0x028)

&nbsp; - Detects all 16 skillchain properties (Light, Darkness, Fusion, Fragmentation, etc.)

&nbsp; - Intelligent element mapping (e.g., Liquefaction → Fire, Distortion → Ice/Water)

&nbsp; - Smart spell selection based on tier, level, MP cost, and disabled settings

&nbsp; - 8-second magic burst window after skillchain detection

&nbsp; - Works with party/alliance skillchains

&nbsp; - One-shot execution per skillchain to prevent spam

\- \*\*Geo Distance Management\*\*: Automatic Full Circle execution for Geomancer pet control

&nbsp; - Real-time monitoring of pet luopan distance from player

&nbsp; - Configurable distance threshold (7-30 yalms, default 10) via slider control

&nbsp; - Automatically uses Full Circle when pet exceeds distance threshold

&nbsp; - Requires active pet and geo abilities enabled in configuration

&nbsp; - Prevents pet from wandering too far during combat

\- \*\*Roll Automation (Corsair)\*\*: Intelligent Phantom Roll and Double-Up management

&nbsp; - Automatic roll casting with configurable Roll 1 and Roll 2 selection

&nbsp; - Smart Double-Up logic: automatically doubles until lucky number or hit threshold

&nbsp; - Lucky number detection stops doubling immediately when hit

&nbsp; - Configurable hit threshold (5-9, default 5) to balance risk vs reward

&nbsp; - Safety limit prevents doubling at 11+ (would bust at 12)

&nbsp; - Real-time roll total tracking via packet detection

&nbsp; - UI displays current totals color-coded: green (lucky), yellow (threshold), white (normal)

&nbsp; - Automatic state reset when changing roll selections

&nbsp; - Bust detection adjusts to 1 roll slot when busted

&nbsp; - Priority execution before buffs and attacks

\- \*\*Ammunition Validation\*\*: Prevents execution of ammo-dependent abilities

&nbsp; - Checks equipped ammo slot for valid ammunition

&nbsp; - Applies to Quick Draw shots, Ranged Attacks, and other ranged abilities

&nbsp; - Automatic validation before ability execution

&nbsp; - Prevents wasted actions when out of ammo



\### User Interface

\- \*\*ImGui Configuration UI\*\*: User-friendly settings interface with real-time updates

\- \*\*Level-Based Filtering\*\*: Shows abilities based on appropriate job level (main or sub)

\- \*\*Spell/Song Filtering\*\*: Automatically disables unlearned magic/songs based on job level and spell availability

\- \*\*Main/Sub Job Display\*\*: Shows combined job name (e.g., "Dark Knight/Warrior")

\- \*\*Per-Ability Toggles\*\*: Enable/disable individual abilities

\- \*\*Group-Based Mutual Exclusivity\*\*: Any ability with `group` field enforces mutual exclusivity

\- \*\*Threshold Configuration\*\*: Customize HP/TP/MP thresholds

\- \*\*Debug Logging\*\*: Detailed logging for troubleshooting

\- \*\*Auto-Refresh\*\*: UI updates automatically when jobs or levels change



\## Supported Jobs



Currently implemented:

\- \*\*Summoner\*\* (SMN) 

&nbsp; - Blood Pacts: Healing Ruby, Healing Ruby II, Shining Ruby

&nbsp; - Pet management and resource tracking

&nbsp; 

\- \*\*Dancer\*\* (DNC)

&nbsp; - Waltzes: Curing Waltz I/II/III, Divine Waltz, Healing Waltz

&nbsp; - Sambas: Drain Samba I/II/III, Aspir Samba I/II, Haste Samba (combat-only, mutually exclusive via `group = 'samba'`)

&nbsp; - Jigs: Spectral Jig (idle-only, intelligent sneak/invis checking)

&nbsp; - Sleep removal via waltz

&nbsp; - Steps: Quickstep, Box Step, Stutter Step, Feather Step (with packet-based tracking and intelligent balancing)



\- \*\*White Mage\*\* (WHM)

&nbsp; - Single-target healing: Cure I-V, Curaga II (emergency single-target)

&nbsp; - AOE healing: Curaga I-IV

&nbsp; - Debuff removal: Erase, Viruna, Paralyna, Blindna, Silena, Poisona, Cursna

&nbsp; - Buff maintenance: Protectra III-V, Shellra III-V, Protect IV-V, Shell IV-V, Haste, Regen I-IV, Aquaveil, Blink, Stoneskin

&nbsp; - Sleep removal via cure spells



\- \*\*Monk\*\* (MNK)

&nbsp; - Self-healing: Chakra

&nbsp; - Debuff removal: Chakra (removes Poison/Blind)

&nbsp; - Buff maintenance: Boost, Dodge, Focus, Counterstance, Footwork, Mantra, Formless Strikes, Impetus

&nbsp; - Attack abilities: Chi Blast



\- \*\*Warrior\*\* (WAR)

&nbsp; - Tank abilities: Provoke (automatic enmity management)

&nbsp; - Buff maintenance: Berserk, Defender, Warcry, Aggressor, Retaliation, Warriors Charge, Blood Rage

&nbsp; - Debuff abilities: Tomahawk



\- \*\*Dark Knight\*\* (DRK)

&nbsp; - Self-healing: Drain, Drain II (combat-only)

&nbsp; - Counter abilities: Weapon Bash, Stun spell (automatic enemy ability interruption)

&nbsp; - Buff maintenance: Last Resort, Souleater, Arcane Circle, Dread Spikes, Diabolic Eye, Nether Void, Scarlet Delirium (all combat-only)

&nbsp; - Debuff abilities: Bio, Bio II, Poison, Poison II (DoTs with `group = 'bio\_dia'`)



\- \*\*Black Mage\*\* (BLM)

&nbsp; - Magic Burst: Automatic elemental nuking on skillchain detection

&nbsp; - Elemental spells: Fire I-VI, Blizzard I-VI, Thunder I-VI, Water I-VI, Aero I-VI, Stone I-VI

&nbsp; - Ancient Magic: Flare I-II, Freeze I-II, Tornado I-II, Quake I-II, Burst I-II, Flood I-II

&nbsp; - Elemental DoT debuffs: Burn, Frost, Choke, Rasp, Shock, Drown

&nbsp; - Self-healing: Drain (combat-only)

&nbsp; - Buff maintenance: Elemental Seal, Manawall, Mana Shield

&nbsp; - Counter abilities: Stun spell (automatic enemy ability interruption)



\- \*\*Paladin\*\* (PLD)

&nbsp; - Single-target healing: Cure I-IV

&nbsp; - Party buffs: Protect I-IV, Shell I-III

&nbsp; - Light-based nukes: Banish, Banish II, Banishga, Holy

&nbsp; - Tank abilities: Flash (AOE blind/enmity)

&nbsp; - Counter abilities: Shield Bash (melee-range interrupt)

&nbsp; - Defensive buffs: Sentinel, Rampart, Fealty, Majesty, Holy Circle, Reprisal

&nbsp; - Support abilities: Cover (protect party member), Chivalry (MP recovery)

&nbsp; - Priority: Tank → Counter → Heal → Buff → Nuke



\- \*\*Red Mage\*\* (RDM)

&nbsp; - Hybrid magic system combining white, black, and enfeebling magic

&nbsp; - Single-target healing: Cure I-IV (HP deficit-based selection)

&nbsp; - Magic burst nuking: Elemental spells Fire-Thunder I-III (tier-restricted)

&nbsp; - Enfeebling magic: Slow I-II, Paralyze I-II, Silence, Bind, Blind, Dia I-II

&nbsp; - Enhancing buffs: Refresh I-II, Haste, Phalanx, Stoneskin, Aquaveil, Blink, Protect I-III, Shell I-III

&nbsp; - Debuff removal: Erase, Viruna, Paralyna, Silena, Blindna, Poisona

&nbsp; - Special abilities: Convert (HP/MP swap for emergency MP recovery)



\- \*\*Dragoon\*\* (DRG)

&nbsp; - Pet management: Call Wyvern (summon wyvern companion)

&nbsp; - Pet healing: Spirit Link (transfer HP to heal wyvern when below 50%)

&nbsp; - Jump abilities: Jump, High Jump (damage and enmity generation)

&nbsp; - Buff maintenance: Ancient Circle (dragon killer), Spirit Bond (wyvern stat boost), Deep Breathing (wyvern breath bonus), Fly High (wyvern ability reset)

&nbsp; - Debuff abilities: Angon (defense down debuff)

&nbsp; - Priority: Pet Healing → Attack → Debuff → Buff → Pet Summoning



\- \*\*Ranger\*\* (RNG)

&nbsp; - Buff maintenance: Velocity Shot (ranged attack speed), Barrage (multi-shot), Camouflage (enmity reduction), Scavenge (ammo recovery), Sharpshot (accuracy boost)

&nbsp; - Attack abilities: Flashy Shot (enmity generation), Stealth Shot (enmity reduction), Bounty Shot (damage), Shadowbind (bind effect)

&nbsp; - Priority: Attack → Buff



\- \*\*Samurai\*\* (SAM)

&nbsp; - Buff maintenance: Hasso (attack speed/accuracy boost), Seigan (counter stance) - mutually exclusive via `group = 'stance'`

&nbsp; - Stun abilities: Blade Bash (melee-range interrupt), Third Eye (anticipate attack)

&nbsp; - Resource recovery: Meditate (TP recovery when below 300 TP)

&nbsp; - Priority: Stun → Recover → Buff



\- \*\*Bard\*\* (BRD)

&nbsp; - Songs: Ballad, Minne, Paeon, Madrigal, Prelude, March, Scherzo, Nocturne, Finale, Lullaby, Elegy, Requiem, Threnody, Etude, Carol

&nbsp; - Buff maintenance and debuff abilities with automatic disabling of unlearned songs in UI



\- \*\*Beastmaster\*\* (BST)

&nbsp; - Pet management: Call Beast, Bestial Loyalty

&nbsp; - Pet healing: Reward (MP recovery for pet)

&nbsp; - Buff maintenance: Killer Instinct, Beast Affinity, Familiar

&nbsp; - Attack abilities: Sic (command pet to attack)



\- \*\*Blue Mage\*\* (BLU) - Very Limited

&nbsp; - Basic spell support with automatic disabling of unlearned spells in UI

&nbsp; - Limited to available learned spells for healing, buffing, and debuffing



\- \*\*Corsair\*\* (COR)

&nbsp; - Roll Automation: Intelligent Phantom Roll and Double-Up management with 24 available rolls

&nbsp;   - Configurable Roll 1 and Roll 2 selection via dropdown menus

&nbsp;   - Automatic Double-Up until lucky number or hit threshold (5-9, configurable)

&nbsp;   - Real-time roll total tracking and display in UI (color-coded by status)

&nbsp;   - Lucky/unlucky numbers shown for each roll (e.g., Warlock's Roll: 4/8)

&nbsp;   - Bust detection and automatic adjustment to single roll

&nbsp;   - State reset when changing roll selections

&nbsp; - Quick Draw: Fire Shot, Water Shot, Thunder Shot, Earth Shot, Wind Shot, Ice Shot (all require ammo)

&nbsp; - Ranged Attack automation with ammo validation

&nbsp; - Buff maintenance: Random Deal



\- \*\*Geomancer\*\* (GEO)

&nbsp; - Geomancy: Indi- spells for self-buffs, Geo- spells for party buffs

&nbsp; - Automatic Geo Full Circle execution when pet luopan exceeds distance threshold

&nbsp; - All spells include buff\_id fields for proper status effect tracking

&nbsp; - Geo spells target self (<me>) for correct luopan placement

&nbsp; - Buff maintenance with automatic disabling of unlearned spells in UI



\- \*\*Ninja\*\* (NIN)

&nbsp; - Buff maintenance: Utsusemi (shadow images)

&nbsp; - Attack abilities: Mijin Gakure (kamikaze)

&nbsp; - Debuff abilities: Kurayami, Hojo, Dokumori, Jubaku, Aisha



\- \*\*Puppetmaster\*\* (PUP)

&nbsp; - Pet management: Activate, Deactivate

&nbsp; - Pet abilities: Maneuver, Overdrive

&nbsp; - Buff maintenance: Overload, Repair, Maintenance

&nbsp; - Attack abilities: Deploy, Retrieve



\- \*\*Runefencer\*\* (RUN)

&nbsp; - Rune effects: Ignis, Gelus, Flabra, Tellus, Sulpor, Unda, Lux, Tenebrae

&nbsp; - Buff maintenance: Vallation, Pflug, Gambit

&nbsp; - Defensive abilities with rune-based protection



\- \*\*Scholar\*\* (SCH)

&nbsp; - Light Arts/Dark Arts: Addendum White/Black for enhanced magic

&nbsp; - Stratagems: Penury, Celerity, Rapture, Accession, Altruism, Focalization, Tranquility, Equanimity, Enlightenment

&nbsp; - Spells: Helix, Storm, Klimaform

&nbsp; - Buff maintenance and magic abilities with automatic disabling of unlearned spells in UI



\- \*\*Thief\*\* (THF)

&nbsp; - Attack abilities: Steal, Mug, Despoil

&nbsp; - Buff maintenance: Bully, Assassin's Charge, Feint

&nbsp; - Enmity control: Accomplice, Collaborator (currently commented out)



\## Installation



1\. Place the entire `Sidekick` folder in your Ashita `addons` directory

2\. Load the addon in-game: `/addon load sidekick`

3\. Configure settings: `/sidekick config`

4\. Start automation: `/sidekick start`



\## Architecture



```

Sidekick/

├── Sidekick.lua              # Main addon file, event handlers, packet routing

├── lib/

│   ├── core/

│   │   ├── common.lua        # Shared utilities, party/entity management

│   │   ├── automation.lua    # Action selection engine, priority handling

│   │   └── resource.lua      # Resource/cooldown tracking (MP/TP)

│   ├── actions/

│   │   ├── heal.lua          # Single-target healing logic

│   │   ├── heal\_pet.lua      # Pet healing logic

│   │   ├── heal\_aoe.lua      # AOE healing logic

│   │   ├── wake.lua          # Sleep removal logic

│   │   ├── debuff\_removal.lua # Debuff removal logic

│   │   ├── recover.lua       # MP/TP recovery logic

│   │   ├── buff.lua          # Buff maintenance logic

│   │   ├── debuff.lua        # Debuff application with packet tracking

│   │   ├── attack.lua        # Offensive ability logic

│   │   ├── tank.lua          # Enmity/threat management logic

│   │   ├── counter.lua       # Enemy ability interruption logic

│   │   ├── nuke.lua          # Magic burst nuking logic

│   │   ├── weaponskill.lua   # Weaponskill automation logic

│   │   ├── go.lua            # Pet attack on engagement logic

│   │   ├── geo.lua           # Geo Full Circle distance management logic

│   │   └── roll.lua          # Corsair roll automation with Double-Up logic

│   ├── jobs/

│   │   ├── bard.lua           # Bard ability definitions

│   │   ├── beastmaster.lua    # Beastmaster ability definitions

│   │   ├── black\_mage.lua    # Black Mage ability definitions

│   │   ├── blue\_mage.lua     # Blue Mage ability definitions

│   │   ├── corsair.lua       # Corsair ability definitions

│   │   ├── dancer.lua        # Dancer ability definitions

│   │   ├── dark\_knight.lua   # Dark Knight ability definitions

│   │   ├── dragoon.lua       # Dragoon ability definitions

│   │   ├── geomancer.lua     # Geomancer ability definitions

│   │   ├── monk.lua          # Monk ability definitions

│   │   ├── ninja.lua         # Ninja ability definitions

│   │   ├── paladin.lua       # Paladin ability definitions

│   │   ├── puppetmaster.lua  # Puppetmaster ability definitions

│   │   ├── ranger.lua        # Ranger ability definitions

│   │   ├── red\_mage.lua      # Red Mage ability definitions

│   │   ├── rune\_fencer.lua   # Rune Fencer ability definitions

│   │   ├── samurai.lua       # Samurai ability definitions

│   │   ├── scholar.lua       # Scholar ability definitions

│   │   ├── summoner.lua      # Summoner ability definitions

│   │   ├── thief.lua         # Thief ability definitions

│   │   ├── warrior.lua       # Warrior ability definitions

│   │   └── white\_mage.lua    # White Mage ability definitions

│   └── config\_ui.lua         # ImGui configuration interface

```



\### Key Features by Module



\*\*wake.lua\*\*:

\- Direct buff reading via `get\_party\_buffs()` for reliable sleep detection (buff ID 2 or 19)

\- Smart ability selection: 1 sleeping → single-target, 2+ sleeping → AOE

\- Matches BackupDancer's proven approach

\- Focus target priority for single-target wakes



\*\*tank.lua\*\*:

\- Monitors target's current target to detect aggro status

\- Automatically uses enmity abilities when player loses mob's attention

\- Only executes when engaged in combat

\- Leverages attack.lua validation for range, cooldown, and resource checks

\- `is\_target\_claiming\_player()` checks if mob is focused on player

\- Intelligent threat management without manual intervention



\*\*debuff.lua\*\*:

\- Packet sniffing for real-time debuff level tracking (0x028/0x029 packets)

\- Dynamic effect\_id to action\_id mapping from job definitions

\- Intelligent step balancing (prioritizes lower stack counts)

\- Automatic expiration detection via message packets

\- Supports both stacking and non-stacking debuffs



\*\*counter.lua\*\*:

\- Real-time enemy ability detection via packet analysis (0x028 action packets)

\- Detects action\_id 0x58DC (22748) - enemy ability "ready/start" animation

\- Automatic validation: target matching, enemy spawn flags, combat state

\- Priority-based counter ability selection (abilities before spells)

\- Instant command execution (no throttle delay for time-critical interrupts)

\- Only active when automation is enabled and player is engaged

\- Event-driven system (no polling overhead)



\*\*nuke.lua\*\*:

\- Skillchain property detection from Additional Effect field in action packets (0x028)

\- Parses all 16 skillchain properties via SkillPropNames mapping

\- Element mapping system: each property maps to 1-4 valid magic burst elements

\- Smart spell selection: filters by element, level requirement, MP cost, disabled settings

\- Tier-based prioritization: selects highest tier spell available for the skillchain

\- 8-second magic burst window matches standard FFXI timing

\- Alliance-aware: responds to skillchains from party and alliance members

\- One-shot per skillchain: automatically clears state after casting

\- Uses attack.lua command building for consistency with other actions

\- Respects config\_ui disabled spell settings (e.g., disabled\_Freeze\_II)



\*\*weaponskill.lua\*\*:

\- User-configurable weaponskill name via text input field in Config UI

\- Adjustable TP threshold (1000-3000) with slider control

\- Monitors current TP using `common.get\_player\_tp()`

\- Requires being engaged with valid target (no explicit range check - assumes TP generation = in range)

\- Command format: `/ws "WeaponskillName" <t>` (with quotes for multi-word names)

\- No recast checking or validation (trusts user input)

\- Global setting saved per-job in settings file

\- Debug output shows TP level and threshold when executing



\*\*go.lua\*\*:

\- Tracks last target index to detect new enemy engagements

\- Automatically sends pet to attack when player switches targets

\- Requires having an active pet (`common.has\_pet()`)

\- One-shot per target (won't spam commands for same enemy)

\- Reuses attack.lua validation logic for range, combat state, and resource checks

\- Creates temporary job definition with go abilities in attack slot

\- Respects per-ability disable settings from Config UI

\- Only executes when engaged and automation enabled



\*\*geo.lua\*\*:

\- Monitors pet luopan distance in real-time using `common.get\_pet\_distance()`

\- Configurable distance threshold (7-30 yalms, default 10) via slider control

\- Automatically executes Full Circle when pet exceeds distance threshold

\- Requires active pet and geo abilities enabled in configuration

\- Uses `resource.is\_ability\_ready()` for cooldown checking on Full Circle

\- Integrated into priority order for jobs with geo abilities

\- Prevents pet from wandering too far during combat



\*\*roll.lua\*\*:

\- Automatic Corsair Phantom Roll and Double-Up management system

\- Packet-based roll total tracking (0x028 action packets, category 0x23)

\- Extracts roll value from packet byte offset 0x0F (value / 8)

\- State machine tracks: roll1/roll2 totals, expecting\_double\_up, is\_stable, last\_roll\_action

\- Smart Double-Up logic: continues until lucky number OR hit threshold OR total ≥ 11

\- Lucky number detection: immediately marks roll stable and stops doubling

\- Configurable hit threshold (5-9, default 5): balances risk vs reward

\- Cooldown management: 1 second after initial roll, 6 seconds between double-ups

\- Intelligent packet attribution: uses last\_roll\_action to assign packets to correct roll

\- Bust detection: automatically switches to 1 roll capacity when bust buff detected

\- Roll capacity check: 2 rolls (normal), 1 roll (busted)

\- Config UI integration: dropdown selection, threshold slider, real-time total display

\- Color-coded roll display: green (lucky), yellow (threshold reached), white (normal)

\- Automatic state reset when roll selection changes

\- Priority positioning: executes before buffs and attacks

\- Only active when engaged in combat with roll automation enabled



\*\*recover.lua\*\*:

\- Automatic MP and TP recovery based on configurable thresholds

\- MP recovery: Monitors `GetMemberMPPercent(0)` and triggers when below `recover\_mp\_threshold`

\- TP recovery: Monitors `GetMemberTP(0)` and triggers when below `recover\_tp\_threshold`

\- Prioritizes MP recovery over TP recovery when both are needed

\- Uses `resource.has\_resource()` and `resource.is\_ability\_ready()` for validation

\- Respects `combat\_only` and `idle\_only` flags for situational abilities

\- Per-ability enable/disable toggles in configuration UI

\- Jobs with support: Red Mage (Convert at 30% MP), Samurai (Meditate at 300 TP)



\*\*common.lua\*\*:

\- Party member validation and range checking

\- Entity manager helpers with error handling

\- Buff/debuff status checking via direct memory reading

\- Target acquisition and validation

\- Enhanced player info functions:

&nbsp; - `get\_player\_level()` returns main job level and subjob level

&nbsp; - `get\_player\_job()` returns main job ID and subjob ID



\## Commands



\- `/sidekick start` or `/sk start` - Start automation

\- `/sidekick stop` or `/sk stop` - Stop automation

\- `/sidekick toggle` or `/sk toggle` - Toggle automation on/off

\- `/sidekick config` or `/sk config` - Show/hide configuration UI

\- `/sidekick focus <index>` - Set focus target (0-5, party member index)

\- `/sidekick focus clear` - Clear focus target

\- `/sidekick debug` or `/sk debug` - Toggle debug mode

\- `/sidekick status` or `/sk status` - Show current status and settings

\- `/sidekick help` or `/sk help` - Show command help



\*\*Note\*\*: Attack Range is configured via the Config UI (Off/Melee/Ranged)



\*\*Note\*\*: `/sk` is a shorthand alias for `/sidekick`



\## Usage



\### Basic Setup



1\. Load the addon: `/addon load sidekick`

2\. Open config: `/sidekick config`

3\. Enable desired features (healing, buffs, etc.)

4\. Adjust thresholds as needed

5\. Start automation: `/sidekick start`



\### Focus Target



Focus targets are prioritized for healing and debuff removal:



```

/sidekick focus 1  # Set party member 1 as focus

/sidekick focus clear  # Clear focus

```



Party indices:

\- 0 = You

\- 1-5 = Other party members



\### Attack Range Management



Control combat distance automatically:



1\. Open config UI: `/sidekick config`

2\. Select "Attack Range" dropdown:

&nbsp;  - \*\*Off\*\*: No range management (default)

&nbsp;  - \*\*Melee\*\*: Maintains 3 yalm distance from target

&nbsp;  - \*\*Ranged\*\*: Maintains 15 yalm distance from target



How it works:

\- When \*\*engaged\*\* and \*\*within range\*\*: Sends `/ms follow off` to stop movement

\- When \*\*engaged\*\* and \*\*beyond range\*\*: Sends `/ms follow on` to chase target

\- When \*\*disengaged\*\*: Sends `/ms follow on` to return to party formation

\- Prevents command spam with intelligent state tracking



\*\*Requirements\*\*: Multisend addon must be loaded and configured



\### Debug Mode



Enable debug logging to troubleshoot issues:



```

/sidekick debug

```



This will show detailed information about ability selection, cooldowns, and action execution.



\## Adding New Jobs



To add support for a new job, create a job definition file in `lib/jobs/`:



\### Example: White Mage (jobs/white\_mage.lua)



```lua

local common = require('lib.core.common')



return {

&nbsp;   job\_id = 3,  -- White Mage

&nbsp;   job\_name = 'White Mage',

&nbsp;   resource\_type = 'mp',

&nbsp;   

&nbsp;   abilities = {

&nbsp;       -- Single-target healing

&nbsp;       heal = {

&nbsp;           {

&nbsp;               name = 'Cure V',

&nbsp;               level = 61,

&nbsp;               cost = 135,

&nbsp;               value = 700,  -- HP restored (used for deficit-based selection)

&nbsp;               id = 0,

&nbsp;               command = function(party\_index)

&nbsp;                   return '/ma "Cure V" <p' .. party\_index .. '>'

&nbsp;               end,

&nbsp;               wakes = true,

&nbsp;           },

&nbsp;           {

&nbsp;               name = 'Cure IV',

&nbsp;               level = 48,

&nbsp;               cost = 88,

&nbsp;               value = 400,  -- HP restored

&nbsp;               id = 0,

&nbsp;               command = function(party\_index)

&nbsp;                   return '/ma "Cure IV" <p' .. party\_index .. '>'

&nbsp;               end,

&nbsp;               wakes = true,

&nbsp;           },

&nbsp;           -- Additional cure spells...

&nbsp;       },

&nbsp;       

&nbsp;       -- AOE healing

&nbsp;       heal\_aoe = {

&nbsp;           {

&nbsp;               name = 'Curaga IV',

&nbsp;               level = 68,

&nbsp;               cost = 260,

&nbsp;               id = 0,

&nbsp;               command = '/ma "Curaga IV" <me>',

&nbsp;               wakes = true,

&nbsp;           },

&nbsp;           {

&nbsp;               name = 'Curaga III',

&nbsp;               level = 51,

&nbsp;               cost = 120,

&nbsp;               id = 0,

&nbsp;               command = '/ma "Curaga III" <me>',

&nbsp;               wakes = true,

&nbsp;           },

&nbsp;           -- Additional curaga spells...

&nbsp;       },

&nbsp;       

&nbsp;       -- Debuff removal

&nbsp;       debuff\_removal = {

&nbsp;           {

&nbsp;               name = 'Erase',

&nbsp;               level = 32,

&nbsp;               cost = 18,

&nbsp;               id = 0,

&nbsp;               command = function(party\_index)

&nbsp;                   return '/ma "Erase" <p' .. party\_index .. '>'

&nbsp;               end,

&nbsp;           },

&nbsp;           {

&nbsp;               name = 'Viruna',

&nbsp;               level = 61,

&nbsp;               cost = 48,

&nbsp;               id = 0,

&nbsp;               command = function(party\_index)

&nbsp;                   return '/ma "Viruna" <p' .. party\_index .. '>'

&nbsp;               end,

&nbsp;           },

&nbsp;           -- Additional removal spells...

&nbsp;       },

&nbsp;       

&nbsp;       -- Buffs

&nbsp;       buff = {

&nbsp;           {

&nbsp;               name = 'Protectra V',

&nbsp;               level = 63,

&nbsp;               cost = 84,

&nbsp;               id = 0,

&nbsp;               command = '/ma "Protectra V" <me>',

&nbsp;               buff\_id = 43,  -- Protect

&nbsp;               combat\_only = false,

&nbsp;           },

&nbsp;           {

&nbsp;               name = 'Shellra V',

&nbsp;               level = 68,

&nbsp;               cost = 93,

&nbsp;               id = 0,

&nbsp;               command = '/ma "Shellra V" <me>',

&nbsp;               buff\_id = 44,  -- Shell

&nbsp;               combat\_only = false,

&nbsp;           },

&nbsp;           {

&nbsp;               name = 'Haste',

&nbsp;               level = 40,

&nbsp;               cost = 40,

&nbsp;               id = 0,

&nbsp;               command = '/ma "Haste" <me>',

&nbsp;               buff\_id = 33,  -- Haste

&nbsp;               combat\_only = true,

&nbsp;           },

&nbsp;           -- Additional buffs...

&nbsp;       },

&nbsp;   },

&nbsp;   

&nbsp;   validators = {},

&nbsp;   

&nbsp;   default\_settings = {

&nbsp;       heal\_enabled = true,

&nbsp;       heal\_threshold = 75,

&nbsp;       heal\_aoe\_enabled = true,

&nbsp;       heal\_aoe\_threshold = 70,

&nbsp;       heal\_aoe\_count\_threshold = 2,

&nbsp;       wake\_enabled = true,

&nbsp;       buff\_enabled = true,

&nbsp;       debuff\_removal\_enabled = true,

&nbsp;   },

&nbsp;   

&nbsp;   priority\_order = {

&nbsp;       'heal\_aoe',

&nbsp;       'heal',

&nbsp;       'debuff\_removal',

&nbsp;       'wake',

&nbsp;       'buff',

&nbsp;   },

}

```



\### Job Definition Fields



\#### Required Fields



\- `job\_id` (number): FFXI job ID

\- `job\_name` (string): Display name for the job

\- `resource\_type` (string): 'mp' or 'tp' for resource checking



\#### Ability Fields



\- `name` (string): Ability display name

\- `level` (number): Required job level to use ability

\- `cost` (number): MP or TP cost

\- `value` (number, optional): HP restored for heal abilities (enables deficit-based selection)

\- `id` (number, optional): Ability/spell ID for cooldown tracking

\- `command` (string or function): Command to execute the ability

\- `range` (number, optional): Ability range in yalms (default: 21)

\- `wakes` (boolean, optional): Whether ability removes sleep

\- `buff\_id` (number, optional): Buff ID for buff maintenance

\- `combat\_only` (boolean, optional): Only use ability in combat

\- `idle\_only` (boolean, optional): Only use ability while idle

\- `self\_only` (boolean, optional): Ability only targets self

\- `requires\_pet` (boolean, optional): Requires active pet

\- `group` (string, optional): Group name for mutual exclusivity (e.g., 'samba', 'bio\_dia')

\- `job\_name` (string): Display name

\- `resource\_type` (string): `'mp'` or `'tp'`

\- `abilities` (table): Ability definitions by category



\#### Mutual Exclusivity Groups



The `group` field enables mutual exclusivity between abilities. When you enable one ability in a group, all others in the same group are automatically disabled. This is useful for:



\- \*\*Sambas\*\* (`group = 'samba'`): Only one Samba can be active at a time

\- \*\*Bio/Dia\*\* (`group = 'bio\_dia'`): Only one Bio or Dia variant active

\- \*\*Any custom grouping\*\*: Define your own groups as needed



Example:

```lua

{

&nbsp;   name = 'Drain Samba III',

&nbsp;   level = 65,

&nbsp;   cost = 400,

&nbsp;   id = 216,

&nbsp;   command = '/ja "Drain Samba III" <me>',

&nbsp;   buff\_id = 368,

&nbsp;   combat\_only = true,

&nbsp;   group = 'samba',  -- Mutually exclusive with other sambas

},

```



\#### Ability Categories



\- `heal`: Single-target healing

\- `heal\_aoe`: AOE/party healing

\- `wake`: Sleep removal (or mark heal abilities with `wakes = true`)

\- `debuff\_removal`: Erase/cleanse abilities

\- `buff`: Self/party buffs

\- `debuff`: Debuffs to apply to enemies

\- `attack`: Offensive abilities that require a target

\- `tank`: Enmity/threat management abilities



\#### Ability Fields



Each ability definition can have:



\*\*Required:\*\*

\- `name` (string): Ability name

\- `level` (number): Required level to use

\- `cost` (number): MP/TP cost

\- `command` (string or function): Command to execute

&nbsp; - If function: receives party\_index or target\_index as parameter

&nbsp; - If string: static command string



\*\*Optional:\*\*

\- `id` (number): Recast ID for cooldown tracking

\- `buff\_id` (number): Buff ID to check for uptime (for buff maintenance)

\- `combat\_only` (boolean): Only use while engaged in combat

\- `idle\_only` (boolean): Only use when idle/not engaged

\- `requires\_pet` (boolean): Requires pet to be active

\- `wakes` (boolean): Can wake from sleep

\- `check\_buff` (function): Custom function to check if buff is active



\*\*For Stacking Debuffs (Steps):\*\*

\- `max\_stacks` (number): Maximum debuff stack level (e.g., 5 for Dancer steps)

\- `track\_stacks` (boolean): Enable packet-based stack tracking

\- `action\_id` (number): Action ID for packet tracking (e.g., 617 for Quickstep)

\- `effect\_id` (number): Effect/status ID for expiration detection (e.g., 386 for Quickstep debuff)



\#### Optional Fields



\- `validators` (table): Job-specific validation functions

\- `default\_settings` (table): Default UI settings

\- `priority\_order` (table): Action priority order (overrides default)



\### Registering the Job



Update the `job\_map` in `Sidekick.lua`:



```lua

local job\_map = {

&nbsp;   \[15] = 'summoner',

&nbsp;   \[19] = 'dancer',

&nbsp;   \[3] = 'white\_mage',  -- White Mage

}

```



\## How It Works



\### Action Selection Flow



1\. \*\*Check Conditions\*\*: Is automation enabled? In event? Has resources?

2\. \*\*Priority Order\*\*: Iterate through action types by priority

3\. \*\*Execute Module\*\*: Each action module checks conditions and selects best ability

4\. \*\*Resource Check\*\*: Verify MP/TP and cooldown availability

5\. \*\*Execute Command\*\*: Send command to game

6\. \*\*Throttle\*\*: Wait 1 second before next action



\### Example: Healing Flow



1\. Check if `heal\_enabled` is true

2\. Get available heal abilities for current level

3\. Check party HP status

4\. If focus target needs heal, prioritize them

5\. Otherwise, heal lowest HP party member

6\. Select strongest affordable heal based on HP deficit

7\. Check cooldown and resources

8\. Build and execute command



\### Packet Tracking (Dancer Steps)



For stacking debuffs like Dancer steps, Sidekick uses real-time packet sniffing for accurate tracking:



\*\*How it works:\*\*

\- \*\*Packet 0x028 (Action)\*\*: Detects step application and current level

&nbsp; - Category 35 identifies step abilities

&nbsp; - Byte parsing extracts step type (Quickstep/Box Step)

&nbsp; - Level byte indicates current stack count (1-5)

\- \*\*Packet 0x029 (Message)\*\*: Detects step expiration

&nbsp; - Monitors debuff expiration message IDs

&nbsp; - Uses effect\_id to identify which step expired

\- \*\*Dynamic Mapping\*\*: effect\_id → action\_id built from job definition

\- \*\*Intelligent Balancing\*\*: Automatically alternates steps to balance stack counts

\- \*\*Throttling\*\*: 2-second minimum between step detections to avoid duplicates



\*\*Step Logic:\*\*

1\. Track current level per step per target

2\. Stop applying when step reaches max stacks (5)

3\. Prioritize the step with lower stack count for balancing

4\. Clear tracking when step expires or target changes

5\. Respect shared recast timer (6 seconds between any steps)



\## Configuration



Settings are saved per job in JSON format:

\- `settings\_summoner.json`

\- `settings\_dancer.json`

\- `settings\_white\_mage.json`

\- etc.



\### Common Settings



\- `automation\_enabled` (boolean): Automation on/off

\- `attack\_range` (string): Range management mode ('Off', 'Melee', 'Ranged')

\- `focus\_enabled` (boolean): Use focus target

\- `focus\_target\_index` (number): Focus target index

\- `heal\_enabled` (boolean): Enable healing

\- `heal\_threshold` (number): HP% threshold for healing

\- `heal\_aoe\_enabled` (boolean): Enable AOE healing

\- `heal\_aoe\_threshold` (number): HP% threshold for AOE

\- `heal\_aoe\_count\_threshold` (number): Min members needing heal for AOE

\- `wake\_enabled` (boolean): Enable sleep removal

\- `buff\_enabled` (boolean): Enable buff maintenance

\- `debuff\_removal\_enabled` (boolean): Enable debuff removal

\- `debuff\_enabled` (boolean): Enable debuff application

\- `attack\_enabled` (boolean): Enable attack abilities

\- `tank\_enabled` (boolean): Enable tank/enmity management



\## Design Principles



\### 1. Maximize Code Reuse

\- Shared logic in core modules

\- Action modules handle generic ability categories

\- Job-specific logic only in job definitions



\### 2. Configuration Over Code

\- No hard-coded ability names in core logic

\- Jobs defined by configuration data

\- Easy to add new jobs without changing core



\### 3. Preserve Working Logic

\- Timing, cooldowns, and safety checks from original implementations

\- Priority-based target selection

\- Range checking and validation



\### 4. Maintainability

\- Clear separation of concerns

\- Self-documenting structure

\- Error handling with pcall

\- Debug logging throughout



\## Troubleshooting



\### Automation Not Working



1\. Check if automation is enabled: `/sidekick status`

2\. Enable debug mode: `/sidekick debug`

3\. Check if your job is supported: `/sidekick reload`

4\. Verify settings in config UI: `/sidekick config`



\### Abilities Not Triggering



1\. Check level requirements in job definition

2\. Verify resource availability (MP/TP)

3\. Check cooldowns with debug mode

4\. Ensure thresholds are set appropriately



\### Focus Target Not Working



1\. Verify party member is active: `/sidekick focus <index>`

2\. Check if member is in same zone

3\. Enable focus in config UI

4\. Use debug mode to see target selection



\### Steps Not Tracking (Dancer)



1\. Ensure debuff module loaded correctly

2\. Check packet handler registration

3\. Enable debug mode to see packet data

4\. Verify target is valid and engaged



\## Performance



\- \*\*Command Throttle\*\*: 1 second between actions (configurable)

\- \*\*Event Blocking\*\*: No actions during cutscenes/events

\- \*\*Range Checking\*\*: Validates targets within ability range

\- \*\*Resource Validation\*\*: Checks MP/TP before attempting abilities

\- \*\*Cooldown Tracking\*\*: Prevents spamming abilities on cooldown



\## Known Limitations



\- Only supports party (not alliance)

\- Range checking uses fixed 21 yalm range

\- Buff tracking requires memory pointer access

\- Step tracking requires packet sniffing (Dancer-specific)

\- Some buff IDs may need adjustment per server



\## Contributing



To contribute new job definitions:



1\. Create job definition file in `lib/jobs/`

2\. Test thoroughly in-game

3\. Document any special requirements

4\. Submit pull request with job map update



\## Credits



Based on automation patterns from:

\- \*\*CyberSkunk\*\* - Summoner automation

\- \*\*BackupDancer\*\* - Dancer automation



Refactored into generic framework for extensibility and maintainability.



\## License



See LICENSE file for details.

