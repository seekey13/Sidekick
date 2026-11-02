-- Hold AOE gather (buff.hold_aoe): an area buff spell waits while a player in
-- your party who lacks it is out of its reach, and the party is asked to gather.
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, BLM, PROTECT, SNEAK, REFRESH = 3, 4, 40, 71, 43
local cat = fake.catalog(WHM, 75, BLM, 37)
local snap = fake.snap

-- Protectra on and held for the group; A near you with Protect, B 15 yalms off without.
local function setup(b)
    local cfg = settings.defaults()
    cfg.rows.Protectra = { on = true }
    cfg.buff.hold_aoe = true
    local g = snap({ { name = 'A', buffs = { [PROTECT] = true } }, b or { name = 'B', dist = 15 } })
    return g, cfg
end

local function decide(g, cfg, mem)
    local intent, why = engine.decide(g, cat, cfg, mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg), intent.why
end

test('off: an area buff goes out for those near you, whoever is far', function ()
    local g, cfg = setup()
    cfg.buff.hold_aoe = false
    eq({ decide(g, cfg) }, { '/ma "Protectra V" <me>', 'Me lacks it' })
end)

test('on: held while a player lacking it is out of reach, and why says so', function ()
    local g, cfg = setup()
    eq({ decide(g, cfg) }, { nil, 'holding Protectra V: B 15.0y away' })
    g.units[3].dist = nil
    eq({ decide(g, cfg) }, { nil, 'holding Protectra V: B not in sight' })
    g.units[3].dist = 9
    eq(decide(g, cfg), '/ma "Protectra V" <me>')
end)

test('on: with everyone near covered, a far player lacking it is waited for without asking', function ()
    local g, cfg = setup()
    local mem = {}
    g.me.buffs[PROTECT] = true
    eq({ decide(g, cfg, mem) }, { nil, 'holding Protectra V: B 15.0y away' })
    eq(engine.gather(g, cfg, mem), nil)
    g.units[3].dist = 5
    eq({ decide(g, cfg, mem) }, { '/ma "Protectra V" <me>', 'B lacks it' })
end)

test('on: a later held row someone near needs is the one asked for', function ()
    local g, cfg = setup()
    local mem = {}
    g.me.buffs[PROTECT] = true
    cfg.rows.Shellra = { on = true }
    decide(g, cfg, mem)
    eq(engine.gather(g, cfg, mem), '/p Gather together for Shellra V')
end)

test('on: no hold for one far who has it, a trust, the dead, another zone or the alliance', function ()
    for _, b in ipairs({
        { name = 'B', dist = 15, buffs = { [PROTECT] = true } },
        { name = 'B', dist = 15, kind = 'trust' },
        { name = 'B', dist = 15, hpp = 0 },
        { name = 'B', dist = 15, in_zone = false },
        { name = 'B', dist = 15, kind = 'alliance' },
    }) do
        local g, cfg = setup(b)
        cfg.revive.on = false
        eq(decide(g, cfg), '/ma "Protectra V" <me>', b.kind or 'B')
    end
end)

test('on: a held row lets the rows after it go', function ()
    local g, cfg = setup()
    cfg.rows.Sneak = { on = true, targets = { [1] = true } }  -- below Protectra in priority
    eq(decide(g, cfg), '/ma "Sneak" A')
    g.units[2].buffs[SNEAK] = true
    eq({ decide(g, cfg) }, { nil, 'holding Protectra V: B 15.0y away' })
    cfg.buff.hold_aoe = false
    g.units[2].buffs[SNEAK] = nil
    eq(decide(g, cfg), '/ma "Protectra V" <me>')
end)

test('gather: a party line at most every 5 seconds, only while one is held', function ()
    local g, cfg = setup()
    local mem = {}
    decide(g, cfg, mem)
    eq(engine.gather(g, cfg, mem), '/p Gather together for Protectra V')
    g.now = g.now + 4
    decide(g, cfg, mem)
    eq(engine.gather(g, cfg, mem), nil)
    g.now = g.now + 1
    decide(g, cfg, mem)
    eq(engine.gather(g, cfg, mem), '/p Gather together for Protectra V')
    g.now = g.now + 10
    g.units[3].dist = 5
    decide(g, cfg, mem)
    eq(engine.gather(g, cfg, mem), nil)
end)

test('gather: off holds quietly; in Japanese, the Japanese line and name', function ()
    local g, cfg = setup()
    local mem = {}
    cfg.buff.gather = false
    eq({ decide(g, cfg, mem) }, { nil, 'holding Protectra V: B 15.0y away' })
    eq(engine.gather(g, cfg, mem), nil)
    cfg.buff.gather, cfg.ui.japanese = true, true
    local jp
    for _, a in ipairs(cat) do if a.name == 'Protectra V' then jp = a.jp end end
    eq(engine.gather(g, cfg, mem),
        '/p \x8f\x57\x82\xdc\x82\xc1\x82\xc4\x82\xad\x82\xbe\x82\xb3\x82\xa2\x81\x42  ' .. jp)
end)

test('blue magic the DAT gives an area but that lands on you alone is never held, nor cast for others', function ()
    local blu = fake.catalog(16, 75, nil, 0)
    local cfg = settings.defaults()
    cfg.rows['Battery Charge'] = { on = true }
    cfg.buff.hold_aoe = true
    local g = snap({ { name = 'A' }, { name = 'B', dist = 20 } })
    local mem = {}
    eq(engine.command(engine.decide(g, blu, cfg, mem), cfg), '/ma "Battery Charge" <me>')
    g.me.buffs[REFRESH] = true
    eq({ engine.decide(g, blu, cfg, mem) }, { nil, 'nothing to do' })
    eq(engine.gather(g, cfg, mem), nil)
end)

test('only spells are held: an area job ability goes out for those near you', function ()
    local g, cfg = setup()
    local ja = {}
    for _, a in ipairs(cat) do
        if a.name == 'Protectra V' then for k, v in pairs(a) do ja[k] = v end end
    end
    ja.kind = 'ja'
    local intent = engine.decide(g, { ja }, cfg, {})
    eq(intent and intent.why, 'Me lacks it')
end)

test('gather in Japanese keeps the English name when there is no Japanese one', function ()
    local g, cfg = setup()
    local mem = { gather = { action = { name = 'Custom', jp = '' }, who = g.units[3], ask = true } }
    cfg.ui.japanese = true
    eq(engine.gather(g, cfg, mem), '/p \x8f\x57\x82\xdc\x82\xc1\x82\xc4\x82\xad\x82\xbe\x82\xb3\x82\xa2\x81\x42  Custom')
end)
