-- ui/model.lua over the real catalog: what the window shows, and the mutators.
local model = require('ui.model')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, BLM, RDM, BRD = 3, 4, 5, 10
local JOBS = { [WHM] = 'WHM', [BLM] = 'BLM', [RDM] = 'RDM', [BRD] = 'BRD' }
local NAMES = { job = function (id) return JOBS[id] end, statuses = fake.res.statuses }

local whm = fake.catalog(WHM, 75, BLM, 37, { 'Divine Seal', 'Martyr' })

local function status(t)
    local s = { running = false, log = true, sent = {} }
    for k, v in pairs(t or {}) do s[k] = v end
    return s
end

local function build(cat, cfg, g, st)
    return model.build(g or fake.snap({ { name = 'A' }, { name = 'B' } }), cat, cfg or settings.defaults(), st or status(), NAMES)
end

local function section(view, id)
    for _, s in ipairs(view.sections) do if s.id == id then return s end end
end

local function row(view, id, key)
    for _, r in ipairs(section(view, id).rows) do if r.key == key then return r end end
end

local function keys(list, field)
    local out = {}
    for i, x in ipairs(list or {}) do out[i] = x[field or 'key'] end
    return out
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

test('WHM 75 / BLM 37: every behavior section, in order, then Options', function ()
    local view = build(whm)
    eq(view.job, 'WHM 75 / BLM 37')
    eq(keys(view.sections, 'id'), { 'heal', 'remove', 'buff', 'revive', 'options' })
    eq(keys(view.sections, 'title'), { 'Healing', 'Debuffs', 'Buffs', 'Raise', 'Options' })
    eq(keys(section(view, 'heal').rows), { 'Cure', 'Curaga', 'Regen', 'Drain', 'Divine Seal', 'Martyr' })  -- heal, then emergency
    eq(keys(section(view, 'revive').rows), { 'Raise', 'Arise' })
end)

test('a section with nothing to show is left out: BLM 75 has no removal or raise', function ()
    eq(keys(build(fake.catalog(BLM, 75, 0, 0)).sections, 'id'), { 'heal', 'buff', 'options' })
end)

test('heal rows are on by default, with no choices or targets', function ()
    local r = row(build(whm), 'heal', 'Cure')
    eq({ r.label, r.on, r.choices, r.targets, r.ready, r.avail, r.action }, { 'Cure', true, nil, nil, true, 'ready', 'Cure V' })
end)

test('a tier buff: off, Auto then each tier, targets on you by default', function ()
    local r = row(build(whm), 'buff', 'Protect')
    eq(r.on, false)
    eq(keys(r.choices, 'label'), { 'Auto (best)', 'Protect', 'Protect II', 'Protect III', 'Protect IV' })
    eq(r.choice, 'Auto (best)')
    eq(keys(r.targets, 'label'), { 'ME', 'P1', 'P2', 'P3', 'P4', 'P5' })
    eq(keys(r.targets, 'on'), { true, false, false, false, false, false })
    eq(keys(r.targets, 'present'), { true, true, true, false, false, false })
    eq(r.targets[2].name, 'A')
end)

test('self-only buffs have no targets', function ()
    eq(row(build(whm), 'buff', 'Protectra').targets, nil)
end)

test('a pick-one group needs a pick: no Auto, and it says so', function ()
    local r = row(build(whm), 'buff', 'barelement')
    eq({ r.label, r.choice, r.choices[1].label, r.ready, r.avail }, { 'Barelement', 'Pick one', 'Barfira', false, 'pick one' })
end)

test('BRD 75 / WHM 37 songs: the shared note on the row, else on each choice', function ()
    local view = build(fake.catalog(BRD, 75, WHM, 37))
    eq(row(view, 'buff', 'minuet').label, 'Valor Minuet (+ATK)')
    eq(row(view, 'buff', 'minuet').choices[2].label, 'Valor Minuet II')
    eq(row(view, 'buff', 'madrigal').label, 'Sword Madrigal / Blade Madrigal')
    eq(keys(row(view, 'buff', 'madrigal').choices, 'label'), { 'Sword Madrigal (+ACC)', 'Blade Madrigal (++ACC)' })
    eq(row(view, 'buff', 'etude').label, 'Etude')
    eq(row(view, 'buff', 'minuet').targets, nil)  -- songs are sung on yourself
    eq(row(view, 'buff', 'Adventurer\'s Dirge').label, 'Adventurer\'s Dirge (-Enmity)')
end)

