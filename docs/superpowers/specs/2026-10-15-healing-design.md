# Healing overhaul: design

Status: implemented 2026-10-15 (build steps 1-4), untested in game; step 5, the in-game prior check, is still to do. Replaces the decision logic in `behaviors/heal.lua` and folds the unused `heal_aoe` role into it.

## Why

Today's heal picks "the biggest cure that doesn't overheal, else the smallest". It ignores MP cost, area heals (`heal_aoe` rows exist but nothing casts them), Regen, and the difference between "hurt" and "about to die". Critical HP fires whatever emergency abilities are listed, in list order.

## The idea in one line

Build one list of **candidates** (an action aimed at a centre, with the units it would cover), then let the **band** (how urgent things are) choose which units count and which **score** ranks the candidates.

- A single-target cure is just a candidate that covers one unit. Curaga covers everyone within its radius of the target. Regen is a candidate whose HP arrives over time.
- So "is Curaga worth it for these three?" and "is Regen better than Cure III here?" come out of the same arithmetic, not separate rules.

## Bands

| Band | Who is in it | Score used | Extras |
|---|---|---|---|
| Critical | `hpp < critical` (default 30) | Danger score, critical units only | Boosts (Divine Seal, Contradance, Rapture) and aimed saves (Martyr) first |
| Danger | `hpp < danger` (default 50, new setting) | Danger score | Holds for a heal that's nearly off recast |
| Efficient | `danger <= hpp`, anyone not at full HP | Efficient score | Regen allowed; Regen already ticking counts as healing on its way; nothing goes while every heal would overheal |

The focus target has its own two lines: `focus_critical` (default 40), `focus_danger` (60). There is no separate "heal under" line: everything over the danger line is Efficient.

Passes run worst band first. A pass that finds nothing usable falls through to the next one, so a unit out of reach never stalls healing for everyone else (same rule as today). A unit under its danger line that the Danger pass can't help isn't picked up by Efficient.

**Excluded units** (`heal.skip`, by name): in no band, and their useful HP counts zero, so nothing is cast for their sake. A Curaga aimed at others may still land on them. The window lists the party with a checkbox each.

## Candidates

For each enabled `heal` action that passes `can.use(a, g)`:

