-- Phase 3a behaviors on fake snapshots: wake, recover, pet, follow, rest.
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, RDM, PLD, BLM, SAM, PUP, DRG = 3, 5, 7, 4, 12, 18, 14
local SLEEP, POISON, INVISIBLE = 2, 3, 69
local OIL = 18731
local snap = fake.snap

local function decide(g, cfg, list, mem)
    cfg = cfg or settings.defaults()
    local intent, why = engine.decide(g, list, cfg, mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg), intent
end

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
    eq({ cmd, intent.behavior, intent.why }, { '/ma "Cure" 101', 'wake', 'A asleep' })
    eq({ decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), cfg_with({ ['wake.on'] = false }), whm) },
        { nil, 'nothing to do' })
end)

test('wake: two asleep together get one area heal; spread, the focus member first', function ()
    local two = function (spread)
        return snap({ { name = 'A', buffs = { [SLEEP] = true } },
                      { name = 'B', buffs = { [SLEEP] = true }, pos = spread and { 30, 0, 0 } or nil } })
    end
    local cmd, intent = decide(two(false), nil, whm)
    eq({ cmd, intent.why }, { '/ma "Curaga" 101', '2 asleep' })
    eq(decide(two(true), nil, whm), '/ma "Cure" 101')
    eq(decide(two(true), cfg_with({ ['heal.focus'] = 'B' }), whm), '/ma "Cure" 102')
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
    eq(decide(g, nil, cat), '/ja "Devotion" 102')
    g.units[3].mpp = 50
    eq(decide(g, nil, cat), '/ja "Devotion" 101')
end)

test('recover: Meditate in combat under the TP line; Chivalry only at 3000 TP', function ()
    local sam = fake.catalog(SAM, 75, nil, 0, { 'Meditate' })
    eq(decide(snap(nil, { combat = true }), nil, sam), '/ja "Meditate" <me>')
    eq({ decide(snap(), nil, sam) }, { nil, 'nothing to do' })
    local pld = fake.catalog(PLD, 75, nil, 0, { 'Chivalry' })
    local g = snap()
    g.me.mpp, g.me.tp = 20, 2000
    eq({ decide(g, cfg_with({ ['heal.on'] = false }), pld) }, { nil, 'nothing to do' })
    g.me.tp = 3000
    eq(decide(g, cfg_with({ ['heal.on'] = false }), pld), '/ja "Chivalry" <me>')
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
    eq({ decide(snap(nil, { pet = automaton({ hpp = 60 }), ammo = OIL }), nil, pup) }, { nil, 'nothing to do' })
    local g = snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL })
    g.me.buffs[INVISIBLE] = true
    eq({ decide(g, nil, pup) }, { nil, 'nothing to do' })
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
    g.combat, g.me.uses_mp = false, false
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
