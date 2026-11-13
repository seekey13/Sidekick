--[[
    What the client DATs don't say: what an action is FOR.

    One row per family (the name without its tier: "Cure IV" -> Cure), shared by
    every job, so the Cure row covers WHM, RDM, PLD and SCH alike. Level, cost,
    recast, range, targets, element and SCH's Addendum gate all come from the
    DATs; see core/catalog.lua. A family with no row is not automated. Rows a job
    module acts on itself, or that need its code, are in the module (core/jobs.lua).

    A row is one use, or a list of uses when one action does several jobs
    (Chakra heals and cures). An exact name ("Healing Ruby II") beats its family.

    role       heal | pet_heal | remove | pet_remove | pet_send | emergency | revive | roll |
               recover | buff | modifier | geo | rune | ward | maneuver | song
               (roll, geo, rune, ward, maneuver and song: a job module's, jobs/cor.lua,
               geo.lua, run.lua, pup.lua and brd.lua)
               (a modifier is a JA fired just before the spell it changes: core/engine.lua)
               (a heal's area comes from the DAT: Curaga is a heal like Cure)
    status     what a buff shows: status name (lowest id with that name wins), id,
               or a list (any one counts). Omitted = the status named like the
               action, else like its family. false = nothing readable.
    removes    statuses a removal clears
    potency    HP healed per tier, before gear and CatsEyeXI's x1.25: a prior until
               a cast is seen (core/observed.lua)
    tick       HP per 3s tick, per tier (Regen)
    boost      { kind, factor, potency =, area =, mp =, tiers = }: while its status is
               on you, heals of that kind ('healing' = Cure/Curaga, 'cure' = those and
               blue magic cures, 'waltz') heal
               x factor and +potency %, and a Cure up to tier `tiers` covers `area`
               yalms at `mp` x the cost (behaviors/heal.lua)
    wakes      the heal also cures sleep
    gives      'tp' for a recover that restores TP (default MP)
    costs_hp   paid for with your HP: only while you're over the danger line
    swaps      trades your HP for your MP: only while you have more HP than MP
    spends_tp  turns all your TP into MP (Chivalry): only from recover.min_tp up
    ammo       item ids, one of which must be in your ammo slot (pet food, oils, shuriken)
    tool       the ninja tool item a cast spends from your inventory (jobs/nin.lua)
    last_shadow the status that shows one shadow left (Utsusemi, jobs/nin.lua)
    pet_range  yalms your pet may be from you (the server refuses Repair past 20)
    item       an inventory item's id: used on you with /item (opt-in: items cost gil)
    one_of     clears just one of `removes` per use, at random (Remedy Ointment)
    gate       'combat' | 'idle' (enemy-targeted actions are combat-only anyway); built in: a row's
               own Combat or Idle (cfg.gates, can.gate) can't change it
    pick_one   families sharing a key keep one selection (enspells, storms, bar-elements)
    match      'weather' | 'element': the row can follow the sky (Auto, first in its list),
               picking the tier whose DAT element matches the zone's weather (storms), or the
               one your weather and the day favor most (enspells) (core/sky.lua)
    blocked_by skip while you have any of these statuses
    trance     no TP needed under Trance (waltzes, Aspir Samba: jobs/dnc.lua)
    requires   needs any of these statuses on you
    priority   sorts ahead (+) / behind (-) inside its role
    area       overrides the DAT's area: 0 for blue magic the DAT gives an area (15)
               though it lands on you alone (Battery Charge, Occultation...)
    main_only  never from a subjob
    learn      { [job] = level (or one per tier) }: an ability the server lists only
               while it can be used, so HasAbility misses it: a pet command, blood
               pact or Ready move with no such pet out, a stratagem outside its Arts
               (LSB's addType). Catalogued from the job's level anyway, shown in
               settings, and sent only while the client lists it (core/catalog.lua,
               can.use)
    first      goes ahead of every behavior, healing too, but for a critical
               member's: a lasting stance healing is cheaper or possible under
               (Light Arts, Addendum: White; behaviors/buff.lua)
    pet        needs a pet out (true) or one of these pets
    kind       'ma' | 'ja' | 'pet': this use only for that command kind
    label      UI name when one action has several uses
    note       short UI hint
    travel     travel buff (Sneak, Deodorize, Invisible): still cast while you're Invisible, when
               nothing else but danger healing goes (core/engine.lua)
    duration   seconds a buff lasts (or per tier), for statuses read off packets (trusts)
    mob_skill  the id a jug pet's move carries in its action packet (the server's mob skill)
    applies    a modifier's test of a catalog record: which spells a buff row may turn it on for
    spreads    { area =, mp =, others = }: the modifier makes a single-target spell land on everyone
               in your party within `area` yalms of you, at `mp` x the cost (Accession, Diffusion);
               `others`: only while someone but you lacks it (Diffusion's long recast)
    unbridled  blue magic cast through Unbridled Learning, never set (jobs/blu.lua)
    luopan     'buff' | 'debuff': a Geo- spell, put down as a luopan; 'spend': spends
               the luopan (Radial Arcana)
    decide     function (a, g, cat, cfg, mem): a recover row that decides for itself
               what to send for it (Radial Arcana, jobs/geo.lua)
    lucky      a Phantom Roll's lucky and unlucky totals (jobs/cor.lua)
    unlucky
    rune       { element, resist, ailments }: what a rune adds, resists and defends
               against, as Runes shows it (jobs/run.lua)
]]--

local jobs = require('core.jobs')

-- Status sets for removals (ids: several names repeat in the status table).
local CURSE    = { 9, 15, 20, 30 }  -- Curse, Doom, Curse II, Bane
local ESUNA    = { 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 20, 21, 30, 31 }
local ERASABLE = { 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
    140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }
local WALTZ    = { 3, 4, 5, 6, 8, 9, 11, 12, 13, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137,
    138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404 }
local PET_CLEANSE = { 3, 4, 5, 6, 8, 9, 31, 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135,
    136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }

-- Ammo items (ids) the server takes: Pet Food Alpha to Theta Biscuit; Automaton Oil to +3;
-- shuriken, Shuriken to Yoru (v2's list).
local PET_FOOD = { 17016, 17017, 17018, 17019, 17020, 17021, 17022, 17023 }
local OILS     = { 18731, 18732, 18733, 19185 }
local SHURIKEN = { 17301, 17302, 17303, 17304, 18712, 22999 }

-- What a Panacea clears (the server's item script): Paralysis, Bind, Weight, Addle,
-- the elemental DoTs, Dia, Bio, stat downs, Inhibit TP.
local PANACEA = { 4, 11, 12, 21, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142,
    144, 145, 147, 148, 149, 167, 168, 174, 175 }

-- Jobs, for `learn`.
local BST, SMN, PUP, SCH = 9, 15, 18, 20

local LIGHT = { 'Light Arts', 'Addendum: White' }
local DARK = { 'Dark Arts', 'Addendum: Black' }
local SAMBA = { role = 'buff', gate = 'combat', pick_one = 'samba', blocked_by = 'Fan Dance' }
local FINISHING_5 = { 'Finishing Move (5)', 'Finishing Move (6+)' }  -- five or more (jobs/dnc.lua)

local K = {
    -- heal ---------------------------------------------------------------------
    -- Cure and Curing Waltz to 99 (LSB's scripts). Cure I-V: the old formula's soft caps. Cure
    -- VI has only the new one: 890 at 500 cure power, the bracket a 99 WHM is in (its cap,
    -- 1010, takes 700). A waltz is (target VIT + your CHR) x its multiplier + a base,
    -- uncapped: Curing Waltz V at the 150 VIT + CHR Curing Waltz IV's 600 stands for
    -- (600 + 1.25 x 150).
    ['Cure']              = { role = 'heal', wakes = true, potency = { 30, 90, 200, 400, 700, 890 } },
    ['Curing Waltz']      = { role = 'heal', wakes = true, blocked_by = 'Saber Dance', trance = true, potency = { 70, 140, 300, 600, 787 } },
    ['Drain']             = { role = 'heal', potency = { 90, 180 } },
    ['Pollen']            = { role = 'heal', potency = { 30 } },
    ['Magic Fruit']       = { role = 'heal', wakes = true, potency = { 300 } },
    ['Plenilune Embrace'] = { role = 'heal', wakes = true, potency = { 650 } },
    ['Vivacious Pulse']   = { role = 'heal' },
    ['Healing Ruby']      = { role = 'heal', wakes = true, pet = { 'Carbuncle' }, potency = { 250, 250 }, learn = { [SMN] = { 1, 65 } } },
    ['Wild Carrot']       = {
        { kind = 'ma', role = 'heal', wakes = true, potency = { 120 } },
        { kind = 'pet', role = 'heal', pet = { 'KeenearedSteffi', 'Rabbit' }, potency = { 120 }, mob_skill = 3903,
          learn = { [BST] = 25 } },
    },
    ['Chakra'] = {
        { role = 'heal' },
        { role = 'remove', removes = { 'Poison', 'Blindness' } },
    },
    -- ponytail: area priors are guesses until the in-game check (Curaga, Divine Waltz, Healing Breeze, Healing Ruby, Wild Carrot).
    -- Curaga: each tier's floor (LSB's minCure), Curaga V's too.
    ['Curaga']           = { role = 'heal', wakes = true, potency = { 60, 130, 270, 450, 600 } },
    ['Divine Waltz']     = { role = 'heal', wakes = true, blocked_by = 'Saber Dance', trance = true, potency = { 70, 300 } },
    ['Healing Breeze']   = { role = 'heal', wakes = true, potency = { 90 } },
    ['Mending Halation'] = { role = 'heal', main_only = true, pet = true },
    -- Two rows: healing decides when a Regen is worth casting; "keep up" holds it on chosen targets.
    -- Ticks and durations to Regen V: LSB's enhancing spell table.
    ['Regen'] = {
        { role = 'heal', status = 'Regen', tick = { 5, 12, 20, 30, 40 }, duration = { 75, 60, 60, 60, 60 } },
        { role = 'buff', label = 'Regen (keep up)', duration = { 75, 60, 60, 60, 60 } },
    },

    -- emergency (critical HP) --------------------------------------------------
    ['Divine Seal']  = { role = 'emergency', boost = { 'cure', 2 } },
    ['Martyr']       = { role = 'emergency' },
    ['Contradance']  = { role = 'emergency', boost = { 'waltz', 2 } },
    ['Apogee']       = { role = 'emergency', pet = { 'Carbuncle' } },
    ['Rapture']      = { role = 'emergency', requires = LIGHT, boost = { 'healing', 1.5 }, learn = { [SCH] = 55 } },
    -- Accession: jobs/sch.lua
    -- A merit: listed at 75 whether merited or not, sent only once the client lists it.
    ['Tranquility']  = { role = 'emergency', requires = LIGHT, learn = { [SCH] = 75 } },

    -- remove -------------------------------------------------------------------
    ['Poisona']       = { role = 'remove', removes = 'Poison' },
    ['Paralyna']      = { role = 'remove', removes = 'Paralysis' },
    ['Blindna']       = { role = 'remove', removes = 'Blindness' },
    ['Silena']        = { role = 'remove', removes = 'Silence' },
    ['Stona']         = { role = 'remove', removes = 'Petrification' },
    ['Viruna']        = { role = 'remove', removes = { 'Disease', 'Plague' } },
    ['Cursna']        = { role = 'remove', removes = CURSE },
    ['Erase']         = { role = 'remove', removes = ERASABLE },
    ['Esuna']         = { role = 'remove', removes = ESUNA },
    ['Healing Waltz'] = { role = 'remove', removes = WALTZ, blocked_by = 'Saber Dance', trance = true },

    -- remove: items, on you only and after any spell. behaviors/remove.lua orders them by what
    -- they'd clear on you, then by priority: cheap and specific first.
    ['Antidote']        = { role = 'remove', item = 4148, removes = 'Poison', priority = 30 },
    ['Eye Drops']       = { role = 'remove', item = 4150, removes = 'Blindness', priority = 30 },
    ['Echo Drops']      = { role = 'remove', item = 4151, removes = 'Silence', priority = 30 },
    ['Holy Water']      = { role = 'remove', item = 4154, removes = CURSE, priority = 20 },  -- Doom one time in three
    ['Hallowed Water']  = { role = 'remove', item = 5306, removes = CURSE, priority = 15 },  -- the same, dearer
    ['Tincture']        = { role = 'remove', item = 5418, removes = { 'Plague', 'Disease' }, priority = 20 },
    ['Remedy Ointment'] = { role = 'remove', item = 5356, removes = { 3, 4, 5, 6, 8 }, priority = 10, one_of = true },
    ['Remedy']          = { role = 'remove', item = 4155, removes = { 3, 4, 5, 6 }, priority = 5 },  -- Disease half the time
    ['Panacea']         = { role = 'remove', item = 4149, removes = PANACEA },

    -- revive -------------------------------------------------------------------
    ['Raise'] = { role = 'revive', gate = 'idle' },
    ['Arise'] = { role = 'revive', gate = 'idle' },

    -- recover ------------------------------------------------------------------
    ['Aspir']            = { role = 'recover' },
    ['Convert']          = { role = 'recover', priority = 100, costs_hp = true, swaps = true },
    ['Chivalry']         = { role = 'recover', spends_tp = true },
    ['Devotion']         = { role = 'recover', costs_hp = true },
    -- Radial Arcana: jobs/geo.lua
    ['Meditate']         = { role = 'recover', gives = 'tp', priority = 100, status = 801 },
    ['Reverse Flourish'] = { role = 'recover', gives = 'tp', priority = 100, requires = FINISHING_5 },

    -- pet ----------------------------------------------------------------------
    -- The ammo is equipped from your bags or wardrobes when it's needed (core/ammo.lua).
    ['Spirit Link']   = { role = 'pet_heal', pet = true, costs_hp = true },
    ['Life Cycle']    = { role = 'pet_heal', pet = true, main_only = true, costs_hp = true },
    ['Dematerialize'] = { role = 'pet_heal', pet = true, main_only = true },
    ['Repair']        = { role = 'pet_heal', pet = true, priority = 100, ammo = OILS, pet_range = 20 },
    ['Role Reversal'] = { role = 'pet_heal', pet = true, costs_hp = true },
    ['Maintenance']   = { role = 'pet_remove', pet = true, removes = PET_CLEANSE, ammo = OILS },
    -- The server's Reward takes pet food only (no Pet Poultice or Roborant); each one also gives Regen.
    ['Reward']        = { role = 'pet_heal', pet = true, ammo = PET_FOOD },
    -- Send the pet at your battle target.
    ['Assault'] = { role = 'pet_send', pet = true, learn = { [SMN] = 1 } },
    ['Fight']   = { role = 'pet_send', pet = true, learn = { [BST] = 1 } },
    ['Deploy']  = { role = 'pet_send', pet = true, learn = { [PUP] = 1 } },

    -- buff: white / enhancing magic ---------------------------------------------
    ['Protect']   = { role = 'buff', duration = 1800 },
    ['Shell']     = { role = 'buff', duration = 1800 },
    ['Protectra'] = { role = 'buff', status = 'Protect', duration = 1800 },
    ['Shellra']   = { role = 'buff', status = 'Shell', duration = 1800 },
    ['Haste']     = { role = 'buff', priority = 25, duration = 180 },
    ['Refresh']   = { role = 'buff', priority = 50, duration = 150 },
    ['Flurry']    = { role = 'buff', priority = 25, status = 581, duration = 180 },
    ['Phalanx']   = { role = 'buff' },
    ['Stoneskin'] = { role = 'buff' },
    ['Blink']     = { role = 'buff' },
    ['Aquaveil']  = { role = 'buff' },
    ['Reraise']   = { role = 'buff' },
    ['Auspice']   = { role = 'buff' },
    ['Enlight']   = { role = 'buff' },
    ['Reprisal']  = { role = 'buff' },
    ['Foil']      = { role = 'buff' },
    ['Klimaform'] = { role = 'buff' },
    ['Afflatus Solace'] = { role = 'buff', pick_one = 'afflatus' },
    ['Afflatus Misery'] = { role = 'buff', pick_one = 'afflatus' },
    ['Sneak']     = { role = 'buff', gate = 'idle', travel = true, priority = -10 },
    ['Invisible'] = { role = 'buff', gate = 'idle', travel = true, priority = -20 },
    ['Deodorize'] = { role = 'buff', gate = 'idle', travel = true, priority = -15 },
    -- Bar-spells, enspells, spikes: below. Enspell II shows its own status ("Enfire II"), found by the full name.
    ['Dread Spikes'] = { role = 'buff' },

    -- modifier: Scholar's stratagems (Penury, Accession...) are jobs/sch.lua's.
    -- No chip: fired by itself for an Addendum spell you lack the Addendum for (core/catalog.lua).
    -- Under Dark Arts, as v2: under Light Arts, Addendum: White is the way in.
    ['Enlightenment'] = { role = 'modifier', requires = DARK, main_only = true },

    -- Corsair's Phantom Rolls, Double-Up, Fold and Snake Eye are jobs/cor.lua's.

    -- Rune Fencer's runes, wards and Embolden are jobs/run.lua's.

    -- buff: Scholar -------------------------------------------------------------
    -- Light Arts first, ahead of healing: it makes white magic cheaper and opens
    -- the stratagems; Addendum: White then opens its spells (Raise, Erase, the -na).
    ['Light Arts']      = { role = 'buff', pick_one = 'arts', priority = 100, status = LIGHT, first = true },
    ['Dark Arts']       = { role = 'buff', pick_one = 'arts', priority = 100, status = { 'Dark Arts', 'Addendum: Black' } },
    ['Addendum: White'] = { role = 'buff', pick_one = 'addendum', priority = 90, requires = 'Light Arts', first = true,
                            learn = { [SCH] = 10 } },
    ['Addendum: Black'] = { role = 'buff', pick_one = 'addendum', requires = 'Dark Arts', learn = { [SCH] = 30 } },
    ['Sublimation'] = {
        { role = 'buff', priority = 50, status = { 'Sublimation: Activated', 'Sublimation: Complete' } },
        { role = 'recover', requires = { 'Sublimation: Activated', 'Sublimation: Complete' } },
    },
    -- Storms: below.

    -- Bard's songs and Pianissimo are jobs/brd.lua's.
    ['Troubadour']  = { role = 'buff', priority = 100 },
    ['Nightingale'] = { role = 'buff', priority = 100 },

    -- buff: Blue magic (the status is a generic boost, not the spell's name) ------
    ['Cocoon']          = { role = 'buff', status = 'Defense Boost' },
    ['Harden Shell']    = { role = 'buff', status = 'Defense Boost', area = 0, unbridled = true },
    ['Metallic Body']   = { role = 'buff', status = 'Stoneskin' },
    ['Diamondhide']     = { role = 'buff', status = 'Stoneskin' },
    ['Refueling']       = { role = 'buff', status = 'Haste' },
    ['Animating Wail']  = { role = 'buff', status = 'Haste', area = 0 },
    ['Feather Barrier'] = { role = 'buff', status = 'Evasion Boost' },
    ['Memento Mori']    = { role = 'buff', status = 'Magic Atk. Boost' },
    ['Saline Coat']     = { role = 'buff', status = 'Magic Def. Boost' },
    ['Amplification']   = { role = 'buff', status = { 'Magic Atk. Boost', 'Magic Def. Boost' } },
    ['Zephyr Mantle']   = { role = 'buff', status = 'Blink' },
    ['Occultation']     = { role = 'buff', status = 'Blink', area = 0 },
    ['Warm-Up']         = { role = 'buff', status = 'Accuracy Boost' },
    ['Triumphant Roar'] = { role = 'buff', status = 'Attack Boost' },
    ['Carcharian Verve']= { role = 'buff', status = 'Attack Boost', unbridled = true },
    ['Reactor Cool']    = { role = 'buff', status = 'Ice Spikes' },
    ['Plasma Charge']   = { role = 'buff', status = 'Shock Spikes' },
    ['Battery Charge']  = { role = 'buff', status = 'Refresh', priority = 50, area = 0 },
    ['Magic Barrier']   = { role = 'buff', status = 'Magic Shield' },
    ['Barrier Tusk']    = { role = 'buff', status = 'Physical Shield', area = 0 },
    ['O. Counterstance']= { role = 'buff', status = 'Counterstance' },
    ['Pyric Bulwark']   = { role = 'buff', unbridled = true },
    -- Diffusion: jobs/blu.lua
    -- No chip: fired by itself before an Unbridled spell (core/catalog.lua); level 75 on CatsEyeXI.
    ['Unbridled Learning'] = { role = 'modifier', main_only = true },

    -- buff: Geomancer's Indi- auras and the luopan's Geo- ones are jobs/geo.lua's.
    ['Lasting Emanation']  = { role = 'buff', pick_one = 'geo_ja', label = 'Lasting Emanation (Duration)', main_only = true, pet = true, status = false },
    ['Ecliptic Attrition'] = { role = 'buff', pick_one = 'geo_ja', label = 'Ecliptic Attrition (Effect)', main_only = true, pet = true, status = false },

    -- buff: Ninja -----------------------------------------------------------------
    -- Each cast spends a tool from your inventory (Shihei, Shinobi-tabi, Sanjaku-tenugui; jobs/nin.lua).
    ['Utsusemi'] = { role = 'buff', status = { 66, 444, 445, 446 }, last_shadow = 66, tool = 1179 },  -- Copy Image (1-4+)
    ['Monomi']   = { role = 'buff', gate = 'idle', travel = true, priority = -10, status = 'Sneak', tool = 2553 },
    ['Tonko']    = { role = 'buff', gate = 'idle', travel = true, priority = -20, status = 'Invisible', tool = 1194 },
    ['Yonin']    = { role = 'buff', pick_one = 'nin_stance' },
    ['Innin']    = { role = 'buff', pick_one = 'nin_stance' },
    ['Sange']    = { role = 'buff', gate = 'combat', ammo = SHURIKEN },  -- Daken then throws the shuriken worn

    -- buff: Dancer ------------------------------------------------------------------
    ['Drain Samba']  = SAMBA,
    ['Aspir Samba']  = { role = 'buff', gate = 'combat', pick_one = 'samba', blocked_by = 'Fan Dance', trance = true },
    ['Haste Samba']  = SAMBA,
    ['Saber Dance']  = { role = 'buff', gate = 'combat', status = { 'Saber Dance', 'Fan Dance' } },
    ['Fan Dance']    = { role = 'buff', gate = 'combat', status = { 'Saber Dance', 'Fan Dance' } },
    -- ponytail: five taken as full; a max finishing move bonus (gear) would allow more.
    ['No Foot Rise'] = { role = 'buff', status = FINISHING_5 },
    ['Presto']       = { role = 'buff', gate = 'combat' },  -- for your next Step, by hand
    -- Does nothing while Sneak or Invisible is up (it won't overwrite either): used once both are off.
    ['Spectral Jig'] = { role = 'buff', gate = 'idle', travel = true, priority = -20, status = { 'Sneak', 'Invisible' } },

    -- buff: job abilities ---------------------------------------------------------
    ['Composure']  = { role = 'buff', priority = 100 },
    ['Majesty']    = { role = 'buff', priority = 100, boost = { 'cure', potency = 25, area = 10 } },
    ['Boost']      = { role = 'buff', status = false },
    ['Avatar\'s Favor'] = { role = 'buff', pet = true, learn = { [SMN] = 55 } },
    ['Shining Ruby']    = { role = 'buff', pet = { 'Carbuncle' }, learn = { [SMN] = 24 } },
    ['Spirit Bond']     = { role = 'buff', gate = 'combat', pet = true },
    ['Hasso']  = { role = 'buff', pick_one = 'sam_stance' },
    ['Seigan'] = { role = 'buff', pick_one = 'sam_stance' },
    ['Berserk']    = { role = 'buff', gate = 'combat', blocked_by = 'Defender' },
    ['Defender']   = { role = 'buff', gate = 'combat', blocked_by = 'Berserk' },
    ['Warcry']     = { role = 'buff', gate = 'combat', blocked_by = 'Blood Rage' },
    ['Blood Rage'] = { role = 'buff', gate = 'combat', blocked_by = 'Warcry' },
    ['Scarlet Delirium'] = { role = 'buff', gate = 'combat', status = { 479, 480 } },
    ['Scavenge']   = { role = 'buff' },
    ['Bounty Shot']= { role = 'buff' },
    ['Velocity Shot'] = { role = 'buff', gate = 'combat', main_only = true },
}

-- Pick-one groups whose members each show the status named like them: the key, then its members.
-- Enspells and storms can follow the sky (`match`, core/sky.lua).
local MATCH = { enspell = 'element', storm = 'weather' }
for key, names in pairs({
    enspell = { 'Enfire', 'Enblizzard', 'Enaero', 'Enstone', 'Enthunder', 'Enwater' },
    spikes = { 'Blaze Spikes', 'Ice Spikes', 'Shock Spikes' },
    storm = { 'Sandstorm', 'Rainstorm', 'Windstorm', 'Firestorm', 'Hailstorm', 'Thunderstorm', 'Voidstorm', 'Aurorastorm' },
}) do
    for _, name in ipairs(names) do
        K[name] = { role = 'buff', pick_one = key, duration = key == 'storm' and 180 or nil, match = MATCH[key] }
    end
end

-- Bar-spells, one pick-one group each: the single-target spell shows its own status, its area -ra the single's.
for key, bars in pairs({
    barelement = { Barfire = 'Barfira', Barblizzard = 'Barblizzara', Baraero = 'Baraera', Barstone = 'Barstonra',
                   Barthunder = 'Barthundra', Barwater = 'Barwatera' },
    barstatus = { Barsleep = 'Barsleepra', Barpoison = 'Barpoisonra', Barparalyze = 'Barparalyzra', Barblind = 'Barblindra',
                  Barsilence = 'Barsilencera', Barpetrify = 'Barpetra', Barvirus = 'Barvira', Baramnesia = 'Baramnesra' },
}) do
    for single, area in pairs(bars) do
        K[single] = { role = 'buff', pick_one = key }
        K[area] = { role = 'buff', pick_one = key, status = single }
    end
end

-- Plain combat-only self buffs.
for _, name in ipairs({
    'Aggressor', 'Retaliation', 'Warrior\'s Charge', 'Dodge', 'Focus', 'Counterstance', 'Footwork',
    'Impetus', 'Perfect Counter', 'Conspirator', 'Assassin\'s Charge', 'Feint', 'Fealty', 'Rampart',
    'Sentinel', 'Holy Circle', 'Arcane Circle', 'Last Resort', 'Souleater', 'Consume Mana',
    'Diabolic Eye', 'Ancient Circle', 'Sharpshot', 'Unlimited Shot', 'Flashy Shot', 'Stealth Shot',
    'Warding Circle', 'Third Eye', 'Swordplay',
}) do
    K[name] = { role = 'buff', gate = 'combat' }
end

-- Absorb- spells (DRK): drain a stat off your battle target onto you.
for name, status in pairs({
    STR = 'STR Boost', DEX = 'DEX Boost', VIT = 'VIT Boost', AGI = 'AGI Boost',
    INT = 'INT Boost', MND = 'MND Boost', CHR = 'CHR Boost', ACC = 'Accuracy Boost',
}) do
    K['Absorb-' .. name] = { role = 'buff', pick_one = 'absorb', status = status }
end
K['Absorb-Attri'] = { role = 'buff', pick_one = 'absorb', status = false }
K['Absorb-TP']    = { role = 'buff', pick_one = 'absorb', status = false }

-- The job modules' own rows (core/jobs.lua).
for _, rows in jobs.each('knowledge') do
    for name, row in pairs(rows) do
        assert(K[name] == nil, 'a job module repeats a knowledge row: ' .. name)
        K[name] = row
    end
end

return K
