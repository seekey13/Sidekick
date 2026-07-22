# **Sidekick** - Support Job Automation Framework

A focused, support-oriented addon for Ashita v4 that automates healing, buffing, debuff removal, resource recovery, and reviving for most jobs in Final Fantasy XI.  Tuned specifically for [CatsEyeXI private server](https://www.catseyexi.com/).

# Quick Start Guide
<img width="1453" height="917" alt="image" src="https://github.com/user-attachments/assets/d109ad58-1d66-4a5b-9cbd-bc8566df0464" />

### Header
<img width="1447" height="546" alt="image" src="https://github.com/user-attachments/assets/3b34103b-819a-4e46-a07a-bccedfb23e09" />

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

**Sidekick is a support-only addon.** It provides healing, buffing, debuff removal, and basic pet management. It does **NOT** automate:
- Combat/attacking
- Tanking/enmity management
- Magic bursting/nuking
- Weaponskills
- Combat movement/positioning
- Full job automation

The one exception is **opt-in leader following** (off by default): with **Follow** enabled, Sidekick will `/follow` a chosen party member or tracked target when they walk beyond a set distance. It never moves your character unless you turn this on.

## Latest Updates
### [2.6.0] - 2026-07-20

### Added
- **UI Opacity**: a new slider in `/sk panel` (1-100, 100 = fully opaque) fades the `/sk` config window so it sits quietly over the game. Dropdown menus (while expanded), right-click menus, and tooltips stay fully opaque so they're always readable at any opacity. Thanks to **Fallen** for the feature idea.

- **Corsair**: New job — *rolls only*. Pick two **Phantom Rolls** in the new **Rolls** section and Sidekick keeps them up, using **Double-Up** on each according to a **Risk Tier** (Lowest / Medium / Highest) built on the roll's lucky and unlucky numbers. It never doubles at 11, since 12 busts, uses **Snake Eye** for guaranteed finishes and **Fold** the moment you Bust, and while **Bust** is up it holds the second roll back until the slot frees. Rolls fire in and out of combat. Quick Draw, Ranged Attack, and Random Deal are deliberately not automated — Sidekick stays support-only.

- **Follow a tracked target**: the **Follow Target** dropdown now lists your session tracked targets alongside party members, so you can follow — and watch the Resting distance against — someone outside your party.

### Changed
- **Geomancer Blaze of Glory is now a Geo precast**: it boosts the luopan your *next* Geo spell puts down, so Sidekick only uses it when no luopan is out and a Geo spell is actually about to be cast (and you can afford it). Its checkbox moved to the **Geo** section next to Full Circle.  
- **Per-tier Combat Only / Idle Only on ungrouped groups**: after you right-click → **Ungroup** a group, each tier now gets its own **Combat Only** / **Idle Only** setting instead of sharing one across the group — so you can run, for example, **Indi-Fury** in combat and **Indi-Refresh** while idle. Grouped (the default) tiers still share a single gate.  Thanks to **Tai** for reporting the bug and feature idea.
- **Combat state no longer flickers between mobs**: on a multi-mob pull there's a brief gap after one mob dies before the next is engaged where there's no battle target. Sidekick now stays "in combat" for a few seconds across that gap, so combat-only support keeps covering and idle-only actions don't kick in early.  

### Fixed
- **Scholar MP costs now account for your Arts** — an Arts stance makes the *opposite* school cost 20% more, so a Cure IV in Dark Arts is really 105 MP, not 88. Sidekick was budgeting the cheaper number and getting casts rejected. Costs shown in the UI and used to decide what to cast now match what the server charges, including the cases where the penalty does **not** apply: under **Tabula Rasa**, or when a stratagem like Penury is assigned (a Penury'd Cure IV in Dark Arts is 44 MP, not 53). **Accession** was also charging 3x instead of the 2x it actually costs, which made Sidekick skip cures it could afford, and it was being offered on spells it cannot extend — Raise, Reraise, Haste, Cure V/VI and friends. Those rows no longer show the **S** option for it, so the charge isn't wasted.
- **Geomancer Entrust fired with no MP for the Indi spell** — Entrust (5 minute recast) was used before checking you could pay for the configured Indi spell, wasting it. Both the ability and the follow-up cast are now gated on that MP.  Thanks to **Tai** for reporting the bug.
- **Job-mastery stars and the Geomancer Indi aura no longer vanish while Follow is on** — the packet tweak that keeps `/follow` alive across position syncs was also clearing the byte that carries the master stars and the Indi aura display, so enabling Follow made them disappear. That byte is no longer touched; following works exactly as before. Thanks to **Morwen** for reporting the bug.

### [2.5.0] - 2026-07-17

### Added
- **Rune Fencer Embolden**: An **E** button on every enhancing magic row (Protect, Shell, Regen, the Bar- spells, Refresh, Phalanx…) opens a popup — **Enable** fires **Embolden** just before the spell so its effect is stronger; **Hold for Embolden** skips the spell until Embolden is ready (off by default: the spell still casts unboosted while Embolden is on cooldown). RUN main only.

- **Scholar Enlightenment**: An **E** button on every spell that needs **Addendum: White** (Cursna, Erase, Raise/Raise II, Reraise, Regen…) fires **Enlightenment** first so the spell can be cast while you're in **Dark Arts** — no swapping stances. A simple on/off toggle rather than a popup, and Sidekick always waits for Enlightenment. The button only shows in Dark Arts / Addendum: Black, and the JA is skipped once Addendum: White is up, so it can be left switched on. Level-75 merit, SCH main only.

- **Paladin self-buffs**: PLD picks up its defensive job abilities — **Fealty**, **Rampart**, **Sentinel** and **Holy Circle**, all combat-only — plus **Reprisal** and **Majesty**, which is cast first among the buffs. Thanks to a **Funny group of Sweatlords** for pointing out they were missing.

- **Puppetmaster Role Reversal**: PUP gains **Role Reversal** (level 75 merit) as a second automaton heal, used when **Repair** is on cooldown. It swaps your HP percentage with the automaton's, so it only fires when you're the healthier of the two and the swap would leave you above 25%.

- **AFK Sleep**: Automation now goes to sleep after 10 minutes with no party movement and no combat, and wakes as soon as you move. **On by default**. It's a pause, not a stop: nothing is saved or reset, so `/sk start` survives a sleep cycle untouched. Anyone in your party moving, or the party being in combat, keeps it awake; only **your own** movement wakes it back up. Toggle it and set the timeout (1-60 minutes) in `/sk panel` beside **Debug Mode**, or with `/sidekick afk [on|off|<seconds>]`. Thanks to **Mythicangel** for the idea.

### Changed
- **Buffs cast in a smarter order** — **Composure** now goes up before Red Mage's other self-buffs so they inherit its longer duration; **Sublimation**, the **Geomancer** self-luopans, and **Refresh** are likewise nudged ahead of lower-priority buffs. Every other buff is unaffected. Thanks to **Plush** for the feature idea and code.

- **Fewer actions dropped** — Sidekick now spaces its commands from when an action actually finishes rather than from when it was sent, including actions you take by hand.
- **Interrupts are now recognized** — an interrupt used to read as a brand new cast, leaving Sidekick frozen thinking you were still casting. It now ends the cast, spaces the next action correctly, and shows as `interrupted` in the panel. The stuck-cast safety net is 5 s → 16 s, now only covering a packet that never arrives at all.
- **Panel debug row shows `Action:` instead of `Casting:`** — names the last thing you did (`casting_begin: Cure IV`, `job_ability`, `ws_finish`, `interrupted (casting_begin)`) instead of `true`/`false`. Melee swings aren't shown.

### Fixed
- **Bard Pianissimo wasted on a song that isn't ready** — in **Pianissimo Fast Casting**, Pianissimo went up as soon as a song was due, even if the song was still on cooldown or unaffordable. It now waits until the song can actually be cast.
- **Bard single-target songs raced ahead of area songs** — in **Pianissimo Fast Casting**, if an area (`[A]`) song was briefly on recast, Sidekick sang a single-target song anyway, which the area song then overwrote. The single-target pass now holds until every configured area song is established first.  Thanks to **Sleazy** for reporting the bug.
- **Erase and Healing Waltz skipped Shock and Drown** — the two elemental damage-over-time debuffs were missing from the removable list. Both are now cured alongside Burn, Frost, Choke, and Rasp.  Thanks again to **Sleazy** for reporting the bug.
- **Interrupted casts confused Trust buff tracking** — a buff left pending by an interrupted cast was claimed by the next spell you cast, recording a buff on a Trust that never got it and skipping the recast for its full duration. A buff pending more than 10 seconds is now dropped.
- **Erase tried to cure things it can't** — Erase shared one status list with the pet cleanses (Beastmaster **Reward**, Puppetmaster **Maintenance**), so it kept firing on Poison, Paralysis, Blind, Silence, Disease, Curse, and Plague. Erase and the pet cleanses now carry their own lists.
- **Scholar Addendums only fired at full charges** — **Addendum: White / Black** were checked against the stratagem timer as a normal cooldown. They now check for a spare stratagem charge like the stratagems do.
- **67 wrong spell/ability ids** — affected spells cast the wrong thing or read the wrong cooldown. RDM/RUN Bar- and En- spells (Barstone cast Barfire), WHM Bar-*ra* line and Raise II, SCH Raise II / Reraise II / Sandstorm, BRD Water/Earth Carol swapped, and wrong cooldowns on DNC Divine Waltz II / Spectral Jig, WHM Afflatus Misery, RUN Vivacious Pulse, SCH Addendum: Black.
- **46 wrong MP costs and levels** — Protect/Shell tiers, Regen II-III, En-II spells, Bar-*ra* line, Foil, Auspice, Enlight, Invisible/Sneak/Deodorize. Also DNC Divine Waltz (25), SCH Sublimation (35) / Blink (29), WHM Divine Seal (15).

### [2.4.0] - 2026-07-15

### Added
- **Auto Follow (opt-in leader following)**: New **Auto Follow** section at the top of `/sk` — pick a **Follow Target** and a **Distance**, and Sidekick `/follow`s them when they walk beyond it. Off by default; it's the only non-combat movement the addon does. Healing always takes priority, it keeps working while automation is stopped/paused and in towns, and a packet guard keeps `/follow` from breaking mid-route. A **Multisend Follow** checkbox in `/sk panel` switches to the old Multisend attack-range follow instead (shows **Attack Range**, disables native Follow) so the two never fight. Massive thank you to **[BUN] Shirahime**, whose follow code this is built on.

- **Start button right-click menu**: **Right-click the Start/Stop button** for two new options, **both off by default**. **Load stopped** makes Sidekick come up stopped every time instead of restoring the state you left it in — handy if a reload has ever come back already running. **Stop after zone** stops automation whenever you change zones.  Thanks to **Nobodi** who proposed the idea.

- **Black Mage support**: Self-only automation. Keeps your **Spikes** up (Blaze / Ice / Shock — pick one tier from the dropdown), self-heals with **Drain**, and recovers MP with **Aspir**. Drain and Aspir are cast on your battle target, so they only fire in combat, and Drain is only ever used on your own HP — never as a party cure. Thanks to **Mythicangel**, who reminded me BLM has buffs.

- **Drain / Drain II / Aspir on Dark Knight, Scholar, and Geomancer**: The HP and MP drains now work on every caster job that learns them, not just Black Mage. **Dark Knight** gets Drain / Drain II for self-healing and Aspir for MP (DRK now heals and recovers at all). **Scholar** adds Drain and Aspir alongside its Cures and Sublimation. **Geomancer** adds Drain for self-healing and Aspir alongside Radial Arcana. All are cast on your battle target, so they're combat-only.

- **Nether Void now boosts Drain / Drain II / Aspir**: The Dark Knight **[N]** button used to appear only on the Absorb row — it's now on the Drain, Drain II, and Aspir rows in the heal and recovery sections too. Turn it on and Nether Void fires just before the drain to boost it, with the same **Hold for Nether Void** option as the Absorb spells. DRK-main only, so it won't show up on the other jobs' Drain/Aspir.

- **Geomancer Geo-bt combat-end timer**: New **Timer (seconds)** slider in the **Geo** section (default 5), under **Distance**. When your Geo-bt target dies, Full Circle now waits this long before dismissing the debuff luopan — if you pull again inside that window the luopan is kept and reused, instead of being dismissed and recast on every single pull.  Thanks to **Tai** for sharing his Geo expierence.

- **Damage-Immune Trusts Skipped**: Trusts that can't take damage — **Moogle**, **Sakura**, **Kupofried**, **Star Sibyl**, **Brygid**, **Cornelia** — are no longer targeted by **Heal**, **AOE Heal**, **Debuff Removal**, or **Buff** (they sit at permanent full HP, so there's nothing to cure or buff). Their **P1–P5** buttons in those config sections are grayed and locked, with a *"Trust cannot take any damage"* tooltip.

- **Bard Pianissimo Fast Casting**: New toggle in `/sk panel` (saved per Bard). Area songs are cast with **Pianissimo** up for its faster cast time, then Pianissimo is removed about a second into the cast so the song still goes out as an area song. In this mode Sidekick always waits for Pianissimo before casting an area song. **Requires the Debuff addon by atom0s (`/debuff`).** Thanks to **Sleazy**, who made me aware of the trick.

- **Ninja Cast with 1 Shadow**: New toggle in `/sk panel` (saved per Ninja). Normally Utsusemi won't recast while any shadows remain. With this on, Utsusemi recasts once you're down to your last shadow (still waits at 2+), and clears that last shadow a second into the cast so the fresh set applies. **Requires the Debuff addon by atom0s (`/debuff`).**

- **Prerequisite-buff spells shown grayed**: Spells that need a buff to cast are now grayed in the config UI with a *"Prerequisite buff not active"* tooltip when that buff isn't up, instead of looking freely available. You can still check them ahead of time; automation waits for the buff. When a subjob gives you the same spell without the requirement, it shows normally — but only if your subjob is high enough to cast it.

- **Pick which statuses a remover strips**: Right-click any multi-status debuff remover (Erase, Esuna, Cursna, Viruna, Healing Waltz, Chakra…) and you'll get a **Remove:** list — one checkbox per status it can cure, all on by default. Uncheck a status (say, Poison on Erase) and Sidekick stops treating that status as a reason to cast — it won't fire the remover, or pick that target, just because of a disabled status. Note that when a remover fires on someone with several debuffs, the game still chooses which one it removes, so this controls *when* Sidekick casts, not exactly *what* comes off. Thanks to **Dasaikuru [DS]** for the feature recommendation.

### Changed
- **No abilities fire while moving**: Sidekick now blocks all player actions while the moving, not just spell casts, so movement no longer causes interrupted or partially-started support actions.

- **Smoother timing after a spell**: A spell's post-cast lockout is longer than an ability's or item's, so Sidekick now waits a little longer (3.1 s vs 1.1 s) after a spell finishes before sending its next command — instead of firing into the tail of the lockout and having the server eat the command. Non-spell actions are unchanged.

### Fixed
- **Phantom statuses on Trusts and pets**: Sidekick read the wrong field of the game's battle messages, so unrelated events — a synth result, a miss, a skill-up — could stamp a bogus status like Sleep or Terror onto a Trust, tracked target, or pet, sending it chasing a status that was never there. It now only reacts to real status gain/loss messages, and as a bonus tracks status **wear-offs** it used to miss.

- **Unknown statuses no longer stick forever**: A buff or debuff Sidekick didn't recognize on a Trust, tracked target, or pet had no expiry timer, so it lingered in tracking until you zoned. Unknowns now clear after 5 minutes as a backstop (they re-add the moment they're detected again).