- **Centres:** you, for self-only actions (Healing Breeze, Chakra); otherwise each unit where `can.reach(a, u)` holds.
- **Covered:** if `a.area == 0`, the centre only. Otherwise every alive, in-zone party unit within `radius(a)` of the centre. This needs unit positions; see Snapshot. An area boost (Majesty, Accession; see Boosts) gives a single-target cure its `area` while the boost's status is on you.
- **Amount per covered unit:** `amount(a, g) = base * mult`:
  - `base` is `g.learned[a]` if this session has seen the action heal (see Learned potency), else `a.potency * (1 + gear% / 100)` (`cure_potency` for spells, `waltz_potency` for TP heals; this is today's rule; the server caps both at +50%, so the knobs clamp there), times 1.25 for healing magic, blue magic and waltzes (CatsEyeXI's `CURE_POWER`; the server applies it in `getCureFinal`'s callers and `useWaltzAbility`, not to Drain, Chakra or blood pacts).
  - Regen: `(tick + regen_potency) * floor(duration / 3)`, the total over its duration. No `mult`.
  - `mult` is the product of what's up at decision time (see Multipliers). It's 1 for anything they don't touch.
  - No potency and nothing learned (Vivacious Pulse, Mending Halation): used only in Danger or Critical, and only when no candidate with an amount exists. Today's "smallest" fallback plays the same part.
- **Need per unit:** `max_hp - hp`. In the Efficient band only, Regen still ticking on the unit is subtracted first.
- **Useful HP per unit:** `min(amount, need)`, or 0 for an excluded unit. Overheal earns nothing, so "don't overheal" falls out of the score instead of being a separate rule.

## Multipliers

"Healing magic" means skill 33 in the DAT: Cure and Curaga.

```lua
-- healing magic
mult = boost * (1 + sky)
-- TP heals (waltzes)
mult = boost
```

- `boost`: Divine Seal x2 and Rapture x1.5 on healing magic, Contradance x2 on waltzes, while the boost's status is on you. Divine Seal and Rapture both apply to the final amount.
- Majesty's `potency` isn't a factor: the server adds it beside gear (`1 + cure% + 0.25`). So the prior becomes `a.potency * (1 + (gear% + 25) / 100)`, and `mult` carries `(1 + (gear% + 25) / 100) / (1 + gear% / 100)` so learning stores the Majesty-free base.
- `sky`: the day and weather bonus, as the server rolls it (`xi.spells.damage.calculateDayAndWeather`). One cast in three applies day and weather together, bonus and penalty alike; the other two get nothing. So the score uses the expected value:

```lua
-- Your weather: Aurorastorm on you makes it Auras, or Stellar Glare if the zone
-- already has Auras or Stellar Glare. It overrides Gloom and Darkness too.
local w = g.weather
if aurorastorm then w = (w == AURAS or w == STELLAR) and STELLAR or AURAS end
sky = ((w == STELLAR and 0.25 or w == AURAS and 0.1 or 0)
     - (w == DARKNESS and 0.25 or w == GLOOM and 0.1 or 0)
     + (g.day == LIGHTSDAY and 0.1 or g.day == DARKSDAY and -0.1 or 0)) / 3
```

  Weather ids: 16 Auras, 17 Stellar Glare, 18 Gloom, 19 Darkness. Days: 6 Lightsday, 7 Darksday. The best case, Lightsday under Stellar Glare, is +11.7%; the worst, Darksday under Darkness, -11.7%.
- Aurorastorm has no factor of its own: the server only swaps your weather (`battleutils::GetWeather`).

## Scores

```lua
-- Efficient: HP that lands where it's needed, per share of what you have left.
-- Comparing shares instead of raw cost puts MP heals and TP heals (waltzes) on one scale.
-- TP at the 3000 cap is free: anything gained past it is lost anyway.
share = a.mp > 0 and a.mp / g.me.mp
     or a.tp > 0 and (g.me.tp >= 3000 and 0 or a.tp / g.me.tp)
     or 0
score = sum(useful_u for all covered u) / math.max(share, 1e-6)  -- free heals (Chakra) win outright
      * math.sqrt(helped)  -- helped: band members it covers whose useful_u > 0

-- Danger: HP% points restored to units in this band, per second you are locked out.
lockout = a.kind == 'ma' and (a.cast + SPELL_THROTTLE) or THROTTLE  -- 3.1s / 1.1s, from core/engine.lua
score = sum(useful_u / max_hp_u * 100 for covered u in the band) / lockout
```

- Efficient ranks resource efficiency in raw HP. Danger ranks speed in HP%, so a mage at 41% isn't always passed over for a tank at 49% just because the tank's deficit is bigger.
- Under the cap, TP is priced against what you have, so a /DNC's waltz loses Efficient to a cure until MP runs low (Curing Waltz II, 175 at 400 TP, scores 200 against Cure III's 4348 at 800 MP). At the cap one waltz goes out, TP drops to 2650 and cures take over again: waltzes spend only the TP that would overflow, and a weaponskill can still be saved for.
- Each member helped weighs in by its square root, a guess to tune in play: enough that one Curaga beats healing three people one at a time, not so much that it spends 180 MP to save one cast. Without it, a Regen II on one member ties Curaga III for four.
- Ties go to the cheaper candidate, then to the focus target.
- Danger counts only units in the band, so in the Critical pass a Curaga can't beat a Cure V by topping off people who aren't dying.

### Worked examples (WHM 75, table potencies x 1.25, no gear, no day or weather bonus)

These numbers are illustrations: the Curaga potency is a prior still to be checked in game.

**Efficient: one member of 1000 HP, at 70% (300 missing) or at 60% (400 missing).**

