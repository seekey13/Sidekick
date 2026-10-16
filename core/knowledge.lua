--[[
    What the client DATs don't say: what an action is FOR.

    One row per family (the name without its tier: "Cure IV" -> Cure), shared by
    every job, so the Cure row covers WHM, RDM, PLD and SCH alike. Level, cost,
    recast, range, targets, element and SCH's Addendum gate all come from the
    DATs; see core/catalog.lua. A family with no row is not automated.

    A row is one use, or a list of uses when one action does several jobs
    (Chakra heals and cures). An exact name ("Healing Ruby II") beats its family.

    role       heal | pet_heal | remove | pet_remove | emergency | revive | recover | buff
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
    gate       'combat' | 'idle' (enemy-targeted actions are combat-only anyway)
    pick_one   families sharing a key keep one selection (enspells, storms, bar-elements)
    blocked_by skip while you have any of these statuses
    requires   needs any of these statuses on you
    priority   sorts ahead (+) / behind (-) inside its role
    main_only  never from a subjob
    pet        needs a pet out (true) or one of these pets
    kind       'ma' | 'ja' | 'pet': this use only for that command kind
    label      UI name when one action has several uses
    note       short UI hint
    travel     travel buff: still cast while Invisible
    duration   seconds a buff lasts (or per tier), for statuses read off packets (trusts)
    mob_skill  the id a jug pet's move carries in its action packet (the server's mob skill)
]]--

-- Status sets for removals (ids: several names repeat in the status table).
local CURSE    = { 9, 15, 20, 30 }  -- Curse, Doom, Curse II, Bane
local ESUNA    = { 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 20, 21, 30, 31 }
local ERASABLE = { 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
    140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }
local WALTZ    = { 3, 4, 5, 6, 8, 9, 11, 12, 13, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137,
    138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404 }
local PET_CLEANSE = { 3, 4, 5, 6, 8, 9, 31, 10, 11, 12, 13, 21, 128, 129, 130, 131, 132, 133, 134, 135,
    136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404 }

