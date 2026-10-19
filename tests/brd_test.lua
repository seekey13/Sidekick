-- Bard (jobs/brd.lua): songs by slot, on everyone near you or through Pianissimo on one member.
local engine = require('core.engine')
local settings = require('core.settings')
local brd = require('jobs.brd')
local fake = require('tests.fake')

local BRD, WHM = 10, 3
local MINUET, MARCH, BALLAD, PIANISSIMO, INVISIBLE = 198, 214, 196, 409, 69
local cat = fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo', 'Nightingale', 'Troubadour' })

local function named(list, name)
    for _, a in ipairs(list) do if a.name == name then return a end end
end

-- BRD 75 / WHM 37 with `others`; `buffs` on you, as stacks (an id twice stands twice).
local function snap(others, buffs, over, waits)
    local o = { main = BRD, main_lv = 75, sub = WHM, sub_lv = 37 }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap(others, o, waits)
    g.me.stacks = {}
    for _, id in ipairs(buffs or {}) do
        g.me.buffs[id] = true
        g.me.stacks[id] = (g.me.stacks[id] or 0) + 1
    end
    return g
end

-- A party player with these statuses, read with their stacks as yours are.
local function player(t, buffs)
    t.buffs, t.stacks = {}, {}
    for _, id in ipairs(buffs or {}) do
        t.buffs[id] = true
        t.stacks[id] = (t.stacks[id] or 0) + 1
    end
    return t
end

-- Song picks: { area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II', ... }.
local function cfg_with(picks, over)
    local cfg = settings.defaults()
    for k, v in pairs(picks or {}) do cfg.song[k] = v end
    for k, v in pairs(over or {}) do cfg.buff[k] = v end
    return cfg
end

local function decide(g, cfg, mem)
    local intent, why = engine.decide(g, cat, cfg or settings.defaults(), mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg or settings.defaults()), intent
end

test('catalog: songs are their own role, by the kind they show; Pianissimo a modifier with no chip', function ()
    local m = named(cat, 'Valor Minuet IV')
    eq({ m.role, m.status, m.duration, m.note, m.pick_one }, { 'song', { MINUET }, 120, '+ATK', nil })
    eq({ named(cat, 'Victory March').status, named(cat, 'Advancing March').status }, { { MARCH }, { MARCH } })
    local p = named(cat, 'Pianissimo')
    eq({ p.role, p.status, p.chip, p.applies }, { 'modifier', { PIANISSIMO }, nil, nil })
    eq(named(cat, 'Nightingale').role, 'buff')  -- still a buff row
    eq({ brd.slots(snap()), brd.slots(snap(nil, nil, { main = WHM, sub = BRD })), brd.slots(snap(nil, nil, { main = WHM, sub = 4 })) },
       { 2, 1, 0 })
end)

test('nothing picked: nothing sung', function ()
    eq(select(2, decide(snap({ player({ name = 'A' }) }))), 'nothing to do')
end)

test('an area song goes when someone near you lacks it, you included', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Victory March' })
    local g = snap({ player({ name = 'A' }), player({ name = 'B', dist = 15 }) })
    local cmd, intent = decide(g, cfg)
    eq({ cmd, intent.behavior, intent.why }, { '/ma "Valor Minuet IV" <me>', 'song', 'Me +1 lack it' })
    -- You and A have both; B is out of its reach (about 10 yalms) and doesn't count.
    g = snap({ player({ name = 'A' }, { MINUET, MARCH }), player({ name = 'B', dist = 15 }) }, { MINUET, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ player({ name = 'A' }, { MINUET }) }, { MINUET, MARCH })
    cmd, intent = decide(g, cfg)
    eq({ cmd, intent.why }, { '/ma "Victory March" <me>', 'A lacks it' })
end)

test('two of one kind stand twice; with one up, the one sung less lately goes', function ()
    local cfg = cfg_with({ area_1 = 'Victory March', area_2 = 'Advancing March' })
    local mem = {}
    local g = snap({}, { MARCH, MARCH })
    eq(select(2, decide(g, cfg, mem)), 'nothing to do')
    g = snap({}, {})
    local cmd, intent = decide(g, cfg, mem)
    eq(cmd, '/ma "Victory March" <me>')
    engine.sent(intent, g, mem)
    g = snap({}, { MARCH }, { now = 1030 })  -- one March up: Victory, sung last
    eq(decide(g, cfg, mem), '/ma "Advancing March" <me>')
end)

test('a song picked twice is one; a song you lack is skipped', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Valor Minuet IV' })
    local g = snap({}, { MINUET })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    eq(#brd.picked(cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Valor Minuet V' }), 'area', brd.actions(cat), 2), 1)  -- V is BRD 87
end)

test('a song on one member: Pianissimo first, then the song on them', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II' })
    local mem = {}
    local g = snap({ player({ name = 'A' }) })
    local cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Pianissimo" <me>', 'for Mage\'s Ballad II -> A: A' })
    engine.sent(intent, g, mem)
    cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.target.name }, { '/ma "Mage\'s Ballad II" 101', 'A' })
    g = snap({ player({ name = 'A' }, { BALLAD }) })
    eq(select(2, decide(g, cfg, {})), 'nothing to do')
end)