test('RDM 75 / WHM 37: a family reaching others at any tier gets targets', function ()
    local view = build(fake.catalog(RDM, 75, WHM, 37))
    local r = row(view, 'buff', 'Phalanx')  -- Phalanx is self-only, Phalanx II is not
    eq({ r.targets ~= nil, #r.choices }, { true, 3 })
    eq(row(view, 'buff', 'enspell').choices[7].label, 'Enfire II')
end)

test('availability: the shortest recast, then MP, combat only', function ()
    local waits = { ['Cure'] = 20, ['Cure II'] = 9.2, ['Cure III'] = 30, ['Cure IV'] = 30, ['Cure V'] = 30 }
    eq(row(build(whm, nil, fake.snap({}, nil, waits)), 'heal', 'Cure').avail, 'recast 10s')
    local g = fake.snap({})
    g.me.mp = 0
    eq(row(build(whm, nil, g), 'heal', 'Cure').avail, 'MP')
    eq(row(build(whm, nil, fake.snap({}, { combat = true })), 'revive', 'Raise').avail, 'idle only')
end)

test('a picked tier is the one checked; a pick the job lost says so', function ()
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, pick = 'Protect II' }
    local r = row(build(whm, cfg, fake.snap({}, nil, { ['Protect II'] = 4 })), 'buff', 'Protect')
    eq({ r.choice, r.pick, r.avail }, { 'Protect II', 'Protect II', 'recast 4s' })
    cfg.rows.Protect.pick = 'Protect V'
    r = row(build(whm, cfg), 'buff', 'Protect')
    eq({ r.choice, r.avail }, { 'Protect V (not available)', 'not available' })
end)

test('building never writes the settings, even on a frame with nobody in it', function ()
    local cfg = settings.defaults()
    cfg.rows.Haste = { on = true, targets = { [3] = true } }
    local before = copy(cfg)
    build(whm, cfg)
    build(whm, cfg, fake.snap({}, { main_lv = 1, sub_lv = 0 }))
    build({}, cfg)  -- zoning: nothing learned
    eq(cfg, before)
end)

test('mutators create a row on first touch, from its default', function ()
    local cfg = settings.defaults()
    model.set_pick(cfg, 'Protect', 'Protect III')
    eq(cfg.rows.Protect, { on = false, pick = 'Protect III' })
    model.set_pick(cfg, 'Protect', nil)
    eq(cfg.rows.Protect, { on = false })
    model.toggle_target(cfg, 'Haste', 2)
    eq(cfg.rows.Haste, { on = false, targets = { [0] = true, [2] = true } })
    model.toggle_target(cfg, 'Haste', 0)
    eq(cfg.rows.Haste.targets, { [2] = true })
    model.set_row_on(cfg, 'Haste', true)
    model.set_row_on(cfg, 'Cure', false)
    eq({ cfg.rows.Haste.on, cfg.rows.Cure }, { true, { on = false } })
    local view = build(whm, cfg)
    eq({ row(view, 'heal', 'Cure').on, row(view, 'buff', 'Haste').on }, { false, true })
    eq(keys(row(view, 'buff', 'Haste').targets, 'on'), { false, false, true, false, false, false })
end)

test('section switches and plain values', function ()
    local cfg = settings.defaults()
    model.set_section(cfg, 'buff', false)
    model.set_value(cfg, 'heal.danger', 60)
    model.set_value(cfg, 'heal.focus', 'A')
    model.set_value(cfg, 'japanese', true)
    model.set_value(cfg, 'ui.display', 'tabs')
    eq({ cfg.buff.on, cfg.heal.danger, cfg.heal.focus, cfg.japanese, cfg.ui.display }, { false, 60, 'A', true, 'tabs' })
    local view = build(whm, cfg)
    eq({ section(view, 'buff').on, view.heal.danger, view.display, view.japanese }, { false, 60, 'tabs', true })
    eq(view.heal.focus_names, { 'A', 'B' })
end)

test('healing skips a member by name, and takes them back', function ()
    local cfg = settings.defaults()
    model.toggle_skip(cfg, 'A')
    eq(cfg.heal.skip, { A = true })
    eq(build(whm, cfg).heal.members, { { name = 'A', healed = false }, { name = 'B', healed = true } })
    model.toggle_skip(cfg, 'A')
    eq(cfg.heal.skip, {})
end)

test('status line: what it would do or why not when stopped, the last send when running', function ()
    local e = { at = 990, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    eq(build(whm, nil, nil, status({ intent = e })).status.text, 'would: Cure IV -> A (heal: A at 62%)')
    eq(build(whm, nil, nil, status({ why = 'safe' })).status.text, 'safe zone')
    local view = build(whm, nil, nil, status({ running = true, why = 'casting', sent = { e } }))
    eq({ view.status.state, view.status.text, view.status.dim }, { 'Running', 'Cure IV -> A (heal: A at 62%)', 'casting' })
    eq(view.recent, { { age = 10, text = 'Cure IV -> A', why = 'heal: A at 62%' } })
    e.target = nil
    eq(model.action_text(e), 'Cure IV')
end)

test('party lines: HP against the danger and critical lines, distance, statuses by name', function ()
    local cfg = settings.defaults()
    cfg.heal.focus = 'tank'
    local g = fake.snap({
        { name = 'A', hpp = 55, buffs = { [40] = true, [33] = true } },
        { name = 'Tank', hpp = 55, kind = 'trust' },  -- under the focus danger line (60), over the others' (50)
        { name = 'C', hpp = 20 },
        { name = 'Gone', in_zone = false },
    }, { safe = true, moving = true, bt = { name = 'Crab', hpp = 50, dist = 4.31 } })
    local view = build(whm, cfg, g)
    eq(keys(view.party, 'hp'), { 'ok', 'ok', 'low', 'critical', 'ok' })
    eq(keys(view.party, 'tag'), { 'ME', 'P1', 'P2', 'P3', 'P4' })
    eq(keys(view.party, 'dist'), { '', '5.0y', '5.0y', '5.0y', 'away' })
    eq({ view.party[2].buffs, view.party[3].kind, view.party[5].away }, { 'Haste, Protect', 'trust', true })
    eq(view.bt, { name = 'Crab', hpp = 50, dist = '4.3y' })
    eq(view.flags, { 'moving', 'safe zone' })
    g.units[3].hpp = 35  -- the focus member is critical on their own line (40)
    eq(build(whm, cfg, g).party[3].hp, 'critical')
end)

test('a long status list is cut short, the whole list kept for the tooltip', function ()
    local buffs = {}
    for id = 40, 47 do buffs[id] = true end
    local p = build(whm, nil, fake.snap({ { name = 'A', buffs = buffs } })).party[2]
    eq(select(2, p.buffs:gsub(', ', '')), 5)
    eq(p.buffs:match('%+%d+$'), '+2')
    eq(select(2, p.buffs_all:gsub('\n', '')), 7)
end)
