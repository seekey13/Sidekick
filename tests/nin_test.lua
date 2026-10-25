-- Ninja (jobs/nin.lua): the tools ninjutsu spend, Sange's shuriken equipped
-- (core/ammo.lua), Utsusemi recast at its last shadow, and their UI.
local engine = require('core.engine')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local NIN, WAR, WHM = 13, 1, 3
local COPY, COPY2, COPY4, SANGE, INVISIBLE = 66, 444, 446, 352, 69  -- statuses: Copy Image (1, 2, 4+)
local SHIHEI, TABI, FUDA = 1179, 1194, 2972
local SHURIKEN, FUMA, KOGA = 17301, 17304, 18712
local cat = fake.catalog(NIN, 75, WAR, 37, { 'Sange', 'Yonin', 'Innin' })

local named = fake.named

-- NIN 75 / WAR 37 holding `items` ({ [id] = count }), these statuses on you; `over` sets snapshot fields.
local function snap(items, buffs, over, waits)
    local o = { main = NIN, main_lv = 75, sub = WAR, sub_lv = 37, items = items or {} }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap({}, o, waits)
    for _, id in ipairs(buffs or {}) do g.me.buffs[id] = true end
    return g
end

-- Buff rows on: { Utsusemi = true, ... }.
local function cfg_with(rows)
    local cfg = settings.defaults()
    for key in pairs(rows or {}) do cfg.rows[key] = { on = true } end
    return cfg
end

local function decide(g, cfg, list, mem) return fake.decide(g, list or cat, cfg, mem) end

