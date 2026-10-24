-- SCH's stratagems (jobs/sch.lua) through the engine's modifier chain: a buff
-- row's stratagems fired first, Accession spreading a buff, and Enlightenment
-- for an Addendum spell; the row's chips in ui/model.lua.
local engine = require('core.engine')
local settings = require('core.settings')
local can = require('core.can')
local model = require('ui.model')
local fake = require('tests.fake')

local SCH, RDM, WHM, BLM = 20, 5, 3, 4
local LIGHT_ARTS, DARK_ARTS, ADDENDUM_WHITE, ENLIGHTENMENT = 358, 359, 401, 416
local PERPETUANCE, ACCESSION, PROTECT = 469, 366, 40
local STRATAGEMS = { 'Light Arts', 'Dark Arts', 'Addendum: White', 'Penury', 'Celerity', 'Accession', 'Perpetuance',
    'Parsimony', 'Alacrity', 'Enlightenment' }
local cat = fake.catalog(SCH, 75, RDM, 37, STRATAGEMS)

-- A snapshot with these statuses on you; others in slots 1..n.
local function snap(buffs, others, waits)
    local g = fake.snap(others or {}, { main = SCH, sub = RDM }, waits)
    for _, id in ipairs(buffs) do g.me.buffs[id] = true end
    return g
end

local function cfg_with(rows)
    local cfg = settings.defaults()
    for k, v in pairs(rows) do cfg.rows[k] = v end
    return cfg
end

local function decide(g, cfg, mem, list) return fake.decide(g, list or cat, cfg, mem) end

-- Decide and, when there is something, send it.
local function step(g, cfg, mem)
    local cmd, intent = decide(g, cfg, mem)
    if cmd then engine.sent(intent, g, mem) end
    return cmd, intent
end

local named = fake.named

test('catalog: the stratagems are modifiers that say which spells they fit', function ()
    local pen, per, acc, par = named(cat, 'Penury', 'modifier'), named(cat, 'Perpetuance'),
        named(cat, 'Accession', 'modifier'), named(cat, 'Parsimony')
    local protect, spikes, raise = named(cat, 'Protect IV'), named(cat, 'Blaze Spikes'), named(cat, 'Raise II')
    eq({ pen.applies(protect), pen.applies(spikes), par.applies(spikes), par.applies(protect) }, { true, false, true, false })
    eq({ per.applies(protect), per.applies(spikes), per.status }, { true, false, { PERPETUANCE } })
    eq({ acc.applies(protect), acc.applies(named(cat, 'Sandstorm')), acc.applies(raise), acc.spreads.mp }, { true, true, false, 2 })
    eq(named(cat, 'Accession', 'emergency').boost.area, 10)  -- healing keeps its own
end)

test('catalog: an Addendum spell can go through Enlightenment', function ()
    local raise = named(cat, 'Raise II')
    eq({ raise.requires, raise.via and raise.via.name }, { { ADDENDUM_WHITE, ENLIGHTENMENT }, 'Enlightenment' })
    eq(named(cat, 'Protect IV').via, nil)
end)

test('can.use: under Dark Arts an Addendum spell is usable while Enlightenment is', function ()
    local raise = named(cat, 'Raise II')
    eq(can.use(raise, snap({ DARK_ARTS })), true)
    eq(select(2, can.use(raise, snap({ DARK_ARTS }, {}, { Enlightenment = 200 }))), 'needs Addendum: White')
    eq(select(2, can.use(raise, snap({ LIGHT_ARTS }))), 'needs Addendum: White')  -- Addendum: White is the way in there
    eq(can.use(raise, snap({ LIGHT_ARTS, ADDENDUM_WHITE })), true)
end)

