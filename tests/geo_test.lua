-- Geomancer's luopan (jobs/geo.lua) through the engine: the Geo row's luopan on its
-- target and recalled once they leave it, the Geo debuff's on your battle target
-- in combat, Blaze of Glory and Entrust as modifiers, Radial Arcana's sequence
-- (behaviors/recover.lua), and the Geomancy section in ui/model.lua.
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local GEO, RDM = 21, 5
local HASTE, FURY, BLAZE, ENTRUST = 580, 549, 569, 584  -- statuses
local JAS = { 'Full Circle', 'Blaze of Glory', 'Entrust', 'Radial Arcana' }
local cat = fake.catalog(GEO, 75, nil, 0, JAS)

local named = fake.named

-- GEO 75 with `others` in slots 1..n; `pet` (a luopan) at `pet_at` yalms along x from you.
local function snap(others, over, waits, pet_at)
    local o = { main = GEO, sub = 0, sub_lv = 0 }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap(others or {}, o, waits)
    if pet_at then g.pet = { sid = 0x1000700, name = 'Luopan', hpp = 100, dist = pet_at, pos = { pet_at, 0, 0 }, buffs = {} } end
    return g
end

local function cfg_with(rows, geo)
    local cfg = settings.defaults()
    for k, v in pairs(rows or {}) do cfg.rows[k] = v end
    for k, v in pairs(geo or {}) do cfg.geo[k] = v end
    return cfg
end

local function decide(g, cfg, mem) return fake.decide(g, cat, cfg, mem) end

local function step(g, cfg, mem) return fake.step(g, cat, cfg, mem) end

local TANK = { name = 'Tank', pos = { 2, 0, 0 } }
local HASTE_ROW = { on = true, pick = 'Geo-Haste', targets = { [1] = true } }
local CRAB = { sid = 0x2000, tidx = 0x20, name = 'Crab', mob = true, hpp = 90, dist = 6, pos = { 6, 0, 0 } }

test('catalog: Geo- spells are luopans, the luopan\'s abilities its own role; Radial Arcana spends it', function ()
    local haste, frailty = named(cat, 'Geo-Haste'), named(cat, 'Geo-Frailty')
    eq({ haste.role, haste.pick_one, haste.luopan, haste.status }, { 'geo', 'geo', 'buff', { HASTE } })
    eq({ frailty.role, frailty.pick_one, frailty.luopan, frailty.status }, { 'geo', 'geo_debuff', 'debuff', nil })
    eq({ named(cat, 'Indi-Haste').role, named(cat, 'Indi-Haste').status, named(cat, 'Indi-Frailty').status },
       { 'buff', { HASTE }, { 612 } })
    eq({ named(cat, 'Blaze of Glory').status, named(cat, 'Entrust').status, named(cat, 'Full Circle').role },
       { { BLAZE }, { ENTRUST }, 'geo' })
    local ra = named(cat, 'Radial Arcana')
    eq({ ra.role, ra.luopan, ra.priority }, { 'recover', 'spend', 90 })
    local sub = fake.catalog(RDM, 75, GEO, 37, JAS)  -- GEO subjob: Indi- only
    eq({ named(sub, 'Geo-Fury'), named(sub, 'Indi-Fury').role }, { nil, 'buff' })
end)

test('settings: luopan rows are opt-in; /sk3 buff finds a Geo- buff', function ()
    local cfg = settings.defaults()
    eq({ settings.row(cfg, named(cat, 'Geo-Haste')).on, settings.row(cfg, named(cat, 'Geo-Frailty')).on,
         settings.row(cfg, named(cat, 'Full Circle')).on }, { false, false, true })
    eq(settings.buff_named(cat, 'geo-haste').name, 'Geo-Haste')
end)

test('the Geo row: Blaze of Glory, then the luopan on its target; the slot full, nothing more', function ()
    local cfg, mem = cfg_with({ geo = HASTE_ROW }), {}
    local cmd, intent = step(snap({ TANK }), cfg, mem)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Blaze of Glory" <me>', 'geo', 'for Geo-Haste -> Tank: Tank' })
    eq(step(snap({ TANK }, nil, { ['Blaze of Glory'] = 600 }), cfg, mem), '/ma "Geo-Haste" 101')
    eq({ decide(snap({ TANK }, { now = 1003 }), cfg, mem) }, { nil, 'nothing to do' })  -- landing
    eq({ decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem) }, { nil, 'nothing to do' })  -- up
