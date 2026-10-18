--[[
    What the client DATs don't say: what an action is FOR.

    One row per family (the name without its tier: "Cure IV" -> Cure), shared by
    every job, so the Cure row covers WHM, RDM, PLD and SCH alike. Level, cost,
    recast, range, targets, element and SCH's Addendum gate all come from the
    DATs; see core/catalog.lua. A family with no row is not automated.

    A row is one use, or a list of uses when one action does several jobs
    (Chakra heals and cures). An exact name ("Healing Ruby II") beats its family.

    role       heal | pet_heal | remove | pet_remove | pet_send | emergency | revive | roll |
               recover | buff | modifier | geo | rune | ward
               (geo: the luopan's spells and abilities, jobs/geo.lua's)
               (rune, ward: Rune Fencer's runes and the abilities that read them, jobs/run.lua's)
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
    ammo       item ids, one of which must be in your ammo slot (pet food, oils)
    pet_range  yalms your pet may be from you (the server refuses Repair past 20)
    item       an inventory item's id: used on you with /item (opt-in: items cost gil)
    one_of     clears just one of `removes` per use, at random (Remedy Ointment)
    gate       'combat' | 'idle' (enemy-targeted actions are combat-only anyway)
    pick_one   families sharing a key keep one selection (enspells, storms, bar-elements)
    blocked_by skip while you have any of these statuses
    requires   needs any of these statuses on you
    priority   sorts ahead (+) / behind (-) inside its role
    area       overrides the DAT's area: 0 for blue magic the DAT gives an area (15)
               though it lands on you alone (Battery Charge, Occultation...)
    main_only  never from a subjob
    pet        needs a pet out (true) or one of these pets
    kind       'ma' | 'ja' | 'pet': this use only for that command kind
    label      UI name when one action has several uses
    note       short UI hint
    travel     travel buff: still cast while Invisible
    duration   seconds a buff lasts (or per tier), for statuses read off packets (trusts)
    mob_skill  the id a jug pet's move carries in its action packet (the server's mob skill)
    applies    a modifier's test of a catalog record: which spells a buff row may turn it on for
    spreads    { area =, mp = }: the modifier makes a single-target spell land on everyone in
               your party within `area` yalms of you, at `mp` x the cost (Accession)
    chip       a modifier's short label on a buff row
    luopan     'buff' | 'debuff': a Geo- spell, put down as a luopan; 'spend': spends
               the luopan (Radial Arcana), which jobs/geo.lua decides when
    lucky      a Phantom Roll's lucky and unlucky totals (jobs/cor.lua)
    unlucky
    rune       { element, resist, ailments }: what a rune adds, resists and defends
               against, as Runes shows it (jobs/run.lua)
]]--

local geo = require('jobs.geo')
local run = require('jobs.run')
local sch = require('jobs.sch')

-- Status sets for removals (ids: several names repeat in the status table).
local CURSE    = { 9, 15, 20, 30 }  -- Curse, Doom, Curse II, Bane
local ESUNA    = { 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 20, 21, 30, 31 }
local ERASABLE = { 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
    140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }
local WALTZ    = { 3, 4, 5, 6, 8, 9, 11, 12, 13, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137,
    138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404 }
local PET_CLEANSE = { 3, 4, 5, 6, 8, 9, 31, 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135,
    136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }

-- Ammo items (ids) the server takes: Pet Food Alpha to Theta Biscuit; Automaton Oil to +3.
local PET_FOOD = { 17016, 17017, 17018, 17019, 17020, 17021, 17022, 17023 }
local OILS     = { 18731, 18732, 18733, 19185 }