| Candidate | MP | Useful at 70% | HP per MP | Useful at 60% | HP per MP |
|---|---|---|---|---|---|
| Regen II (240 total) | 36 | 240 | **6.67** | not offered | |
| Regen III (400 total) | 64 | not offered | | 400 | **6.25** |
| Cure III (250) | 46 | 250 | 5.43 | 250 | 5.43 |
| Cure II (112) | 24 | 112 | 4.67 | 112 | 4.67 |
| Cure (37) | 8 | 37 | 4.63 | 37 | 4.63 |
| Cure IV (500) | 88 | 300 | 3.41 | 400 | 4.55 |
| Cure V (875) | 135 | 300 | 2.22 | 400 | 2.96 |

Each gap is offered the biggest Regen whose whole total lands: Regen II at 70%, Regen III at 60%, and either wins. Its HP is now on its way: at 60% that fills the member, who drops out of the Efficient band; at 70%, 60 HP is still missing, which a Cure (37) takes next. If more damage pushes them under 50%, the Danger band cures them anyway, because it ignores pending Regen. With 150 missing, Regen (125 of 150 for 15 MP, 8.3) beats Cure and Cure II (4.7); with 20 missing every heal would overheal, so nothing goes.

**Efficient: members bunched together, each 300 missing.** Curaga III at 337 each (270 x 1.25) gives 300 useful on each for 180 MP. For four: 1200 / 180 = 6.67, x sqrt 4 = 13.3, ahead of Regen II's 6.67 on any one of them. For three: 5 x sqrt 3 = 8.7, still ahead. For two: 3.33 x sqrt 2 = 4.7, so they're healed one at a time. Spread them past the radius and Curaga covers fewer people, so a single-target heal wins again. Nobody sets an "AoE threshold".

**Danger: one member at 45% of 1000 (550 missing), WHM/DNC with 400 TP.**

| Candidate | HP% points | Lockout | Points per second |
|---|---|---|---|
| Curing Waltz II (175) | 17.5 | 1.1s | **15.9** |
| Cure V (875) | 55 | 2.5 + 3.1s | 9.8 |
| Cure IV (500) | 50 | 5.6s | 8.9 |

The waltz goes out first because it's instant. On the next tick the member is at 62%, so the Efficient band takes over.

**Critical: one member at 20% of 1000 (800 missing), Divine Seal up.** Cure IV x2 = 1000 and Cure V x2 = 1750 are both capped at 800, so they tie on 80 points. The cheaper wins: Cure IV.

**Sky: the same member at 60%, Lightsday under Stellar Glare.** `sky` = (0.1 + 0.25) / 3 = 0.117, so Cure III's expected heal is 279 for 46 MP: 6.07 HP/MP. Regen gets no bonus and stays at 6.25, so Regen still wins. Even the best day and weather rarely tip a choice.

## Critical band

1. **A boost is already on you** (its status is up): the danger score, which now includes the boost factor, picks the heal that spends it.
2. **A factor boost is usable** (Divine Seal, Contradance, Rapture), and a heal of the kind it boosts has a usable candidate covering a critical unit: fire the boost (instant). The next tick lands in step 1. An area boost (Accession) fires only when its area candidate wins (see Boosts).
3. **Other emergencies** work as today: an aimed save (Martyr) on the critical unit, then the other self-only emergencies.
4. **Otherwise** run the danger score over critical units only.

## Boosts

Knowledge gains `boost = { kind, factor = 1, potency, area }`, where kind is `'healing'` (healing-magic skill 33: Cure, Curaga) or `'waltz'` (TP-cost heals). `factor` multiplies the amount and `potency` adds to the cure-potency sum (see Multipliers). `area` (yalms) makes a Cure an area candidate.

```lua
['Divine Seal'] = { role = 'emergency', boost = { 'healing', 2 } },
['Contradance'] = { role = 'emergency', boost = { 'waltz', 2 } },
['Rapture']     = { role = 'emergency', requires = LIGHT, boost = { 'healing', 1.5 } },
['Majesty']     = { role = 'buff', priority = 100, boost = { 'healing', potency = 25, area = 10 } },
['Accession']   = { role = 'emergency', requires = LIGHT, boost = { 'healing', area = 10, mp = 2, tiers = 4 } },
```

