-- core/engine.lua and the behaviors, on fake snapshots over a real catalog
-- (WHM 75 / BLM 37 from the dumped client data).
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local cat = fake.catalog(3, 75, 4, 37, { 'Divine Seal', 'Martyr' })
local snap = fake.snap

local function decide(g, cfg, mem, list)
    local intent, why = engine.decide(g, list or cat, cfg or settings.defaults(), mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg or settings.defaults()), intent
end

-- Healing (behaviors/heal.lua). Members have 1000 HP; WHM 75 table potencies x 1.25.
local heal = require('behaviors.heal')
local game = require('core.game')
local observed = require('core.observed')
local can = require('core.can')

local DNC, SCH, PLD = 19, 20, 7
local DIVINE_SEAL, LIGHT_ARTS, ACCESSION, MAJESTY, REGEN = 78, 358, 366, 621, 42
local dnc = fake.catalog(3, 75, DNC, 37, { 'Curing Waltz', 'Curing Waltz II' })
local sch = fake.catalog(SCH, 75, nil, 0, { 'Accession' })

-- Four members at `hpp`, together or 20 yalms apart (past every heal's 10y radius).
local function four(hpp, spread)
    local t = {}
    for i = 1, 4 do t[i] = { name = 'P' .. i, hpp = hpp, pos = spread and { i * 20, 0, 0 } or nil } end
    return t
end

local function with(g, statuses)
    for _, id in ipairs(statuses) do g.me.buffs[id] = true end
    return g
end

-- Regen out of the way, for tests about something else.
local function no_regen()
    local cfg = settings.defaults()
    cfg.rows.Regen = { on = false }
    return cfg
end

test('efficient: the best HP per MP, never paying for overheal', function ()
    local cmd, intent = decide(snap({ { name = 'A', hpp = 70 } }), no_regen())
    eq({ cmd, intent.why }, { '/ma "Cure III" 101', 'efficient: A 70%' })  -- 250 of 300 for 46 MP
end)

test('efficient runs from the danger line up to full HP', function ()
    local cmd, intent = decide(snap({ { name = 'A', hpp = 90 } }))
    eq({ cmd, intent.why }, { '/ma "Cure" 101', 'efficient: A 90%' })  -- 37.5 of 100 for 8 MP
    eq({ decide(snap({ { name = 'A', hpp = 100 } })) }, { nil, 'nothing to do' })
end)

test('efficient waits while every heal would overheal', function ()
    eq({ decide(snap({ { name = 'A', hpp = 98 } })) }, { nil, 'nothing to do' })  -- 20 missing: Cure is 37.5
    eq(decide(snap({ { name = 'A', hpp = 96 } })), '/ma "Cure" 101')              -- 40 missing: Cure fits
    eq(decide(snap({ { name = 'A', hpp = 49 }, { name = 'B', hpp = 98 } }, nil, { Cure = 5 })),
        '/ma "Cure V" 101')  -- danger is untouched
end)

test('Regen: the biggest whose whole total lands', function ()
    eq(decide(snap({ { name = 'A', hpp = 85 } })), '/ma "Regen" 101')      -- 125 of 150 for 15 MP
    eq(decide(snap({ { name = 'A', hpp = 70 } })), '/ma "Regen II" 101')   -- 240 of 300 for 36 MP
    eq(decide(snap({ { name = 'A', hpp = 60 } })), '/ma "Regen III" 101')  -- 400 of 400 for 64 MP
end)

test('Regen wins a big enough gap; while it ticks efficient waits, danger does not', function ()
    eq(decide(snap({ { name = 'A', hpp = 60 } })), '/ma "Regen III" 101')  -- 400 over 60s for 64 MP
    local pending = { name = 'A', hpp = 60, hot = 400, buffs = { [REGEN] = true } }
    eq({ decide(snap({ pending })) }, { nil, 'nothing to do' })
    eq(decide(snap({ { name = 'A', hpp = 45, hot = 400, buffs = { [REGEN] = true } } })), '/ma "Cure V" 101')
end)

test('a Regen not yours counts as a whole Regen I still to come', function ()
    local theirs = function (hpp) return { { name = 'A', hpp = hpp, buffs = { [REGEN] = true } } } end
    eq({ decide(snap(theirs(90))) }, { nil, 'nothing to do' })  -- 100 missing, 125 on its way
    eq(decide(snap(theirs(70))), '/ma "Cure" 101')              -- 300 missing: the other 175
    eq(decide(snap(theirs(45))), '/ma "Cure V" 101')            -- danger ignores it
    eq({ decide(snap({ { name = 'A', hpp = 90, buffs = { [539] = true } } })) }, { nil, 'nothing to do' })  -- GEO aura
end)

test('a Regen sent is counted once it lands, tick by tick', function ()
    local _, intent = decide(snap({ { name = 'A', hpp = 60 } }))
    intent.sent(0)
    observed.landed('ma111', 101, 10)
    eq({ observed.hot(101, 10), observed.hot(101, 40), observed.hot(101, 70) }, { 400, 200, 0 })
end)

test('Curaga for a bunched group, a single heal once they spread', function ()
    local cmd, intent = decide(snap(four(70)))
    eq({ cmd, intent.why }, { '/ma "Curaga III" <me>', 'efficient: P1 70% +3' })  -- 1200 HP for 180 MP
    eq(decide(snap(four(70, true))), '/ma "Regen II" 101')
end)

test('each member helped weighs in: Curaga for three, one at a time for two', function ()
    local three = { { name = 'P1', hpp = 70 }, { name = 'P2', hpp = 70 }, { name = 'P3', hpp = 70 } }
    eq(decide(snap(three)), '/ma "Curaga III" <me>')  -- 900 for 180 MP x sqrt 3 beats Regen II's 240 for 36
    table.remove(three)
    eq(decide(snap(three)), '/ma "Regen II" 101')     -- 600 for 180 MP x sqrt 2 does not
end)

test('danger: an instant waltz before a slower, bigger cure', function ()
    local g = snap({ { name = 'A', hpp = 45 } })
    g.me.tp = 400
    local cmd, intent = decide(g, nil, nil, dnc)
    eq({ cmd, intent.why }, { '/ja "Curing Waltz II" 101', 'danger: A 45%' })
end)

test('critical: Divine Seal, then the boosted cure that does the job cheapest', function ()
    local g = snap({ { name = 'A', hpp = 20 } })
    eq(decide(g), '/ja "Divine Seal" <me>')
    eq(decide(with(g, { DIVINE_SEAL })), '/ma "Cure IV" 101')  -- x2 caps IV and V at 800: the cheaper
    eq(decide(snap({ { name = 'A', hpp = 20 } }, nil, { ['Divine Seal'] = 600 })), '/ja "Martyr" 101')
end)

test('learned potency replaces the table; a reading under Divine Seal is halved', function ()
    local g = snap({ { name = 'A', hpp = 60 } })
    g.learned = { ma3 = 400 }
    eq(decide(g), '/ma "Cure III" 101')  -- Regen III without it
    local _, intent = decide(with(snap({ { name = 'A', hpp = 20 } }), { DIVINE_SEAL }))
    intent.sent(0)
    observed.healed('ma4', 101, 800)  -- capped at the 800 missing: says nothing
    eq(observed.learned.ma4, nil)
    observed.healed('ma4', 101, 600)
    eq(observed.learned.ma4, 300)
end)

test('Majesty spreads one Cure over a bunched group, and is divided out of a reading', function ()
    local pld = fake.catalog(PLD, 75, nil, 0, { 'Majesty' })
    local cmd, intent = decide(with(snap(four(70)), { MAJESTY }), nil, nil, pld)
    eq({ cmd, intent.why }, { '/ma "Cure III" <me>', 'efficient: P1 70% +3' })
    cmd, intent = decide(with(snap(four(70, true)), { MAJESTY }), nil, nil, pld)
    eq({ cmd, intent.why }, { '/ma "Cure III" 101', 'efficient: P1 70%' })
    intent.sent(0)
    observed.healed('ma3', 101, 250)
    eq(observed.learned.ma3, 200)  -- 250 / 1.25
end)

test('danger fires Accession when a spread Cure IV beats every single cure', function ()
    local three = { four(45)[1], four(45)[2], four(45)[3] }
    local cmd, intent = decide(with(snap(three), { LIGHT_ARTS }), nil, nil, sch)
    eq({ cmd, intent.why }, { '/ja "Accession" <me>', 'danger: P1 45% +2, for Cure IV' })
    eq(decide(with(snap({ { name = 'A', hpp = 45 } }), { LIGHT_ARTS }), nil, nil, sch), '/ma "Cure IV" 101')
    eq(decide(with(snap(four(70)), { LIGHT_ARTS }), no_regen(), nil, sch), '/ma "Cure III" 101')  -- efficient: no charge
    -- Up (by hand or from the line above): Cure I-IV spread, Cure V never does.
    local whm_sch = fake.catalog(3, 75, SCH, 37, { 'Accession' })
    three = { four(45)[1], four(45)[2], four(45)[3] }
    eq(decide(with(snap(three), { LIGHT_ARTS, ACCESSION }), nil, nil, whm_sch), '/ma "Cure IV" <me>')
end)

test('a stratagem with its timer running but a charge banked is usable', function ()
    eq({ game.charge_wait(100, 75), game.charge_wait(200, 75), game.charge_wait(100, 37) }, { 0, 8, 0 })
    local accession
    for _, a in ipairs(sch) do if a.name == 'Accession' then accession = a end end
    local g = with(snap({}), { LIGHT_ARTS })
    g.recast = function () return game.charge_wait(100, 75) end
    eq(can.use(accession, g), true)
end)

test('sky: the day and weather bonus, one cast in three', function ()
    local function sky(weather, day, storm)
        local g = snap({}, { weather = weather, day = day })
        if storm then g.me.buffs[184] = true end  -- Aurorastorm
        return math.floor(heal.sky(g) * 1000 + 0.5) / 1000
    end
    eq({ sky(17, 6), sky(19, 7), sky(18, nil, true), sky(16, nil, true) }, { 0.117, -0.117, 0.033, 0.083 })
end)

test('low on MP, a TP heal beats an MP heal by share of what you have', function ()
    local g = snap({ { name = 'A', hpp = 70 } })
    g.me.tp, g.me.mp = 1000, 60
    eq(decide(g, no_regen(), nil, dnc), '/ja "Curing Waltz II" 101')
    g.me.mp = 1000
    eq(decide(g, no_regen(), nil, dnc), '/ma "Cure III" 101')
end)

test('TP at the cap is free: a waltz then; at 2650 TP the cure again', function ()
    local g = snap({ { name = 'A', hpp = 70 } })
    g.me.tp = 3000
    eq(decide(g, no_regen(), nil, dnc), '/ja "Curing Waltz II" 101')
    g.me.tp = 2650
    eq(decide(g, no_regen(), nil, dnc), '/ma "Cure III" 101')
end)

test('a heal nearly off recast holds in danger (not debuff removal), never in efficient', function ()
    local waits = {}
    for _, a in ipairs(cat) do if a.role == 'heal' then waits[a.name] = 5 end end
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, targets = { [1] = true } }
    local g = snap({ { name = 'A', hpp = 45 } }, nil, waits)
    eq({ decide(g, cfg) }, { nil, 'waiting for a cure' })
    g.units[2].buffs[3] = true  -- poisoned
    eq(decide(g, cfg), '/ma "Poisona" 101')
    eq(decide(snap({ { name = 'A', hpp = 70 } }, nil, waits), cfg), '/ma "Protect IV" 101')
end)

