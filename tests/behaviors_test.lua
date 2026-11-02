-- Phase 3 behaviors on fake snapshots: wake, recover, pet, follow, rest, removal by item.
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, RDM, PLD, BLM, SAM, PUP, DRG, MNK = 3, 5, 7, 4, 12, 18, 14, 2
local SLEEP, POISON, INVISIBLE, SNEAK = 2, 3, 69, 71
local OIL = 18731
local snap = fake.snap

local function decide(g, cfg, list, mem) return fake.decide(g, list, cfg, mem) end

local function cfg_with(t)
    local cfg = settings.defaults()
    for path, v in pairs(t) do
        local parent, key = path:match('^(.-)%.([^.]+)$')
        cfg[parent][key] = v
    end
    return cfg
end

-- Wake ----------------------------------------------------------------------------

local whm = fake.catalog(WHM, 75, BLM, 37)

test('wake: the cheapest heal that wakes, on a sleeper at full HP', function ()
    local cmd, intent = decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), nil, whm)
    eq({ cmd, intent.behavior, intent.why }, { '/ma "Cure" A', 'wake', 'A asleep' })
    eq({ decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), cfg_with({ ['wake.on'] = false }), whm) },
        { nil, 'nothing to do' })
end)

test('wake: two asleep together get one area heal; spread, the focus member first', function ()
    local two = function (spread)
        return snap({ { name = 'A', buffs = { [SLEEP] = true } },
                      { name = 'B', buffs = { [SLEEP] = true }, pos = spread and { 30, 0, 0 } or nil } })
    end
    local cmd, intent = decide(two(false), nil, whm)
    eq({ cmd, intent.why }, { '/ma "Curaga" A', '2 asleep' })
    eq(decide(two(true), nil, whm), '/ma "Cure" A')
    eq(decide(two(true), cfg_with({ ['heal.focus'] = 'B' }), whm), '/ma "Cure" B')
end)

-- Recover ---------------------------------------------------------------------------

test('recover: Convert under the MP line, only while it gains and you are out of danger', function ()
    local rdm = fake.catalog(RDM, 75, nil, 0, { 'Convert' })
    local cfg = cfg_with({ ['heal.on'] = false })
    local g = snap()
    g.me.mpp, g.me.mp, g.me.hp = 20, 200, 1000
    local cmd, intent = decide(g, cfg, rdm)
    eq({ cmd, intent.why }, { '/ja "Convert" <me>', 'MP 20%' })
    g.me.hpp = 40
    eq({ decide(g, cfg, rdm) }, { nil, 'nothing to do' })
    g.me.hpp, g.me.mpp = 100, 50
    eq({ decide(g, cfg, rdm) }, { nil, 'nothing to do' })
end)

test('recover: Devotion on the member lowest on MP, never one with no MP', function ()
    local cat = fake.catalog(WHM, 75, nil, 0, { 'Devotion' })
    local g = snap({ { name = 'A', mpp = 25 }, { name = 'B', mpp = 10 }, { name = 'War', mpp = 0, uses_mp = false } })
    eq(decide(g, nil, cat), '/ja "Devotion" B')
    g.units[3].mpp = 50
    eq(decide(g, nil, cat), '/ja "Devotion" A')
end)

test('recover: Meditate in combat under the TP line; Chivalry from its own TP line', function ()
    local sam = fake.catalog(SAM, 75, nil, 0, { 'Meditate' })
    eq(decide(snap(nil, { combat = true }), nil, sam), '/ja "Meditate" <me>')
    eq({ decide(snap(), nil, sam) }, { nil, 'nothing to do' })
    local pld = fake.catalog(PLD, 75, nil, 0, { 'Chivalry' })
    local cfg = cfg_with({ ['heal.on'] = false })
    local g = snap()
    g.me.mpp, g.me.tp = 20, 2000
    eq({ decide(g, cfg, pld) }, { nil, 'nothing to do' })
    g.me.tp = 3000
    eq(decide(g, cfg, pld), '/ja "Chivalry" <me>')
    g.me.tp, cfg.recover.min_tp = 2000, 1500
    eq(decide(g, cfg, pld), '/ja "Chivalry" <me>')
end)

test('recover: Aspir from the battle target', function ()
    local g = snap(nil, { combat = true, bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 } })
    g.me.mpp = 20
    eq(decide(g, nil, whm), '/ma "Aspir" <bt>')
end)

-- Pet ------------------------------------------------------------------------------