test('revive under Dark Arts: Enlightenment first, then the raise while its status is expected', function ()
    local g = snap({ DARK_ARTS }, { { name = 'A', hpp = 0 } })
    local cfg, mem = settings.defaults(), {}
    local cmd, intent = step(g, cfg, mem)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Enlightenment" <me>', 'revive', 'for Raise II -> A: A' })
    -- The JA is on recast now and its status not read yet: still the raise.
    g = snap({ DARK_ARTS }, { { name = 'A', hpp = 0 } }, { Enlightenment = 300 })
    g.now = 1001
    eq(step(g, cfg, mem), '/ma "Raise II" 101')
    -- No status after the window: the raise can't go.
    g = snap({ DARK_ARTS }, { { name = 'A', hpp = 0 } }, { Enlightenment = 300 })
    g.now = 1000 + engine.EXPECT + 0.1
    eq(decide(g, cfg, mem), nil)
end)

test('a buff row\'s stratagem goes first, then the spell; never when it can\'t', function ()
    local cfg = cfg_with({ Protect = { on = true, mods = { Perpetuance = true, Penury = true } } })
    local mem = {}
    local g = snap({ LIGHT_ARTS })
    eq(step(g, cfg, mem), '/ja "Penury" <me>')
    g = snap({ LIGHT_ARTS })
    g.now = 1001.5
    eq(step(g, cfg, mem), '/ja "Perpetuance" <me>')
    g = snap({ LIGHT_ARTS, PERPETUANCE })  -- Penury's status read, Perpetuance's expected
    eq(step(g, cfg, mem), '/ma "Protect IV" <me>')
    -- Dark Arts: no white stratagem, so the spell alone.
    eq(decide(snap({ DARK_ARTS }), cfg, {}), '/ma "Protect IV" <me>')
    -- No charge left: the spell alone.
    eq(decide(snap({ LIGHT_ARTS }, {}, { Penury = 30, Perpetuance = 30 }), cfg, {}), '/ma "Protect IV" <me>')
    -- A stratagem that doesn't fit the spell is never fired for it.
    cfg = cfg_with({ spikes = { on = true, pick = 'Blaze Spikes', mods = { Penury = true } } })
    eq(decide(snap({ LIGHT_ARTS }), cfg, {}), '/ma "Blaze Spikes" <me>')
end)