The catalog resolves the boost's status the same way it resolves a buff's status (named like the action). Both radii are the server's (`xi.combat.magicAoE.calculateTypeAndRadius`: 10y radial around the target).

- **Majesty (PLD)** is a `buff`: the buff behavior keeps it up (180s), and healing never fires it. While its status is on you, every Cure tier covers 10y, in every band. With Majesty up, Efficient picks an area Cure for a bunched group by the same arithmetic as Curaga. The server's effect (`scripts/effects/majesty.lua`) also adds 25 to `CURE_POTENCY_II`, which `getCureFinal` adds to the potency sum (capped at 30), so Cure and Curaga both heal more. It also cuts white magic recast by 25%, which the score doesn't see.
- **Accession (SCH)** is fired by healing, in Danger and Critical only. Efficient never spends a stratagem charge. In those bands, score each Cure I-IV candidate a second time as if Accession were up: it covers band units within `area`, its lockout adds `THROTTLE` for the JA, and `can.use` checks the doubled MP (`mp = 2`, `battleutils` cost). If that beats the best plain candidate, fire Accession; the next tick casts the cure with the status up (Critical step 1). One hurt unit never pays for it, because covering one unit scores the same and locks out longer.
  - `tiers = 4`: only spells flagged `RADIAL_ACCE` spread, which is Cure I-IV (v2's `ACCESSION_SPELL_IDS`, from `spell_list.sql`). Cure V stays single-target.
  - The server doubles that cure's recast (triples it on a /SCH), which the score doesn't see either.
  - A charge is spent whenever the score says so. Nothing else in v3 competes for charges yet (Addendum: White lasts hours), so there's no reserve; see Not in this design.
  - An Accession already up (raised by hand) counts like Majesty: the next Cure I-IV is scored as an area candidate.

## Regen

- **Values (CatsEyeXI):** 5 / 12 / 20 HP every 3s for Regen / II / III, over knowledge's existing 75 / 60 / 60s: 125 / 240 / 400 HP in total.
- **Two uses** in knowledge, so both features survive:
  - A `heal` use with `tick = { 5, 12, 20 }`. Healing decides when it's worth it. On each target, only the biggest tier whose whole total lands (total <= need) is a candidate, and none when even Regen I would overheal: 125-239 missing offers Regen, 240-399 Regen II, 400+ Regen III. Tiers can't simply compete: per MP the smallest always wins (Regen 8.3 HP/MP, II 6.67, III 6.25), so Efficient would put Regen I on everyone, and its status would keep a bigger Regen off for 75s.
  - The existing `buff` use, labelled `'Regen (keep up)'`, for "always keep Regen on the tank". It stays opt-in.
- **Efficient band only.** It's a candidate only if the target lacks the Regen status.
- **Gear:** `regen_potency` (new setting) adds HP per tick.
- **Pending:** when your own Regen lands (0x028, gain message, status Regen), record `{ sid, ends, per_tick }`. Pending HP = `per_tick * ticks left`. The Efficient band subtracts it from need; a unit whose `hp + pending` reaches full HP isn't in the band at all. Someone else's Regen blocks recasting (the status is up). Its timing is unknown, so it, and the GEO Regen aura, count as a whole Regen I still to come, 125 HP: a member missing 100 with it up isn't cured, one missing 300 is cured for the other 175.
- **Danger and Critical ignore pending.** HP over time doesn't save someone who's dying.

## Learned potency

Table potencies are caps; a leveling character with low MND heals well below them. Gear swaps (LuAshitacast cure sets) change potency at cast time. So learn the real numbers:

- `packets.lua` already parses 0x028 per-target messages. A result whose message is an HP recovery (below) carries the HP restored as its param. When the actor is you or your pet, report `(action, target sid, amount)`. The ids, from the server's scripts, `abilities.sql` / `pet_skills.sql` defaults and `messageutils.h` area variants:

| Actor, category | Heal | Primary | Others in the area |
|---|---|---|---|
| you, 4 (spell) | Cure, Curaga, blue cures | 7 | 263 (Curaga) |
| you, 6/14/15 (ability) | Curing Waltz, Divine Waltz, Chakra | 102 | 263 (Divine Waltz) |
| your pet, 13 (pet skill) | Healing Ruby / II | 318 / 263 | 263 |
| your pet, 11 (mob skill) | Wild Carrot | 238 | 238 |

  So the set is `{ 7, 24, 102, 238, 263, 318, 367 }` (24 and 367 are the other "recovers HP" area variants). The packet param is the spell id, ability id or pet skill id; for these three pet heals the pet skill id equals the Blood Pact / Ready ability id (512, 517, 735). Today's `HEALS_028` (which wakes a cured sleeper) becomes this set: it lacks Curaga's 263 now, and its 2 is a damage message, not a heal.
- At send time, store each unit's need and the `mult` in force. If `amount < need`, the heal wasn't capped by the target's max HP, so it's a real reading. Learn the base, not the boosted number, so a Divine Seal cure or a Lightsday cure doesn't inflate later ones: `r = amount / mult; learned = learned and (0.7 * learned + 0.3 * r) or r`. Ignore capped readings.
- The CatsEyeXI 1.25 and gear are already inside a reading, so they're applied to the table prior only. `mult` holds the expected `sky`, not the roll, so one reading can be 12% off either way; the EMA evens that out.
- Key by `kind .. id`. Keep it for the session only; table x gear is the prior until the first reading.
- The gear knobs (`cure_potency`, `waltz_potency`) then matter only before the first reading. Regen ticks never show in packets, so `regen_potency` stays the only Regen source.

## Snapshot and module changes

- `core/game.lua`, per unit:
  - `pos = { x, y, z }`, for area geometry.
  - `max_hp` falls back to `hp * 100 / hpp` when the unit has never been seen at 100%. Integer hpp makes this rough at low HP, but rough is good enough to score. Trusts included: the server's party list packet (`0x0dd_group_list.cpp`) carries a trust's real HP, so `party:GetMemberHP` reads it like a player's. v2 read every party slot the same way and cached max at 100%, but had no fallback: an unseen max meant a deficit of 0.
  - `hot` = pending Regen HP.
  - `game.recast` for the stratagem timer (recast 231) returns 0 while a charge is banked. Port v2's `STRATAGEM_TIERS` and `charges_from_recast` (`lib/core/common.lua`). Today the raw timer blocks every stratagem while any charge recharges; this fixes Addendum: White too.
  - Plus `g.learned`, `g.day` and `g.weather`. v2's `lib/core/vanadiel.lua` already reads both from FFXiMain.dll signatures; port those two readers. Aurorastorm and the boosts come from your own statuses, which the snapshot already has.
- **New `core/observed.lua`** (about 40 lines): learned potency plus your ticking Regens, fed by `packets.lua` and read by `game.read`. The engine still decides from the snapshot alone, so tests stay pure.
- `core/catalog.lua`: copy `cast` (seconds, DAT value / 4), `skill` (for "healing magic"), `tick` per tier, and `boost`.
- `core/knowledge.lua`:
  - `heal_aoe` becomes `heal`; the DAT `area` says whether it's an area heal.
  - Potency priors for Curaga I-IV, Divine Waltz, Healing Breeze, Healing Ruby I/II, Wild Carrot (pet).
  - `boost` fields (Majesty, and a new Accession entry) and Regen's two uses.
- `tools/parity.lua`: `ROLE.heal_aoe` becomes `'heal'`. v2's `heal_aoe|Accession` moves from `MODULE_OWNED` to `ACCEPTED`: v3 lists it as an emergency boost.
- `core/settings.lua`:
  - `heal = { on, danger = 50, critical = 30, focus, focus_danger = 60, focus_critical = 40, skip = { [name] = true }, cure_potency, waltz_potency, regen_potency }`.
  - `settings.key` becomes `a.pick_one or a.label or a.family`, so Regen's two uses (and Reward's three) get their own rows. `pick_one` stays first: Lasting Emanation and Ecliptic Attrition are labelled members of one group (`geo_ja`).