-- What a Panacea clears (the server's item script): Paralysis, Bind, Weight, Addle,
-- the elemental DoTs, Dia, Bio, stat downs, Inhibit TP.
local PANACEA = { 4, 11, 12, 21, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142,
    144, 145, 147, 148, 149, 167, 168, 174, 175 }

local LIGHT = { 'Light Arts', 'Addendum: White' }
local DARK = { 'Dark Arts', 'Addendum: Black' }
local SAMBA = { role = 'buff', pick_one = 'samba', blocked_by = 'Fan Dance' }

local K = {
    -- heal ---------------------------------------------------------------------
    ['Cure']              = { role = 'heal', wakes = true, potency = { 30, 90, 200, 400, 700 } },
    ['Curing Waltz']      = { role = 'heal', wakes = true, blocked_by = 'Saber Dance', potency = { 70, 140, 300, 600 } },
    ['Drain']             = { role = 'heal', potency = { 90, 180 } },
    ['Pollen']            = { role = 'heal', potency = { 30 } },
    ['Magic Fruit']       = { role = 'heal', wakes = true, potency = { 300 } },
    ['Plenilune Embrace'] = { role = 'heal', wakes = true, potency = { 650 } },
    ['Vivacious Pulse']   = { role = 'heal' },
    ['Healing Ruby']      = { role = 'heal', wakes = true, pet = { 'Carbuncle' }, potency = { 250, 250 } },
    ['Wild Carrot']       = {
        { kind = 'ma', role = 'heal', wakes = true, potency = { 120 } },
        { kind = 'pet', role = 'heal', pet = { 'KeenearedSteffi', 'Rabbit' }, potency = { 120 }, mob_skill = 3903 },
    },
    ['Chakra'] = {
        { role = 'heal' },
        { role = 'remove', removes = { 'Poison', 'Blindness' } },
    },
    -- ponytail: area priors are guesses until the in-game check (Curaga, Divine Waltz, Healing Breeze, Healing Ruby, Wild Carrot).
    ['Curaga']           = { role = 'heal', wakes = true, potency = { 60, 130, 270, 450 } },
    ['Divine Waltz']     = { role = 'heal', wakes = true, blocked_by = 'Saber Dance', potency = { 70, 300 } },
    ['Healing Breeze']   = { role = 'heal', wakes = true, potency = { 90 } },
    ['Mending Halation'] = { role = 'heal', main_only = true, pet = true },
    -- Two rows: healing decides when a Regen is worth casting; "keep up" holds it on chosen targets.
    ['Regen'] = {
        { role = 'heal', status = 'Regen', tick = { 5, 12, 20 }, duration = { 75, 60, 60 } },
        { role = 'buff', label = 'Regen (keep up)', duration = { 75, 60, 60 } },
    },

    -- emergency (critical HP) --------------------------------------------------
    ['Divine Seal']  = { role = 'emergency', boost = { 'cure', 2 } },
    ['Martyr']       = { role = 'emergency' },
    ['Contradance']  = { role = 'emergency', boost = { 'waltz', 2 } },
    ['Apogee']       = { role = 'emergency', pet = { 'Carbuncle' } },
    ['Rapture']      = { role = 'emergency', requires = LIGHT, boost = { 'healing', 1.5 } },
    ['Accession'] = {
        { role = 'emergency', requires = LIGHT, boost = { 'healing', area = 10, mp = 2, tiers = 4 } },
        { role = 'modifier', requires = LIGHT, applies = sch.spreads, spreads = { area = 10, mp = 2 },
          chip = 'Acc', note = 'on everyone near you, at twice the MP' },
    },
    ['Tranquility']  = { role = 'emergency', requires = LIGHT },

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
    ['Healing Waltz'] = { role = 'remove', removes = WALTZ, blocked_by = 'Saber Dance' },

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
    -- Spends the luopan: jobs/geo.lua decides when, for behaviors/recover.lua.
    ['Radial Arcana']    = { role = 'recover', main_only = true, pet = true, priority = 90, luopan = 'spend' },
    ['Meditate']         = { role = 'recover', gives = 'tp', priority = 100, status = 801 },
    ['Reverse Flourish'] = { role = 'recover', gives = 'tp', priority = 100, requires = 'Finishing Move (5)' },

    -- pet ----------------------------------------------------------------------
    -- ponytail: equipping the ammo is the BST and PUP job modules' (phase 4); until then it's worn by hand.
    ['Spirit Link']   = { role = 'pet_heal', pet = true, costs_hp = true },
    ['Life Cycle']    = { role = 'pet_heal', pet = true, main_only = true, costs_hp = true },
    ['Dematerialize'] = { role = 'pet_heal', pet = true, main_only = true },
    ['Repair']        = { role = 'pet_heal', pet = true, priority = 100, ammo = OILS, pet_range = 20 },
    ['Role Reversal'] = { role = 'pet_heal', pet = true, costs_hp = true },
    ['Maintenance']   = { role = 'pet_remove', pet = true, removes = PET_CLEANSE, ammo = OILS },
    -- The server's Reward takes pet food only (no Pet Poultice or Roborant); each one also gives Regen.
    ['Reward']        = { role = 'pet_heal', pet = true, ammo = PET_FOOD },
    -- Send the pet at your battle target.
    ['Assault'] = { role = 'pet_send', pet = true },
    ['Fight']   = { role = 'pet_send', pet = true },
    ['Deploy']  = { role = 'pet_send', pet = true },

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
    ['Deodorize'] = { role = 'buff', gate = 'idle' },

    ['Barfire']     = { role = 'buff', pick_one = 'barelement' },
    ['Barblizzard'] = { role = 'buff', pick_one = 'barelement' },
    ['Baraero']     = { role = 'buff', pick_one = 'barelement' },
    ['Barstone']    = { role = 'buff', pick_one = 'barelement' },
    ['Barthunder']  = { role = 'buff', pick_one = 'barelement' },
    ['Barwater']    = { role = 'buff', pick_one = 'barelement' },
    ['Barfira']     = { role = 'buff', pick_one = 'barelement', status = 'Barfire' },
    ['Barblizzara'] = { role = 'buff', pick_one = 'barelement', status = 'Barblizzard' },
    ['Baraera']     = { role = 'buff', pick_one = 'barelement', status = 'Baraero' },
    ['Barstonra']   = { role = 'buff', pick_one = 'barelement', status = 'Barstone' },
    ['Barthundra']  = { role = 'buff', pick_one = 'barelement', status = 'Barthunder' },
    ['Barwatera']   = { role = 'buff', pick_one = 'barelement', status = 'Barwater' },

    ['Barsleep']     = { role = 'buff', pick_one = 'barstatus' },
    ['Barpoison']    = { role = 'buff', pick_one = 'barstatus' },
    ['Barparalyze']  = { role = 'buff', pick_one = 'barstatus' },
    ['Barblind']     = { role = 'buff', pick_one = 'barstatus' },
    ['Barsilence']   = { role = 'buff', pick_one = 'barstatus' },
    ['Barpetrify']   = { role = 'buff', pick_one = 'barstatus' },
    ['Barvirus']     = { role = 'buff', pick_one = 'barstatus' },
    ['Baramnesia']   = { role = 'buff', pick_one = 'barstatus' },
    ['Barsleepra']   = { role = 'buff', pick_one = 'barstatus', status = 'Barsleep' },
    ['Barpoisonra']  = { role = 'buff', pick_one = 'barstatus', status = 'Barpoison' },
    ['Barparalyzra'] = { role = 'buff', pick_one = 'barstatus', status = 'Barparalyze' },
    ['Barblindra']   = { role = 'buff', pick_one = 'barstatus', status = 'Barblind' },
    ['Barsilencera'] = { role = 'buff', pick_one = 'barstatus', status = 'Barsilence' },
    ['Barpetra']     = { role = 'buff', pick_one = 'barstatus', status = 'Barpetrify' },
    ['Barvira']      = { role = 'buff', pick_one = 'barstatus', status = 'Barvirus' },
    ['Baramnesra']   = { role = 'buff', pick_one = 'barstatus', status = 'Baramnesia' },

    -- Enspell II shows its own status ("Enfire II"), found by the full name.
    ['Enfire']     = { role = 'buff', pick_one = 'enspell' },
    ['Enblizzard'] = { role = 'buff', pick_one = 'enspell' },
    ['Enaero']     = { role = 'buff', pick_one = 'enspell' },
    ['Enstone']    = { role = 'buff', pick_one = 'enspell' },
    ['Enthunder']  = { role = 'buff', pick_one = 'enspell' },
    ['Enwater']    = { role = 'buff', pick_one = 'enspell' },
    ['Blaze Spikes'] = { role = 'buff', pick_one = 'spikes' },
    ['Ice Spikes']   = { role = 'buff', pick_one = 'spikes' },
    ['Shock Spikes'] = { role = 'buff', pick_one = 'spikes' },
    ['Dread Spikes'] = { role = 'buff' },

    -- modifier: Scholar's stratagems, fired just before the spell (jobs/sch.lua) --
    ['Penury']      = { role = 'modifier', requires = LIGHT, applies = sch.white, chip = 'Pen', note = 'half the MP' },
    ['Celerity']    = { role = 'modifier', requires = LIGHT, applies = sch.white, chip = 'Cel', note = 'half the casting time' },
    ['Perpetuance'] = { role = 'modifier', requires = LIGHT, applies = sch.enhancing, chip = 'Per', note = 'longer duration' },
    ['Parsimony']   = { role = 'modifier', requires = DARK, applies = sch.black, chip = 'Par', note = 'half the MP' },
    ['Alacrity']    = { role = 'modifier', requires = DARK, applies = sch.black, chip = 'Ala', note = 'half the casting time' },
    -- No chip: fired by itself for an Addendum spell you lack the Addendum for (core/catalog.lua).
    -- Under Dark Arts, as v2: under Light Arts, Addendum: White is the way in.
    ['Enlightenment'] = { role = 'modifier', requires = DARK, main_only = true },

    -- Corsair: Phantom Rolls, kept up and Double-Upped by jobs/cor.lua, not as buff rows.
    -- The note is what the roll gives; Double-Up and Fold are found by name.
    ['Double-Up'] = { role = 'roll' },
    ['Fold']      = { role = 'roll' },
    ['Snake Eye'] = { role = 'modifier', note = 'the next die rolls 1' },  -- fired before a Double-Up

    -- Rune Fencer: the wards read the runes up (jobs/run.lua), in priority order as v2.
    -- Valiance does nothing on you under Vallation; Vallation would replace a
    -- party-wide Valiance with less (v2's rule); Liement stops both.
    ['Vallation'] = { role = 'ward', priority = 3, status = 'Vallation', blocked_by = { 'Valiance', 'Liement' } },
    ['Valiance']  = { role = 'ward', priority = 2, status = 'Valiance', blocked_by = { 'Vallation', 'Liement' } },
    ['Pflug']     = { role = 'ward', priority = 1, status = 'Pflug' },
    -- Fired before white enhancing magic, as a stratagem (not the Spikes, which are black).
    ['Embolden']  = { role = 'modifier', applies = sch.enhancing, chip = 'Emb', note = 'more potent' },

    -- buff: Scholar -------------------------------------------------------------
    ['Light Arts']      = { role = 'buff', pick_one = 'arts', priority = 100, status = LIGHT },
    ['Dark Arts']       = { role = 'buff', pick_one = 'arts', priority = 100, status = { 'Dark Arts', 'Addendum: Black' } },
    ['Addendum: White'] = { role = 'buff', pick_one = 'addendum', requires = 'Light Arts' },
    ['Addendum: Black'] = { role = 'buff', pick_one = 'addendum', requires = 'Dark Arts' },
    ['Sublimation'] = {
        { role = 'buff', priority = 50, status = { 'Sublimation: Activated', 'Sublimation: Complete' } },
        { role = 'recover', requires = { 'Sublimation: Activated', 'Sublimation: Complete' } },
    },
    ['Sandstorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Rainstorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Windstorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Firestorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Hailstorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Thunderstorm'] = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Voidstorm']    = { role = 'buff', pick_one = 'storm', duration = 180 },
    ['Aurorastorm']  = { role = 'buff', pick_one = 'storm', duration = 180 },

    -- buff: Bard (songs) ---------------------------------------------------------
    ['Valor Minuet']       = { role = 'buff', pick_one = 'minuet', status = 'Minuet', note = '+ATK' },
    ['Knight\'s Minne']    = { role = 'buff', pick_one = 'minne', status = 'Minne', note = '+DEF' },
    ['Army\'s Paeon']      = { role = 'buff', pick_one = 'paeon', status = 'Paeon', note = '+Regen' },
    ['Mage\'s Ballad']     = { role = 'buff', pick_one = 'ballad', status = 'Ballad', note = '+Refresh' },
    ['Sword Madrigal']     = { role = 'buff', pick_one = 'madrigal', status = 'Madrigal', note = '+ACC' },
    ['Blade Madrigal']     = { role = 'buff', pick_one = 'madrigal', status = 'Madrigal', note = '++ACC' },
    ['Hunter\'s Prelude']  = { role = 'buff', pick_one = 'prelude', status = 'Prelude', note = '+Rng Acc.' },
    ['Archer\'s Prelude']  = { role = 'buff', pick_one = 'prelude', status = 'Prelude', note = '++Rng Acc.' },
    ['Advancing March']    = { role = 'buff', pick_one = 'march', status = 'March', note = '+Haste' },
    ['Victory March']      = { role = 'buff', pick_one = 'march', status = 'March', note = '++Haste' },
    ['Sheepfoe Mambo']     = { role = 'buff', pick_one = 'mambo', status = 'Mambo', note = '+EVA' },
    ['Dragonfoe Mambo']    = { role = 'buff', pick_one = 'mambo', status = 'Mambo', note = '++EVA' },
    ['Raptor Mazurka']     = { role = 'buff', pick_one = 'mazurka', status = 'Mazurka', note = '+Move Spd.' },
    ['Chocobo Mazurka']    = { role = 'buff', pick_one = 'mazurka', status = 'Mazurka', note = '+Move Spd.' },
    ['Adventurer\'s Dirge']= { role = 'buff', status = 'Dirge', note = '-Enmity' },
    ['Foe Sirvente']       = { role = 'buff', status = 'Sirvente', note = '+Enmity' },
    ['Goddess\'s Hymnus']  = { role = 'buff', status = 'Hymnus', note = 'Reraise' },
    ['Fowl Aubade']        = { role = 'buff', pick_one = 'resistance', status = 'Aubade', note = '+Slow Res.' },
    ['Herb Pastoral']      = { role = 'buff', pick_one = 'resistance', status = 'Pastoral', note = '+Poison Res.' },
    ['Shining Fantasia']   = { role = 'buff', pick_one = 'resistance', status = 'Fantasia', note = '+Blind Res.' },
    ['Scop\'s Operetta']   = { role = 'buff', pick_one = 'resistance', status = 'Operetta', note = '+Silence Res.' },
    ['Puppet\'s Operetta'] = { role = 'buff', pick_one = 'resistance', status = 'Operetta', note = '+Silence Res.' },
    ['Gold Capriccio']     = { role = 'buff', pick_one = 'resistance', status = 'Capriccio', note = '+Pet. Res.' },
    ['Warding Round']      = { role = 'buff', pick_one = 'resistance', status = 'Round', note = '+Curse Res.' },
    ['Goblin Gavotte']     = { role = 'buff', pick_one = 'resistance', status = 'Gavotte', note = '+Bind Res.' },
    ['Fire Carol']         = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Fire Res.' },
    ['Ice Carol']          = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Ice Res.' },
    ['Wind Carol']         = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Wind Res.' },
    ['Earth Carol']        = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Earth Res.' },
    ['Lightning Carol']    = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Lightning Res.' },
    ['Water Carol']        = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Water Res.' },
    ['Light Carol']        = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Light Res.' },
    ['Dark Carol']         = { role = 'buff', pick_one = 'carol', status = 'Carol', note = '+Dark Res.' },
    ['Sinewy Etude']       = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+STR' },
    ['Dextrous Etude']     = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+DEX' },
    ['Vivacious Etude']    = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+VIT' },
    ['Quick Etude']        = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+AGI' },
    ['Learned Etude']      = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+INT' },
    ['Spirited Etude']     = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+MND' },
    ['Enchanting Etude']   = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '+CHR' },
    ['Herculean Etude']    = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++STR' },
    ['Uncanny Etude']      = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++DEX' },
    ['Vital Etude']        = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++VIT' },
    ['Swift Etude']        = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++AGI' },
    ['Sage Etude']         = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++INT' },
    ['Logical Etude']      = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++MND' },
    ['Bewitching Etude']   = { role = 'buff', pick_one = 'etude', status = 'Etude', note = '++CHR' },
    ['Troubadour']  = { role = 'buff', priority = 100 },
    ['Nightingale'] = { role = 'buff', priority = 100 },

    -- buff: Blue magic (the status is a generic boost, not the spell's name) ------
    ['Cocoon']          = { role = 'buff', status = 'Defense Boost' },
    ['Harden Shell']    = { role = 'buff', status = 'Defense Boost', area = 0 },
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
    ['Carcharian Verve']= { role = 'buff', status = 'Attack Boost' },
    ['Reactor Cool']    = { role = 'buff', status = 'Ice Spikes' },
    ['Plasma Charge']   = { role = 'buff', status = 'Shock Spikes' },
    ['Battery Charge']  = { role = 'buff', status = 'Refresh', priority = 50, area = 0 },
    ['Magic Barrier']   = { role = 'buff', status = 'Magic Shield' },
    ['Barrier Tusk']    = { role = 'buff', status = 'Physical Shield', area = 0 },
    ['O. Counterstance']= { role = 'buff', status = 'Counterstance' },
    ['Pyric Bulwark']   = { role = 'buff' },

    -- buff: Geomancer's Indi- auras and the luopan's Geo- ones are filled in below, from geo.AURAS.
    ['Lasting Emanation']  = { role = 'buff', pick_one = 'geo_ja', label = 'Lasting Emanation (Duration)', main_only = true, pet = true, status = false },
    ['Ecliptic Attrition'] = { role = 'buff', pick_one = 'geo_ja', label = 'Ecliptic Attrition (Effect)', main_only = true, pet = true, status = false },

    -- geo: Geomancer's luopan (jobs/geo.lua) ------------------------------------
    ['Full Circle']    = { role = 'geo', main_only = true, pet = true, note = 'recall the luopan' },
    ['Blaze of Glory'] = { role = 'geo', main_only = true, status = 'Blaze of Glory', note = 'before a luopan' },
    ['Entrust']        = { role = 'geo', main_only = true, status = 'Entrust', note = 'an Indi- on a member' },

    -- buff: Ninja -----------------------------------------------------------------
    ['Utsusemi'] = { role = 'buff', status = { 66, 444, 445, 446 } },  -- Copy Image (1-4)
    ['Monomi']   = { role = 'buff', gate = 'idle', travel = true, priority = -10, status = 'Sneak' },
    ['Tonko']    = { role = 'buff', gate = 'idle', travel = true, priority = -20, status = 'Invisible' },
    ['Yonin']    = { role = 'buff', pick_one = 'nin_stance' },
    ['Innin']    = { role = 'buff', pick_one = 'nin_stance' },
    ['Sange']    = { role = 'buff', gate = 'combat' },

    -- buff: Dancer ------------------------------------------------------------------
    ['Drain Samba']  = SAMBA,
    ['Aspir Samba']  = SAMBA,
    ['Haste Samba']  = SAMBA,
    ['Saber Dance']  = { role = 'buff', gate = 'combat', status = { 'Saber Dance', 'Fan Dance' } },
    ['Fan Dance']    = { role = 'buff', gate = 'combat', status = { 'Saber Dance', 'Fan Dance' } },
    ['No Foot Rise'] = { role = 'buff', status = 'Finishing Move (5)' },
    ['Presto']       = { role = 'buff' },
    ['Spectral Jig'] = { role = 'buff', gate = 'idle', travel = true, priority = -20, status = { 'Sneak', 'Invisible' } },

    -- buff: job abilities ---------------------------------------------------------
    ['Composure']  = { role = 'buff', priority = 100 },
    ['Majesty']    = { role = 'buff', priority = 100, boost = { 'cure', potency = 25, area = 10 } },
    ['Boost']      = { role = 'buff', status = false },
    ['Avatar\'s Favor'] = { role = 'buff', pet = true },
    ['Shining Ruby']    = { role = 'buff', pet = { 'Carbuncle' } },
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

-- Phantom Rolls: { note, lucky, unlucky } (v2's table). Each shows the status named like it.
for name, r in pairs({
    ['Corsair\'s Roll'] = { 'EXP+', 5, 9 },      ['Ninja Roll'] = { 'EVA+', 4, 8 },
    ['Hunter\'s Roll'] = { 'ACC+', 4, 8 },       ['Chaos Roll'] = { 'ATK+', 4, 8 },
    ['Magus\'s Roll'] = { 'MDEF+', 2, 6 },       ['Healer\'s Roll'] = { 'Cure+', 3, 7 },
    ['Drachen Roll'] = { 'PACC+', 4, 8 },        ['Choral Roll'] = { 'SIR-', 2, 6 },
    ['Monk\'s Roll'] = { 'SB+', 3, 7 },          ['Beast Roll'] = { 'PATK+', 4, 8 },
    ['Samurai Roll'] = { 'STP+', 2, 6 },         ['Evoker\'s Roll'] = { 'Refresh+', 5, 9 },
    ['Rogue\'s Roll'] = { 'CRIT+', 5, 9 },       ['Warlock\'s Roll'] = { 'MACC+', 4, 8 },
    ['Fighter\'s Roll'] = { 'DA+', 5, 9 },       ['Puppet Roll'] = { 'PMAG+', 3, 7 },
    ['Gallant\'s Roll'] = { 'DMG Reflect', 3, 7 }, ['Wizard\'s Roll'] = { 'MATK+', 5, 9 },
    ['Dancer\'s Roll'] = { 'Regen+', 3, 7 },     ['Scholar\'s Roll'] = { 'CMP+', 2, 6 },
    ['Naturalist\'s Roll'] = { 'Enhancing+', 3, 7 }, ['Runeist\'s Roll'] = { 'MEVA+', 4, 8 },
    ['Companion\'s Roll'] = { 'Pet Regain & Regen', 2, 10 }, ['Bolter\'s Roll'] = { 'Move Speed+', 3, 9 },
    ['Caster\'s Roll'] = { 'Fast Cast+', 2, 7 },
}) do
    K[name] = { role = 'roll', note = r[1], lucky = r[2], unlucky = r[3] }
end

-- Rune Fencer's runes: each shows the status named like it.
for _, r in ipairs(run.RUNES) do
    K[r[1]] = { role = 'rune', status = r[1], rune = { element = r[2], resist = r[3], ailments = r[4] } }
end

-- Geomancer: an Indi- aura is on you, a Geo- one on a luopan (jobs/geo.lua); both show
-- the same status. An offensive Indi- shows only "Colure Active" on you; an offensive
-- Geo- goes on your battle target, where nothing can be read.
for name, status in pairs(geo.AURAS) do
    local priority = name == 'Refresh' and 50 or nil
    K['Indi-' .. name] = { role = 'buff', pick_one = 'indi', status = status, priority = priority }
    K['Geo-' .. name] = { role = 'geo', pick_one = 'geo', luopan = 'buff', main_only = true, status = status, priority = priority }
end
for _, name in ipairs(geo.DEBUFFS) do
    K['Indi-' .. name] = { role = 'buff', pick_one = 'indi', status = geo.COLURE }
    K['Geo-' .. name] = { role = 'geo', pick_one = 'geo_debuff', luopan = 'debuff', main_only = true, status = false }
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

return K