end)

test('the Geo row: a target on the move waits; one with the aura is passed over; off, nothing', function ()
    local row = { on = true, pick = 'Geo-Haste', targets = { [1] = true, [2] = true } }
    local cfg = cfg_with({ geo = row, ['Blaze of Glory'] = { on = false } })
    local moving = { name = 'Tank', moving = true }
    eq({ decide(snap({ moving }), cfg, {}) }, { nil, 'nothing to do' })
    eq(decide(snap({ { name = 'Tank', buffs = { [HASTE] = true } }, { name = 'Mage' } }), cfg, {}), '/ma "Geo-Haste" 102')
    eq({ decide(snap({ TANK }), cfg_with({ geo = { on = false, pick = 'Geo-Haste' } }), {}) }, { nil, 'nothing to do' })
end)

test('drift: once who it went on is past geo.distance from it, Full Circle; then it goes down by them', function ()
    local cfg, mem = cfg_with({ geo = HASTE_ROW, ['Blaze of Glory'] = { on = false } }), {}
    step(snap({ TANK }), cfg, mem)
    local far = { name = 'Tank', pos = { 14, 0, 0 } }
    eq({ decide(snap({ { name = 'Tank', pos = { 9, 0, 0 } } }, { now = 1003 }, nil, 1), cfg, mem) }, { nil, 'nothing to do' })
    local cmd, intent = step(snap({ far }, { now = 1004 }, nil, 1), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Full Circle" <me>', 'Tank 13.0y from it' })
    eq(step(snap({ far }, { now = 1006 }), cfg, mem), '/ma "Geo-Haste" 101')
    -- Not sent here (a reload): measured from the row's first target.
    eq(decide(snap({ far }, nil, nil, 1), cfg, {}), '/ja "Full Circle" <me>')
    eq(decide(snap({ { name = 'Tank' } }, nil, nil, 1), cfg_with({}), {}), nil)  -- no row: left alone
end)

test('the Geo debuff: in combat on your battle target, not while it moves; it takes the slot from a buff luopan', function ()
    local cfg = cfg_with({ geo = HASTE_ROW, geo_debuff = { on = true, pick = 'Geo-Frailty' }, ['Blaze of Glory'] = { on = false } })
    local fight = { bt = CRAB, combat = true, combat_at = 1000 }
    eq(decide(snap({ TANK }, fight), cfg, {}), '/ma "Geo-Frailty" <bt>')
    local moving = {}
    for k, v in pairs(CRAB) do moving[k] = v end
    moving.moving = true
    eq({ decide(snap({ TANK }, { bt = moving, combat = true, combat_at = 1000 }), cfg, {}) }, { nil, 'nothing to do' })
    local mem = {}
    step(snap({ TANK }), cfg, mem)  -- Geo-Haste out of combat
    local cmd, intent = step(snap({ TANK }, { now = 1003, bt = CRAB, combat = true, combat_at = 1003 }, nil, 2), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Full Circle" <me>', 'for Geo-Frailty' })
    eq(step(snap({ TANK }, { now = 1005, bt = CRAB, combat = true, combat_at = 1005 }), cfg, mem), '/ma "Geo-Frailty" <bt>')
    cfg.rows.geo_debuff.on = false  -- turned off mid-fight: its luopan stays (on the mob, far from the Geo row's target)
    eq({ decide(snap({ TANK }, { now = 1008, bt = CRAB, combat = true, combat_at = 1008 }, nil, 30), cfg, mem) },
       { nil, 'nothing to do' })
end)

test('the Geo debuff\'s luopan, combat over: kept geo.linger seconds, then recalled for the Geo row', function ()
    local cfg = cfg_with({ geo = HASTE_ROW, geo_debuff = { on = true, pick = 'Geo-Frailty' }, ['Blaze of Glory'] = { on = false } })
    local mem = {}
    step(snap({ TANK }, { bt = CRAB, combat = true, combat_at = 1000 }), cfg, mem)
    eq({ decide(snap({ TANK }, { now = 1004, combat_at = 1002 }, nil, 6), cfg, mem) }, { nil, 'nothing to do' })
    eq({ decide(snap({ TANK }, { now = 1005, bt = CRAB, combat = true, combat_at = 1005 }, nil, 6), cfg, mem) },
       { nil, 'nothing to do' })  -- a new battle target keeps it
    local cmd, intent = step(snap({ TANK }, { now = 1011, combat_at = 1005 }, nil, 6), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Full Circle" <me>', 'combat over' })
    eq(decide(snap({ TANK }, { now = 1013, combat_at = 1005 }), cfg, mem), '/ma "Geo-Haste" 101')
end)

test('Blaze of Glory goes before the debuff too, and only when the luopan can go', function ()
    local cfg = cfg_with({ geo_debuff = { on = true, pick = 'Geo-Frailty' } })
    eq(decide(snap({}, { bt = CRAB, combat = true, combat_at = 1000 }), cfg, {}), '/ja "Blaze of Glory" <me>')
    local poor = snap({}, { bt = CRAB, combat = true, combat_at = 1000 })
    poor.me.mp = 100  -- Geo-Frailty is 294
    eq(decide(poor, cfg, {}), nil)
end)

test('Entrust: then the Indi- picked on the member, while they lack its aura and are within 20 yalms', function ()
    local cfg, mem = cfg_with({}, { entrust = 'tank', entrust_spell = 'Indi-Fury' }), {}
    local cmd, intent = step(snap({ TANK }), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Entrust" <me>', 'for Indi-Fury -> Tank: Tank (Entrust)' })
    eq(step(snap({ TANK }, nil, { Entrust = 300 }), cfg, mem), '/ma "Indi-Fury" 101')
    eq(decide(snap({ { name = 'Tank', buffs = { [FURY] = true } } }), cfg, {}), nil)
    eq(decide(snap({ { name = 'Tank', dist = 21 } }), cfg, {}), nil)
    eq(decide(snap({ TANK }, nil, { Entrust = 300 }), cfg, {}), nil)  -- on recast, not up
    eq(decide(snap({ TANK }), cfg_with({ Entrust = { on = false } }, { entrust = 'Tank', entrust_spell = 'Indi-Fury' }), {}), nil)
end)

-- Radial Arcana: MP under the Recover line (30%).
local function low(others, over, waits, pet_at)
    local g = snap(others, over, waits, pet_at)
    g.me.mpp = 20
    return g
end

test('Radial Arcana: a cheap luopan you are in spends at once', function ()
    local cfg, mem = cfg_with(), { geo = { luopan = { action = named(cat, 'Geo-Precision'), up = true, at = 0 } } }
    local cmd, intent = step(low({}, nil, nil, 3), cfg, mem)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Radial Arcana" <me>', 'recover', 'MP 20%' })
    eq(decide(low({}, nil, nil, 3), cfg, { geo = { luopan = { action = named(cat, 'Geo-Haste'), up = true, at = 0 } } }),
       '/ja "Full Circle" <me>')
    local spent = low({}, nil, nil, 3)
    spent.pet.hpp = 5
    eq(decide(spent, cfg, { geo = { luopan = { action = named(cat, 'Geo-Haste'), up = true, at = 0 } } }), '/ja "Radial Arcana" <me>')
    local unread = low({}, nil, nil, 3)
    eq(decide(unread, cfg, {}), '/ja "Full Circle" <me>')  -- not sent here: taken as dear
end)

test('Radial Arcana: a dear one is recalled, a Geo-Voidance put down on you, then spent; the slot kept meanwhile', function ()
    local cfg = cfg_with({ geo = { on = true, pick = 'Geo-Haste', targets = { [0] = true } }, ['Blaze of Glory'] = { on = false } })
    local mem = { geo = { luopan = { action = named(cat, 'Geo-Haste'), sid = 1, up = true, at = 0 } } }
    eq(step(low({}, nil, nil, 3), cfg, mem), '/ja "Full Circle" <me>')
    local g = snap({}, { now = 1002 })  -- the Full Circle gave MP back: over the line now, but begun
    local cmd, intent = step(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ma "Geo-Voidance" <me>', 'for Radial Arcana' })
    eq({ decide(snap({}, { now = 1004 }), cfg, mem) }, { nil, 'nothing to do' })  -- landing: the Geo row waits
    eq(step(snap({}, { now = 1006 }, nil, 1), cfg, mem), '/ja "Radial Arcana" <me>')
    eq(decide(snap({}, { now = 1008 }), cfg, mem), '/ma "Geo-Haste" 1')  -- done: the Geo row again
end)

test('Radial Arcana: off recast, Recover off or the MP over the line, nothing begins', function ()
    local mem = function () return { geo = { luopan = { action = named(cat, 'Geo-Haste'), up = true, at = 0 } } } end
    eq(decide(low({}, nil, { ['Radial Arcana'] = 60 }, 3), cfg_with(), mem()), nil)
    local off = cfg_with()
    off.recover.on = false
    eq(decide(low({}, nil, nil, 3), off, mem()), nil)
    eq(decide(snap({}, nil, nil, 3), cfg_with(), mem()), nil)
    eq(decide(low({}, nil, nil, 3), cfg_with({ ['Radial Arcana'] = { on = false } }), mem()), nil)
end)

test('a luopan that came while nothing decided (a new pet since) is not the one remembered', function ()
    local cfg = cfg_with({ geo = HASTE_ROW, geo_debuff = { on = true, pick = 'Geo-Frailty' }, ['Blaze of Glory'] = { on = false } })
    local mem = {}
    step(snap({ TANK }, { bt = CRAB, combat = true, combat_at = 1000 }), cfg, mem)
    local g = snap({ TANK }, { now = 1003, bt = CRAB, combat = true, combat_at = 1003 }, nil, 6)
    g.pet.since = 1003
    decide(g, cfg, mem)  -- the debuff's, seen up
    g = snap({ TANK }, { now = 1060, combat_at = 1003 }, nil, 2)
    g.pet.since = 1050  -- put down by hand on the Tank meanwhile
    eq({ decide(g, cfg, mem) }, { nil, 'nothing to do' })  -- not recalled as the debuff's
end)

test('Radial Arcana sent: the luopan going is left alone, not recalled again', function ()
    local cfg = cfg_with({ geo = { on = true, pick = 'Geo-Haste', targets = { [0] = true } },
                           geo_debuff = { on = true, pick = 'Geo-Frailty' }, ['Blaze of Glory'] = { on = false } })
    local mem = { geo = { luopan = { action = named(cat, 'Geo-Voidance'), sid = 1, spare = true, up = true, at = 0 } } }
    eq(step(low({}, nil, nil, 1), cfg, mem), '/ja "Radial Arcana" <me>')
    eq(decide(snap({}, { now = 1001.2 }, { ['Radial Arcana'] = 300 }, 1), cfg, mem), nil)
    local fight = { now = 1001.2, bt = CRAB, combat = true, combat_at = 1001 }
    eq(decide(snap({}, fight, { ['Radial Arcana'] = 300 }, 1), cfg, mem), nil)
end)

test('Radial Arcana: no Geo-Voidance to follow, a dear luopan is left; off mid-sequence, the slot is let go', function ()
    local function dear() return { geo = { luopan = { action = named(cat, 'Geo-Haste'), up = true, at = 0 } } } end
    local silenced = low({}, { silenced = true }, nil, 3)
    eq(decide(silenced, cfg_with(), dear()), nil)
    local cfg = cfg_with({ geo = { on = true, pick = 'Geo-Haste', targets = { [0] = true } }, ['Blaze of Glory'] = { on = false } })
    local mem = { geo = { arcana = 1010 } }
    eq(decide(snap({}), cfg, mem), '/ma "Geo-Voidance" <me>')  -- the sequence goes on, not the Geo row
    cfg.recover.on = false
    eq(decide(snap({}), cfg, mem), '/ma "Geo-Haste" 1')
end)

test('the Geo debuff takes the slot only when it could follow: in range and not moving', function ()
    local cfg = cfg_with({ geo = HASTE_ROW, geo_debuff = { on = true, pick = 'Geo-Frailty' }, ['Blaze of Glory'] = { on = false } })
    local far = {}
    for k, v in pairs(CRAB) do far[k] = v end
    far.dist = 30
    local mem = {}
    step(snap({ TANK }), cfg, mem)
    eq(decide(snap({ TANK }, { now = 1003, bt = far, combat = true, combat_at = 1003 }, nil, 2), cfg, mem), nil)
    local poor = snap({ TANK }, { now = 1003, bt = CRAB, combat = true, combat_at = 1003 }, nil, 2)
    poor.me.mp = 100
    eq(decide(poor, cfg, mem), nil)  -- 100 + 100 back from Geo-Haste is short of Geo-Frailty's 294
    poor.me.mp = 200
    eq(decide(poor, cfg, mem), '/ja "Full Circle" <me>')  -- 200 + 100 back covers it
    poor.pet.hpp = 50
    eq(decide(poor, cfg, mem), nil)  -- the refund falls with its HP: 200 + 50
end)

test('the Geo row changed while its luopan is out: recalled to follow its pick or targets', function ()
    local cfg, mem = cfg_with({ geo = { on = true, pick = 'Geo-Haste', targets = { [1] = true } },
                               ['Blaze of Glory'] = { on = false } }), {}
    step(snap({ TANK }), cfg, mem)
    eq(decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem), nil)
    cfg.rows.geo.pick = 'Geo-Fury'
    local cmd, intent = decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Full Circle" <me>', 'the Geo row changed' })
    cfg.rows.geo.pick, cfg.rows.geo.targets = 'Geo-Haste', { [0] = true }
    eq(decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem), '/ja "Full Circle" <me>')
    cfg.rows.geo.targets = { [0] = true, [1] = true }  -- still one of its targets: kept
    eq(decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem), nil)
    cfg.rows.geo.on = false  -- off: left alone
    eq(decide(snap({ TANK }, { now = 1003 }, nil, 2), cfg, mem), nil)
end)

test('drift after a reload with no targets saved: from you; one whose holder is gone is recalled', function ()
    local cfg = cfg_with({ geo = { on = true, pick = 'Geo-Haste' }, ['Blaze of Glory'] = { on = false } })
    eq(decide(snap({}, nil, nil, 25), cfg, {}), '/ja "Full Circle" <me>')
    local mem = { geo = { luopan = { action = named(cat, 'Geo-Haste'), sid = 999, up = true, at = 0 } } }
    local cmd, intent = decide(snap({ TANK }, nil, nil, 2), cfg_with({ geo = HASTE_ROW }), mem)
    eq({ cmd, intent.why }, { '/ja "Full Circle" <me>', 'who it went on is gone' })
    local nowhere = snap({ { name = 'Tank', pos = false } }, nil, nil, 2)
    nowhere.units[2].pos = nil
    local _, lost = decide(nowhere, cfg_with({ geo = HASTE_ROW }), { geo = { luopan = { sid = 101, up = true, at = 0 } } })
    eq(lost.why, 'Tank out of sight')
end)

test('model: Geomancy under Buff for a GEO main job, its rows with picks and the Geo row\'s chips', function ()
    local cfg = settings.defaults()
    local function names() return { job = function () return 'GEO' end, statuses = fake.res.statuses } end
    local view = model.build(snap({ TANK }), cat, cfg, { sent = {} }, names())
    local s
    for _, x in ipairs(view.sections) do if x.id == 'geo' then s = x end end
    eq({ s.title, s.header, s.on }, { 'Geomancy', 'Buff', true })
    local rows = {}
    for _, r in ipairs(s.rows) do rows[r.key] = r end
    eq({ rows.geo.label, rows.geo.on, rows.geo.choice, #rows.geo.targets, rows.geo_debuff.label, rows.geo_debuff.targets },
       { 'Geo', false, 'Pick one', 6, 'Geo debuff', nil })
    eq({ rows['Full Circle'].on, rows['Full Circle'].avail, rows['Blaze of Glory'].on, rows.Entrust.on },
       { true, 'no pet', true, true })
    local recovery
    for _, x in ipairs(view.sections) do if x.id == 'recover' then recovery = x end end
    for _, r in ipairs(recovery.rows) do
        if r.key == 'Radial Arcana' then eq({ r.ready, r.avail }, { true, 'ready' }) end  -- no luopan: it puts one down
    end
    eq({ view.geo.distance, view.geo.linger, view.geo.names, view.geo.indi[1] }, { 10, 5, { 'Tank' }, 'Indi-AGI' })
    local rdm = model.build(snap({ TANK }), fake.catalog(RDM, 75, GEO, 37, JAS), cfg, { sent = {} }, names())
    for _, x in ipairs(rdm.sections) do assert(x.id ~= 'geo', 'no Geomancy on a GEO subjob') end
end)
