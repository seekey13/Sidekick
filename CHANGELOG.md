# Changelog

All notable changes to Sidekick will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.6.0] - 2026-07-20

### Added
- **Config window transparency** (`ui_opacity`, global, default 100): a **UI Transparency** slider (1-100) on the `/sk panel` controls row drives the `/sk` config window's alpha via a window-scoped `ImGuiStyleVar_Alpha` push. Readability surfaces are exempt and render fully opaque however faded the window is: expanded dropdown menus (`ui_components.begin_opaque_combo` / `end_opaque_combo` — the popup's bg alpha is armed only on frames the popup is actually open, tracked per label from the previous frame, because a stray `SetNextWindowBgAlpha` on a closed combo leaks onto the next window begun, usually a tooltip) and every tooltip (`ui_components.set_tooltip` wraps `imgui.SetTooltip` in a full-alpha style push; all config-UI call sites route through it). The closed combo preview keeps the window's fade. Thanks to **Fallen** for the feature idea.

- **Geo spells are gated on the luopan slot being free**: only one luopan can exist at a time, so a Geo cast while one is already out is rejected by the server. Geomancer gains a `validate_ability` that drops `group = 'Geo'` spells from `filter_abilities_by_level` whenever `common.get_pet_entity()` returns a pet; `buff.lua` skips them until the slot frees. Scoped to `'Geo'` — `'Indi'` follows the caster and needs no luopan, and `'Geo-bt'` has to stay available while a luopan is out or `geo.lua`'s "Full Circle (Geo-bt taking the luopan)" branch could never fire. The config UI gates on `can_use_ability` rather than the validator, so the rows remain visible and selectable.

- **Geo auras on Trusts are dropped when the luopan is**: a Trust has no readable buff array (`common.get_member_buffs` falls back to packet-tracked `trust_buffs` for server ids ≥ `0x1000000`), and a Geo aura that ends because its luopan went away sends no wear-off packet — not 0x028 message 83, not a 0x029 lose message. The tracked buff therefore survived a Full Circle until its duration cap, `buff.lua` saw the Trust as already buffed, and the Geo spell was never recast on it. `geo.lua` now clears every `group = 'Geo'` buff id from tracking for all party members the tick the luopan entity disappears. Keyed on the entity vanishing rather than on the Full Circle cast, so expiry and a killed luopan are covered too. `group = 'Indi'` is excluded — Indi follows the caster, not the luopan.