-- What you hold where ammo can be worn from: { [id] = { en, level } }, NIN-wearable, in the bag.
local function owned(items)
    return function (ids)
        local out = {}
        for _, id in ipairs(ids) do
            local it = items[id]
            if it then out[#out + 1] = { id = id, en = it[1], level = it[2], jobs = bit.lshift(1, NIN), bag = 0 } end
        end
        return out
    end
end

-- Tools ---------------------------------------------------------------------------

test('catalog: Utsusemi, Tonko and Monomi spend their tool; Sange wants shuriken worn', function ()
    local u, t, m = named(cat, 'Utsusemi: Ni'), named(cat, 'Tonko: Ni'), named(cat, 'Monomi: Ichi')
    eq({ u.tool, u.last_shadow, u.status }, { SHIHEI, COPY, { COPY, COPY2, 445, COPY4 } })
    eq({ t.tool, m.tool }, { TABI, 2553 })
    eq(named(cat, 'Sange').ammo, { 17301, 17302, 17303, 17304, KOGA, 22999 })
end)

test('a ninjutsu waits with no tool for it; Shikanofuda stands in on a NIN main job only', function ()
    local cfg = cfg_with({ Utsusemi = true })
    eq({ decide(snap(), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap({ [TABI] = 5 }), cfg) }, { nil, 'nothing to do' }, 'another family\'s tool')
    eq(decide(snap({ [SHIHEI] = 1 }), cfg), '/ma "Utsusemi: Ni" <me>')
    eq(decide(snap({ [FUDA] = 1 }), cfg), '/ma "Utsusemi: Ni" <me>')
    local war = fake.catalog(WAR, 75, NIN, 37)
    local sub = { main = WAR, sub = NIN }
    eq({ decide(snap({ [FUDA] = 9 }, nil, sub), cfg, war) }, { nil, 'nothing to do' }, 'a NIN subjob needs Shihei')
    eq(decide(snap({ [SHIHEI] = 1 }, nil, sub), cfg, war), '/ma "Utsusemi: Ni" <me>')
end)

test('Utsusemi is recast once its shadows are gone; Ichi while Ni is on recast', function ()
    local cfg, items = cfg_with({ Utsusemi = true }), { [SHIHEI] = 3 }
    eq({ decide(snap(items, { COPY4 }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(items, { COPY }), cfg) }, { nil, 'nothing to do' }, 'one left: not without the option')
    eq(decide(snap(items, nil, nil, { ['Utsusemi: Ni'] = 30 }), cfg), '/ma "Utsusemi: Ichi" <me>')
end)

test('Tonko and Monomi are idle only, and go while you are Invisible', function ()
    local cfg, items = cfg_with({ Tonko = true, Monomi = true }), { [TABI] = 1, [2553] = 1 }
    eq(decide(snap(items), cfg), '/ma "Monomi: Ichi" <me>')  -- Sneak before Invisible, as v2
    eq(decide(snap(items, { INVISIBLE }), cfg), '/ma "Monomi: Ichi" <me>')
    eq(decide(snap(items, { 71 }), cfg), '/ma "Tonko: Ni" <me>')
    eq({ decide(snap({ [TABI] = 1 }, { INVISIBLE }), cfg) }, { nil, 'invisible' }, 'no Sanjaku-tenugui')
    eq({ decide(snap(items, nil, { combat = true }), cfg) }, { nil, 'nothing to do' })
end)

-- One shadow -----------------------------------------------------------------------

test('with one_shadow, Utsusemi is recast at its last shadow; Ni needs no cancel, it replaces them', function ()
    local cfg, items, mem = cfg_with({ Utsusemi = true }), { [SHIHEI] = 3 }, {}
    cfg.buff.one_shadow = true
    eq({ decide(snap(items, { COPY2 }), cfg) }, { nil, 'nothing to do' }, 'two left')
    local g = snap(items, { COPY })
    local cmd, intent = decide(g, cfg, cat, mem)
    eq({ cmd, intent.why, intent.cancel }, { '/ma "Utsusemi: Ni" <me>', 'Me: one shadow left', nil })
    engine.sent(intent, g, mem)
    eq(mem.cancel, nil)
end)

-- Ichi at one shadow (Ni on recast), sent: g, mem.
local function ichi_sent()
    local cfg, mem = cfg_with({ Utsusemi = true }), {}
    cfg.buff.one_shadow = true
    local g = snap({ [SHIHEI] = 3 }, { COPY }, nil, { ['Utsusemi: Ni'] = 60 })
    local cmd, intent = decide(g, cfg, cat, mem)
    eq({ cmd, intent.why, intent.cancel }, { '/ma "Utsusemi: Ichi" <me>', 'Me: one shadow left', COPY })
    engine.sent(intent, g, mem)
    return g, mem
end

test('Ichi at one shadow cancels it a second into the cast, once', function ()
    local g, mem = ichi_sent()
    g.casting = true
    g.now = g.now + 0.5
    eq(engine.cancel(g, mem), nil, 'not yet')
    g.now = g.now + 0.5
    eq(engine.cancel(g, mem), COPY)
    eq(engine.cancel(g, mem), nil, 'once')
end)

test('a cast that shows late is waited for until 1.1s; one that never shows, or a shadow gone, cancels nothing', function ()
    local g, mem = ichi_sent()
    g.now = g.now + 1
    eq(engine.cancel(g, mem), nil, 'not casting yet')
    g.now, g.casting = g.now + 0.05, true
    eq(engine.cancel(g, mem), COPY, 'shown late')
    g, mem = ichi_sent()
    g.now = g.now + 1.1
    eq(engine.cancel(g, mem), nil, 'never shown')
    eq(mem.cancel, nil, 'and forgotten')
    g, mem = ichi_sent()
    g.casting, g.me.buffs[COPY] = true, nil
    g.now = g.now + 1
    eq(engine.cancel(g, mem), nil, 'gone already')
end)

-- Sange --------------------------------------------------------------------------------

test('Sange in combat with no shuriken worn equips the best you hold, then goes', function ()
    local cfg = cfg_with({ Sange = true })
    local items = { [SHURIKEN] = { 'Shuriken', 18 }, [FUMA] = { 'Fuma Shuriken', 60 } }
    local g = snap(nil, nil, { combat = true, owned = owned(items) })
    local cmd, intent = decide(g, cfg)
    eq({ cmd, intent.behavior, intent.why }, { '/equip ammo "Fuma Shuriken" 0', 'buff', 'for Sange: Me lacks it' })
    g.ammo = FUMA
    eq(decide(g, cfg), '/ja "Sange" <me>')
    g.me.buffs[SANGE] = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
end)

test('Sange: no equip out of combat, with none held, on recast, or while one just sent shows', function ()
    local cfg = cfg_with({ Sange = true })
    local items = { [SHURIKEN] = { 'Shuriken', 18 } }
    eq({ decide(snap(nil, nil, { owned = owned(items) }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, nil, { combat = true, owned = owned({}) }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, nil, { combat = true, owned = owned(items) }, { Sange = 60 }), cfg) }, { nil, 'nothing to do' })
    local mem, g = {}, snap(nil, nil, { combat = true, owned = owned(items) })
    local _, intent = decide(g, cfg, cat, mem)
    engine.sent(intent, g, mem)
    g.now = g.now + 1
    eq({ decide(g, cfg, cat, mem) }, { nil, 'nothing to do' })
end)

test('Sange waiting on its shuriken leaves the buff rows after it to go', function ()
    local cfg = cfg_with({ Sange = true, Utsusemi = true })
    local mem, g = {}, snap({ [SHIHEI] = 1 }, nil, { combat = true, owned = owned({ [SHURIKEN] = { 'Shuriken', 18 } }) })
    local cmd, intent = decide(g, cfg, cat, mem)
    eq(cmd, '/equip ammo "Shuriken" 0')
    engine.sent(intent, g, mem)
    g.now = g.now + 1.5
    eq(decide(g, cfg, cat, mem), '/ma "Utsusemi: Ni" <me>')
end)

test('Sange\'s equip names the shuriken in Japanese on a Japanese client', function ()
    local cfg = cfg_with({ Sange = true })
    cfg.ui.japanese = true
    local own = function (ids)
        local out = {}
        for _, id in ipairs(ids) do
            if id == SHURIKEN then out[1] = { id = id, en = 'Shuriken', jp = '\142\232', level = 18, jobs = bit.lshift(1, NIN), bag = 0 } end
        end
        return out
    end
    eq(decide(snap(nil, nil, { combat = true, owned = own }), cfg), '/equip ammo "\142\232" 0')
end)

test('equips given up on are counted per action: another row\'s doesn\'t reset them', function ()
    local cfg = cfg_with({ Sange = true, Utsusemi = true })
    local mem, g = {}, snap({ [SHIHEI] = 9 }, { COPY4 }, { combat = true, owned = owned({ [SHURIKEN] = { 'Shuriken', 18 } }) })
    for _ = 1, 3 do
        local cmd, intent = decide(g, cfg, cat, mem)
        eq(cmd, '/equip ammo "Shuriken" 0')
        engine.sent(intent, g, mem)
        mem.ammo_tried.Reward = { into = 'x', n = 1 }  -- pet care's food in between
        g.now = g.now + 3
    end
    eq({ decide(g, cfg, cat, mem) }, { nil, 'nothing to do' })
end)

test('a row with no ammo and no tier it can use still sends nothing', function ()
    local cfg = cfg_with({ Utsusemi = true, nin_stance = true })
    cfg.rows.nin_stance.pick = 'Yonin'
    eq({ decide(snap({ [SHIHEI] = 1 }, { COPY4 }, nil, { Yonin = 30 }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap({ [SHIHEI] = 1 }, { COPY4 }, nil, { Yonin = 30, ['Utsusemi: Ni'] = 30, ['Utsusemi: Ichi'] = 10 }), cfg) },
       { nil, 'nothing to do' })
end)

-- UI -----------------------------------------------------------------------------------

local NAMES = { job = function (id) return ({ [13] = 'NIN', [1] = 'WAR', [3] = 'WHM' })[id] end, statuses = fake.res.statuses }
local function status() return { running = false, open = true, log = false, sent = {} } end

local function rows(view)
    local out = {}
    for _, sec in ipairs(view.sections) do for _, r in ipairs(sec.rows or {}) do out[r.key] = r end end
    return out
end

test('ui: a ninjutsu row shows its tools (not as an item row) and says when there are none', function ()
    local cfg = cfg_with({ Utsusemi = true })
    local r = rows(model.build(snap({ [SHIHEI] = 4, [FUDA] = 2 }), cat, cfg, status(), NAMES))
    eq({ r.Utsusemi.tools, r.Utsusemi.count, r.Utsusemi.ready, r.Tonko.tools }, { 6, nil, true, 2 })
    r = rows(model.build(snap(), cat, cfg, status(), NAMES))
    eq({ r.Utsusemi.tools, r.Utsusemi.ready, r.Utsusemi.avail }, { 0, false, 'no tools' })
    eq(r.Yonin and r.Yonin.tools or r.nin_stance.tools, nil)
    local war = fake.catalog(WAR, 75, NIN, 37)
    r = rows(model.build(snap({ [FUDA] = 9 }, nil, { main = WAR, sub = NIN }), war, cfg, status(), NAMES))
    eq({ r.Utsusemi.tools, r.Utsusemi.avail }, { 0, 'no tools' }, 'Shikanofuda counts on a NIN main job only')
end)

test('ui: Sange says it equips the shuriken you hold', function ()
    local g = snap(nil, nil, { combat = true, owned = owned({ [KOGA] = { 'Koga Shuriken', 75 } }) })
    local r = rows(model.build(g, cat, cfg_with(), status(), NAMES))
    eq({ r.Sange.ready, r.Sange.avail }, { true, 'equips Koga Shuriken' })
end)

test('ui: the one-shadow option shows for a job with Utsusemi, and can be set from another session', function ()
    local cfg = settings.defaults()
    local view = model.build(snap(), cat, cfg, status(), NAMES)
    eq({ view.buff.shadows, view.buff.one_shadow }, { true, false })
    local whm = model.build(fake.snap(), fake.catalog(WHM, 75, nil, 0), cfg, status(), NAMES)
    eq(whm.buff.shadows, false)
    local act = model.actions(cfg, status(), function () end)
    eq({ model.apply(act, cfg, { 'set', n = 2, 'buff.one_shadow', true }, cat), cfg.buff.one_shadow }, { true, true })
    eq({ model.apply(act, cfg, { 'set', n = 2, 'buff.one_shadow', false }, cat), cfg.buff.one_shadow }, { true, false })
end)
