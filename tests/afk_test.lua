-- AFK sleep (core/afk.lua): asleep after the party's stillness out of combat,
-- awake on your own movement, and its gate, view and remote setting.
local afk = require('core.afk')
local engine = require('core.engine')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local cat = fake.catalog(3, 75, 4, 37, {})

-- A snapshot `t` seconds in: `over` its flags, `others` the party but you.
local function at(t, over, others)
    local o = { now = t }
    for k, v in pairs(over or {}) do o[k] = v end
    return fake.snap(others or { { name = 'A' } }, o)
end

test('asleep once no one has moved out of combat for the minutes set; your movement wakes it', function ()
    local cfg, st = settings.defaults(), {}
    eq(cfg.afk, { on = true, minutes = 10 })  -- on, as v2
    eq({ afk.update(at(0), cfg, st) }, { false })
    eq(afk.left(at(60), cfg, st), 540)
    eq({ afk.update(at(599), cfg, st) }, { false })
    eq({ afk.update(at(600), cfg, st) }, { true, 'AFK: no movement or combat for 10 min. Automation asleep: move to wake.' })
    eq({ afk.update(at(700), cfg, st) }, { true })  -- said once
    eq(afk.left(at(700), cfg, st), nil)
    eq({ afk.update(at(701, { moving = true }), cfg, st) }, { false, 'AFK: you moved. Automation resumed.' })
    eq(afk.left(at(701), cfg, st), 600)  -- a full wait again
end)

test('the party moving or combat keeps it awake; neither wakes it once asleep', function ()
    local cfg, st = settings.defaults(), {}
    cfg.afk.minutes = 1
    afk.update(at(0), cfg, st)
    afk.update(at(50, nil, { { name = 'A', moving = true } }), cfg, st)  -- a member moved
    eq({ afk.update(at(100), cfg, st) }, { false })
    afk.update(at(105, { combat = true }), cfg, st)
    eq({ afk.update(at(160), cfg, st) }, { false })
    afk.update(at(165, nil, { { name = 'T', kind = 'trust', moving = true } }), cfg, st)  -- a trust too
    eq({ afk.update(at(220), cfg, st) }, { false })
    -- Players outside your party never count: the alliance and those you track.
    local outside = { { name = 'B0', kind = 'alliance', moving = true }, { name = 'X', kind = 'tracked', moving = true } }
    eq(afk.update(at(225, nil, outside), cfg, st), true)  -- 60s after the trust moved
    eq(afk.update(at(300, { combat = true }, { { name = 'A', moving = true } }), cfg, st), true)  -- a pull is no proof you're back
end)

test('off: never asleep, and turned on again it waits the whole time', function ()
    local cfg, st = settings.defaults(), {}
    cfg.afk.minutes = 1
    afk.update(at(0), cfg, st)
    eq(afk.update(at(60), cfg, st), true)
    cfg.afk.on = false
    eq({ afk.update(at(61), cfg, st) }, { false })
    eq(afk.left(at(61), cfg, st), nil)
    cfg.afk.on = true
    eq({ afk.update(at(62), cfg, st) }, { false })
    eq(afk.left(at(70), cfg, st), 52)
end)

test('asleep is a gate: nothing is decided, and the HUD says why', function ()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A', hpp = 40 } }, { afk = true })
    eq({ engine.decide(g, cat, cfg, {}) }, { nil, 'afk' })
    g.afk = nil
    eq(engine.decide(g, cat, cfg, {}) ~= nil, true)
    local st = { running = true, sent = {}, why = 'afk' }
    local view = model.build(fake.snap({}, { afk = true, afk_in = nil }), cat, cfg, st, { job = function () return 'WHM' end, statuses = {} })
    eq({ view.status.dim, view.flags, view.afk }, { 'AFK asleep', { 'AFK asleep' }, { minutes = 10, asleep = true } })
    view = model.build(fake.snap({}, { afk_in = 90 }), cat, cfg, st, { job = function () return 'WHM' end, statuses = {} })
    eq(view.afk, { minutes = 10, asleep = false, left = 90 })
end)

test('another session may switch it and set its minutes, held to the slider\'s range', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, {}, function () end, {}, nil)
    local function call(...) return { n = select('#', ...) - 1, ... } end
    eq({ model.apply(act, cfg, call('section', 'afk', false), cat), cfg.afk.on }, { true, false })
    eq({ model.apply(act, cfg, call('set', 'afk.minutes', 90), cat), cfg.afk.minutes }, { true, afk.MAX })
    eq({ model.apply(act, cfg, call('set', 'afk.minutes', 0), cat), cfg.afk.minutes }, { true, afk.MIN })
    eq(model.apply(act, cfg, call('set', 'afk.on', 'yes'), cat), false)
end)