- `core/can.lua`: holds `THROTTLE` / `SPELL_THROTTLE` for the lockout (not `core/engine.lua`, which requires the behaviors: heal requiring it back would loop). The engine reads them from there. Nothing else changes. Heal stays the first behavior; `why` names the band (`danger: Tank 42%`).
- **Hold:** Danger and Critical only. If nothing is usable but a candidate covering a unit in the band is within 15s of coming off recast, hold (today's rule). The Efficient band never holds, so buffs and raises go out.

## Replaced from v2

v2's AOE Healing section had its own threshold (70%), needed 2+ hurt with a low average, and kept a per-member group selection. The score replaces the threshold and the count: Curaga wins exactly when it's the better buy. The group selection becomes `heal.skip`, which applies to every heal. Each family keeps its on/off row.

## Not in this design (add when)

- **Incoming damage rate** (HP lost per second per unit), to value Regen on a tank under fire above `min(total, need)`. Add when Regen proves undervalued in play.
- **Alliance:** an area heal covers only the target's party; score each party separately. Comes with Phase 3 alliance units.
- **SCH Celerity / WHM Afflatus Solace:** job-module modifiers that shorten a cure's lockout or change its amount. Comes with the SCH and WHM modules.
- **Stratagem reserve** (v2's "Hold a Stratagem for AOE"): fence a charge for Accession cures. Add with the SCH module, when storms and Protect also spend charges.
- **Accession Regen** (area Regen in Efficient): needs a price for a stratagem charge in the Efficient score.
- **Pet healing** (`pet_heal`), Fast Cast in the lockout, and Benediction-class one-hours.
- **Obis:** a Korin Obi makes the day and weather bonus land every cast (penalties stay 1 in 3); a Hachirin-no-Obi makes both land every cast. Needs a gear read. Add when someone heals in one.
- **Blue cures' elements:** they roll day and weather for their own element; here they get `sky` 0.

## Tests (`tests/engine_test.lua`)

Rewrite today's heal tests around the bands. One test each:

- Efficient picks the best HP per MP without overheal (the table above).
- Regen wins in Efficient; while it's pending, Efficient doesn't cure that unit, but Danger does.
- Curaga wins for a bunched group and loses when the group is spread past its radius.
- Danger prefers an instant waltz over a slower, bigger cure.
- Critical fires Divine Seal, then with the Seal status up picks the boosted cure (Cure IV over Cure V at 800 missing).
- With Majesty up, Efficient picks one Cure for a bunched group; spread past the radius, it cures one. Its +25 potency is divided out of a learned reading.
- Danger fires Accession when area Cure IV beats every single cure; not for one hurt unit, not in Efficient, never paired with Cure V.
- A stratagem with the timer running but a charge banked passes `can.use`.
- `sky`: Lightsday under Stellar Glare is +0.117, Darksday under Darkness -0.117, Aurorastorm under Gloom +0.033, Aurorastorm under Auras +0.083.
- A learned potency overrides the table, and a reading taken under Divine Seal is halved before it's stored.
- With low MP, a TP heal beats an MP heal of the same size (share of pool).
- At 3000 TP a waltz wins Efficient; at 2650 TP and full MP the cure does.
- Hold happens in Danger, never in Efficient.
- Out of range still skips to the next unit, as today.
- The focus target enters Danger at 59% while others wait for 49%.
- An excluded unit is never healed for its own sake.

## Build order

Each step leaves `luajit tests/run.lua` green.

1. Data: catalog `cast`/`tick`/`boost`; knowledge roles, priors, Regen uses, Majesty and Accession boosts; settings fields and the `settings.key` change; the parity mapping.
2. Snapshot: `pos`, `max_hp` fallback, stratagem charges, `core/observed.lua` and the packets hook.
3. `behaviors/heal.lua`: candidates, bands, scores, boosts, hold.
4. Tests as above.
5. The in-game prior check; adjust priors.