- **Debuff removal no longer loops or forgets a resisted cure**: When a na-/Erase is cast on a Trust, tracked target, alliance member, or pet, that status is now held as "being cured" for a few seconds rather than dropped the instant the cast goes out. A resisted or interrupted cure retries the status instead of forgetting it, and Sidekick won't re-cast the same cure while it's still resolving.

- **Red Mage Composure now casts**: Composure's recast id was wrong (it pointed at a different ability's timer), so Sidekick read the wrong cooldown and never fired it. Corrected to Composure's own recast id. Thanks to **Dasaikuru [DS]** for the report.

- **Job default settings scrubbed for errors**: Red Mage's **Convert** never fired on its own — its MP threshold was stored under the wrong name, so the slider you saw wasn't the setting automation actually read. Every job's defaults were checked for the same mistake. Thanks to **Muziko** for finding the original bug.

- **Scholar / Geomancer MP recovery**: Same problem as the Red Mage bug above, found first. Scholar's MP threshold was saved under the wrong name and Geomancer had none at all, so **Sublimation**, **Radial Arcana**, and the new **Aspir** never fired on their own until you dragged the slider. Both now have working defaults.

- **Geo-bt luopan no longer dismissed the instant it lands**: Casting a Geo-bt debuff (like Geo-Frailty) could Full Circle the luopan the moment it appeared, wasting the cast. The luopan takes a moment to register after the spell finishes, and in that gap Sidekick lost track of it and treated the new luopan as someone else's. It now recognizes a freshly-cast luopan as its own. Thanks to **Nobodi** for the report.