test('a member out of reach is skipped, not the end of healing', function ()
    local g = snap({ { name = 'Far', hpp = 20, dist = 30, pos = { 100, 0, 0 } }, { name = 'Near', hpp = 60 } })
    eq(decide(g), '/ma "Regen III" 102')
end)

test('the focus member enters danger at 59% while others wait for 49%', function ()
    local cfg = settings.defaults()
    cfg.heal.focus = 'Tank'
    local g = snap({ { name = 'A', hpp = 55 }, { name = 'Tank', hpp = 59 } })
    local cmd, intent = decide(g, cfg)
    eq({ cmd, intent.why }, { '/ma "Cure IV" 102', 'danger: Tank 59%' })
    intent = select(2, decide(g))
    eq(intent.why:match('^%a+'), 'efficient')
end)

test('a skipped member is never healed for their own sake', function ()
    local cfg = settings.defaults()
    cfg.heal.skip = { A = true }
    eq({ decide(snap({ { name = 'A', hpp = 40 } }), cfg) }, { nil, 'nothing to do' })
end)

test('removal: the specific -na first, Erase for what only it clears', function ()
    local g = snap({ { name = 'A', buffs = { [4] = true, [13] = true } } })  -- Paralysis, Slow
    eq(decide(g), '/ma "Paralyna" 101')
    g = snap({ { name = 'A', buffs = { [13] = true } } })
    eq(decide(g), '/ma "Erase" 101')
end)

