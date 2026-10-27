-- Rune Fencer's runes (jobs/run.lua): the Idle set, each ward's set taking the
-- slots once it's ready, the ward fired in combat, through the engine; Embolden
-- as a modifier; and the Runes section in ui/model.lua.
local run = require('jobs.run')
local engine = require('core.engine')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local RUN, WAR, BLM, WHM = 22, 1, 4, 3
local IGNIS, TELLUS, VALLATION, VALIANCE, EMBOLDEN, LIEMENT, INVISIBLE = 523, 526, 531, 535, 534, 537, 69
local JAS = { 'Ignis', 'Gelus', 'Tellus', 'Vallation', 'Valiance', 'Pflug', 'Embolden', 'Swordplay' }
local cat = fake.catalog(RUN, 75, BLM, 37, JAS)

local named = fake.named

-- RUN 75 (or `over`'s jobs) with these statuses on you, counted: { [id] = n }.
local function snap(stacks, over, waits)
    local o = { main = RUN, main_lv = 75, sub = BLM, sub_lv = 37 }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap({}, o, waits)
    g.me.stacks = {}
    for id, n in pairs(stacks or {}) do g.me.buffs[id], g.me.stacks[id] = true, n end
    return g
end

-- Settings with these sets: { idle = { 'Ignis', ... }, vallation = {...} }; buffs off.
local function cfg_with(sets)
    local cfg = settings.defaults()
    for key, picks in pairs(sets or {}) do
        for i, name in ipairs(picks) do cfg.rune[key .. '_' .. i] = name end
    end
    return cfg
end

local function decide(g, cfg, list) return fake.decide(g, list or cat, cfg) end

test('catalog: runes, wards in priority order with their blocks, Embolden for white enhancing magic', function ()
    local ignis, vallation = named(cat, 'Ignis'), named(cat, 'Vallation')
    eq({ ignis.role, ignis.status, ignis.rune }, { 'rune', { IGNIS }, { element = 'Fire', resist = 'Ice', ailments = 'Paralyze / Bind' } })
    eq({ vallation.role, vallation.status, vallation.blocked_by }, { 'ward', { VALLATION }, { VALIANCE, LIEMENT } })
    local _, wards = run.actions(cat)
    eq({ wards[1].name, wards[2].name, wards[3].name }, { 'Vallation', 'Valiance', 'Pflug' })
    local e = named(cat, 'Embolden')
    eq({ e.role, e.status, e.chip }, { 'modifier', { EMBOLDEN }, 'Emb' })
    eq({ e.applies(named(cat, 'Protect')), e.applies(named(cat, 'Blaze Spikes')) }, { true, false })
end)

test('rune slots follow the RUN level, main or sub', function ()
    eq({ run.slots(5), run.slots(34), run.slots(35), run.slots(64), run.slots(65) }, { 1, 1, 2, 2, 3 })
    local level = require('core.util').level
    eq(level(snap(), run.JOB), 75)
    eq(level(snap(nil, { main = WAR, sub = RUN, sub_lv = 37 }), run.JOB), 37)
    eq(level(snap(nil, { main = WAR, sub = WHM }), run.JOB), 0)
end)

test('Idle keeps its runes up, the same rune twice meaning two; an empty slot is skipped', function ()
    local cfg = cfg_with({ idle = { 'Ignis', '', 'Ignis' } })
    eq(decide(snap(), cfg), '/ja "Ignis" <me>')
    eq(decide(snap({ [IGNIS] = 1 }), cfg), '/ja "Ignis" <me>')
    eq(decide(snap({ [IGNIS] = 2 }), cfg), nil)
    cfg.rune.idle_2 = 'Gelus'
    eq(decide(snap({ [IGNIS] = 2 }), cfg), '/ja "Gelus" <me>')
end)

test('runes, Quick Draw and stratagems cost no MP, whatever the DAT says: they go at 0 MP', function ()
    local g = snap()
    g.me.mp = 0
    eq(decide(g, cfg_with({ idle = { 'Ignis' } })), '/ja "Ignis" <me>')
    local sch = fake.catalog(20, 75, WHM, 37, { 'Penury', 'Light Arts' })
    eq({ named(cat, 'Ignis').mp, named(sch, 'Penury').mp }, { 0, 0 })
end)

-- The game pushes the oldest rune out for a new one past the slots.
local function cast(held, name, slots)
    held[#held + 1] = name
    if #held > slots then table.remove(held, 1) end
end
local function stacks_of(held)
    local ids = {}
    for _, n in ipairs({ 'Ignis', 'Gelus', 'Tellus' }) do ids[n] = named(cat, n).status[1] end
    local out = {}
    for _, n in ipairs(held) do out[ids[n]] = (out[ids[n]] or 0) + 1 end
    return out
end

test('a set settles however the runes up are ordered, the oldest pushed out each time', function ()
    local cfg = cfg_with({ idle = { 'Gelus', 'Ignis', 'Ignis' } })
    local list = fake.catalog(RUN, 75, BLM, 37, { 'Ignis', 'Gelus', 'Tellus' })
    for _, start in ipairs({ { 'Ignis', 'Gelus', 'Tellus' }, { 'Gelus', 'Tellus', 'Tellus' }, { 'Ignis', 'Ignis', 'Tellus' } }) do
        local held, casts = { unpack(start) }, 0
        while true do
            local cmd = decide(snap(stacks_of(held)), cfg, list)
            if not cmd then break end
            cast(held, cmd:match('"(.-)"'), 3)
            casts = casts + 1
            assert(casts <= 3, 'settles within the slots')
        end
        eq(stacks_of(held), stacks_of({ 'Gelus', 'Ignis', 'Ignis' }))
    end
end)

test('a set holds only as many runes as the level stands: a RUN subjob\'s two', function ()
    local cfg = cfg_with({ idle = { 'Ignis', 'Ignis', 'Gelus' } })
    local sub = { main = WAR, main_lv = 75, sub = RUN, sub_lv = 37 }
    local list = fake.catalog(WAR, 75, RUN, 37, JAS)
    eq(decide(snap({ [IGNIS] = 2 }, sub), cfg, list), nil, 'the third slot is past a 37\'s two')
end)

test('a ready ward takes the slots: its runes up, then it fires in combat only', function ()
    local cfg = cfg_with({ idle = { 'Ignis' }, vallation = { 'Tellus' } })
    local cmd, intent = decide(snap(), cfg)
    eq({ cmd, intent.why, intent.behavior }, { '/ja "Tellus" <me>', 'for Vallation', 'rune' })
    eq(decide(snap({ [TELLUS] = 1 }), cfg), nil, 'out of combat its set waits up: Idle does not swap it back')
    eq(decide(snap({ [TELLUS] = 1 }, { combat = true }), cfg), '/ja "Vallation" <me>')
    eq(decide(snap({ [TELLUS] = 1 }, nil, { Vallation = 120, Valiance = 300, Pflug = 180 }), cfg), '/ja "Ignis" <me>',
        'on recast, Idle takes the slots back')
end)

test('a ward\'s set waits out the runes\' shared recast rather than letting Idle in', function ()
    local cfg = cfg_with({ idle = { 'Ignis' }, vallation = { 'Tellus' } })
    eq(decide(snap({ [IGNIS] = 1 }, nil, { Tellus = 3, Ignis = 3 }), cfg), nil)
end)

test('a ward that is off, has no runes picked or is blocked takes nothing: the next one does', function ()
    local cfg = cfg_with({ idle = { 'Ignis' }, vallation = { 'Tellus' }, valiance = { 'Gelus' } })
    cfg.rows.Vallation = { on = false }
    eq(decide(snap(), cfg), '/ja "Gelus" <me>')
    eq(decide(snap({ [VALLATION] = 1 }), cfg), '/ja "Ignis" <me>', 'Valiance does nothing under Vallation')
    cfg.rows.Vallation, cfg.rune.vallation_1 = nil, ''
    eq(select(2, decide(snap(), cfg)).why, 'for Valiance')
    eq(decide(snap({ [LIEMENT] = 1 }), cfg), '/ja "Ignis" <me>', 'Liement stops both')
    local valiance = named(cat, 'Valiance')
    eq({ require('core.can').use(valiance, snap({ [LIEMENT] = 1 })) }, { false, 'blocked by Liement' },
        'the row names the status that is up')
end)

test('nothing goes while you are Invisible, off RUN or with Runes off', function ()
    local cfg = cfg_with({ idle = { 'Ignis' } })
    eq(decide(snap({ [INVISIBLE] = 1 }), cfg), nil)
    eq(decide(snap(nil, { main = WAR, sub = WHM }), cfg), nil)
    cfg.rune.on = false
    eq(decide(snap(), cfg), nil)
end)

test('runes still go while a cure is held for, ahead of the luopan', function ()
    local at = {}
    for i, x in ipairs(engine.BEHAVIORS) do at[x.name] = i end
    eq(engine.BEHAVIORS[at.rune].quick, true)
    eq(at.rune < at.geo and at.geo < at.buff, true, 'before the luopan and buffs, as v2')
end)

test('Embolden on a buff row goes just before the spell', function ()
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, mods = { Embolden = true } }
    local cmd, intent = decide(snap(), cfg)
    eq({ cmd, intent.expect }, { '/ja "Embolden" <me>', { EMBOLDEN } })
    eq(decide(snap({ [EMBOLDEN] = 1 }), cfg), '/ma "Protect III" <me>')
    eq(decide(snap(nil, nil, { Embolden = 200 }), cfg), '/ma "Protect III" <me>', 'on recast, the spell goes unboosted')
end)

test('Hold on its row: the spell waits while Embolden can\'t go with it', function ()
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, mods = { Embolden = true }, hold = true }
    eq(decide(snap(nil, nil, { Embolden = 200 }), cfg), nil)
    eq(decide(snap({ [EMBOLDEN] = 1 }, nil, { Embolden = 200 }), cfg), '/ma "Protect III" <me>', 'up already: it goes')
    eq(decide(snap(), cfg), '/ja "Embolden" <me>')
    cfg.rows.Shell = { on = true }
    eq(decide(snap(nil, nil, { Embolden = 200 }), cfg), '/ma "Shell IV" <me>', 'only that row waits')
end)