- **Geomancer Indi/Geo MP costs corrected**: Many Indi, Geo, and Geo-bt spells had `cost` values from retail rather than CatsEyeXI's `spell_list`, so Sidekick could skip a spell it could actually afford (thought MP was too low) or attempt one it couldn't. All geomancy MP costs now match the server. Thanks to **Tai** for the report.

- **Bard Mazurka songs now work with Pianissimo**: Chocobo Mazurka and Raptor Mazurka were missing their single-target flag, so casting them on `ME` skipped Pianissimo (fired area-only) and the `P1`-`P5` buttons did nothing. Both now behave like every other song.

- **Level-synced Bard songs no longer lock the song slots**: After a level-sync down, higher-level songs you selected stay selected but drop off the config window (you can't sing them), so they couldn't be turned off — and they kept using up your 2 song slots, blocking you from picking songs you *can* sing. Uncastable songs are now auto-deselected (on every target: `A` / `ME` / `P1`-`P5`) so the slots free up. Re-select them once you level back up. Only songs are affected; stratagem / Nether Void / Diffusion picks have no slot limit, so they stay put and switch back on when you level up. Thanks to **Muziko** for the report.

- **`/anon` no longer stops automation**: Sidekick now reads your job directly from the game client instead of the party list, which hides your job while `/anon` is on. Automation now works normally with `/anon` active. Thanks to **Karth** for the report.

- **Haste duration on low-level tracked targets**: Sidekick assumed Haste always lasts 180s, but it wears off sooner on players under level 40. It now scales the tracked Haste timer to the target's level (from the `/check` done when you Track Target); level 40+ is unchanged at 180s. Thanks to **Plush** for pointing out that Haste duration drops below level 40.

### [2.3.1] - 2026-07-13

### Added
- **Dancer Curing Waltz IV**: Dancer's single-target Waltz tier now includes **Curing Waltz IV**, slotting above Curing Waltz III for higher-HP cures.

### [2.3.0] - 2026-07-10

Rename to Sidekick, addon outgrew the old name Medic.  As it now supports a lot more than the healer/support type roles.

Adds **Chakra** to Monk (a self-cure that recovers HP and clears its own Poison / Blindness), four new self-support jobs (**Warrior**, **Dark Knight**, **Ranger**, **Thief**), and full support for **Blue Mage**.

### Added
- **Monk Chakra**: Monk now self-casts **Chakra** to recover HP and to remove its own **Poison** and **Blindness**. Wired as both a self-heal and a self debuff removal (see [Supported Jobs](#supported-jobs)).
- **Warrior / Dark Knight / Ranger / Thief**: Four new self-support jobs (see [Supported Jobs](#supported-jobs)). Warrior self-buffs Berserk, Defender, Warcry, Blood Rage, Aggressor, Retaliation, and Warrior's Charge; Dark Knight self-buffs via job abilities and Dread Spikes plus the ten Absorb spells on the battle target; Ranger self-buffs Sharpshot, Scavenge, Velocity Shot, Unlimited Shot, Flashy/Stealth Shot plus Bounty Shot on the battle target; Thief self-buffs Conspirator, Assassin's Charge, and Feint (combat-only).
- **Blue Mage**: Full mage support (see [Supported Jobs](#supported-jobs)). Blue-magic healing (Pollen self, Wild Carrot / Magic Fruit party), AOE healing (Healing Breeze), and self-buffs; the **Unbridled Learning** JA is popped automatically right before its level-75 spells, and a **Diffusion** (D) button spreads the next blue buff to the party. Blue magic that isn't in your equipped set-spell list is grayed and skipped — Sidekick never equips spells for you.
- **Dark Knight Nether Void (N button)**: An **N** button on the Absorb row fires Nether Void the tick before the selected Absorb to boost it; **Hold for Nether Void** skips the Absorb until Nether Void is ready (off by default — the Absorb still casts without it when Nether Void is on cooldown).

### Fixed
- **Merit Job Abilities Fired Before Unlock**: Automation no longer attempts merit-unlocked JAs (e.g. DRK Diabolic Eye) the player hasn't bought yet; unlearned merit abilities are gated out and grayed with a *Not Learned* tooltip.
- **Unlearned Spells Attempted by Automation**: Automation now drops any spell whose scroll was never learned, matching the UI's existing check (previously it could loop a command error on an unlearned spell).

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
- **Beastmaster Ready Charges**: Ready-move charges are tracked like Scholar stratagems and shown in the `/sk panel` header.
- **Expanded Item-Based Removal**: The item-cure feature grows from 2 items to 9 (Antidote, Eye/Echo Drops, Holy/Hallowed Water, Tincture, Remedy Ointment, Remedy, Panacea), grouped under one collapsing **Item Debuff Removal** header with a master toggle. Only reliably-cured ailments are listed per item (Remedy skips Disease, Panacea skips Amnesia) so it can't loop the stack on something it won't clear.

### Changed
- **Item Removal Matched by ID**: Inventory counts and the `/item` command now key off item ID rather than the English name, so custom-server items (Remedy Ointment, Hallowed Water, Tincture) resolve correctly instead of showing `?`. Items are never used while moving, and the whole section stays hidden until inventory is readable.
- **Cursna Curse List**: Cursna and Holy/Hallowed Water share `common.CURSE_DEBUFFS` (Curse, Doom, Bane) so the curable set is defined once.
- **UI Section Order & Colors**: Status-removal sections now read Sleep → Debuff → Pet Debuff → Item; the ammo-count `(n)` reuses the current-job green when equipped and the automation-stopped red when not.
- **Targeted Cure Before Erase**: Debuff removal now uses a targeted na-spell (Poisona, Paralyna, etc.) before generic Erase, so the exact ailment is stripped first and Erase mops up the rest.
- **Group Esuna (AOE)**: Esuna now fires when 2+ members within 10 yalms (you + party + alliance) share an Esuna-removable ailment, clearing them in one cast; a single affected target uses the cheaper na-spell instead. Pets and Trusts aren't in the AOE.
- **Party Button Tooltips**: Hovering a target button (**ME** / **P1–P5**) now shows that member's character name; on Trust/tracked buttons the reliability caveat is appended below the name.
- **"Not Learned" Tooltip**: Unlearned abilities show a *Not Learned* hover tooltip instead of a `(Not Learned)` label suffix.
- **Debug Scalars Moved**: The Zone / Target / Moving / Casting readout moved from the configuration window to the `/sk panel` header (shown while Debug Mode is on).

### Fixed
- **Removal Spells Looping on Trusts/Alliance/Pet**: After curing a status (e.g. Poisona on a Trust, or a Reward/Maintenance strip on a pet), Sidekick now drops that status from tracking immediately instead of re-casting every tick until it detects the removal.
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
- **Debug Mode Moved**: The Debug Mode checkbox moved from the configuration window to the `/sk panel` header.

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
- **Debug Panel**: New `lib/ui/panel.lua` debug info panel showing party game_state snapshot (toggle with `/sidekick panel`).
- **Status Removal Module**: New combined `lib/actions/status_removal.lua` with `execute_debuff_removal` and `execute_wake` entry points.
- **Dancer Level-75 Abilities**: Added Saber Dance, Fan Dance, No Foot Rise, and Presto to the Dancer job definition.
- **Geomancer Geo Targeting**: `<me>` Geo buff spells now target party members via single-select ME/P1-P5 buttons (like other party buffs), with Full Circle distance measured from the selected Geo target.
- **Geomancer Geo Debuffs**: New `<bt>` Geo debuff spells (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) cast on your battle target. These are combat-only and selected via a dropdown under Enable Geo. In combat the selected debuff takes over the single luopan; Full Circle frees it for Geo buffs once combat ends. A **Timer (seconds)** slider (`geo_bt_timer`, 1-20, default 5) delays that end-of-combat Full Circle so a fresh battle target within the window reuses the luopan instead of recasting on every pull.

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
- **Leader Following** (opt-in, off by default): `/follow` a chosen party member or tracked target when they move beyond a set distance. Healing and every other support action always take priority, and an autorun-cancel packet guard keeps `/follow` alive across the server's position syncs so it doesn't break mid-route. The only non-combat movement Sidekick performs.
- **AFK Sleep** (on by default): Sleeps automation after a configurable period with no party movement and no combat, and wakes on your own movement. A runtime pause, not a stop — nothing is saved or reset, so your settings and automation state survive a sleep cycle.
- **Corsair Rolls**: Keeps two chosen Phantom Rolls up and Double-Ups each one according to a **Risk Tier** (Lowest / Medium / Highest) built on the roll's lucky and unlucky numbers, backing off at 11 so it can't bust. **Snake Eye** is used for guaranteed finishes and **Fold** clears a Bust the moment it lands. Roll totals are read from the action packet, and the second roll is held back while Bust is active.
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
- **Attack Range Selector**: Choose `Off`, `Melee (3 yalms)`, or `Ranged (15 yalms)` to set how close a follow target must be (requires [Multisend](https://github.com/ThornyFFXI/Multisend)). Shown only when **Multisend Follow** is enabled in `/sk panel`, which also disables the native Follow feature so the two movement systems don't fight
- **Auto-Refresh**: UI updates automatically when jobs or levels change

### Core System Features
- **Smart Resource Management**: Automatic MP/TP checking and cooldown tracking
- **Status Ailment Detection**: Automatically detects and prevents casting when Silenced (magic) or Amnesiac (job abilities)
- **Job-Specific Ability Validation**: Jobs can implement custom validators for fine-grained ability control (e.g., checking pet type, buff requirements, etc.)
- **Pet Entity Management**: Consolidated pet entity access with `get_pet_entity()` for consistent pet checking across all features
- **Packet-Based Casting Detection**: Casting state is read from the parsed 0x028 action packet's category (`casting_begin` locks, `spell_finish` clears), including interrupts, which repeat the start category with a marker instead of reporting a finish
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
  - Automaton healing with **Role Reversal** (level 75 merit) when Repair is on cooldown — only fires when you're healthier than the automaton and the swap leaves you above 25% HP
  - Automaton debuff removal with **Maintenance** (same Oil ammo)

- **Bard** (BRD)
  - Buff with songs on self or party members using Pianissimo (level 20+) — the ME button self-buffs via Pianissimo too
  - Area songs: an `[A]` button (left of the target buttons) sings without Pianissimo so everyone in range (10 yalms) gets it
  - Songs: Minuet, Minne, Paeon, Madrigal, Prelude, March, Ballad, Etude, Carol, Mambo, Mazurka, Scherzo, Threnody, etc.
  - Song limits: 2 songs per party member (main job) or 1 song per party member (sub job)
  - Stack same-buff tiers: right-click → Ungroup to cast each tier independently (e.g. Mage's Ballad + Mage's Ballad II)
  - Party button targeting with automatic Pianissimo usage
  - Settings persist through reloads

- **Black Mage** (BLM) — *self-only support*
  - Self-buff with elemental Spikes (Blaze Spikes, Ice Spikes, Shock Spikes — grouped, single tier selectable via dropdown)
  - Self-heal with **Drain** on your battle target (drains its HP to you — combat-only)
  - MP recovery with **Aspir** on your battle target (drains its MP — combat-only)

- **Blue Mage** (BLU)
  - Self-heal with **Pollen**; party healing with **Wild Carrot** and **Magic Fruit** (blue magic cures can't target outside the party)
  - AOE healing with **Healing Breeze**
  - Self-buffs with blue magic (Cocoon, Metallic Body, Refueling, Feather Barrier, Memento Mori, Zephyr Mantle, Warm-Up, Amplification, Saline Coat, Reactor Cool, Plasma Charge)
  - **Unbridled Learning** spells (level 75: Battery Charge, Animating Wail, Magic Barrier, Occultation, Orcish Counterstance, Barrier Tusk, Harden Shell, Pyric Bulwark, Carcharian Verve) — the Unbridled Learning JA is popped automatically right before the spell, and the spell is held while the JA is on cooldown
  - **Diffusion** (level 75 merit, BLU main): a **D** button on every blue buff row opens a popup — **Enable** fires Diffusion before the buff to spread it to the whole party; **Hold for Diffusion** skips the buff until Diffusion is ready (off by default: the buff still casts self-only when Diffusion is on cooldown)
  - **Set-spell awareness**: blue magic that isn't currently equipped in your set-spell list is grayed out (*"Blue Magic not currently equipped"*) and skipped by automation — it stays selectable, and Sidekick never equips spells for you (use the blusets addon or the in-game menu)

- **Corsair** (COR) — *rolls only*
  - Maintains two **Phantom Rolls** of your choice (pick them from the **Rolls** section) and uses **Double-Up** on each until it is good enough
  - **Risk Tier** (default *Medium*) decides how far it chases a total. Every tier doubles at 5 or less (no die can bust) unless it is already sitting on the roll's **lucky** number, never doubles at 11 (12 busts), and uses **Snake Eye** at 10 for a guaranteed 11:
    - *Lowest* — banks the **lucky** number on sight, and stops at 6 or more; never takes a bust chance
    - *Medium* — banks the **lucky** number, chases it while it's still one die away, and rerolls off the **unlucky** number while the bust chance is 50% or less
    - *Highest* — 11 or nothing. It rolls straight past the **lucky** number (free at 5 or less, where nothing can bust) and keeps doubling through 6-10 whenever **Fold** is up to undo a Bust, otherwise plays like Medium. Expect to give up lucky totals regularly — that's the trade for chasing the cap
  - **Fold** is used the moment you Bust, whatever the tier — that frees the slot, so a fresh roll goes back in and the chase restarts
  - **Snake Eye** and **Fold** are level 75 merit abilities, main job only; without them the tiers still work, just without the guaranteed finishes and the Bust insurance
  - Roll totals aren't in memory, so they're read from the roll action packet (the packet names which roll it belongs to, so Double-Ups can't be mixed up between your two slots)
  - While **Bust** is up only one roll slot exists, so the second roll is held back until it wears
  - Rolls fire in and out of combat. Quick Draw, Ranged Attack, and Random Deal are deliberately not automated (Sidekick is support-only)

- **Dancer** (DNC)
  - Critical HP abilities (Contradance)
  - Single-target healing with waltzes (Curing Waltz I/II/III)
  - AOE healing with waltzes (Divine Waltz, Divine Waltz II)
  - Debuff removal with waltz (Healing Waltz)
  - Buff with sambas (Drain Samba I/II/III, Aspir Samba, Haste Samba)
  - Buff with jigs (Spectral Jig)
  - Buff with level-75 job abilities (Saber Dance, Fan Dance, No Foot Rise, Presto)
  - Self-buff blocking: Saber Dance suppresses Waltzes and Fan Dance suppresses Sambas while active, so those stances aren't interrupted by an automatic Waltz/Samba

- **Dark Knight** (DRK) — *self-only support*
  - Self-buffs with job abilities (Arcane Circle, Last Resort, Souleater, Consume Mana, Diabolic Eye, Scarlet Delirium)
  - Self-buff with dark magic (Dread Spikes)
  - Absorb spells on your battle target (Absorb-Attri, Absorb-ACC, Absorb-TP, Absorb-STR/DEX/INT/AGI/VIT/CHR/MND) — combat-only, single spell selectable via dropdown
  - Self-heal with dark magic (**Drain**, **Drain II**) on your battle target — combat-only, drains its HP to you
  - MP recovery with dark magic (**Aspir**) on your battle target — combat-only, drains its MP
  - **Nether Void** (level 75, DRK main): an **N** button on the Absorb, Drain/Drain II, and Aspir rows opens a popup — **Enable** fires Nether Void before the selected spell to boost it; **Hold for Nether Void** skips the spell until Nether Void is ready (off by default: the spell still casts without it when Nether Void is on cooldown)

- **Geomancer** (GEO)
  - AOE healing with job abilities (Mending Halation)
  - Pet healing with job abilities (Life Cycle)
  - Buff with Geo geomancy spells, single-target party member selection (ME/P1-P5 buttons, single-select)
  - Buff with Indi geomancy spells (self)
  - Debuff with Geo geomancy spells on your battle target (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) — combat-only, single debuff selectable via dropdown
  - Entrust system: Select target party member and Indi spell to automatically cast via Entrust ability
  - Buff with job abilities (Lasting Emanation, Ecliptic Attrition, Collimated Fervor, Dematerialize)
  - Blaze of Glory as a Geo precast: fired only when no luopan is out and the pending Geo spell is affordable
  - Self-heal with dark magic (**Drain**) on your battle target — combat-only, drains its HP to you
  - MP recovery with job abilities (Radial Arcana) and dark magic (**Aspir**, on your battle target — combat-only)
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
  - Buff with white magic (Protect I-IV, Shell I-IV, Reprisal)
  - Buff with job abilities (Majesty, and the combat-only Fealty, Rampart, Sentinel, Holy Circle) — Majesty is prioritized so its Cure-potency bonus is up before the Cures it boosts
  - MP recovery with **Chivalry** (converts TP to MP; TP threshold set by the **Chivalry Min TP** setting)

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
  - **Embolden** (level 60, RUN main): an **E** button on every enhancing magic row opens a popup — **Enable** fires Embolden before the spell to boost its potency; **Hold for Embolden** skips the spell until Embolden is ready (off by default: the spell still casts unboosted when Embolden is on cooldown). Not offered on the Spikes, which it doesn't boost

- **Scholar** (SCH)
  - Single-target healing with white magic (Cure I-IV) and self-heal with dark magic (**Drain**, on your battle target — combat-only)
  - Debuff removal with white magic (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
  - Revive with white magic (Raise, Raise II — requires Addendum: White)
  - Buff with enhancing magic (Protect I-IV, Shell I-IV, Regen I-III, Reraise, Reraise II, Stoneskin, Blink, Aquaveil, Sneak, Invisible, Deodorize)
  - Buff with geomancy spells (Sandstorm, Rainstorm, Windstorm, Firestorm, Hailstorm, Thunderstorm, Voidstorm, Aurorastorm, Klimaform)
  - Buff with elemental magic (Blaze Spikes, Ice Spikes, Shock Spikes)
  - Buff with job abilities (Light Arts, Dark Arts, Addendum: White, Addendum: Black, Sublimation)
  - MP recovery with job abilities (Sublimation) and dark magic (**Aspir**, on your battle target — combat-only)
  - **Enlightenment** (level 75 merit, SCH main): an **E** button on every spell that needs Addendum: White (Cursna, Erase, Raise / Raise II, Reraise, Regen…) fires Enlightenment first so the spell can be cast in **Dark Arts**. A plain on/off toggle — the spell can't be cast without it, so Sidekick always waits for it, and skips the JA when Addendum: White is already up. Shown only while in Dark Arts / Addendum: Black

- **Summoner** (SMN)
  - Critical HP abilities (Apogee)
  - Single-target healing with blood pacts (Healing Ruby - requires Carbuncle)
  - AOE healing with blood pacts (Healing Ruby II - requires Carbuncle)
  - Buff with blood pacts (Avatar's Favor, Shining Ruby)
  - Smart pet validation: Carbuncle-specific abilities only execute when Carbuncle is summoned; avatar-agnostic abilities work with any avatar

- **Thief** (THF) — *self-only support*
  - Self-buffs with job abilities (Conspirator, Assassin's Charge, Feint) — combat-only.

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

1. Place the entire `Sidekick` folder in your Ashita `addons` directory
2. Load the addon in-game: `/addon load sidekick`
3. Configure settings: `/sidekick` (opens the configuration UI)
4. Start automation: `/sidekick start`

## Commands

- `/sidekick` or `/sk` - Show/hide configuration UI (default action)
- `/sidekick help` or `/sk help` - Show command help
- `/sidekick start` or `/sk start` - Start automation
- `/sidekick stop` or `/sk stop` - Stop automation
- `/sidekick toggle` or `/sk toggle` - Toggle automation on/off
- `/sidekick config` or `/sk config` - Show/hide configuration UI
- `/sidekick focus <index>` - Set focus target (0-5, party member index)
- `/sidekick focus clear` - Clear focus target
- `/sidekick debug` or `/sk debug` - Toggle debug mode
- `/sidekick recast` or `/sk recast` - Show all active ability recast timers
- `/sidekick afk` or `/sk afk` - Show AFK Sleep state (enabled, timeout, awake/asleep)
- `/sidekick afk on|off` - Enable/disable AFK Sleep
- `/sidekick afk <seconds>` - Set the AFK Sleep timeout in **seconds** (60-3600; the `/sk panel` field shows the same value in minutes)
- `/sidekick status` or `/sk status` - Show current status and settings

**Note**: `/sk` is a shorthand alias for `/sidekick`. Running `/sidekick` with no arguments opens the configuration UI; use `/sidekick help` to list commands.

## Usage

### Basic Setup

1. Load the addon: `/addon load sidekick`
2. Open config: `/sk config`
3. Enable desired features (healing, buffs, etc.)
4. Adjust thresholds as needed
5. Start automation: `/sk start`

### Focus Target

Focus targets are prioritized for healing and debuff removal:

```
/sidekick focus 1  # Set party member 1 as focus
/sidekick focus clear  # Clear focus
```

Party indices:
- 0 = You
- 1-5 = Other party members

### Debug Mode

Enable debug logging to troubleshoot issues:

```
/sidekick debug
```

This will show detailed information about ability selection, cooldowns, and action execution.

## Architecture

```
Sidekick/
├── Sidekick.lua              # Main addon file
├── lib/
│   ├── core/
│   │   ├── action_core.lua   # Resource/cooldown tracking, buff-ID utils, ability candidacy
│   │   ├── afk.lua           # AFK Sleep dead-man's switch
│   │   ├── automation.lua    # Action selection engine
│   │   ├── common.lua        # Shared utilities
│   │   ├── parse_packets.lua # Packet parsing for casting state
│   │   └── targets.lua       # Target-resolution helpers
│   ├── actions/
│   │   ├── buff.lua          # Buff maintenance
│   │   ├── follow.lua        # Opt-in leader following
│   │   ├── geo.lua           # Geo buff/debuff targeting & Full Circle / luopan management
│   │   ├── heal.lua          # Healing (single-target, AOE, pet)
│   │   ├── item.lua          # Consumable-based status removal
│   │   ├── recover.lua       # MP/TP recovery
│   │   ├── rest.lua          # Automatic resting (/heal)
│   │   ├── revive.lua        # Raise dead members
│   │   └── status_removal.lua # Debuff removal & sleep wake (single + AOE)
│   ├── jobs/
│   │   ├── bard.lua          # Bard abilities
│   │   ├── beastmaster.lua   # Beastmaster abilities (pet-only)
│   │   ├── black_mage.lua    # Black Mage abilities (self-only)
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
│   │   ├── thief.lua         # Thief abilities (self-only)
│   │   ├── warrior.lua       # Warrior abilities (self-only)
│   │   └── white_mage.lua    # White Mage abilities
│   └── ui/
│       ├── components.lua    # Reusable ImGui render components
│       ├── config.lua        # ImGui configuration window
│       ├── panel.lua         # Debug info panel
│       └── tooltips.lua      # Contextual hover help
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical map.

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
- `multisend_follow` (boolean): Movement mode switch (checkbox in `/sk panel`). `true` = Multisend attack-range follow (shows Attack Range, disables native Follow); `false` = native leader Follow (hides Attack Range). Mutually exclusive; off by default
- `follow_enabled` (boolean): Enable opt-in leader following (`/follow` the follow target when far); off by default. Ignored while `multisend_follow` is on
- `follow_distance` (number): Distance in yalms the follow target must exceed before `/follow` is sent (1-15, default 5)
- `follow_target` (string): Character name to follow — a party member (P1-P5) or a session tracked target — shared by leader following and the resting distance check (optional)
- `afk_enabled` (boolean): Enable AFK Sleep — pause automation after `afk_timeout` with no party movement and no combat, resume on your own movement (checkbox in `/sk panel`); on by default
- `afk_timeout` (number): Seconds of no party movement and no combat before sleeping (60-3600, default 600). Stored in seconds; the `/sk panel` field shows minutes
- `geo_enabled` (boolean): Enable geo management (Geo buffs, Geo debuffs, and Full Circle / luopan handling)
- `geo_distance_threshold` (number): Distance (yalms) the luopan may drift from the selected Geo target before Full Circle recalls and recasts it (7-30)
- `geo_bt_timer` (number): Seconds to wait after the Geo-bt battle target dies before Full Circle dismisses the luopan; a new battle target within the window reuses it instead (1-20, default 5)
- `selected_Geo-bt` (string): Selected Geo debuff spell to cast on your battle target (combat-only)
- `disabled_group_Geo-bt` (boolean): Disables casting the selected Geo debuff
- `ungrouped_<group>` (boolean): When true, casts every tier in the group independently instead of only the selected tier (right-click → Ungroup)
- `stratagem_hold[<key>]` (boolean): When true, hold the spell until its assigned stratagem can fire; when false (default), cast without the stratagem if no charge is available

**Note**: Group/AOE heal target selection is per-session (not persisted). Debug Mode toggles from the `/sk panel` header.

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
- 1.1-second command throttle to prevent spam (3.1 s after a spell, matching its longer lockout), timed from when an action completes
- Early returns for disabled states

## Known Limitations

- Alliance automation is limited to abilities with `target_outside = true` (spells/abilities that can be cast on non-party targets)
- Designed to work on [CatsEyeXI private server](https://www.catseyexi.com/)
- To use attack range requires [Multisend](https://github.com/ThornyFFXI/Multisend)
- Requires Ashita v4

## License

See [LICENSE file for details.](https://github.com/seekey13/Sidekick/blob/main/LICENSE)