test('a song on you through Pianissimo is sung on <me>, with Pianissimo up', function ()
    local cfg = cfg_with({ me_1 = 'Mage\'s Ballad II' })
    eq(decide(snap({}, { PIANISSIMO }), cfg), '/ma "Mage\'s Ballad II" <me>')
end)

test('Pianissimo on recast: the songs on one member wait, and say so', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }) }, {}, nil, { Pianissimo = 20 })
    eq(select(2, decide(g, cfg)), 'holding Mage\'s Ballad II for Pianissimo')
    local below = fake.catalog(BRD, 15, WHM, 7, {})  -- no Pianissimo under BRD 20
    eq(select(2, engine.decide(snap({ player({ name = 'A' }) }, {}, { main_lv = 15, sub_lv = 7 }), below, cfg, {})), 'nothing to do')
end)

test('while an area song is owed and can\'t go, the songs on one member wait', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }, { MINUET }) }, {}, nil, { ['Valor Minuet IV'] = 10 })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ player({ name = 'A' }, { MINUET }) }, { MINUET })
    eq(decide(g, cfg), '/ja "Pianissimo" <me>')
end)

test('Pianissimo up: the area songs wait, the next song lands on one member', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }) }, { PIANISSIMO })
    eq(decide(g, cfg), '/ma "Mage\'s Ballad II" 101')
    cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('a member\'s own songs leave them fewer slots for the area ones', function ()
    -- A has Ballad of their own: one slot left, filled by either area song.
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Victory March', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }, { BALLAD, MARCH }) }, { MINUET, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ player({ name = 'A' }, { BALLAD }) }, { MINUET, MARCH })
    eq(decide(g, cfg), '/ma "Valor Minuet IV" <me>')
    -- Two of their own: no area song counts for them.
    cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II', p1_2 = 'Mage\'s Ballad' })
    g = snap({ player({ name = 'A' }, { BALLAD, BALLAD }) }, { MINUET })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    -- Yours too: with two songs of your own, the area song is for the others alone.
    cfg = cfg_with({ area_1 = 'Valor Minuet IV', me_1 = 'Mage\'s Ballad II', me_2 = 'Victory March' })
    g = snap({ player({ name = 'A' }, { MINUET }) }, { BALLAD, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('a trust\'s statuses come one per id: any one stands for them all', function ()
    local cfg = cfg_with({ area_1 = 'Victory March', area_2 = 'Advancing March' })
    local g = snap({ { name = 'Kupipi', kind = 'trust', buffs = { [MARCH] = true } } }, { MARCH, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ { name = 'Kupipi', kind = 'trust' } }, { MARCH, MARCH })
    eq(select(2, decide(g, cfg)).why, 'Kupipi lacks it')
end)

test('on a BRD subjob, one slot per target', function ()
    local sub = fake.catalog(WHM, 75, BRD, 37, { 'Pianissimo' })
    local cfg = cfg_with({ area_1 = 'Valor Minuet III', area_2 = 'Army\'s Paeon III' })
    local g = snap({}, { MINUET }, { main = WHM, sub = BRD })
    eq(select(2, engine.decide(g, sub, cfg, {})), 'nothing to do')
end)

test('the songs on one member: only one there, alive and in reach; nothing while you\'re Invisible', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II', p2_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A', dist = 25 }), player({ name = 'B', hpp = 0 }) }, { PIANISSIMO })
    local quiet = cfg_with({ p1_1 = 'Mage\'s Ballad II', p2_1 = 'Mage\'s Ballad II' })
    quiet.revive.on = false  -- B would be raised
    eq(select(2, decide(g, quiet)), 'nothing to do')
    g = snap({ player({ name = 'A', dist = 18 }) }, { PIANISSIMO })
    eq(decide(g, cfg), '/ma "Mage\'s Ballad II" 101')
    g = snap({ player({ name = 'A' }) }, { PIANISSIMO, INVISIBLE })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('Hold area buffs: an area song waits for a player who lacks it, the songs on one member with it', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p2_1 = 'Mage\'s Ballad II' }, { hold_aoe = true })
    local mem = {}
    local g = snap({ player({ name = 'Far', dist = 25 }), player({ name = 'B' }) })
    eq(select(2, engine.decide(g, cat, cfg, mem)), 'holding Valor Minuet IV: Far 25.0y away')
    eq(engine.gather(g, cfg, mem), '/p Gather together for Valor Minuet IV')
    -- One with a song of their own isn't waited for: the area song goes.
    cfg.song.p1_1 = 'Mage\'s Ballad'
    eq(decide(g, cfg), '/ma "Valor Minuet IV" <me>')
end)