local pup = fake.catalog(PUP, 75, nil, 0, { 'Repair', 'Maintenance', 'Deploy' })
local function automaton(t)
    local p = { name = 'Automaton', hpp = 100, dist = 3, status = 0, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

test('pet: Repair under the pet HP line, only with an oil worn', function ()
    eq({ decide(snap(nil, { pet = automaton({ hpp = 40 }) }), nil, pup) }, { nil, 'nothing to do' })
    local cmd, intent = decide(snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL }), nil, pup)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Repair" <me>', 'pet', 'Automaton 40%' })
    eq(decide(snap(nil, { pet = automaton({ hpp = 40 }), ammo = 19185 }), nil, pup), '/ja "Repair" <me>')  -- +3
    eq({ decide(snap(nil, { pet = automaton({ hpp = 60 }), ammo = OIL }), nil, pup) }, { nil, 'nothing to do' })
    local g = snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL })
    g.me.buffs[INVISIBLE] = true
    eq({ decide(g, nil, pup) }, { nil, 'invisible' })
end)

test('pet: Repair only within 20 yalms of the automaton, as the server allows', function ()
    eq({ decide(snap(nil, { pet = automaton({ hpp = 40, dist = 25 }), ammo = OIL }), nil, pup) }, { nil, 'nothing to do' })
end)

test('pet: cared for and sent in while healing waits for a cure', function ()
    local cat = fake.catalog(PUP, 75, WHM, 37, { 'Repair', 'Deploy' })
    local waits = {}
    for _, a in ipairs(cat) do if a.role == 'heal' then waits[a.name] = 5 end end
    local hurt = { { name = 'A', hpp = 45 } }
    eq(decide(snap(hurt, { pet = automaton({ hpp = 40 }), ammo = OIL }, waits), nil, cat), '/ja "Repair" <me>')
    local cfg = settings.defaults()
    cfg.rows.Deploy = { on = true }
    local g = snap(hurt, { pet = automaton(), bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 }, combat = true }, waits)
    eq(decide(g, cfg, cat), '/pet "Deploy" <bt>')
    g.pet = nil
    eq({ decide(g, cfg, cat) }, { nil, 'waiting for a cure' })
end)

test('pet: Maintenance clears what ails it', function ()
    eq(decide(snap(nil, { pet = automaton({ buffs = { [POISON] = true } }), ammo = OIL }), nil, pup),
        '/ja "Maintenance" <me>')
end)