local NAMES = { job = function (id) return ({ [22] = 'RUN', [4] = 'BLM', [1] = 'WAR', [3] = 'WHM' })[id] end,
                statuses = fake.res.statuses }
local function view(g, list, cfg)
    return model.build(g, list or cat, cfg or settings.defaults(), { running = false, sent = {} }, NAMES)
end

local function section(v, id)
    for _, s in ipairs(v.sections) do if s.id == id then return s end end
end

test('model: Runes under Buff, Idle then each ward with its switch, its readiness and its picks', function ()
    local cfg = cfg_with({ idle = { 'Ignis', 'Gelus' } })
    local v = view(snap(nil, nil, { Valiance = 30 }), nil, cfg)
    eq(section(v, 'rune').header, 'Buff')
    eq({ v.rune.slots, #v.rune.runes, v.rune.runes[1] }, { 3, 3, { name = 'Ignis', label = 'Ignis', element = 'Fire', resist = 'Ice', ailments = 'Paralyze / Bind' } })
    local idle, vallation, valiance = v.rune.sets[1], v.rune.sets[2], v.rune.sets[3]
    eq({ idle.key, idle.label, idle.shows, idle.ward, idle.picks }, { 'idle', 'Idle', 'element', nil, { 'Ignis', 'Gelus', '' } })
    eq({ vallation.ward, vallation.shows, vallation.on, vallation.ready, vallation.avail }, { 'Vallation', 'resist', true, true, 'ready' })
    eq({ valiance.ready, valiance.avail }, { false, 'recast 30s' })
    eq(v.rune.sets[4].shows, 'ailments')
    eq(v.heal.stratagems, false, 'Embolden is no stratagem: no charge to keep for healing')
    eq(section(view(snap(nil, { main = WHM, sub = BLM }), fake.catalog(WHM, 75, BLM, 37, {})), 'rune'), nil)
    -- A RUN subjob at 37: two slots, and only the wards it has.
    local sub = view(snap(nil, { main = WAR, sub = RUN, sub_lv = 37 }), fake.catalog(WAR, 75, RUN, 37, { 'Ignis', 'Vallation' }))
    eq({ sub.rune.slots, #sub.rune.sets, sub.rune.sets[2].ward }, { 2, 2, 'Vallation' })
end)

test('model: a buff row of white enhancing magic gets an Emb chip', function ()
    local v = view(snap())
    local protect
    for _, r in ipairs(section(v, 'buff').rows) do if r.key == 'Protect' then protect = r end end
    eq(protect.mods, { { name = 'Embolden', label = 'Emb', note = 'more potent', on = false } })
    eq(protect.hold, false)
    local cfg = settings.defaults()
    local act = model.actions(cfg, { running = false, sent = {} }, function () end)
    act.hold('Protect', true)
    eq(cfg.rows.Protect, { on = false, hold = true })
    eq(model.apply(act, cfg, { 'hold', n = 2, 'Protect', false }, cat), true)
    eq(cfg.rows.Protect.hold, nil)
    eq(model.apply(act, cfg, { 'hold', n = 1, 'Protect' }, cat), false, 'its state, never a toggle')
end)

test('another session may pick a rune for any set\'s slot, by name', function ()
    local cfg, st = settings.defaults(), { running = false, sent = {} }
    local act = model.actions(cfg, st, function () end)
    eq(model.apply(act, cfg, { 'set', n = 2, 'rune.pflug_3', 'Lux' }), true)
    eq(model.apply(act, cfg, { 'set', n = 2, 'rune.pflug_4', 'Lux' }), false)
    eq(model.apply(act, cfg, { 'set', n = 2, 'rune.idle_1', 3 }), false)
    eq(cfg.rune.pflug_3, 'Lux')
end)