test('Accession spreads a buff from you whenever one of its targets near lacks it (as v2)', function ()
    local cfg = cfg_with({ Protect = { on = true, targets = { [0] = true, [1] = true, [2] = true },
                                       mods = { Accession = true } } })
    local others = { { name = 'A' }, { name = 'B', buffs = { [PROTECT] = true } } }
    local mem = {}
    local cmd, intent = step(snap({ LIGHT_ARTS }, others), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Accession" <me>', 'for Protect IV: Me +1 lack it' })
    local g = snap({ LIGHT_ARTS }, others, { Accession = 40 })
    g.now = 1001.5
    eq(step(g, cfg, mem), '/ma "Protect IV" <me>')
    -- One lacks it: spread all the same.
    cmd, intent = decide(snap({ LIGHT_ARTS, PROTECT }, others), cfg, {})
    eq({ cmd, intent.why }, { '/ja "Accession" <me>', 'for Protect IV: A lacks it' })
    -- Accession already up (healing fired it): used, though off recast it couldn't be.
    others = { { name = 'A' }, { name = 'B' } }
    eq(decide(snap({ LIGHT_ARTS, ACCESSION }, others, { Accession = 40 }), cfg, {}), '/ma "Protect IV" <me>')
    -- Not the MP for twice the cost: one at a time.
    g = snap({ LIGHT_ARTS }, others)
    g.me.mp = 100
    eq(decide(g, cfg, {}), '/ma "Protect IV" <me>')
    -- Untargeted members don't count: with only them lacking it, nothing to do.
    cfg.rows.Protect.targets = { [0] = true }
    eq(decide(snap({ LIGHT_ARTS, PROTECT }, others), cfg, {}), nil)
end)

test('Accession: held for the group like an area spell, and only for the row\'s targets', function ()
    local cfg = cfg_with({ Protect = { on = true, targets = { [0] = true, [1] = true, [2] = true },
                                       mods = { Accession = true } } })
    cfg.buff.hold_aoe = true
    local others = { { name = 'A' }, { name = 'B', dist = 15 } }
    local mem = {}
    eq({ decide(snap({ LIGHT_ARTS }, others), cfg, mem) }, { nil, 'holding Protect IV: B 15.0y away' })
    eq(engine.gather(snap({ LIGHT_ARTS }, others), cfg, mem), '/p Gather together for Protect IV')
    cfg.rows.Protect.targets = { [0] = true, [1] = true }
    eq(decide(snap({ LIGHT_ARTS }, others), cfg, {}), '/ja "Accession" <me>')
end)

test('UI: a buff row shows the stratagems that fit it, and act.mod turns one on and off', function ()
    local names = { job = function () return 'SCH' end, statuses = fake.res.statuses }
    local cfg = settings.defaults()
    local function rows()
        local view = model.build(fake.snap({}), cat, cfg, { running = false, sent = {} }, names)
        local out = {}
        for _, s in ipairs(view.sections) do
            if s.id == 'buff' then
                out.has_mods = s.has_mods
                for _, r in ipairs(s.rows) do out[r.key] = r end
            end
        end
        return out
    end
    local function chips(r)
        local out = {}
        for i, m in ipairs(r.mods or {}) do out[i] = m.label .. (m.on and '+' or '') end
        return out
    end
    local r = rows()
    eq({ r.has_mods, chips(r.Protect), chips(r.spikes), chips(r.storm), r['Light Arts'] and r['Light Arts'].mods },
       { true, { 'Pen', 'Cel', 'Acc', 'Per' }, { 'Par', 'Ala' }, { 'Pen', 'Cel', 'Acc', 'Per' }, nil })
    eq(r.Protect.mods[3].note, 'on everyone near you, at twice the MP')
    local function heal_view(list)
        return model.build(fake.snap({}), list, cfg, { running = false, sent = {} }, names).heal
    end
    eq({ heal_view(cat).stratagems, heal_view(cat).reserve, heal_view(fake.catalog(WHM, 75, BLM, 37)).stratagems },
       { true, false, false })
    local n = 0
    local act = model.actions(cfg, {}, function () n = n + 1 end)
    act.mod('Protect', 'Accession')
    eq({ cfg.rows.Protect, chips(rows().Protect) }, { { on = false, mods = { Accession = true } }, { 'Pen', 'Cel', 'Acc+', 'Per' } })
    act.mod('Protect', 'Accession')
    eq({ cfg.rows.Protect.mods, n }, { {}, 2 })
    -- Jobs without stratagems: no chips.
    local whm = fake.catalog(WHM, 75, BLM, 37)
    local view = model.build(fake.snap({}), whm, settings.defaults(), { running = false, sent = {} }, names)
    for _, s in ipairs(view.sections) do
        if s.id == 'buff' then eq(s.has_mods, false) end
    end
end)

test('Accession held for the group like Protectra, even for one far player lacking it', function ()
    local cfg = cfg_with({ Protect = { on = true, targets = { [0] = true, [1] = true, [2] = true },
                                       mods = { Accession = true } } })
    cfg.buff.hold_aoe = true
    local others = { { name = 'A', buffs = { [PROTECT] = true } }, { name = 'B', dist = 15 } }
    eq({ decide(snap({ LIGHT_ARTS, PROTECT }, others), cfg, {}) }, { nil, 'holding Protect IV: B 15.0y away' })
end)

test('charges: counted from the pool timer and your SCH level', function ()
    local sch = require('jobs.sch')
    local p = sch.POOL
    eq({ p:banked(0, 75), p:banked(1, 75), p:banked(100, 75), p:banked(240, 75), p:banked(0, 37), p:banked(0, 5) },
       { 5, 4, 2, 0, 2, 0 })
end)

test('heal.reserve: buff rows leave the last charge for healing', function ()
    local protect = cfg_with({ Protect = { on = true, targets = { [0] = true, [1] = true },
                                           mods = { Penury = true, Accession = true } } })
    local addendum = cfg_with({ addendum = { on = true, pick = 'Addendum: White' } })
    local others = { { name = 'A', buffs = { [PROTECT] = true } } }
    local function with(cfg, charges, reserve)
        local g = snap({ LIGHT_ARTS }, others)
        g.stratagems = charges
        cfg.heal.reserve = reserve
        return (decide(g, cfg, {}))
    end
    eq({ with(protect, 1, false), with(protect, 2, true) }, { '/ja "Penury" <me>', '/ja "Penury" <me>' })
    eq({ with(addendum, 1, false), with(addendum, 2, true) }, { '/ja "Addendum: White" <me>', '/ja "Addendum: White" <me>' })
    -- One left: no Penury, no Accession, the spell alone; no Addendum.
    eq({ with(protect, 1, true), with(addendum, 1, true) }, { '/ma "Protect IV" <me>', nil })
    -- Charges unknown (no SCH): nothing held back.
    eq(with(protect, nil, true), '/ja "Penury" <me>')
end)

test('heal\'s own Accession is expected too, so a lagging status read spends no second charge', function ()
    local cfg = settings.defaults()
    local others = { { name = 'A', hpp = 45 }, { name = 'B', hpp = 45 }, { name = 'C', hpp = 45 } }
    local mem = {}
    eq(step(snap({ LIGHT_ARTS }, others), cfg, mem), '/ja "Accession" <me>')
    local g = snap({ LIGHT_ARTS }, others)
    g.now = 1001.2
    local cmd = step(g, cfg, mem)
    eq(cmd:match('^/ma "Cure'), '/ma "Cure')
end)

test('expected statuses stay out of the snapshot the HUD and /sk3 state read', function ()
    local g = snap({ DARK_ARTS }, { { name = 'A', hpp = 0 } })
    local mem = { expect = { [ENLIGHTENMENT] = 1001 } }
    eq(decide(g, settings.defaults(), mem), '/ma "Raise II" 101')
    eq({ g.me.buffs[ENLIGHTENMENT], g.units[1].buffs[ENLIGHTENMENT] }, { nil, nil })
end)

test('Hold on a row: its spell waits while a stratagem picked can\'t go (wrong Arts, no charge); without, it goes alone', function ()
    local cfg = cfg_with({ Protect = { on = true, mods = { Penury = true }, hold = true } })
    eq(decide(snap({ DARK_ARTS }), cfg, {}), nil)
    eq(decide(snap({ LIGHT_ARTS }), cfg, {}), '/ja "Penury" <me>')
    cfg.rows.Protect.hold = nil
    eq(decide(snap({ DARK_ARTS }), cfg, {}), '/ma "Protect IV" <me>')
end)

test('Hold counts the charges: it waits while there are more stratagems to fire than charges to spend', function ()
    local cfg = cfg_with({ Protect = { on = true, mods = { Penury = true, Celerity = true }, hold = true } })
    local function with(charges, reserve, over)
        local g = snap({ LIGHT_ARTS })
        g.stratagems = charges
        for _, id in ipairs(over or {}) do g.me.buffs[id] = true end
        cfg.heal.reserve = reserve
        return decide(g, cfg, {})
    end
    eq({ with(1) }, { nil, 'holding Protect IV for Penury' })
    eq(with(2), '/ja "Penury" <me>')
    eq(with(2, true), nil, 'the reserve leaves one: too few for two')
    eq(with(1, false, { 360 }), '/ja "Celerity" <me>', 'Penury up already: one to fire, one charge')
    eq(with(nil), '/ja "Penury" <me>', 'charges unknown: not counted')
end)

test('Hold and Accession: waits only when the spell would spread to someone it reaches', function ()
    local cfg = cfg_with({ Protect = { on = true, targets = { [0] = false, [1] = true }, mods = { Accession = true }, hold = true } })
    local function with(others, waits)
        local g = snap({ LIGHT_ARTS }, others, waits)
        return (decide(g, cfg, {}))
    end
    eq(with({ { name = 'A' } }, { Accession = 30 }), nil, 'A near and lacking it: waits for Accession')
    eq(with({ { name = 'A', dist = 15 } }, { Accession = 30 }), '/ma "Protect IV" 101', 'A too far to spread to: goes alone')
end)

test('a held row says what it waits for', function ()
    local cfg = cfg_with({ Protect = { on = true, mods = { Penury = true }, hold = true } })
    local v = model.build(snap({ DARK_ARTS }), cat, cfg, { running = false, sent = {} },
        { job = function () return 'SCH' end, statuses = fake.res.statuses })
    local row
    for _, s in ipairs(v.sections) do
        for _, r in ipairs(s.rows or {}) do if r.key == 'Protect' then row = r end end
    end
    eq({ row.ready, row.avail }, { false, 'waits for Pen: needs Light Arts' })
end)

-- The client lists the stratagems only under their Arts (LSB's addType): a SCH
-- loaded outside either still has them, each waiting on its Arts.
local bare = fake.catalog(SCH, 75, RDM, 37, { 'Light Arts', 'Dark Arts', 'Enlightenment' })

test('loaded outside either Arts: the stratagems are still there, each waiting on its Arts', function ()
    local names = { job = function () return 'SCH' end, statuses = fake.res.statuses }
    local view = model.build(snap({}), bare, settings.defaults(), { running = false, sent = {} }, names)
    local rows = {}
    for _, s in ipairs(view.sections) do
        for _, r in ipairs(s.rows or {}) do rows[r.key] = r end
    end
    local chips = {}
    for i, m in ipairs(rows.Protect.mods) do chips[i] = m.label end
    eq(chips, { 'Pen', 'Cel', 'Acc' })
    eq({ rows.Rapture.ready, rows.Rapture.avail, rows.addendum.avail }, { false, 'needs Light Arts', 'pick one' })
    eq(view.heal.stratagems, true)
    -- Under Light Arts, but the client doesn't list it (a merit not taken): never sent.
    local g = snap({ LIGHT_ARTS })
    g.listed = function (a) return a.name ~= 'Tranquility' end
    eq({ can.use(named(bare, 'Tranquility'), g) }, { false, 'not listed' })
    eq(can.use(named(bare, 'Rapture'), g), true)
end)

test('Light Arts goes first, ahead of healing; then the cure', function ()
    local cfg = cfg_with({ arts = { on = true, pick = 'Light Arts' }, Regen = { on = false } })
    local hurt = { { name = 'A', hpp = 60 } }
    local cmd, intent = decide(snap({}, hurt), cfg, {})
    eq({ cmd, intent.behavior }, { '/ja "Light Arts" <me>', 'first' })
    eq(decide(snap({ LIGHT_ARTS }, hurt), cfg, {}):match('^/ma "Cure'), '/ma "Cure')
    -- On recast, or with the buff section off, healing doesn't wait for it.
    eq(decide(snap({}, hurt, { ['Light Arts'] = 30 }), cfg, {}):match('^/ma "Cure'), '/ma "Cure')
    cfg.buff.on = false
    eq(decide(snap({}, hurt), cfg, {}):match('^/ma "Cure'), '/ma "Cure')
    -- Dark Arts picked keeps its place among the buffs, after healing.
    cfg = cfg_with({ arts = { on = true, pick = 'Dark Arts' }, Regen = { on = false } })
    eq(decide(snap({}, hurt), cfg, {}):match('^/ma "Cure'), '/ma "Cure')
end)

test('Addendum: White goes first too, once Light Arts is up', function ()
    local cfg = cfg_with({ arts = { on = true, pick = 'Light Arts' }, addendum = { on = true, pick = 'Addendum: White' },
                          Regen = { on = false } })
    local hurt = { { name = 'A', hpp = 60 } }
    eq(decide(snap({}, hurt), cfg, {}), '/ja "Light Arts" <me>')
    local cmd, intent = decide(snap({ LIGHT_ARTS }, hurt), cfg, {})
    eq({ cmd, intent.behavior }, { '/ja "Addendum: White" <me>', 'first' })
    eq(decide(snap({ ADDENDUM_WHITE }, hurt), cfg, {}):match('^/ma "Cure'), '/ma "Cure')
end)