test('pet: sent at the battle target when idle, opt-in', function ()
    local bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 }
    local cfg = settings.defaults()
    eq({ decide(snap(nil, { pet = automaton(), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
    cfg.rows.Deploy = { on = true }
    local cmd, intent = decide(snap(nil, { pet = automaton(), bt = bt, combat = true }), cfg, pup)
    eq({ cmd, intent.behavior }, { '/pet "Deploy" <bt>', 'pet_send' })
    eq({ decide(snap(nil, { pet = automaton({ status = 1 }), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, { pet = automaton({ hpp = 0 }), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
end)

test('pet: Spirit Link waits while you are in danger yourself', function ()
    local drg = fake.catalog(DRG, 75, nil, 0, { 'Spirit Link' })
    local g = snap(nil, { pet = automaton({ name = 'Wyvern', hpp = 30 }) })
    eq(decide(g, nil, drg), '/ja "Spirit Link" <me>')
    g.me.hpp = 40
    eq({ decide(g, cfg_with({ ['heal.on'] = false }), drg) }, { nil, 'nothing to do' })
end)

-- Follow and rest -------------------------------------------------------------------------

local function follower()
    return cfg_with({ ['follow.on'] = true, ['follow.target'] = 'a' })
end

test('follow: past the distance, by party slot; not while moving', function ()
    local cmd, intent = decide(snap({ { name = 'B' }, { name = 'A', dist = 8 } }), follower(), whm)
    eq({ cmd, intent.why }, { '/follow <p2>', 'A 8.0y away' })
    eq({ decide(snap({ { name = 'A', dist = 4 } }), follower(), whm) }, { nil, 'nothing to do' })
    eq({ decide(snap({ { name = 'A', dist = 8 } }, { moving = true }), follower(), whm) }, { nil, 'moving' })
end)

test('rest: after the quiet delay, out of combat, MP not full', function ()
    local cfg = cfg_with({ ['rest.on'] = true })
    local g = snap(nil, { moved_at = 990 })
    g.me.mpp = 50
    local cmd, intent = decide(g, cfg, whm)
    eq({ cmd, intent.why }, { '/heal on', 'MP 50%' })
    eq({ decide(g, cfg, whm, { sent_at = 997 }) }, { nil, 'nothing to do' })
    g.moved_at = 998
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.moved_at, g.combat = 990, true
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.combat, g.combat_at = false, 997  -- the fight just ended
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.combat_at, g.me.uses_mp = nil, false
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
end)

test('resting: nothing else runs; stand at full MP or when the leader leaves', function ()
    local cfg = cfg_with({ ['rest.on'] = true, ['follow.target'] = 'A' })
    local g = snap({ { name = 'A', hpp = 40 } }, { resting = true })
    g.me.mpp = 50
    eq({ decide(g, cfg, whm) }, { nil, 'resting' })
    g.me.mpp = 100
    eq(decide(g, cfg, whm), '/heal off')
    g.me.mpp, g.units[2].dist = 50, 9
    local cmd, intent = decide(g, cfg, whm)
    eq({ cmd, intent.why }, { '/heal off', 'A left' })
end)

-- Removal by item, and the other removers only ever on you --------------------------------

local SILENCE, PARALYSIS, BLINDNESS, BIND, WEIGHT, DOOM = 6, 4, 5, 11, 12, 15
local ANTIDOTE, PANACEA, ECHO_DROPS, REMEDY = 4148, 4149, 4151, 4155

test('items: Echo Drops when silenced, opt-in, only with one in your bag, amnesia or not', function ()
    local g = snap(nil, { silenced = true, amnesia = true, items = { [ECHO_DROPS] = 3 } })
    g.me.buffs[SILENCE] = true
    local cfg = settings.defaults()
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    cfg.rows['Echo Drops'] = { on = true }
    local cmd, intent = decide(g, cfg, whm)
    eq({ cmd, intent.behavior, intent.why }, { '/item "Echo Drops" <me>', 'remove', 'Me' })
    g.items = {}
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
end)

test('items: a spell that can go first; then the most specific item you carry, for you only', function ()
    local cfg = settings.defaults()
    for _, k in ipairs({ 'Antidote', 'Remedy', 'Panacea' }) do cfg.rows[k] = { on = true } end
    local carried = { [ANTIDOTE] = 1, [REMEDY] = 1, [PANACEA] = 1 }
    local g = snap(nil, { items = carried })
    g.me.buffs[POISON] = true
    eq(decide(g, cfg, whm), '/ma "Poisona" <me>')
    local blm = fake.catalog(BLM, 75, nil, 0)
    g = snap({ { name = 'A', buffs = { [POISON] = true } } }, { items = carried })
    eq({ decide(g, cfg, blm) }, { nil, 'nothing to do' })
    g.me.buffs[POISON] = true
    eq(decide(g, cfg, blm), '/item "Antidote" <me>')
    g.me.buffs[POISON], g.me.buffs[PARALYSIS] = nil, true
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')
    carried[REMEDY] = nil
    eq(decide(g, cfg, blm), '/item "Panacea" <me>')
end)

test('items: Doom first, then Silence if you cast, then the one clearing the most of yours', function ()
    local blm = fake.catalog(BLM, 75, nil, 0)
    local cfg, carried = settings.defaults(), {}
    for _, a in ipairs(blm) do if a.kind == 'item' then cfg.rows[a.family] = { on = true }; carried[a.id] = 1 end end
    local g = snap(nil, { items = carried })
    for _, id in ipairs({ DOOM, SILENCE, POISON }) do g.me.buffs[id] = true end
    eq(decide(g, cfg, blm), '/item "Holy Water" <me>')
    g.me.buffs[DOOM] = nil
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')      -- Silence and Poison in one
    carried[REMEDY] = nil
    eq(decide(g, cfg, blm), '/item "Echo Drops" <me>')  -- you cast: Silence before Poison
    g.me.uses_mp = false
    eq(decide(g, cfg, blm), '/item "Antidote" <me>')    -- you don't
    carried[REMEDY] = 1                                 -- Bad Breath: Remedy, then Panacea; never the Ointment
    for _, id in ipairs({ PARALYSIS, BLINDNESS, BIND, WEIGHT }) do g.me.buffs[id] = true end
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')
    for _, id in ipairs({ POISON, PARALYSIS, BLINDNESS, SILENCE }) do g.me.buffs[id] = nil end
    eq(decide(g, cfg, blm), '/item "Panacea" <me>')
end)

test('items: a status left on still makes the Ointment a gamble', function ()
    local blm, cfg = fake.catalog(BLM, 75, nil, 0), settings.defaults()
    for _, k in ipairs({ 'Remedy Ointment', 'Remedy' }) do cfg.rows[k] = { on = true } end
    cfg.remove.skip = { poison = true }
    local g = snap(nil, { items = { [5356] = 1, [REMEDY] = 1 } })
    g.me.buffs[POISON], g.me.buffs[BLINDNESS] = true, true
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')  -- the Ointment could take the Poison left on
end)

test('items: an /item the server never answered holds the next one 4s', function ()
    local blm, cfg, mem = fake.catalog(BLM, 75, nil, 0), settings.defaults(), {}
    cfg.rows['Echo Drops'] = { on = true }
    local g = snap(nil, { items = { [ECHO_DROPS] = 3 } })
    g.me.buffs[SILENCE] = true
    local _, intent = decide(g, cfg, blm, mem)
    engine.sent(intent, g, mem)
    g.now = 1002
    eq({ decide(g, cfg, blm, mem) }, { nil, 'nothing to do' })
    g.finished = 1001  -- it went off
    eq(decide(g, cfg, blm, mem), '/item "Echo Drops" <me>')
    g.finished, g.now = nil, 1004
    eq(decide(g, cfg, blm, mem), '/item "Echo Drops" <me>')
end)

test('Chakra clears only your own poison, not a member\'s near you', function ()
    local mnk = fake.catalog(MNK, 75, nil, 0, { 'Chakra' })
    local g = snap({ { name = 'A', buffs = { [POISON] = true } } })
    eq({ decide(g, nil, mnk) }, { nil, 'nothing to do' })
    g.me.buffs[POISON] = true
    eq(decide(g, nil, mnk), '/ja "Chakra" <me>')
end)

-- Invisible and Sneak -------------------------------------------------------------

-- `g` with `id` on you.
local function under(g, id) g.me.buffs[id] = true; return g end

test('Invisible: danger healing goes, efficient healing waits; Sneak stops neither', function ()
    eq({ decide(under(snap({ { name = 'A', hpp = 60 } }), INVISIBLE), nil, whm) }, { nil, 'invisible' })
    local cmd, intent = decide(under(snap({ { name = 'A', hpp = 40 } }), INVISIBLE), nil, whm)
    eq({ cmd ~= nil, intent.behavior, intent.why }, { true, 'heal', 'danger: A 40%' })
    eq(decide(under(snap({ { name = 'A', hpp = 20 } }), INVISIBLE), nil, whm) ~= nil, true, 'critical too')
    eq(select(2, decide(under(snap({ { name = 'A', hpp = 60 } }), SNEAK), nil, whm)).why, 'efficient: A 60%')
end)

-- Sneak, Invisible and Protect kept up on you and P1.
local function travel_cfg()
    local cfg = settings.defaults()
    for _, key in ipairs({ 'Protect', 'Sneak', 'Invisible' }) do
        cfg.rows[key] = { on = true, targets = { [0] = true, [1] = true } }
    end
    return cfg
end

test('Invisible: no removal, wake, pet care or other buff, only travel buffs; Sneak stops none', function ()
    local cfg = travel_cfg()
    local others = { { name = 'A', buffs = { [POISON] = true, [SNEAK] = true, [INVISIBLE] = true } },
                     { name = 'B', buffs = { [SLEEP] = true } } }
    eq(decide(under(snap(others), SNEAK), cfg, whm), '/ma "Poisona" A')
    eq(decide(under(snap(others), INVISIBLE), cfg, whm), '/ma "Sneak" <me>')
    eq({ decide(under(under(snap(others), SNEAK), INVISIBLE), cfg, whm) }, { nil, 'invisible' })
    local g = snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL })
    eq(decide(under(g, SNEAK), nil, pup), '/ja "Repair" <me>')
    eq({ decide(under(g, INVISIBLE), nil, pup) }, { nil, 'invisible' })
    eq(decide(under(snap({ { name = 'A', dist = 12 } }), INVISIBLE), follower(), whm), '/follow <p1>')
end)

test('your own Invisible goes last: members first, your Sneak and other buffs before it', function ()
    local cfg = travel_cfg()
    local function with(mine, theirs)
        local g = snap({ { name = 'A', buffs = theirs } })
        for _, id in ipairs(mine) do g.me.buffs[id] = true end
        return g
    end
    local PROTECT = 40
    eq(decide(with({}, {}), cfg, whm), '/ma "Protect IV" <me>')
    eq(decide(with({ PROTECT }, { [PROTECT] = true }), cfg, whm), '/ma "Sneak" <me>')
    eq(decide(with({ PROTECT, SNEAK }, { [PROTECT] = true }), cfg, whm), '/ma "Sneak" A')
    eq(decide(with({ PROTECT, SNEAK }, { [PROTECT] = true, [SNEAK] = true }), cfg, whm), '/ma "Invisible" A')
    local all = { [PROTECT] = true, [SNEAK] = true, [INVISIBLE] = true }
    local cmd, intent = decide(with({ PROTECT, SNEAK }, all), cfg, whm)
    eq({ cmd, intent.behavior }, { '/ma "Invisible" <me>', 'buff' })
    -- A member loses theirs while you're Invisible: theirs again, then yours.
    eq(decide(with({ PROTECT, SNEAK, INVISIBLE }, { [PROTECT] = true, [SNEAK] = true }), cfg, whm),
        '/ma "Invisible" A')
    eq({ decide(with({ PROTECT, SNEAK, INVISIBLE }, all), cfg, whm) }, { nil, 'invisible' })
end)

test('Spectral Jig is used again only once both its Sneak and its Invisible are off', function ()
    local dnc = fake.catalog(19, 75, WHM, 37, { 'Spectral Jig' })
    local cfg = settings.defaults()
    cfg.rows['Spectral Jig'] = { on = true }
    cfg.rows.Sneak = { on = true, targets = { [0] = true } }
    local g = snap(nil, { main = 19, sub = WHM })
    eq(decide(g, cfg, dnc), '/ja "Spectral Jig" <me>', 'not Sneak first: the Jig gives it')
    eq({ decide(under(g, SNEAK), cfg, dnc) }, { nil, 'nothing to do' }, 'Invisible broken: Sneak is still up')
    g = under(snap(nil, { main = 19, sub = WHM }), INVISIBLE)
    eq(decide(g, cfg, dnc), '/ma "Sneak" <me>', 'Sneak lost, Invisible up: the Jig would do nothing')
end)

test('your own Invisible waits for a member\'s Sneak briefly on recast, not a long one', function ()
    local cfg = travel_cfg()
    local PROTECT = 40
    local function g(wait)
        local s = snap({ { name = 'A', buffs = { [PROTECT] = true } } }, nil, { Sneak = wait })
        s.me.buffs[PROTECT], s.me.buffs[SNEAK] = true, true
        return s
    end
    eq(decide(g(3), cfg, whm), '/ma "Invisible" A')
    local short = g(3)
    short.units[2].buffs[INVISIBLE] = true
    eq({ decide(short, cfg, whm) }, { nil, 'nothing to do' }, 'A lacks only Sneak, 3s off')
    local long = g(30)
    long.units[2].buffs[INVISIBLE] = true
    eq(decide(long, cfg, whm), '/ma "Invisible" <me>')
end)

test('your own Invisible waits at most OTHERS_FIRST seconds for a buff briefly on recast', function ()
    local cfg = travel_cfg()
    local mem = {}
    local g = snap({ { name = 'A', buffs = { [SNEAK] = true, [INVISIBLE] = true } } })
    g.recast = function (a) return a.name:find('Protect') and 5 or 0 end
    g.me.buffs[SNEAK] = true
    eq({ decide(g, cfg, whm, mem) }, { nil, 'nothing to do' }, 'Protect 5s off, A lacks it')
    g.now = g.now + 14
    eq({ decide(g, cfg, whm, mem) }, { nil, 'nothing to do' })
    g.now = g.now + 1
    eq(decide(g, cfg, whm, mem), '/ma "Invisible" <me>', 'waited long enough')
    g.recast = function () return 0 end
    eq(decide(g, cfg, whm, {}), '/ma "Protect IV" <me>')
    g.recast = function (a) return a.name:find('Protect') and 60 or 0 end
    eq(decide(g, cfg, whm, {}), '/ma "Invisible" <me>', 'a long recast is not waited for')
end)

test('resting starts and stops while you are Invisible', function ()
    local cfg = cfg_with({ ['rest.on'] = true })
    local g = under(snap(nil, { moved_at = 0 }), INVISIBLE)
    g.me.mpp = 10
    eq(decide(g, cfg, whm), '/heal on')
end)
