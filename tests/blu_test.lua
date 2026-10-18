-- Blue Mage (jobs/blu.lua): only the set spells are in the catalog, read from
-- the server's 0x044; Diffusion spreads a blue magic buff on you to the party.
local blu = require('jobs.blu')
local catalog = require('core.catalog')
local engine = require('core.engine')
local packets = require('core.packets')
local settings = require('core.settings')
local K = require('core.knowledge')
local model = require('ui.model')
local fake = require('tests.fake')

local BLU, WHM = 16, 3
local COCOON, METALLIC, REFUELING, HEALING_BREEZE = 547, 517, 530, 581  -- spell ids
local DEFENSE_BOOST, DIFFUSION = 93, 356
local cat = fake.catalog(BLU, 75, WHM, 37, { 'Diffusion' })

local function named(list, name, role)
    for _, a in ipairs(list) do
        if a.name == name and (not role or a.role == role) then return a end
    end
end

-- The catalog for BLU 75 / WHM 37 with only `set` (spell ids) set.
local function with_set(set)
    local ids = {}
    for _, id in ipairs(set) do ids[id] = true end
    return catalog.build(fake.res, {
        main = BLU, main_lv = 75, sub = WHM, sub_lv = 37,
        has_spell = function () return true end,
        has_ability = function () return false end,
        set_spells = ids,
    }, K)
end

-- A 0x044 as the server builds it: the job at 0x04, BLU's set slots from 0x08.
local function job_packet(job, slots)
    local b = {}
    for i = 1, 0x9C do b[i] = 0 end
    b[0x04 + 1] = job
    for i, v in ipairs(slots) do b[0x08 + i] = v end
    return { id = 0x044, data = string.char(unpack(b)) }
end

-- BLU 75 / WHM 37 with these statuses on you; others in slots 1..n.
local function snap(buffs, others, waits)
    local g = fake.snap(others or {}, { main = BLU, sub = WHM }, waits)
    for _, id in ipairs(buffs or {}) do g.me.buffs[id] = true end
    return g
end

local function cfg_with(rows)
    local cfg = settings.defaults()
    for k, v in pairs(rows) do cfg.rows[k] = v end
    return cfg
end

local function decide(g, cfg, mem)
    local intent, why = engine.decide(g, cat, cfg, mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg), intent
end

-- Set spells -----------------------------------------------------------------------

test('catalog: only the set blue magic; other jobs\' spells are untouched', function ()
    local list = with_set({ COCOON, HEALING_BREEZE })
    eq({ named(list, 'Cocoon') ~= nil, named(list, 'Healing Breeze') ~= nil, named(list, 'Metallic Body') },
       { true, true, nil })
    eq(named(list, 'Cure III') ~= nil, true)  -- the WHM subjob's
    -- None set (the set not known yet): no blue magic at all.
    list = with_set({})
    eq({ named(list, 'Cocoon'), named(list, 'Cure III') ~= nil }, { nil, true })
end)

test('0x044: BLU\'s 20 slots hold each spell id - 0x200, 0 for an empty one', function ()
    eq(blu.set(), nil)
    packets.handle(job_packet(BLU, { COCOON - 0x200, 0, METALLIC - 0x200 }), {}, 0)
    local v = blu.version()
    eq(blu.set(), { [COCOON] = true, [METALLIC] = true })
    packets.handle(job_packet(WHM, { REFUELING - 0x200 }), {}, 0)  -- another job's: not a set
    eq({ blu.set(), blu.version() }, { { [COCOON] = true, [METALLIC] = true }, v })
    local all = {}
    for i = 1, 20 do all[i] = REFUELING - 0x200 + i - 1 end
    packets.handle(job_packet(BLU, all), {}, 0)
    eq({ blu.set()[REFUELING], blu.set()[REFUELING + 19], blu.set()[METALLIC], blu.version() }, { true, true, nil, v + 1 })
end)

-- Diffusion ------------------------------------------------------------------------

test('catalog: Diffusion fits blue magic that goes on you alone', function ()
    local dif = named(cat, 'Diffusion')
    eq({ dif.role, dif.status, dif.chip, dif.spreads }, { 'modifier', { DIFFUSION }, 'Dif', { area = 10, mp = 1 } })
    eq({ dif.applies(named(cat, 'Cocoon')), dif.applies(named(cat, 'Refueling')), dif.applies(named(cat, 'Protect')) },
       { true, true, false })
end)

test('Diffusion spreads a blue magic buff whenever someone near you lacks it', function ()
    local cfg = cfg_with({ Cocoon = { on = true, mods = { Diffusion = true } } })
    local others = { { name = 'A' }, { name = 'B', buffs = { [DEFENSE_BOOST] = true } } }
    local mem = {}
    local cmd, intent = decide(snap({}, others), cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Diffusion" <me>', 'for Cocoon: Me +1 lack it' })
    engine.sent(intent, snap({}, others), mem)
    local g = snap({}, others, { Diffusion = 600 })
    g.now = 1001.5
    eq(decide(g, cfg, mem), '/ma "Cocoon" <me>')
    -- Up on you, but A lacks it: spread to A.
    cmd, intent = decide(snap({ DEFENSE_BOOST }, others), cfg, {})
    eq({ cmd, intent.why }, { '/ja "Diffusion" <me>', 'for Cocoon: A lacks it' })
    -- Without the chip, only you count.
    cfg.rows.Cocoon.mods = nil
    eq(decide(snap({ DEFENSE_BOOST }, others), cfg, {}), nil)
end)

test('Diffusion on recast: the spell goes alone, or waits with Hold on', function ()
    local cfg = cfg_with({ Cocoon = { on = true, mods = { Diffusion = true } } })
    local others = { { name = 'A' } }
    eq(decide(snap({}, others, { Diffusion = 300 }), cfg), '/ma "Cocoon" <me>')
    eq(decide(snap({ DEFENSE_BOOST }, others, { Diffusion = 300 }), cfg), nil)  -- only A lacks it
    cfg.rows.Cocoon.hold = true
    eq(decide(snap({}, others, { Diffusion = 300 }), cfg), nil)
end)

test('UI: a blue magic buff row has a Dif chip; other rows don\'t', function ()
    local names = { job = function () return 'BLU' end, statuses = fake.res.statuses }
    local view = model.build(fake.snap({}), cat, settings.defaults(), { running = false, sent = {} }, names)
    local rows = {}
    for _, s in ipairs(view.sections) do
        if s.id == 'buff' then for _, r in ipairs(s.rows) do rows[r.key] = r end end
    end
    eq({ rows.Cocoon.mods[1].label, rows.Cocoon.mods[1].note, rows.Protect ~= nil, rows.Protect.mods == nil },
       { 'Dif', 'on everyone near you', true, true })
end)