- **Corsair roll risk tiers**: The flat `roll_hit_threshold` setting is replaced by `risk_tier` (`'lowest'` / `'medium'` / `'highest'`, default medium), rendered as a **Risk Tier** dropdown in the **Rolls** section via the existing `ui_components.combo`. The Double-Up decision moves out of `roll.lua` into a new dependency-free module, `lib/core/roll_strategy.lua`: `decide(total, lucky, unlucky, tier, snake_eye_ready, fold_ready)` returns `'stop'` / `'double'` / `'snake_eye_then_double'`, and `should_fold(has_bust_buff, fold_ready)` returns a boolean. Every tier doubles freely at totals ≤5 (no die can bust), never doubles at 11, and takes **Snake Eye** at 10 for a guaranteed 11; Snake Eye at `lucky - 1` is spent by Lowest/Medium but reserved by Highest (its ~5 min recast outlasts one chase). Lowest stops at 6+, Medium chases `lucky` while it's one die away and rerolls off `unlucky` while bust chance is ≤50% (`total <= 8`), Highest chases 11 whenever **Fold** is ready to insure the Bust and falls back to Medium's logic when it isn't. The zero-risk lucky stop is tier-dependent, not baseline: banking `lucky` is only right for the tiers whose ceiling *is* `lucky`, so **Highest rolls straight through it** — free, since the worst a die can do from 5 is land on 11. `unlucky`, previously reference data only, is now a real input. **Fold-on-Bust** is universal and runs ahead of everything else in `roll.execute` — clearing Bust frees the slot, so the existing cast-missing-roll priority recasts into it and the chase restarts with no new state. Snake Eye is tracked by a per-slot `snake_eye_armed` flag rather than its recast (which reads busy immediately after the cast), cleared when the slot's next packet total resolves; the per-slot `is_stable` flag is gone, since the stop decision is now recomputed each tick. Both merits are looked up by fixed name from `abilities.roll_control` and gated through `common.filter_abilities_by_level` (level 75, main job, merit-learned) plus a **read-only** recast probe. `roll_strategy.self_test()` covers every branch and is wired to the new **`/sidekick roll_test`** command, printing PASS/FAIL per case.
- **`action_core.is_ability_recast_zero(recast_id)`**: read-only recast check for callers that need to know whether an ability is available *without* trying to use it. `is_ability_ready` is a **consuming** check — it arms a timestamp the first time it sees a zero timer and clears it on the call that returns true (the `POST_RECAST_DELAY` machinery), so two calls in the same tick disagree by design. That is why Fold never fired on a Bust: `roll.execute` called `is_usable` to compute `fold_ready`, and the `try_use` that followed called `is_usable` again, re-arming the delay and returning false every time. Readiness now comes from the read-only probe; `try_use` remains the single consuming call at cast time.
- **`common.successf`** (green, `chat.success`) and a lucky-number callout: landing on a roll's `lucky` total prints `[Roll] Corsair's Roll (EXP+): LUCKY 5!` in green from the packet handler, and `[Roll] Corsair's Roll (EXP+): 11!!!` on the 11 cap. The lucky line reports the hit only, not a stop: Lowest/Medium bank the lucky number, Highest rolls past it. The two never collide — no roll's `lucky` is anywhere near 11.
- **Debug output repeat suppression** (`common.debugf`): each distinct message prints at most once per 60 seconds, with the swallowed count appended to the next print (`... (x184)`). The window only limits how often an *unchanged* state repeats — a real state change formats a different string and prints immediately — so it is sized against the slowest thing being waited on (Phantom Roll's ~60s recast). The tick loop runs per frame, so steady-state lines used to repeat ~60x/second and bury everything that changed. Suppression is per message rather than consecutive, since modules interleave (Roll1 / Roll2 / Roll1 …) and no two identical lines are ever adjacent.
- **Corsair (rolls only)**: New job def (`lib/jobs/corsair.lua`, job id 17, `resource_type = 'tp'`) carrying all 25 Phantom Rolls, and a new `roll` action type (`lib/actions/roll.lua`) slotted into `master_priority` immediately ahead of `buff`. Two roll slots are configurable (`roll1_name` / `roll2_name`); available slots drop to 1 while **Bust** (309) is up, and no new roll is cast at capacity. Double-Up fires while the Double-Up Chance buff (308) is up, kept or stopped by the risk tier above. Every roll shares Phantom Roll's `recast_id = 193`, so `action_core.try_use` gates the cast on that one timer plus Amnesia. **Roll totals are packet-derived**: `roll.handle_action_packet` reads them off the parsed 0x028 action packet — `Type == 6`, `Param` = the roll's ability id (the server rewrites it to the *underlying* roll's id on a Double-Up, so packets self-identify their slot), and on the caster's own target entry `action.Info` = the die 1-6, `action.Param` = the running total, `action.Message` = 420/421 roll, 424 double-up, 426/427 bust. `parse_packets.lua`'s per-action fields were relabelled to match the server packer `src/map/packets/s2c/0x028_battle2.cpp` (`Resolution 3 | Kind 2 | Animation 12 | Info 5 | Scale 2 | Knockback 3`, replacing the mislabelled `Reaction/Animation/SpecialEffect/Knockback` — same total width, so `Param`/`Message`/`Flags` offsets are unchanged). Each roll carries `ability_id` (abilities.sql `abilityId`), which does double duty: `has_spell_learned` gates on `HasAbility(ability_id + 512)` so rolls the player has not learned are dropped from both the UI and automation (rolls unlock individually, so level alone is not enough), and the packet handler matches it against `cmd_arg`. Dispatched from the existing 0x028 handler just after the parse, guarded on the job actually having `abilities.roll`. Quick Draw / Ranged Attack / Random Deal from the pre-3.0 job file are deliberately dropped (support-only), as is the old engaged-only gate, so rolls also fire out of combat.

### Changed
- **Blaze of Glory is now a Geo precast, not a self-buff**: it enhances the luopan created by the *next* Geo spell, so firing it as a plain self-buff burned the 10-minute recast with a luopan already out or with no Geo cast pending. The ability moved from `abilities.buff` to `abilities.geo` (its checkbox now renders in the Geo section beside Full Circle; the `disabled_Blaze_of_Glory` settings key is unchanged), and `geo.lua` fires it only when the luopan slot is free *and* a Geo spell is actually pending that it can pay for — `next_geo_spell()` resolves that to the combat `<bt>` debuff when one is selected, else the selected Geo `<me>`/party tier on its one enabled target, and returns nil when that target already holds the buff. Runs ahead of the Geo-bt cast and ahead of `buff.lua`'s Geo cast (buff comes after geo in `priority_order`).
- **Ungrouped groups gate each tier's Combat Only / Idle Only independently** (`common.ability_gate_key`): the combat/idle gate key was per-group for any grouped ability, so an ungrouped group (right-click → **Ungroup**) still shared one Combat Only / Idle Only setting across all its tiers. Key selection is now unified in `common.ability_gate_key(prefix, ability, settings)` — group-level (`<prefix>_group_<group>`) while grouped, per-ability (`<prefix>_<ability_name>`) once `ungrouped_<group>` is set, with **no** fallback to the group value once ungrouped (matching how `disabled_group_<group>` already behaves). So an ungrouped Geo group can run e.g. **Indi-Fury** Combat Only and **Indi-Refresh** Idle Only. `is_ability_combat_only` / `is_ability_idle_only` and the right-click popup in `components.lua` all route through the one helper; the popup builds its gate keys inside the menu so a grouped `<bt>`/`combat_only` ability with no name still reaches its **Ungroup** checkbox to re-group. Note: an existing `ungrouped_X` + `combat_only_group_X` combo loses its per-group gate on reload — re-set the gate per tier.
- **`is_combat` holds through a grace window after the battle target vanishes** (`common.is_combat`, `COMBAT_GRACE = 5.0`s): a multi-mob pull has no `<bt>` for a moment between one mob dying and someone engaging the next, which flickered every `combat_only` ability off and every `idle_only` ability on for a tick or two. `is_combat` now stamps `os.clock()` on each real battle-target read and stays true for `COMBAT_GRACE` seconds after the target disappears, so support coverage overlaps the dead-mob → next-mob gap instead of thrashing. `is_idle` inherits it (it's the negation).

### Fixed
- **Scholar Arts MP tax was ignored** (`common.arts_adjusted_cost`, applied through `common.effective_ability_cost`): an Arts stance taxes the **opposite** magic school by 20%, so under Dark Arts a Cure IV really costs 105 MP, not 88 — Sidekick budgeted the untaxed number, queued the cure, and ate the server's rejection. The tax is keyed off the spell's `Type` from the resource manager (1 white / 2 black) rather than a hardcoded spell list, so it covers subjob spells for free and never touches ninjutsu, songs, summoning, blue, geomancy, JAs or items. Three details come straight from `battleutils::CalculateSpellCost`: it adds as `cost += (int16)(base * mod / 100.0f)`, a C cast, so the tax **truncates** and never rounds up; **Tabula Rasa** (377) suppresses it entirely (`light_arts.lua` / `dark_arts.lua` skip the `+20` mod while TR is up, and `tabula_rasa.lua` subtracts 30 from that same mod); and a cost-modifying stratagem **replaces** the tax instead of compounding with it, since Penury/Parsimony/Accession/Manifestation all clear `applyArts` server-side. That last one is why a Penury'd Cure IV in Dark Arts is 44 MP and not 53. Whether a stratagem applied is tracked by a flag rather than `modifier ~= 1.0`, since Accession 2.0x × Penury 0.5x multiplies back out to 1.0 and still suppressed the tax.
- **Accession cost was 3x, the server charges 2x** (`scholar.lua`, `mp_modifier`): `battleutils::CalculateSpellCost` does a plain `cost *= 2` for a `SPELLAOE_RADIAL_ACCE` spell under Accession, matching the ability's own description ("MP cost is doubled"). The 50% overestimate made Sidekick skip Accession'd cures it could afford.
- **Accession was offered on spells it cannot extend**: matching the stratagem's colour (`magic = 'white'`) and `magic_types` was too coarse — the server extends a spell only when its `spell_list.sql` `AOE` column is `4` (`SPELLAOE_RADIAL_ACCE`), so Raise/Raise II/III/Arise, all four Reraise tiers, Haste/Haste II, Flurry, Cure V/VI, Temper, Gain-\*, Crusade and Sacrifice are untouched by it, as are the lines that are already AoE on their own (Curaga, Cura, Esuna, Boost-\*, Hastega). Sidekick would still burn the charge, double the budgeted MP and drop the Arts tax that in fact still applies. Precast entries gain an optional `spell_ids` allowlist (Accession's is copied from `spell_list.sql`) enforced by the new `common.stratagem_applies(strat, ability)`, which gates all three consumers together: the **S** popup no longer offers it on those rows, `effective_ability_cost` no longer applies the modifier, and `check_stratagem` no longer fires the JA. A stratagem with no `spell_ids` behaves as before.
- **Ability MP costs displayed in the UI could disagree with the cost the automation gated on**: `components.lua` carried its own `get_stratagem_mp_modifier` keyed on the group name, while `common.effective_ability_cost` prefers the ability name and falls back to the group — so a per-ability assignment showed one number and gated on another. The duplicate is deleted; all five display sites (group dropdown current + list, self single, party single, ability checkbox) now call `effective_ability_cost` directly, which also gets them the Arts adjustment for free.
- **Entrust fired without the MP to follow it**: the Indi spell's MP cost was only checked in the branch that casts it, so with the Entrust buff already up Sidekick would pop **Entrust** (5 minute recast) and then sit unable to afford the Indi spell. The cost check is now hoisted above the buff branch in `geo.lua`, gating the JA and the follow-up cast alike.

## [2.5.0] - 2026-07-17

### Added
- **Rune Fencer Embolden**: Embolden (60, RUN main) boosts the potency of the next enhancing magic. An **E** button in the leading slot of every white *enhancing* buff row opens a popup with **Enable** (fire Embolden the tick before the spell, same follow-up lock as the Scholar stratagems) and **Hold for Embolden** (ON skips the spell until Embolden is ready; OFF, the default, casts it unboosted while Embolden is on cooldown). Both keys are required to draw the button — `magic = 'white'` keeps it off the black-magic Spikes, `magic_type = 'enhancing'` off the white non-enhancing rows. Reuses the `recast_gate` precast machinery introduced for DRK Nether Void, named by the ability's `column = 'embolden'` field. RUN/SCH in **Light Arts** is the one case needing a second leading column, since Embolden's rows are exactly the rows the Scholar **S** button also claims there: the row reads `[E][S]` on Protect and `[ ][S]` on Cure. Every other job/stance shares the single scholar column (`embolden_needs_own_column`), decided per-stance rather than per-row.

- **Scholar Enlightenment**: Enlightenment (75 merit, SCH main) frees the next spell from the addenda, so an Addendum: White spell can be cast in Dark Arts. An **E** button appears on every row Addendum: White gates (the job data writes those as `requires_buff = {401, 416}`) while in Dark Arts / Addendum: Black; off-stance the whole column collapses, and rows gated on an arts stance instead (`{358, 401}`, e.g. Tranquility) carry no 416 and get no button. Unlike the other recast-gate buttons it is a plain **toggle** rather than a popup, Hold being implicit. Backed by a new `precast_required` ability flag, which makes `check_stratagem` hold the spell regardless of the Hold setting (scoped to the strat firing this tick, so it can't hold an unrelated charge stratagem) and skip the JA when Addendum: White is already up. `common.precast_satisfies_prereq` opens the `requires_buff` gates in `buff.lua` / `revive.lua` so an assigned Enlightenment lets its spell reach `check_stratagem` at all. Level / merit / main-job are checked there (`common.precast_permanently_usable`); recast deliberately is not, since a JA that can *never* fire would hold the spell forever.

- **Paladin self-buffs**: PLD gains its defensive job abilities and Reprisal. **Majesty** (70) carries `priority = 100`, sorting ahead of the other self-buffs, and is not `combat_only`. **Fealty** (75, merit `ability_id = 157`), **Rampart** (62), **Sentinel** (30) and **Holy Circle** (5) are all `combat_only`. **Reprisal** (61) is enhancing white magic (`spell_id = 97`, 24 MP) rather than a JA, so it reads the spell recast table and carries the enhancing-magic column buttons.

- **Puppetmaster Role Reversal**: A second `heal_pet` entry for PUP (75, merit `ability_id = 179` — 180 is Ventriloquy, `recast_id = 211`, `pet_required`). **Repair** carries `priority = 100` so Role Reversal is only reached when Repair is on cooldown. Because it swaps master/pet HP *percentages*, `heal_pet`'s pet-HP gate isn't sufficient on its own: a new PUP `validate_ability` requires `pet_hpp >= 25` and `player.hpp > pet_hpp`, so it can't drop the player to critical HP or make the pet worse when the player is the hurt one.

- **AFK Sleep**: Sidekick now puts automation to sleep after a period with no party movement and no combat, and wakes it when you physically move again. **On by default** with a 10 minute timeout. Sleep is a runtime gate, not a stop: `automation_enabled` stays true and nothing is written to disk. Two activity signals keep it awake, both already sampled each tick (no new memory reads): any party member moving (indices 0-5, via `game_state.player` / `game_state.party[i].position`) and party combat (`common.is_combat()` — `<bt>` resolves on party *claim*, not on your own engagement). Only **your own** movement wakes it back up. Controls live in `/sk panel` beside Debug Mode (an **AFK Sleep** checkbox and a **Timeout (minutes)** field, 1-60) or via `/sidekick afk [on|off|<seconds 60-3600>]`; the automation status line in `/sk` reads *"Automation asleep - move to wake"* while gated, and the panel debug row shows the live countdown. Backed by the new `lib/core/afk.lua` and the `afk_enabled` / `afk_timeout` settings keys.

### Changed
- **Party State Panel Upgrade** `/sk panel` reorganized and styled.

- **Ability ordering via `priority`**: `common.filter_abilities_by_level` now sorts the available-ability list by an optional `priority` field (descending) before the existing cost-descending tiebreak, so an ability can be forced ahead of others regardless of MP cost. Unset reads as 0, leaving every other job/section unchanged. It applies to any action type routed through that filter (`buff`, `heal`, `heal_pet`, `recover_mp`, `recover_tp`, …), which matters most after main/sub ability merging — e.g. **SAM Meditate** and **DNC Reverse Flourish** (100) each outrank whatever a subjob contributes to the same `recover_tp` list. Used where cast order matters within a tick: **RDM Composure** (100) casts before its other self-buffs so their durations inherit the Composure bonus; **SCH Sublimation** (50), the **GEO** Indi/Geo self-buffs (50), **BLU Battery Charge** (50) and **RUN/RDM Refresh** (50) sort ahead of their lower-priority peers, with **RDM/WHM Haste** and **RDM Flurry** (25) below them; **GEO Radial Arcana** (90) is preferred over Aspir; **PUP Repair** (100) is preferred over Role Reversal. Do **not** set it on a grouped tier — `buff.lua`'s default-tier auto-select casts the first grouped tier it sees expecting highest cost first, and a per-group special-case would make the comparator intransitive (sort crash), so `priority` stays off grouped abilities.

- **Command throttle times from an action's completion, not its send** (1.0 s → 1.1 s, matching the game's server-side post-action lockout). The lockout runs from when the server *resolves* an action, but `execute_command` can only stamp on send — a whole cast time early for a spell, so the stamp expires mid-cast and the next command fires into the lockout and is eaten. `automation.notify_action_finished()` re-stamps from the player's own 0x028 finish packets (`ACTION_FINISH_CATEGORIES` in `Sidekick.lua`: 2/3/4/5 ranged/WS/spell/item, 6/14/15 job abilities; the `*_begin` categories 7/8/9/12 are excluded, since each has its own finish packet later — unless the begin carries `INTERRUPT_PARAM`, which `is_action_finish` accepts because a cancelled action never sends a finish and locks out just the same). Only ever moves the stamp later, never earlier. Also catches actions the **player** took by hand, which `execute_command` never sees.

- **Spells carry a longer completion lockout in the command throttle** (1.1 s → 3.1 s, spell finishes only). A spell's server-side post-cast lockout is longer than a job ability's or item's, so `automation.notify_action_finished(is_spell_finish)` stamps the extra seconds forward when the resolving 0x028 is category 4 (`spell_finish`), while ranged / WS / item / JA finishes keep the 1.1 s gap. The throttle check always subtracts `command_throttle`, so a stamp pushed `(spell_finish_throttle − command_throttle)` into the future yields the full 3.1 s gap. Stops the next command firing into the tail of a spell's lockout and being eaten. An interrupted spell arrives as its `*_begin` category (not 4) and correctly keeps the short 1.1 s gap.

- **Removal spells no longer loop on Trusts/tracked/alliance/pet targets, and a resisted cure retries instead of orphaning the status**: These targets give no reliable wear-off packet, so after Sidekick cast e.g. Poisona the tracked Poison lingered and the cure re-fired every tick. On casting a na-/Erase spell — including a pet Reward/Maintenance strip — `common.drop_removed_debuff` now marks one matching status as **in-flight** for `REMOVAL_SUPPRESS_WINDOW` (~4 s) rather than deleting it outright: `common.removable_after_suppression` hides it from the removal selector while the cast resolves (no loop-casting), a landed cast's removal packet (`0x028` msg-83 / `0x029` wear-off) clears it for real inside the window, and a rejected/resisted cast — which sends no packet — lets the mark expire so the status becomes eligible again and is retried, instead of vanishing from tracking while still on the target. Each removal clears one status per cast; the debuff base-duration timer catches anything guessed wrong, and the panel keeps reading the full tracked list.

- **Casting detection rebuilt on parsed 0x028 categories**: the old detector probed raw bytes (actor id at `0x05`, "completion flag" at `0x0F`). Now reads `parse_packets.parse_action_packet` — category 8 `casting_begin` sets the lock, 4 `spell_finish` clears it, 1 (melee) is dropped since an autoattack says nothing about casting.

- **Interrupts read straight from the packet**: an interrupted action sends no finish packet. It repeats its own `*_begin` category (7 WS / 8 casting / 9 item / 12 ranged) with `Param` replaced by `28787` (`0x7073`) where the spell/ability id would be — now `common.INTERRUPT_PARAM`, and no real id collides with it. Three readers key off it. `handle_action_packet` ignores that second category 8 instead of treating it as a fresh `casting_begin`, which re-armed the cast lock and froze automation until the timeout. `is_action_finish` (`Sidekick.lua`) restarts the command throttle from an interrupted `*_begin`, since the server locks out the same whether the action landed or was cancelled. `get_last_action` reports `interrupted (casting_begin)` rather than a bogus cast plus a spell lookup on an id that isn't one. `cast_timeout` 5 s → 16 s: with interrupts detected and zoning clearing the lock explicitly, the backstop now covers only a genuinely missed packet.

- **Debug panel shows `Action:` instead of `Casting: true/false`**: `common.get_last_action()` names the last 0x028 category seen from the player (`casting_begin: Cure IV`, `job_ability`, `ws_finish`, `interrupted (casting_begin)`, …), so a cast is watchable start-to-finish. Melee isn't recorded (it'd drown everything else while engaged); the spell name resolves only for categories 4/8, where `Param` is a spell id. Reads `none` before the first action, after the stuck-cast timeout, and after a zone change.

- **Ability id fields split into `spell_id` / `recast_id`**: the single `id` field is gone. `spell_id` (`spell_list.sql` `spellid`) is used by `/ma`, `recast_id` (`abilities.sql` `recastId`) by everything else, and the *field name* — not the command text — now selects which recast table `action_core.is_usable` reads. Replaces the old `is_spell_command` command-sniffing helper. Each ability carries exactly one. Item/ammo tier tables (BST `PET_FOOD`, NIN `SHURIKENS`, PUP `OILS`) keep their bare `id` (item ids, not abilities).

### Fixed
- **Bard single-target songs raced ahead of area songs** — in **Pianissimo Fast Casting**, if an area (`[A]`) song was briefly on recast, Sidekick sang a single-target song anyway, which the area song then overwrote the moment it came back up. The single-target pass now holds until every configured area song is established first.  Thanks to **Sleazy** for reporting the bug.

- **Erase and Healing Waltz skipped Shock and Drown** — the two elemental damage-over-time debuffs (thunder and water) were missing from the removable list, so Sidekick left them up even though Erase (and Dancer's Healing Waltz) can strip them. Both are now recognized and cured alongside Burn, Frost, Choke, and Rasp.  Thanks again to **Sleazy** for reporting the bug.

- **Phantom statuses (e.g. Sleep/Terror after a synth) from 0x029 battle messages**: the `0x029` handler treated `param` (0x0C) as a status id for *every* battle message, ignoring the message id at `0x18`. `0x029` carries damage, misses, no-effect, synth results and skill-ups too — any of those whose `param` happened to equal a status id (Sleep=2, Terror=28, …) injected a phantom status onto a Trust / tracked / alliance / pet target. `parse_message_packet` now also reads `message` (`MessageNum` @ 0x18, masked to 15 bits) and the handler acts only on verified status messages: `STATUS_GAIN_MESSAGES` (186/203/205/230/236/237/242/243/266/277/278/280 — the "gains/receives the effect of / is `<status>`" families) and `STATUS_LOSE_MESSAGES` (204/206 `EffectWearsOff`, 343 effect-disappears), where `param` is genuinely a status id. Message ids verified against the CatsEyeXI server enums `msg_std.h` / `msg_basic.h`. As a bonus this adds the missing **wear-off** path: `EffectWearsOff` (206) is broadcast in-range on every status expiry and was previously mis-read as a *gain* (re-adding the buff that just wore off) — it now routes to `common.handle_buff_removal`.

- **Unidentified packet-tracked statuses lingered forever**: `common.base_buff_duration` returned `nil` (no timer) for any status not in its known-duration tables, so an unrecognized buff/debuff on a Trust / tracked / alliance / pet target — whose wear-off packets are unreliable — was tracked until zone. Unknowns now fall back to a `UNKNOWN_BUFF_DURATION` (300 s) cap so nothing is immortal; Sidekick never re-applies unknown statuses, so an early drop just clears tracking and re-adds on next detection.

- **Bard Pianissimo burned on a song that isn't ready**: `buff.lua` raised Pianissimo as soon as an area song *wanted* recasting, without checking the song was castable — so Pianissimo's recast burned down while the song waited on its own recast or MP, and was gone by the time the song came up. Both the area phase and the single-target target-modifier path now gate on `action_core.is_usable(ability, job_def, common.effective_ability_cost(...))`; a song that isn't ready falls through to the next instead of consuming the modifier.

- **Interrupted casts recorded a Trust buff that never landed**: an interrupt sends no `spell_finish`, so the entry `register_pending_buff` stacked at cast start was never popped — the next unrelated `spell_finish` claimed the stale entry and recorded a buff the target never got, suppressing that buff's recast for its full base duration. `handle_buff_application()` now drops a pending entry older than `PENDING_BUFF_TIMEOUT` (10 s), and still rejects `INTERRUPT_PARAM` on category 4 in case an interrupt ever lands there.

- **Erase fired on ailments it cannot remove**: one `common.ERASABLE_DEBUFFS` list was shared by WHM/SCH **Erase** and the pet cleanses (BST **Reward**, PUP **Maintenance**), and it carried the Na-spell ailments (Poison, Paralysis, Blindness, Silence, Disease, Curse, Plague) — which Erase doesn't touch, so it fired and failed on them. The list is now split: `ERASABLE_DEBUFFS` is Erase's real set, and the pet cleanses carry a new `common.PET_CLEANSE_DEBUFFS` superset (Erase's list plus the Na ailments). Neither pet ability is an Erase server-side — Maintenance walks its own ailment list before falling back to `eraseStatusEffect()`, and Reward is a Jackcoat-gear-gated cleanse that never calls Erase at all, so Reward over-claims here and no-ops rather than missing a real cleanse. The 120 s debuff-expiry backstop keys off the superset, since it has to cover every debuff with *any* remover.

- **Scholar Addendums only fired at full stratagem charges**: **Addendum: White / Black** carried `recast_id = 231`, but the stratagem pool counts *down per charge* rather than to zero, so a plain recast gate passed only when the pool was full. Both now carry `requires_stratagem_charge` and are gated on `game_state.stratagems >= 1` through a new Scholar `validate_ability`.

- **67 wrong ability ids across 6 jobs**, audited against the CatsEyeXI server SQL. These pointed at the wrong spell/timer, so the affected abilities cast the wrong thing or mis-read their cooldown:
  - **Red Mage / Rune Fencer**: the whole Bar-element and Bar-status line was shifted (Barstone cast Barfire, Barsleep cast Barblizzard, …); all six En-spells and their II tiers were off; RUN Protect I-III and Shell IV, RDM Flurry and Phalanx II.
  - **White Mage**: the Bar-status *-ra* line was shifted by one (Barsleepra cast Baramnesia, …); Raise II pointed at Teleport-Vahzl.
  - **Scholar**: Raise II pointed at Reraise II, Reraise II at Reraise III, Sandstorm at Flash; Addendum: Black used its `abilityId` as a recast id.
  - **Bard**: Water Carol and Earth Carol were swapped.
  - **Dancer**: Divine Waltz II and Spectral Jig had wrong recast ids.
  - **White Mage / Rune Fencer**: Afflatus Misery and Vivacious Pulse used `abilityId` values as recast ids.
- **46 wrong MP costs and levels** corrected to match the server SQL — RDM/RUN/WHM/SCH (Protect/Shell tiers, Regen II-III, the En-II spells, the Bar-*ra* line, Foil, Auspice, Enlight, Invisible/Sneak/Deodorize, …), plus DNC Divine Waltz (25), SCH Sublimation (35) and Blink (29), WHM Divine Seal (15).

## [2.4.0] - 2026-07-15

### Added
- **Auto Follow (opt-in leader following)**: Sidekick can now `/follow` a chosen party member when they move beyond a set distance — the first non-combat movement it performs, **off by default**. Configured in the new **Auto Follow** section at the top of `/sk` (a **Follow Target** dropdown and a **Distance (yalms)** slider — `follow_enabled` / `follow_target` / `follow_distance`, default 5). It's a job-independent action injected once into the merged `available_actions` (not into all 21 job files) and wired **low** in `master_priority`, just above `rest`, so healing and every other support action preempt it. It keeps running while automation is stopped or "paused" (a standalone `follow_tick` that takes over whenever the priority engine won't reach the follow action) and, unlike combat actions, isn't gated on `can_attack`, so it works in towns/safe zones. A server autorun-cancel packet guard (0x0D byte 0x42 / 0x37 byte 0x58, active only while enabled) zeroes the flag on position syncs so `/follow` survives them and doesn't break mid-route; switching targets calls `common.reset_autofollow` so the client stops running at the old leader. A **Multisend Follow** checkbox in `/sk panel` switches to the legacy Multisend attack-range follow instead — showing the **Attack Range** combo and disabling native Follow — so the two movement systems are mutually exclusive and never fight.

- **Start button right-click menu (`Load stopped` / `Stop after zone`)**: The **Start/Stop** button now takes a right-click, opening a menu with two persisted toggles, **both off by default** so nothing changes on upgrade. **Load stopped** ignores the saved `automation_enabled` value and comes up stopped every load, instead of restoring the state you left. **Stop after zone** stops automation on the zone-change packet (`0x0A`, alongside the existing Trust-buff / tracked-target clears) and prints *"Automation stopped (zoned)."*. Backed by the `load_stopped` / `stop_after_zone` settings keys; an absent key reads as off.

- **Black Mage (BLM) support**: Self-only automation. Self-buffs the elemental **Spikes** (Blaze Spikes 10, Ice Spikes 20, Shock Spikes 30 — grouped as `spikes`, single tier selectable via dropdown); self-heals with **Drain** (12) on the battle target; recovers MP with **Aspir** (25) on the battle target. Drain and Aspir are dark magic cast on `<bt>` and so are inherently combat-only; Drain is flagged `self_only` so the heal engine only ever fires it on the caster's own HP (never as a party heal), and prefers the highest-value Drain that fits the HP deficit.
- **Drain / Drain II / Aspir on Dark Knight, Scholar, Geomancer**: The dark-magic HP/MP drains are now shared across the caster jobs that learn them.
  - **Dark Knight**: **Drain** (10) / **Drain II** (62) as self-heals and **Aspir** (20) for MP recovery, on the battle target (combat-only). DRK gains the `heal` and `recover` actions in its priority order.
  - **Scholar**: **Drain** (21) added to healing and **Aspir** (36) added to MP recovery, alongside its existing Cures and Sublimation.
  - **Geomancer**: **Drain** (15) as a self-heal and **Aspir** (30) added to MP recovery (alongside Radial Arcana). GEO gains the `heal` action.

- **Nether Void now boosts Drain / Drain II / Aspir**: The DRK Nether Void **[N]** button (previously only on the Absorb row) now also appears on the Drain, Drain II, and Aspir rows in the heal / recovery sections. Enabling it fires Nether Void the tick before the drain to boost it, with the same **Hold for Nether Void** behavior as the Absorb spells. Abilities opt in via a new `nether_void` ability flag (DRK only); `render_nether_void_button` self-gates on it plus the existing Absorb group and is rendered from `ability_checkbox`, so it stays hidden for the other jobs' Drain/Aspir and when DRK is a subjob.

- **Bard Pianissimo Fast Casting mode**: New per-Bard toggle (checkbox beside **Debug Mode** in `/sk panel`, persisted in `settings_bard.json`). When on, area songs are cast with **Pianissimo** up — for its shorter cast time — then Pianissimo is stripped ~1 second into the cast (`/debuff 409`) so the song still lands as an area song. Always holds for Pianissimo: an area song won't fire until Pianissimo is available (no fallback to a plain area cast). **Requires the Debuff addon by atom0s (`/debuff`).** The removal is queued from the tick loop ahead of the casting guard (`common.schedule_command_removal` / `common.process_scheduled_removal`), since the normal action pipeline is suppressed mid-cast.

- **Ninja Cast with 1 Shadow mode**: New per-Ninja toggle (checkbox beside **Debug Mode** in `/sk panel`, persisted in `settings_ninja.json`). Utsusemi normally blocks while ANY Copy Image buff is up (66 / 444 / 445 / 446). When on, Ichi / Ni recast once you are down to the 1-shadow buff (66) — still blocked at 2+ shadows — and `/debuff 66` is issued ~1 second into the cast so the lingering shadow clears and the fresh set applies. **Requires the Debuff addon by atom0s (`/debuff`).** Shares the mid-cast removal scheduler with Bard fast-casting; the per-tier ignore/strip buff is set via a new `one_shadow_buff` ability field.

- **Damage-immune trusts excluded from support**: Trusts that can't take damage — **Moogle**, **Sakura**, **Kupofried**, **Star Sibyl**, **Brygid**, **Cornelia** — are skipped by **Heal**, **AOE Heal**, **Debuff Removal**, and **Buff** (no point curing/buffing a target at permanent full HP). These trusts only ever appear as party members, so their **P1–P5** buttons in those config sections render grayed and click-locked, with a *"Trust cannot take any damage"* tooltip. Backed by `common.is_trust_excluded(name)` (a fixed name list), checked in the heal / status-removal / buff action modules and in `render_party_buttons` / `render_heal_group_selection`.

- **Geomancer Geo-bt combat-end timer**: New **Timer (seconds)** slider in the **Geo** config section (1-20, default 5, `geo_bt_timer`), below **Distance (yalms)**. After the Geo-bt battle target dies, Full Circle now waits this many seconds before dismissing the debuff luopan; if a fresh battle target appears in that window the luopan is kept and the next Geo-bt reuses it, instead of Full Circling and recasting on every pull. The countdown (`geo_bt_end_time` in `geo.lua`) resets the moment a battle target reappears.

- **Prerequisite-buff spells shown grayed**: Spells with a `requires_buff` prerequisite now render grayed in the config UI (like an unlearned spell) with a *"Prerequisite buff not active"* tooltip when that buff isn't up, instead of appearing freely available. The checkbox stays selectable, so the user can enable them ahead of time; automation still waits for the buff. Subjob-supplied copies drop the requirement: when a subjob learns the same spell without it, the merge clears `requires_buff`, gated on the subjob being high enough to actually cast it. Backed by `requires_buff_unmet` in the row renderers and the level-gated `requires_buff` clearing in `merge_abilities`.

- **Per-status opt-out for multi-status debuff removers**: Multi-status removers (Erase, Esuna, Cursna, Viruna, Healing Waltz, Chakra…) now expose a **Remove:** list in their right-click menu — one checkbox per status the ability can strip, all enabled by default. Unchecking a status drops it from that remover's effective removal list, so the automation won't target a member (or count them for target selection) solely because they carry a disabled status. Backed by a new `common.effective_debuff_ids(ability, settings)` that filters `debuff_id` against `skip_debuff_<AbilityName>_<id>` settings keys (single-id / nil / all-enabled removers pass through unchanged; a fully-disabled remover resolves to `{}`, i.e. removes nothing). Status labels come from the new `common.DEBUFF_NAMES` table. Only affects targeting — when Erase/Waltz actually fires with a mix of enabled and disabled statuses present, the game still picks which one is stripped.

### Changed
- **No abilities fire while moving**: Sidekick now blocks all player actions while the moving, not just spell casts, so movement no longer causes interrupted or partially-started support actions.

### Fixed
- **Red Mage Composure now casts**: Composure's `id` (recast id) was `247`, another ability's timer, so the recast check read the wrong cooldown and Composure never auto-fired. Corrected to `50`.

- **Geomancer Indi/Geo MP costs corrected**: Many Indi, Geo, and Geo-bt spell `cost` values came from retail rather than CatsEyeXI's `spell_list` `mpCost`, so Sidekick could skip a spell it could actually afford or attempt one it couldn't. All geomancy costs now match the server (`spell_list.sql`).

- **Scholar / Geomancer MP recovery threshold**: Both jobs read the self-MP recovery cutoff from `recover_mp_threshold`, but Scholar defaulted the unused `recover_threshold` key (and Geomancer set none), so their MP-recovery abilities (Sublimation / Radial Arcana / the new Aspir) never auto-fired until the config slider was dragged. Scholar now defaults `recover_mp_threshold = 50` and Geomancer `recover_mp_threshold = 30`.

- **Job default settings scrubbed for errors**: Red Mage defaulted an unused `recover_threshold` key instead of `recover_mp_threshold`, so **Convert** never auto-fired until the config slider was dragged. Every job's `default_settings` was then checked against the keys the action modules actually read.

- **Geo-bt luopan no longer Full Circled the instant it lands**: When a Geo-bt debuff (e.g. Geo-Frailty) was cast, `geo_bt_pending` was set immediately but the luopan entity registers a moment after the cast completes. In that gap `common.targets.get_pet()` returns nil, so the "luopan gone" check cleared `geo_bt_pending`; when the luopan then spawned, the "take over a non-debuff luopan" branch saw an unowned luopan in combat and Full Circled it right away — wasting the cast. The cast is now marked with `geo_bt_cast_time` and the ownership flag isn't cleared during the post-cast spawn window (8s grace), so the freshly-landed luopan is recognized as ours.

- **Bard Mazurka songs now respect Pianissimo**: Chocobo Mazurka and Raptor Mazurka were missing `target_modifier = true`, so single-target (`ME` / `P1`-`P5`) casts skipped the Pianissimo precast — the song fired area-only from the caster, so `ME` cast without Pianissimo and the party-target buttons did nothing. Both now carry the flag like every other song.

- **Level-synced Bard songs no longer lock the song slots**: A song selected at a higher level stays selected after a level-sync down, but its row drops off the config UI (not castable), so it couldn't be turned off — and it kept holding one of the 2 main / 1 sub song slots, blocking the player from picking songs they *can* sing. The config window now deselects any song the player can't currently sing (across every target slot — `A` / `ME` / `P1`-`P5` / tracked) on render, freeing the slots. Songs must be re-selected after leveling back up. This applies only to songs, which have a slot limit; stratagem / Nether Void / Diffusion assignments have no limit, so an out-of-range pick is left dormant and re-activates on level-up (matching general buffs). Implemented as `ui_components.disable_uncastable_songs`, called from `ui_config.render`.

- **`/anon` no longer stops automation**: `common.get_player_job` now reads main/sub job straight from `AshitaCore:GetMemoryManager():GetPlayer()` (`GetMainJob`/`GetSubJob`) instead of the party manager (`GetMemberMainJob(0)`), which reports the player's main job as 0 while `/anon` is active — leaving no job definition loaded and automation silently doing nothing. The Player struct reports the real job regardless of `/anon`. The party route was originally used for packet sync during zoning, but Sidekick's tick loop is guarded off while loading, so that lag window never applied.

- **Haste duration on low-level tracked targets**: Haste's base duration was tracked as a flat 180s for everyone, but on CatsEyeXI it lands shorter on players below level 40. `common.base_buff_duration` now scales the Haste timer by the tracked target's `/check`-resolved level (linear `4.5667 * Level - 2.67`, verified lv10=43s / lv40=180s); level 40+ keeps the flat 180.

### [2.3.1] - 2026-07-13

### Added
- **Dancer Curing Waltz IV**: Dancer's single-target Waltz tier now includes **Curing Waltz IV**, slotting above Curing Waltz III for higher-HP cures. Thanks to **Crobat** for reporting the bug.

## [2.3.0] - 2026-07-10

Rename to Sidekick, addon outgrew the old name Medic.  As it now supports a lot more than the healer/support type roles.

Adds **Chakra** to Monk (a self-cure that recovers HP and clears its own Poison / Blindness), four new self-support jobs (**Warrior**, **Dark Knight**, **Ranger**, **Thief**), and full support for **Blue Mage**.

### Added
- **Self-buff blocking (`blocked_by`)**: A new ability field naming buff id(s) that suppress the ability while active — distinct from `buff_id` (the buff the ability *grants*). Backed by `action_core.is_self_blocked` / `action_core.filter_self_buff_blocked`, wired into `buff.lua`, `heal.lua` (`execute` + `execute_aoe`), and `status_removal.lua` (debuff removal). On Dancer, **Saber Dance** (410) blocks all Waltzes (Curing/Divine/Healing) and **Fan Dance** (411) blocks all Sambas, so those stances are no longer interrupted by an automatic Waltz/Samba.
- **Thief (THF) support**: Self-only automation. Self-buffs **Conspirator**, **Assassin's Charge**, and **Feint** via job abilities — all combat-only.
- **Monk Chakra**: New self-only Chakra automation (recast id 15, level 35). Wired as both a `heal` action (self HP recovery, priority above buffs) and a `debuff_removal` action that strips **Poison** (3) and **Blindness** (5) from the Monk. Enabled by default (`heal_enabled` / `debuff_removal_enabled`).
- **Warrior (WAR) support**: Self-only automation. Self-buffs **Berserk**, **Defender**, **Warcry**, **Blood Rage**, **Aggressor**, **Retaliation**, and **Warrior's Charge** — all independent checkboxes. Note that Berserk/Defender cancel each other and Warcry/Blood Rage remove each other's effect, so only one of each pair should be enabled at a time.
- **Dark Knight (DRK) support**: Self-only automation. Self-buffs via job abilities (**Arcane Circle**, **Last Resort**, **Souleater**, **Consume Mana**, **Diabolic Eye**, **Scarlet Delirium**) and dark magic (**Dread Spikes**), plus the ten **Absorb** spells (Absorb-Attri/ACC/TP/STR/DEX/INT/AGI/VIT/CHR/MND) cast on the battle target — grouped as `absorb` (single spell selectable via dropdown) and automatically combat-only (`<bt>`). Attribute absorbs track the caster's boost effect so they aren't recast while the boost holds; Absorb-Attri (steals a random buff) and Absorb-TP (instant drain) leave no fixed effect and fire whenever their recast is up.
- **DRK Nether Void (N button)**: Nether Void (level 75 on CatsEyeXI, recast id 91, DRK main only) augments the next Absorb spell, stratagem-style. An **N** button in the Absorb row's leading slot (next to the ON/OFF button) opens a popup with **Enable** — automation fires Nether Void the tick before the selected Absorb (same follow-up lock as Scholar stratagems) — and **Hold for Nether Void** — ON skips the Absorb until Nether Void is ready; OFF (default) casts the Absorb without it when Nether Void is on cooldown. Backed by a new `recast_gate` stratagem field in `check_stratagem`: unlike Scholar's charge pool, a recast-gated stratagem is checked against its own JA recast timer (plus a level guard so a de-level can't loop an unusable JA); the hold checkbox reuses the existing `stratagem_hold` machinery. While the N column is on-screen, every other buff row draws one alignment spacer (same exactly-one-indent rule as the Scholar S / Bard `[A]` columns — on DRK/SCH in Light Arts a row gets the N button or the scholar element, never both), and Nether Void never appears in the Scholar S popup.
- **Ranger (RNG) support**: Self-only automation. Self-buffs **Sharpshot**, **Scavenge**, **Velocity Shot** (RNG-main only), **Unlimited Shot**, **Flashy Shot**, and **Stealth Shot**, plus **Bounty Shot** on the battle target (automatically combat-only). Scavenge and Bounty Shot leave no effect on the player, so they fire whenever their recast is up.
- **Blue Mage (BLU) support**: Full mage support. Single-target healing (**Pollen** self-only, **Wild Carrot** / **Magic Fruit** party-only — blue magic cures can't target outside the party), AOE healing (**Healing Breeze**), and self-buffs via blue magic (Cocoon, Metallic Body, Refueling, Feather Barrier, Memento Mori, Zephyr Mantle, Diamondhide, Warm-Up, Amplification, Saline Coat, Reactor Cool, Plasma Charge). `buff_id`s mirror the in-game overwrite rules so spells sharing an effect (e.g. Refueling / Animating Wail = Haste) don't reapply over each other.
- **BLU Unbridled Learning precast (`requires_precast`)**: The level-75 Unbridled Learning spells (Battery Charge, Animating Wail, Magic Barrier, Occultation, Orcish Counterstance, Barrier Tusk, Harden Shell, Pyric Bulwark, Carcharian Verve) carry `requires_precast = 'Unbridled Learning'`; a new `common.check_required_precast` fires the JA the tick before the spell (same follow-up lock as stratagems) and skips the spell while the JA is on cooldown. Never user-configured.
- **BLU Diffusion (D button)**: Diffusion (level 75 merit, BLU main; `ability_id` merit-gated like the DRK JAs) spreads the next blue buff to the party, reusing the `recast_gate` stratagem machinery introduced for DRK Nether Void. A **D** button in every blue buff row's leading slot (hidden on Diamondhide, which is already AOE via `no_diffusion`) opens a popup with **Enable** (fire Diffusion the tick before the buff) and **Hold for Diffusion** (ON holds the buff until Diffusion is ready; OFF, default, casts it self-only when Diffusion is on cooldown). `magic = 'blue'` keeps both Diffusion and Unbridled Learning out of the Scholar S popup.
- **BLU set-spell gating**: Blue magic that isn't in the player's currently-equipped set-spell list is grayed with a *"Blue Magic not currently equipped"* tooltip and dropped by automation (`common.is_blue_magic_unequipped`, read from `get_equipped_blue_spells`, checked in `filter_abilities_by_level`). The row stays selectable — Sidekick never equips spells for you.

### Fixed
- **Merit job abilities no longer fire before they're unlocked**: Automation used to attempt merit-unlocked JAs (e.g. DRK **Diabolic Eye**) the player hadn't bought yet, producing a command error every recast. Merit JAs now carry an `ability_id` (the raw abilities.sql id); `has_spell_learned` checks it via Ashita's `HasAbility(ability_id + 512)` the same way spells use `HasSpell`, the UI grays the row with the *Not Learned* tooltip (the Nether Void **N** button renders disabled the same way), and `check_stratagem` gates Nether Void itself. Tagged: Diabolic Eye, Scarlet Delirium, Nether Void (DRK); Warrior's Charge, Blood Rage (WAR); Flashy Shot, Stealth Shot (RNG); Sange (NIN); Saber Dance, Fan Dance, No Foot Rise, Presto (DNC); Martyr, Devotion (WHM).
- **Unlearned spells no longer attempted by automation**: `filter_abilities_by_level` now drops any ability `has_spell_learned` rejects. Previously only the UI and the Geo module checked it, so automation could try casting a spell whose scroll was never learned (same command-error loop as the merit JAs).

## [2.2.0] - 2026-07-06

Adds three pet-support jobs (Beastmaster, Dragoon, Puppetmaster) with consumable-ammo auto-equip and packet-based pet status tracking, three self-support jobs (Monk, Samurai, Ninja — Ninja adds an inventory-based Ninjutsu-tool gate), and a right-click Idle Only ability toggle; generalizes Trust/tracked buff tracking into a timed-expiry system with base durations (extended to debuffs and to alliance members / the pet), adds per-caster song slots, and stops removal spells and cure-wake from looping on targets whose buffs can't be read from memory, and reworks debuff-removal priority (targeted na-spells before Erase, group-AOE Esuna) — alongside a repo-wide dead-code sweep and UI polish.

### Added
- **Idle Only ability toggle**: The right-click ability menu now offers an **Idle Only** checkbox alongside **Combat Only** — the ability only fires out of combat (e.g. Monk **Boost** on cooldown while idle). The two are mutually exclusive (checking one clears the other). Persisted per ability/group (`idle_only_<name>`/`idle_only_group_<group>`) via new `common.is_ability_idle_only`; statically `idle_only` abilities (WHM/SCH refresh-buffs) and `<bt>` abilities still suppress the menu.
- **Timed buff expiry for Trusts & tracked targets**: Trusts and tracked targets get no reliable wear-off packets, so tracked buffs now record a start time and base duration on application and are dropped by timer once elapsed (generalizing the BST Reward `reapply_interval` idea). Base durations: Haste/Flurry 180s, Refresh 150s, Regen 75s / II–III 60s, Phalanx II 120s, Protect/Shell all tiers 1800s, all bard songs 120s. Buffs without a known duration keep the old packet-only behavior; re-application refreshes the timer.
- **Debuff base durations (timed backstop)**: Packet-detected debuffs that a Sidekick ability can remove now record a base duration so a missed removal packet can't keep the tracked status alive forever. Any erasable debuff defaults to 120s (Poison/Paralyze/Blind/Silence/Dia/Bio); the explicit table covers only what that misses — Sleep 90s, Petrify 60s, Doom 30s (non-erasable but removable), Bind 60s / Gravity 90s / Slow 180s (accurate non-120 durations), and Curse/Bane/Disease/Plague (never time out). Debuffs nothing strips (Stun/Amnesia/Addle/Terror) are excluded — no remover, no loop to guard.
- **Timed expiry now covers alliance members & the pet**: `expire_timed_buffs` previously ran only for Trusts and tracked targets. Alliance members and the pet are also read from the packet-tracked `trust_buffs` (never from memory), so they now get the same timer backstop for both buffs and debuffs. Regular party members (read from memory) are still skipped.
- **Per-caster song slot eviction**: Song slots are tracked per caster (2 per bard per target, mirroring FFXI). Each tracked buff records its caster (from the 0x028 action packet). When a new song lands from a caster who already has 2 songs on that target, that caster's oldest-start-time song is evicted; songs from a different bard sit in their own slot bucket and are never affected. Applies to any tracked ally (Trusts, tracked players, alliance members); skipped when the caster is unknown (0x029 packets carry no caster).
- **Beastmaster (BST) support**: Pet-only automation. Pet healing via **Reward** (gated on a **Pet Food** biscuit worn in the ammo slot), a **Reward (Regen)** buff variant using a **Pet Poultice**, **Reward (Erase)** pet debuff removal using a **Pet Roborant**, and party AOE heal **Wild Carrot** from a rabbit jug pet (Keeneared Steffi / Rabbit), gated on 2 spare Ready charges (its cost). Only one ammo can be worn at a time, so the biscuit / poultice / roborant Rewards never contend for the slot on the same tick.
- **Dragoon (DRG) support**: Pet-only automation. Pet (wyvern) healing via **Spirit Link** (transfers the master's HP), plus self-buffs **Ancient Circle** and **Spirit Bond**.
- **Monk (MNK) support**: Self-only automation. Self-buffs **Boost**, **Dodge**, **Focus**, **Counterstance**, and **Footwork** — all independent job abilities (no mutually exclusive stances, so nothing is grouped).
- **Samurai (SAM) support**: Self-only automation. Self-buffs **Warding Circle**, **Third Eye**, and the **Hasso**/**Seigan** stance (grouped as `sam_stance`, so only the selected stance is maintained — they're mutually exclusive in FFXI), plus TP recovery via **Meditate** (`recover_tp`, fires below the TP threshold; default 1000).
- **Puppetmaster (PUP) support**: Pet-only automation. Automaton healing via **Repair** and automaton debuff removal via **Maintenance**, both gated on an **Automaton Oil** worn in the ammo slot (higher tiers heal more). Oils can only be equipped with PUP as **main** job (`ammo_main_job_only`), so auto-equip is skipped when PUP is the subjob.
- **Ninja (NIN) support**: Self-buff automation. Ninjutsu stances **Yonin**/**Innin** (grouped `nin_stance`, mutually exclusive), **Utsusemi** (shadows, Ichi/Ni grouped) and the idle-only **Tonko** (movement, grouped) / **Monomi** (Sneak) utility spells, plus **Sange** (throws a shuriken). Ninjutsu spells gate on their **tool in inventory** (new `requires_item`, below); Sange gates on a **shuriken equipped in the ammo slot** (`requires_equipped_ammo`, auto-equipped like BST food / PUP oil, NIN-main-only).
- **Inventory-tool gating (`requires_item`)**: New consumable gate for abilities that spend an item held **in inventory** (not worn) — Ninjutsu tools. `requires_item` lists the spell's family tool plus **Shikanofuda** (2972, the universal substitute); `common.count_equippable_items` sums both and `find_equippable_item` gates the spell out at zero. Distinct from `requires_equipped_ammo` (ammo-slot item + auto-equip): a tool is consumed from the bag, never equipped. The UI draws an inline green/red `(N)` count and grays the row (with a *"No `<tool>` or Shikanofuda in inventory."* tooltip) at zero, locking its ON/OFF toggle off.
- **Consumable-Ammo Gating & Auto-Equip**: Abilities can require a consumable equipped in the ammo slot (`requires_equipped_ammo`). When a usable tier is owned but not worn, Sidekick issues a `/equip ammo` for the best tier the player's **main** level allows — searching main inventory and all eight Mog Wardrobes — the tick before the ability fires. If none are owned the ability is gated out (effectively disabled). New `common` helpers: `count_equippable_items`, `get_equipped_item_id`, `is_ammo_equipped`, `find_equippable_item`, `select_ammo_equip_command`, `ammo_equip_command`.
- **Pet Status Tracking (packet-based)**: The client keeps no pet buff memory, so a pet's buffs/debuffs are now inferred from the same 0x028/0x029 packets used for Trusts and routed into `trust_buffs`, keyed by the pet's server id (refreshed each tick). Exposed as `game_state.pet_debuffs`; the tracked list is dropped when the pet is swapped or released so no stale status lingers. New helpers `common.is_pet`, `common.apply_pet_buff`. As with Trusts, this tracking is inferred and not perfectly reliable.
- **Pet Debuff Removal**: New `pet_debuff_removal` action type (`status_removal.execute_pet_debuff_removal`) strips status ailments from the pet — BST Reward + Pet Roborant, PUP Maintenance + Oil — using the packet-tracked `game_state.pet_debuffs` list. Rendered as its own collapsible config section with an inline ammo count and an *"unreliable tracking"* warning tooltip.
- **Beastmaster Ready Charges**: Ready is a charge system (recast id 102; 3 charges, 30s each) like Scholar stratagems. The stratagem charge math was generalized into a shared `charges_from_recast` helper now driving both. Surfaced as `game_state.ready_charges` and shown in the `/sk panel` header next to the stratagem counter. Abilities gate on it via `requires_ready_charge`, with `ready_charge_cost` (default 1) for multi-charge moves like Wild Carrot (2).
- **`requires_pet_name` (generalized pet-type gate)**: Replaces Summoner's `requires_carbuncle` with a list of acceptable pet names (`common.pet_type_ok`), shared by job validators and the config UI. Used by SMN (Carbuncle blood pacts) and BST (rabbit-only Wild Carrot). The UI grays such rows and tooltips the required pet when the wrong pet is out.
- **Buff `reapply_interval`**: For buffs we can't detect on the target (e.g. pet Regen from Reward, which pet tracking can't see), the buff is reapplied on a fixed time interval since the last cast instead of every recast, so consumables aren't wasted.
- **Expanded item-based status removal**: The consumable-cure feature grew from 2 items to 9 — Antidote (Poison), Eye Drops (Blind), Echo Drops (Silence), Holy Water & Hallowed Water (Curse/Doom/Bane via `common.CURSE_DEBUFFS`), Tincture (Plague/Disease), Remedy Ointment & Remedy (Poison/Paralyze/Blind/Silence), Panacea (the stat-down family, the ≥128 tail of `ERASABLE_DEBUFFS`). Each `ITEM_REMOVALS` row now carries an `item_id` and a `buff_ids` list; dedicated single-cures are ordered before premium multi-cures so a cheap item wins (Antidote before Remedy for Poison). Only reliably-removed statuses are listed — Remedy omits Disease and Panacea omits Amnesia ("potentially" cures) so the item can't loop the stack on a debuff it won't clear. Gated by a master `item_removal_enabled` toggle plus per-item settings, and never fired while moving (`common.is_player_moving()`, same rule as casting).
- **CLAUDE.md**: Contributor / AI-assistant guidance doc (architecture map, in-game verification notes, conventions).

### Changed
- **Debuff removal prefers the specific remover**: The level-filtered removal list is now ranked (`removal_rank`) so a targeted na-spell — which strips the *exact* ailment — is tried before generic Erase, which strips a *random* erasable status. A member with Poison + an erasable status now clears Poison with Poisona this tick and the leftover with Erase next tick, instead of Erase possibly burning on Poison first. Ranking is targeted (0) < Erase / any wildcard remover (1) < the self-centered AOE / Esuna (2).
- **Esuna cast as a group AOE (was self-only)**: The old self-only Esuna pass — which fired whenever the *player alone* had an Esuna-removable ailment — is replaced by a party/alliance-aware pass. Esuna now fires when **2+ members within its 10-yalm radius** (self + party + alliance) share an Esuna-removable ailment, clearing them in one cast; below that threshold single-target na-spells handle it (so a solo self-debuff now uses the cheaper na-spell). **Pets and tracked (Trust) targets are not inside the AOE** — they don't count toward the threshold and their tracking isn't dropped by it. On cast, one Esuna-removable status is dropped from each affected alliance member's tracked list (party/self refresh from memory). Esuna still fires as a single-target last resort for an Esuna-only ailment (e.g. status 21) nothing else covers.
- **Party Button Tooltips**: Hovering a party target button (**ME** / **P1–P5**) now shows that member's character name. On Trust/tracked buttons the reliability caveat (*"...Removal / Buff tracking is not totally reliable"*) is appended **below** the name instead of replacing it. Driven by `common.get_party_member_name()`.
- **"Not Learned" as Tooltip**: The inline ` (Not Learned)` label suffix on unlearned abilities was removed. Unlearned abilities now surface a **Not Learned** hover tooltip instead, alongside the existing Combat Only / Idle Only tooltips, for cleaner ability rows. Applies to `self_single_ability`, `party_single_ability`, and `ability_checkbox`.
- **Debug Scalars Moved to Panel**: The debug scalar readout (Zone / Target / Moving / Casting, plus the target's party slot + target index when the target is a party member) moved out of the configuration window into the `/sk panel` debug header row. Shown only while Debug Mode is on.
- **Bard Area-Column Alignment**: Row leading-slot rendering unified behind a new `job_def.has_songs` flag (set during job load when either job carries song magic) and a single `render_leading_slot` helper. A BRD/SCH combo now draws exactly **one** indent instead of stacking the Scholar S-button spacer and the Bard `[A]` area-column indent.
- **Item removal matched by item ID**: Inventory counts and the `/item` command now key off item ID instead of the English item name (`get_item_count(item_id)`; the `/item` name is resolved from `GetItemById(id).Name[1]`, falling back to the label). Custom-server items whose resource name doesn't match the English string (Remedy Ointment, Hallowed Water, Tincture) previously showed `?` and never fired; they now resolve correctly.
- **Item removal grouped under one header**: The bare Echo Drops / Holy Water checkboxes moved into a collapsing **Item Debuff Removal** section (like Debuff/Sleep/Pet Debuff Removal), rendering one checkbox per item with a live count via `item_removal_checkboxes`. The whole section stays hidden until inventory is readable (`item.inventory_loaded` / `ui.item_inventory_loaded`): a still-loading `?` count hides it, a real 0 shows it.
- **Status-removal section order**: Config now lists **Sleep → Debuff → Pet Debuff → Item Debuff Removal**.
- **Cursna shares `common.CURSE_DEBUFFS`**: Curse/Doom/Bane (9, 15, 20, 30) is defined once and used by both Cursna and Holy/Hallowed Water.
- **Ammo-count colors**: The `(n)` after ammo-gated rows (e.g. Repair Oil) reuses the current-job green when equipped and the automation-stopped red when not, dropping the one-off color literals.

### Fixed
- **Removal spells no longer loop on Trusts/tracked/alliance/pet targets**: These targets give no reliable wear-off packet, so after Sidekick cast e.g. Poisona the tracked Poison lingered and the cure re-fired every tick. On casting a na-/Erase spell — and now on a pet Reward/Maintenance strip too — Sidekick optimistically drops one matching status from the target's tracked list (`common.drop_removed_debuff`); each removal spell clears one status per cast, and the debuff base-duration timer catches anything guessed wrong. A pet carrying several erasable statuses just gets one dropped per cast; which one wears isn't important since more casts strip the rest.
- **Cure-wake now clears Sleep on Trusts & alliance too**: The "cure landed → drop Sleep from tracking" inference previously ran for tracked targets only, so waking a Trust or alliance member with a Cure left Sleep in tracking and re-cured every tick until the timer cleared it. Widened to every packet-tracked ally (Trust/tracked/alliance/pet).
- **Afflatus Solace Recast ID**: Corrected recast id from `245` to `29` (White Mage) so its cooldown gate reads the right timer.
- **Consumable checkbox click-locked at zero**: A consumable-gated `ability_checkbox` (e.g. pet-debuff-removal rows) with none of the item owned now renders unchecked **and** ignores clicks, so it can't be turned on while unusable. Non-destructive — the saved setting is untouched and restores once the item is back.
- **Auto-equip no longer needs a pet to reach buff ammo**: `buff.execute` dropped its `get_pet()` gate before `ammo_equip_command`; the skip now lives in `ammo_equip_command`, which only bypasses a **pet-only** ammo (BST poultice) when no pet is out. Lets a pet-less job (NIN Sange → Shuriken) share the same auto-equip path.
- **Wild Carrot rabbit pet name**: Corrected the accepted BST jug-pet name to **KeenearedSteffi** (was `Lucky Lulush`) so Wild Carrot's `requires_pet_name` gate matches the real pet.

### Removed
- **`sidekick_heartbeat.log`**: Stray committed log file removed from the repo.

### Internal / Maintenance
- Repo-wide dead-code sweep across `common.lua`, `action_core.lua`, `automation.lua`, `parse_packets.lua`, `config.lua`, `components.lua`, and every `lib/jobs/*.lua`: removed unused functions, write-only state, dead fallbacks, commented-out blocks, and unused exports/fields (~480 lines net removed). No functional change intended.
  - Deleted the unused custom-recast subsystem (`get_ability_recast`, `set/is/get/clear_custom_recast`) from `action_core`.
  - Dropped the dead throttle API and a duplicate require/table from `automation`.
  - Replaced hand-rolled buff scans with `action_core.has_any_buff` in the action modules.
  - Dropped unused `UserIndex` / `SpellGroup` / message fields from `parse_packets`.
- `ARCHITECTURE.md` updated to drop the removed `action_core` recast helpers.

## [2.1.0] - 2026-07-05

### Added
- **Group / AOE Heal Target Selection**: Group healing and AOE healing now have per-target selection buttons (ME / P1-P5, plus alliance B/C and tracked targets for Group healing) rendered under the threshold slider as **Group Targets** / **AOE Targets**. Deselecting a member excludes them from the scan (single-target Group healing) or from the below-threshold average (AOE). Defaults are asymmetric so behavior is correct even when the config window is never opened: party and tracked members are **ON** by default; alliance (B/C) members are **OFF** by default. AOE selection lists ME and party members only (Curaga-style AOE is party-scoped). Selections are **per-session** and reset on each load. Backed by session-only state in `ctx.party_buffs['heal_group' / 'heal_aoe_group']`, read by `heal.lua` via `make_group_filter()`.
- **Bard Area Songs (`[A]` button)**: Every Bard song now has an **A** button in the leading slot, left of the ME/P1-P5 target buttons. It sings the song **without Pianissimo** so everyone within the song's AoE (10 yalms) receives it. The area recast tracks only in-range, same-zone party members who are **not** given a specific ME/P button, so dedicated single-target songs don't trigger an endless area recast. Trusts are skipped for recast timing (their buff tracking is unreliable) but are still covered by the AoE cast. Mazurka (no Pianissimo) is always area.
- **Single-Target Self Songs via Pianissimo**: The **ME** button for Bard songs now uses Pianissimo, so a Bard can single-target buff themselves the same way as P1-P5. The ME button requires Pianissimo to be available (below its level the `[A]` area button still works).
- **Stacking Same-`buff_id` Songs (Ungroup)**: A grouped buff can be **ungrouped** via right-click, casting every tier in the group independently instead of only the single selected tier. Enables e.g. Mage's Ballad + Mage's Ballad II (both `buff_id` 196) on the same target simultaneously. Song-needed logic counts active buff instances (`count_instances` / `wanted_instances`) so stacked tiers each demand their own instance. Persisted per group as `ungrouped_<group>` (off / grouped by default).
- **Hold for Stratagem**: New checkbox in the Scholar stratagem assignment popup. When **ON**, the spell is skipped until an assigned stratagem can fire (enough charges, correct Arts, not status-blocked). When **OFF** (default), a stratagem that can't fire falls through and the spell casts **without** it, rather than blocking the cast. Persisted per ability/group key as `stratagem_hold[<key>]`.
- **Debug Mode in Panel Header**: The **Debug Mode** checkbox now lives in the debug panel header row (next to the Stratagems counter), moved out of the configuration window.

### Changed
- **Automatic Config Window Sizing**: The configuration window now uses imgui `AlwaysAutoResize` instead of a manually computed fixed width, so it grows/shrinks to fit its content (party size, alliance, tracked targets, new buttons). Opening the window force-expands it once, so a collapsed `imgui.ini` state no longer leaves the user staring at an empty title bar. A mere collapse now keeps the window open; only the `[X]` closes it.
- **Debug Mode Location**: The Debug Mode toggle moved from the bottom of the configuration window to the `/sk panel` header.
- **Stratagem Tooltips**: Added hover help for the Scholar stratagem button and the Hold for Stratagem checkbox.
- **Trust Buff-Tracking Warning**: Trust/tracked buttons in the Buff section now show a *"Trust/Tracked Buff tracking is not totally reliable"* tooltip (distinct from the removal-section warning), driven by a new `ctx.show_buff_warning` flag.
- **Focus / Group threshold labels**: Slider labels shortened (`Focus Healing (HP%)` → `Focus (HP%)`).

### Fixed
- **`HasSpell` Check**: `common.has_spell_learned()` no longer treats an unlearned spell as learned. Previously `ok and known or true` returned `true` whenever `known` was `false` (unlearned), so unavailable spells were wrongly considered known. Now only a `pcall` **error** assumes known.
- **Stratagem Stuck from High-Level SCH**: A stratagem assigned on a high-level Scholar main job carried over into `stratagem_settings` when the player switched to a lower level or `???/SCH`, leaving automation trying to fire a JA the player couldn't use and the config un-removable. `common.prune_unavailable_stratagems()` (called on job/level change from `Sidekick.lua`) now drops any assigned stratagem above the current SCH level, bailing on a transient level-0 read so config is never wiped during zoning.
- **Geo-bt UI Alignment**: Geo-bt debuff rows no longer receive the Scholar stratagem spacer indent (the Geo section has no S-button rows to align with). Bard song rows likewise skip the stratagem spacer because the `[A]` button already supplies the leading indent, preventing a double indent.
- **Song 2-Limit**: Song-slot counting now keys on `magic == 'song'` (recognizing both grouped and ungrouped song config keys via `is_song_config_key`) instead of `target_modifier`, so the per-member song limit (2 main / 1 sub) is enforced correctly, including Mazurka (which has no Pianissimo).

## [2.0.0] - 2026-03-04

### BREAKING CHANGES
- **PL Mode Removed**: All PL Mode functionality (`pl_mode_active`, `setup_pl_mode_job`, `clear_player_data`, `restore_normal_mode`, and related settings) has been removed. Users should clear any legacy `pl_*` settings keys from their configuration files.
- **Module Consolidation**: `heal_aoe.lua`, `heal_pet.lua`, `debuff_removal.lua`, and `wake.lua` have been merged into `heal.lua` and `status_removal.lua` respectively. Direct imports of the old modules will fail.
- **Config UI Renamed**: `config_ui.lua` renamed to `ui_config.lua`. Any external references must be updated.

### Added
- **Revive / Raise System**: New `lib/actions/revive.lua` action module automatically raises dead party members, tracked targets, and alliance sub-party members. Filters abilities by level, recast readiness, `requires_buff` prerequisites (e.g., Scholar's Raise spells require Addendum: White), and range before casting. Falls back through all usable abilities if the preferred spell cannot be built. Controlled by `settings.revive_enabled`. Job definitions for White Mage (Raise/Raise II/Arise), Scholar (Raise/Raise II), and Red Mage (Raise) include `revive` ability blocks.
- **Mount Detection**: `common.is_mounted()` returns `true` when the player is riding a mount, detected via entity status 5 OR buff 252 (Mounted) as a dual safeguard. Synced once per tick inside `refresh_game_state()` from the player snapshot. `automation_tick()` returns early when mounted, suppressing all automation while riding.
- **Alliance Support**: Healing, debuff removal, wake, and buff automation extended to alliance sub-parties B and C (flat indices 6–17). Requires abilities with `target_outside = true`. `game_state.alliance[2|3]` snapshots are built each tick alongside `alliance_leaders` and `alliance_member_sids` for packet-based buff tracking. Alliance members dropped from the roster have their stale `trust_buffs` entries purged automatically.
- **Alliance UI**: Per-member buff-toggle buttons (`<B0>`–`<B5>`, `<C0>`–`<C5>`) rendered in the configuration window; alliance sub-parties displayed in the debug panel with HP, MP, TP, job, buffs, party leader (`^`), and Trust NPC (`*`) indicators. Alliance members are excluded from the tracked-target add list.
- **HP Estimation for Tracked Targets**: On add, a `/check <name>` command is issued; the 0x0C9 check-response packet resolves the target's level. A built-in `AVERAGE_HP_BY_LEVEL` table (levels 1–75) is used to seed `max_hp` before the target is ever seen at 100%, enabling accurate deficit-based healing from the first heal.
- **`requires_no_buff` Ability Flag**: Buff abilities can specify `requires_no_buff = <id or table>`. The ability is skipped while any of the listed buffs are active on the player. Used for mutually exclusive stances (e.g., Saber Dance vs. Fan Dance).
- **Dancer Level-75 Abilities**: Added Saber Dance, Fan Dance, No Foot Rise, and Presto to the Dancer job definition. Saber Dance and Fan Dance share a `dance` group and use `requires_no_buff` to prevent both being active simultaneously.
- **`common.get_alliance_count()`**: Centralized helper returning the total number of active alliance members across sub-parties B and C.
- **`common.sorted_alliance_members(sub_party)`**: Returns sub-party members sorted by local slot index (0–5). Replaces inline sort logic previously duplicated across `panel.lua`, `config.lua`, and `components.lua`.
- **`common.apply_external_buff(server_id, buff_id)`**: Shared dedup-insert helper used by both `apply_alliance_member_buff` and `apply_tracked_target_buff`, replacing duplicated implementations.
- **`game_state.alliance_size`**: Separate counter for active alliance members only; `party_size` now counts main-party members (indices 0–5) only.
- **Centralized Game State**: New `common.game_state` snapshot refreshed once per automation tick provides a consistent view of player/party HP, MP, buffs, and positions.
- **Action Core Module**: New `lib/core/action_core.lua` consolidates resource management, cooldown tracking, buff-ID utilities, and ability candidacy helpers (replacing deleted `lib/core/resource.lua`).
- **Packet-Based Buff Tracking**: Buff gain/loss tracking via 0x028 and 0x029 packets for Trusts and tracked (out-of-party) targets.
- **Tracked Targets**: Session-scoped tracking of out-of-party players for heal, buff, and status removal automation.
- **Debug Panel**: New `lib/ui/panel.lua` debug info panel showing party game_state snapshot (toggle with `/sidekick panel`).
- **Status Removal Module**: New combined `lib/actions/status_removal.lua` with `execute_debuff_removal` and `execute_wake` entry points.
- **Geomancer Geo Targeting**: The `<me>` Geo buff spells now target a single party member (`group = 'Geo'`, `exclusive_target = true`), cast through the same ME/P1-P5 button targeting as other party buffs. Selecting a target deselects the others (single-select, handled by `toggle_group_party_buff` in `components.lua`). `common.get_pet_distance_from_member(party_index)` measures luopan drift from the selected target; distance-based Full Circle is skipped when no Geo target is selected.
- **Geomancer Geo Debuffs (Geo-bt)**: New `<bt>` enemy-target debuff spells (Geo-Vex, Geo-Frailty, Geo-Paralysis, Geo-Languor, Geo-Slip, Geo-Torpor, Geo-Slow, Geo-Poison) in `abilities.geo` with `group = 'Geo-bt'`. Combat-only (enforced by `common.is_ability_combat_only` for any `<bt>` ability; the right-click Combat Only toggle is suppressed). Rendered under **Enable Geo** as an ON/OFF + dropdown (`selected_Geo-bt`). Casting and luopan lifecycle live in `geo.lua`, not `buff.lua`.
- **Single Luopan Lifecycle**: `geo.lua` tracks luopan ownership with a `geo_bt_pending` flag. In combat the selected Geo debuff takes over the single luopan (Full Circle a non-debuff luopan, then cast); the distance-based Full Circle is suppressed while a debuff luopan is active so it isn't dismissed mid-fight. When combat ends, Full Circle frees the luopan so Geo buffs can be re-placed. Indi/Entrust do not use a luopan and are unaffected.
- **Configuration Tooltips**: Comprehensive contextual tooltips added across the configuration UI (`lib/ui/tooltips.lua`), explaining each section, slider, dropdown, button, and checkbox. Wired in via `ui.item_tooltip()` in `config.lua`/`components.lua`.

### Changed
- **`is_resting()` now cached**: `common.is_resting()` no longer calls `GetPlayerEntity()` on every invocation. The value is synced once per tick inside `refresh_game_state()` from the player's entity status (33 = resting), eliminating per-call overhead in the hot automation loop. Transient entity read failures do not clobber the cached value.
- **Revive priority above Buff**: In the `priority_order` for White Mage, Scholar, and Red Mage, `revive` is now listed before `buff`. Dead members are raised before living members receive buffs out-of-combat. No in-combat effect since all raise spells are `idle_only = true`.
- **Status labels in debug panel**: `fmt_status()` in `panel.lua` now maps common entity status integers to human-readable strings (`Idle`, `Engaged`, `Dead`, `Resting`, `Mounted`, `Sitting`) via a `STATUS_LABELS` table. Unknown codes still fall back to `tostring()`.
- **Config UI mounted state**: When `common.is_mounted()` is true the configuration window shows `Paused` button text and `Automation paused (mounted).` status text, distinct from the normal paused/resting states.
- **Heal AOE**: Merged into `heal.lua` as `execute_aoe`; requires at least 2 members below threshold before firing (hardcoded, previously configurable via slider).
- **Heal Pet**: Merged into `heal.lua` as `execute_pet`.
- **Recovery Priority**: Recovery actions (Convert, Manafont, etc.) execute before critical heals to ensure MP is available for subsequent healing.
- **Curaga II**: Fixed MP cost from 60 to 120 (White Mage).
- **Bar Spells**: Converted from dynamic-target functions to static self-target `<me>` commands (White Mage).
- **Attack Range Labels**: Attack Range options now display explicit distances — `Off`, `Melee (3 yalms)`, `Ranged (15 yalms)` (previously `Off`/`Melee`/`Ranged`).
- **Tracked Target Button**: The "Add Tracked Target" button is relabeled "Track Target".

### Removed
- **PL Mode**: All PL Mode functionality and UI elements.
- **lib/core/resource.lua**: Replaced by `action_core.lua`.
- **lib/actions/heal_aoe.lua**: Merged into `heal.lua`.
- **lib/actions/heal_pet.lua**: Merged into `heal.lua`.
- **lib/actions/debuff_removal.lua**: Merged into `status_removal.lua`.
- **lib/actions/wake.lua**: Merged into `status_removal.lua`.

## [1.3.0] - 2026-01-22

### Added
- **Contradance for Dancer**: Added Contradance to Dancer's critical abilities category for emergency situations
- **Pianissimo Support for Bard**: Bard songs can now be cast on party members using the Pianissimo ability (level 20+):
  - New `target_modifier` ability category for abilities that redirect self-targeted spells to party members
  - All Bard songs (except Mazurkas) flagged with `target_modifier = true` to indicate Pianissimo compatibility
  - Bard songs converted to function-based commands for dynamic targeting: `function(target) return '/ma "Song Name" '..target end`
  - Party buttons (P1-P5) automatically disabled when Pianissimo unavailable (below level 20 main/sub)
  - Grayed-out text and "(Pianissimo Lv20)" suffix displayed for songs requiring unavailable Pianissimo
  - Common `check_target_modifier()` helper function validates modifier availability (level, settings, blocks, resources, cooldown)
  - Integrated into buff.lua: checks `ability.target_modifier`, calls helper, uses modifier before casting party-targeted buff
- **Song Limit Enforcement**: Bard songs per party member limited based on job type to match game mechanics:
  - **Bard Main Job**: Maximum 2 songs per party member (including self)
  - **Bard Sub Job**: Maximum 1 song per party member (including self)
  - Auto-deselects existing song when limit reached before enabling new selection
  - Only applies to abilities with `target_modifier = true` flag
- **Party Buff Settings Persistence**: Party buff selections (song targets, etc.) now persist through addon reloads:
  - Settings saved to `settings.party_buffs[ability_name][party_index]` structure
  - Loaded on first UI render, similar to Entrust and Focus target persistence
  - Prevents loss of song configurations when reloading addon or changing zones

### Changed
- **Entrust Logic Refactored**: Geomancer Entrust now uses common `check_target_modifier()` helper for DRY code:
  - Removed ~40 lines of duplicated validation logic (level, settings, blocks, resources, cooldown)
  - Creates temporary job_def structure to present Entrust in target_modifier format
  - Calls centralized validation helper, maintains original dedicated UI for 10-minute cooldown
  - Preserves spell selection dropdown + target dropdown UX for infrequent single-use ability

### Technical
- Created `check_target_modifier()` in common.lua: validates target modifier ability availability and returns command to use it
- Function checks: buff already active, level requirement, disabled setting, status blocks, resource cost, ability cooldown
- Added `combat_only` check to `check_target_modifier()` validation flow
- Party buff toggle now saves selections to `settings.party_buffs` for persistence across sessions
- Config UI loads `settings.party_buffs` on first render to restore saved party buff selections
- Song limit logic in `toggle_party_buff()`: counts active songs with `target_modifier = true`, deselects when at limit
- Helper function `find_ability_by_name()` added to ui_components.lua for ability lookups
- Modified `render_party_buttons()` to accept ability object, check target_modifier availability, disable P1-P5 buttons when modifier unavailable
- Party buff rendering pushes LIGHT_GRAY text color for disabled modifier buttons (4 colors total vs 3 for normal disabled)

## [1.2.0] - 2026-01-18

### Added
- **Automatic Resting**: New rest action module for MP-based jobs automatically triggers `/heal on` when idle to recover MP:
  - **Two-Phase Timer**: Conditions become favorable → wait configurable timer duration (1-20s, default 5s) → start resting
  - **HP Threshold Safety**: Stops resting if any party member drops below threshold (1-99%, default 70%)
  - **Follow Target System**: Optional follow target selection (P1-P5) with distance monitoring (1-15 yalms, default 7)
  - **Smart Blocking**: Prevents resting when engaged, moving, casting, or when MP is full
  - **Priority**: Executes last in action priority order to allow healing/buffing to take precedence
  - Available for: White Mage, Scholar, Red Mage, Paladin, Geomancer, Bard, Rune Fencer, Summoner
- **Conditional Ability Conditions**: Two mutually exclusive conditions for conditional ability usage with color-coded UI indicators:
  - `idle_only` (green) - Only usable when not in combat (checks `is_idle()`)
  - `combat_only` (yellow) - Only usable when in combat with a battle target nearby (checks `is_combat()`); user-toggleable per ability/group via right-click
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
- **Config UI Refactored**: Reduced `ui_config.lua` from 1,758 lines to 876 lines (52% reduction) by extracting all rendering logic to `ui_components.lua`
- **Context Object Pattern**: UI components now use a context object `{settings, save_callback, party_buffs, job_def, ...}` for cleaner function signatures

### Technical
- Added `is_combat()` function to check for combat state (has battle target nearby)
- Updated `is_engaged()` function to check player status for active engagement (status == 1)
- `filter_abilities_by_level()` now checks `idle_only` and user-configured combat-only settings (`combat_only_*`) to conditionally filter abilities
- All UI components updated to display conditional flags with color coding: idle_only (green), combat_only (yellow)
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

- **Samurai** (SAM)
  - Self-buffs with job abilities (Warding Circle, Third Eye, Hasso/Seigan stance)
  - TP recovery with Meditate

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