test('revive: the best raise, idle only, and not again while they decide', function ()
    local mem = {}
    local g = snap({ { name = 'Dead', hpp = 0 } })
    local cmd, intent = decide(g, nil, mem)
    eq(cmd, '/ma "Arise" 101')
    engine.sent(intent, g, mem)
    eq({ decide(g, nil, mem) }, { nil, 'nothing to do' })
    eq({ decide(snap({ { name = 'Dead', hpp = 0 } }, { combat = true })) }, { nil, 'nothing to do' })
end)

test('buffs are opt-in, and go only where they are missing', function ()
    local g = snap({ { name = 'A' } })
    eq({ decide(g) }, { nil, 'nothing to do' })
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, targets = { [1] = true } }
    eq(decide(g, cfg), '/ma "Protect IV" 101')
    g.units[2].buffs[40] = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
end)

test('a pick_one group casts only its pick; an area buff covers those near you', function ()
    local cfg = settings.defaults()
    cfg.rows.barelement = { on = true }
    local g = snap({ { name = 'A' } })
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
    cfg.rows.barelement.pick = 'Barfira'
    eq(decide(g, cfg), '/ma "Barfira" <me>')
end)

test('gates stop everything', function ()
    eq({ decide(snap({ { name = 'A', hpp = 50, hp = 500 } }, { casting = true })) }, { nil, 'casting' })
    eq({ decide(snap({ { name = 'A', hpp = 50, hp = 500 } }, { silenced = true })) }, { nil, 'nothing to do' })
end)

test('throttle: 1.1s after anything, 3.1s after a spell lands', function ()
    local mem = { sent_at = 100 }
    eq(engine.ready({ now = 101 }, mem), false)
    eq(engine.ready({ now = 101.2 }, mem), true)
    eq(engine.ready({ now = 103, finished = 100.5, spell_finish = true }, mem), false)
    eq(engine.ready({ now = 103.7, finished = 100.5, spell_finish = true }, mem), true)
end)