local LIGHT = { 'Light Arts', 'Addendum: White' }
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
    ['Accession']    = { role = 'emergency', requires = LIGHT, boost = { 'healing', area = 10, mp = 2, tiers = 4 } },
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

    -- revive -------------------------------------------------------------------
    ['Raise'] = { role = 'revive', gate = 'idle' },
    ['Arise'] = { role = 'revive', gate = 'idle' },

    -- recover ------------------------------------------------------------------
    ['Aspir']            = { role = 'recover' },
    ['Convert']          = { role = 'recover', priority = 100 },
    ['Chivalry']         = { role = 'recover' },
    ['Devotion']         = { role = 'recover' },
    ['Radial Arcana']    = { role = 'recover', main_only = true, pet = true, priority = 90 },
    ['Meditate']         = { role = 'recover', gives = 'tp', priority = 100, status = 801 },
    ['Reverse Flourish'] = { role = 'recover', gives = 'tp', priority = 100, requires = 'Finishing Move (5)' },

    -- pet ----------------------------------------------------------------------
    ['Spirit Link']   = { role = 'pet_heal', pet = true },
    ['Life Cycle']    = { role = 'pet_heal', pet = true, main_only = true },
    ['Dematerialize'] = { role = 'pet_heal', pet = true, main_only = true },
    ['Repair']        = { role = 'pet_heal', pet = true, priority = 100 },
    ['Role Reversal'] = { role = 'pet_heal', pet = true },
    ['Maintenance']   = { role = 'pet_remove', pet = true, removes = PET_CLEANSE },
    ['Reward'] = {
        { role = 'pet_heal', pet = true },
        { role = 'buff', label = 'Reward (Regen)', pet = true, status = false },
        { role = 'pet_remove', label = 'Reward (Erase)', pet = true, removes = PET_CLEANSE },
    },

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
    ['Harden Shell']    = { role = 'buff', status = 'Defense Boost' },
    ['Metallic Body']   = { role = 'buff', status = 'Stoneskin' },
    ['Diamondhide']     = { role = 'buff', status = 'Stoneskin' },
    ['Refueling']       = { role = 'buff', status = 'Haste' },
    ['Animating Wail']  = { role = 'buff', status = 'Haste' },
    ['Feather Barrier'] = { role = 'buff', status = 'Evasion Boost' },
    ['Memento Mori']    = { role = 'buff', status = 'Magic Atk. Boost' },
    ['Saline Coat']     = { role = 'buff', status = 'Magic Def. Boost' },
    ['Amplification']   = { role = 'buff', status = { 'Magic Atk. Boost', 'Magic Def. Boost' } },
    ['Zephyr Mantle']   = { role = 'buff', status = 'Blink' },
    ['Occultation']     = { role = 'buff', status = 'Blink' },
    ['Warm-Up']         = { role = 'buff', status = 'Accuracy Boost' },
    ['Triumphant Roar'] = { role = 'buff', status = 'Attack Boost' },
    ['Carcharian Verve']= { role = 'buff', status = 'Attack Boost' },
    ['Reactor Cool']    = { role = 'buff', status = 'Ice Spikes' },
    ['Plasma Charge']   = { role = 'buff', status = 'Shock Spikes' },
    ['Battery Charge']  = { role = 'buff', status = 'Refresh', priority = 50 },
    ['Magic Barrier']   = { role = 'buff', status = 'Magic Shield' },
    ['Barrier Tusk']    = { role = 'buff', status = 'Physical Shield' },
    ['O. Counterstance']= { role = 'buff', status = 'Counterstance' },
    ['Pyric Bulwark']   = { role = 'buff' },

    -- buff: Geomancer (Indi- on you, Geo- on a luopan: both show the aura status) --
    ['Indi-Regen']      = { role = 'buff', pick_one = 'indi', status = 539 },
    ['Indi-Refresh']    = { role = 'buff', pick_one = 'indi', status = 541, priority = 50 },
    ['Indi-STR']        = { role = 'buff', pick_one = 'indi', status = 542 },
    ['Indi-DEX']        = { role = 'buff', pick_one = 'indi', status = 543 },
    ['Indi-VIT']        = { role = 'buff', pick_one = 'indi', status = 544 },
    ['Indi-AGI']        = { role = 'buff', pick_one = 'indi', status = 545 },
    ['Indi-INT']        = { role = 'buff', pick_one = 'indi', status = 546 },
    ['Indi-MND']        = { role = 'buff', pick_one = 'indi', status = 547 },
    ['Indi-CHR']        = { role = 'buff', pick_one = 'indi', status = 548 },
    ['Indi-Fury']       = { role = 'buff', pick_one = 'indi', status = 549 },
    ['Indi-Barrier']    = { role = 'buff', pick_one = 'indi', status = 550 },
    ['Indi-Acumen']     = { role = 'buff', pick_one = 'indi', status = 551 },
    ['Indi-Fend']       = { role = 'buff', pick_one = 'indi', status = 552 },
    ['Indi-Precision']  = { role = 'buff', pick_one = 'indi', status = 553 },
    ['Indi-Voidance']   = { role = 'buff', pick_one = 'indi', status = 554 },
    ['Indi-Focus']      = { role = 'buff', pick_one = 'indi', status = 555 },
    ['Indi-Attunement'] = { role = 'buff', pick_one = 'indi', status = 556 },
    ['Indi-Haste']      = { role = 'buff', pick_one = 'indi', status = 580 },
    -- Offensive Indi auras show only "Colure Active" on you.
    ['Indi-Poison']     = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Frailty']    = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Slow']       = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Torpor']     = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Slip']       = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Languor']    = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Paralysis']  = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Indi-Vex']        = { role = 'buff', pick_one = 'indi', status = 612 },
    ['Geo-Regen']       = { role = 'buff', pick_one = 'geo', main_only = true, status = 539 },
    ['Geo-Refresh']     = { role = 'buff', pick_one = 'geo', main_only = true, status = 541, priority = 50 },
    ['Geo-STR']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 542 },
    ['Geo-DEX']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 543 },
    ['Geo-VIT']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 544 },
    ['Geo-AGI']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 545 },
    ['Geo-INT']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 546 },
    ['Geo-MND']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 547 },
    ['Geo-CHR']         = { role = 'buff', pick_one = 'geo', main_only = true, status = 548 },
    ['Geo-Fury']        = { role = 'buff', pick_one = 'geo', main_only = true, status = 549 },
    ['Geo-Barrier']     = { role = 'buff', pick_one = 'geo', main_only = true, status = 550 },
    ['Geo-Acumen']      = { role = 'buff', pick_one = 'geo', main_only = true, status = 551 },
    ['Geo-Fend']        = { role = 'buff', pick_one = 'geo', main_only = true, status = 552 },
    ['Geo-Precision']   = { role = 'buff', pick_one = 'geo', main_only = true, status = 553 },
    ['Geo-Voidance']    = { role = 'buff', pick_one = 'geo', main_only = true, status = 554 },
    ['Geo-Focus']       = { role = 'buff', pick_one = 'geo', main_only = true, status = 555 },
    ['Geo-Attunement']  = { role = 'buff', pick_one = 'geo', main_only = true, status = 556 },
    ['Geo-Haste']       = { role = 'buff', pick_one = 'geo', main_only = true, status = 580 },
    ['Lasting Emanation']  = { role = 'buff', pick_one = 'geo_ja', label = 'Lasting Emanation (Duration)', main_only = true, pet = true, status = false },
    ['Ecliptic Attrition'] = { role = 'buff', pick_one = 'geo_ja', label = 'Ecliptic Attrition (Effect)', main_only = true, pet = true, status = false },

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
