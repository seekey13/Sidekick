-- ui/model.lua over the real catalog: what the window shows, and the mutators.
local model = require('ui.model')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, BLM, RDM, PLD, BRD = 3, 4, 5, 7, 10
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

-- ME P1-P5, then B0-B5 and C0-C5, then any extra labels (tracked).
local function slot_labels(extra)
    local out = { 'ME', 'P1', 'P2', 'P3', 'P4', 'P5' }
    for i = 0, 5 do out[#out + 1] = 'B' .. i end
    for i = 0, 5 do out[#out + 1] = 'C' .. i end
    for _, s in ipairs(extra or {}) do out[#out + 1] = s end
    return out
end

local function flags(n, at)
    local out = {}
    for i = 1, n do out[i] = i == at end
    return out
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

test('WHM 75 / BLM 37: every section, in order, each under its header, then UI / Log', function ()
    local view = build(whm)
    eq(view.job, 'WHM 75 / BLM 37')
    eq(keys(view.sections, 'id'), { 'profile', 'follow', 'heal', 'revive', 'wake', 'remove', 'buff', 'recover', 'rest', 'track', 'afk', 'ui' })
    eq(keys(view.sections, 'title'), { 'Profiles', 'Follow', 'Healing', 'Revive', 'Wake sleepers', 'Debuff removal', 'Buffs',
        'Recovery', 'Resting', 'Tracked players', 'AFK sleep', 'UI / Log' })
    eq(keys(view.sections, 'header'), { 'Profiles', 'Follow', 'Heal', 'Heal', 'Remove', 'Remove', 'Buff', 'Recover', 'Recover',
        'Tracked', 'AFK', 'UI / Log' })
    local on = {}
    for i = 2, #view.sections do
        if view.sections[i].id ~= 'afk' then on[#on + 1] = view.sections[i].on end
    end
    eq(on, { false, true, true, true, true, true, true, false })  -- Profiles, Tracked, UI / Log: no switch
    eq(section(view, 'afk').on, true)
    eq({ section(view, 'profile').on, section(view, 'track').on, section(view, 'ui').on }, { nil, nil, nil })
    local cfg = settings.defaults()
    cfg.ui.on = true  -- a custom UI's own key
    eq(section(build(whm, cfg), 'ui').on, nil)
    eq(keys(section(view, 'recover').rows), { 'Aspir' })  -- from BLM
    eq(keys(section(view, 'heal').rows), { 'Cure', 'Curaga', 'Regen', 'Drain', 'Divine Seal', 'Martyr' })  -- heal, then emergency
    eq(keys(section(view, 'revive').rows), { 'Raise', 'Arise' })
end)

test('recovery says whether a row spends TP, so Chivalry\'s line is shown only then', function ()
    eq(build(whm).recover, { mp = 30, tp = 1000, min_tp = 3000, spends_tp = false })
    eq(build(fake.catalog(PLD, 75, nil, 0, { 'Chivalry' })).recover.spends_tp, true)
end)

test('a section with nothing to show is left out: BLM 75 has no raise, no heal that wakes, only items under Debuffs', function ()
    local blm = fake.catalog(BLM, 75, 0, 0)
    for _, a in ipairs(blm) do
        if a.role == 'heal' then eq(a.wakes, nil, a.name) end
    end
    local view = build(blm)
    eq(keys(view.sections, 'id'), { 'profile', 'follow', 'heal', 'remove', 'buff', 'recover', 'rest', 'track', 'afk', 'ui' })
    local rows, items = section(view, 'remove').rows, {}
    for _, r in ipairs(rows) do if r.count then items[#items + 1] = r.key end end
    eq(items, { 'Antidote', 'Eye Drops', 'Echo Drops', 'Holy Water', 'Tincture',
        'Hallowed Water', 'Remedy Ointment', 'Remedy', 'Panacea' })
    eq({ rows[1].key, rows[1].label, rows[1].on, rows[1].ready, rows[1].avail, rows[1].action },
        { 'poison', 'Poison', true, false, 'nothing on removes it', 'Antidote, Remedy Ointment, Remedy' })  -- items are opt-in
    eq(rows[1].usable, false)
end)

test('Debuff removal lists the debuffs your removers clear, worst first, each switched by name', function ()
    local view = build(whm, nil, fake.snap({ { name = 'A' } }))
    local rows, removers, debuffs = section(view, 'remove').rows, {}, {}
    for _, r in ipairs(rows) do
        if r.remover then removers[#removers + 1] = r.key elseif r.debuff then debuffs[#debuffs + 1] = r.key end
    end
    eq(removers, { 'Poisona', 'Paralyna', 'Blindna', 'Silena', 'Stona', 'Viruna', 'Cursna', 'Esuna', 'Erase' })
    eq({ debuffs[1], debuffs[2], debuffs[3] }, { 'poison', 'paralysis', 'blindness' })
    eq({ rows[#removers].remover, rows[#removers + 1].debuff }, { true, true })  -- removers, then debuffs, then items
    local para = row(view, 'remove', 'paralysis')
    eq({ para.label, para.on, para.debuff, para.usable, para.ready, para.count }, { 'Paralysis', true, true, true, true, nil })
    eq(para.action, 'Paralyna, Esuna, Remedy Ointment, Remedy, Panacea')
    local cfg, writes = settings.defaults(), 0
    local act = model.actions(cfg, status(), function () writes = writes + 1 end)
    local g = fake.snap({ { name = 'A' } })
    act.debuff('paralysis', false)  -- everyone's
    eq({ cfg.remove.skip, row(build(whm, cfg, g), 'remove', 'paralysis').on }, { { paralysis = true }, false })
    act.debuff('silence', false, 'A')  -- A's own, made from everyone's
    view = build(whm, cfg, g)
    eq({ cfg.remove.own.A, row(view, 'remove', 'silence').on, row(view, 'remove', 'silence').own.A,
         row(view, 'remove', 'paralysis').own.A },
       { { set = true, skip = { paralysis = true, silence = true } }, true, false, false })
    act.debuff('paralysis', nil, 'A')  -- toggled, for A alone
    eq({ cfg.remove.own.A.skip, cfg.remove.skip, writes }, { { silence = true }, { paralysis = true }, 3 })
    act.debuff('paralysis', true, '')  -- no one
    eq(writes, 3)
end)

test('debuff labels capitalise each word; a remover that heals too says so', function ()
    eq(row(build(whm, nil, fake.snap({ { name = 'A' } })), 'remove', 'critical hit evasion down').label, 'Critical Hit Evasion Down')
    local mnk = fake.catalog(2, 75, nil, 0, { 'Chakra' })
    local view = build(mnk, nil, fake.snap({ { name = 'A' } }))
    eq({ row(view, 'remove', 'Chakra').remover, row(view, 'remove', 'Chakra').shared }, { true, true })
    eq(row(build(whm, nil, fake.snap({ { name = 'A' } })), 'remove', 'Erase').shared, nil)
end)

test('Doom is switched as any debuff, for everyone or a player', function ()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A' } })
    local doom = row(build(whm, cfg, g), 'remove', 'doom')
    eq({ doom.on, doom.locked, doom.usable }, { true, nil, true })
    local act = model.actions(cfg, status(), function () end)
    act.debuff('doom', false)
    act.debuffs({ 'doom', 'poison' }, false, 'A')
    doom = row(build(whm, cfg, g), 'remove', 'doom')
    eq({ cfg.remove.skip, cfg.remove.own.A.skip, doom.on, doom.own.A },
       { { doom = true }, { doom = true, poison = true }, false, false })
end)

test('removal runs on every present player until they are off, by name, and a player\'s debuffs replace everyone\'s', function ()
    local who = section(build(whm), 'remove').who
    eq(#who, 18)
    eq({ who[1].label, who[1].on, who[1].group, who[2].name, who[2].on, who[7].label, who[7].present, who[7].on },
       { 'ME', true, 'party', 'A', true, 'B0', false, false })
    local cfg = settings.defaults()
    cfg.remove.off = { A = true }
    cfg.remove.skip = { poison = true }
    cfg.remove.own = { B = { set = true, skip = {} } }
    local view = build(whm, cfg)
    who = section(view, 'remove').who
    eq({ who[1].on, who[2].name, who[2].on, who[3].name, who[3].on, who[7].on }, { true, 'A', false, 'B', true, false })
    local poison = row(view, 'remove', 'poison')
    eq({ poison.on, poison.own.B, row(view, 'remove', 'paralysis').own.B, poison.own.A }, { false, true, true, nil })
    -- Whoever takes A's slot is on: it was A who was switched off.
    who = section(build(whm, cfg, fake.snap({ { name = 'C' } })), 'remove').who
    eq({ who[2].name, who[2].on }, { 'C', true })
end)

test('a debuff nothing ticked removes is not usable: unticking Erase greys out what only it clears', function ()
    local cfg = settings.defaults()
    local g = fake.snap({ { name = 'A' } })
    eq({ row(build(whm, cfg, g), 'remove', 'Dia').usable, row(build(whm, cfg, g), 'remove', 'slow').usable }, { true, true })
    cfg.rows.Erase = { on = false }
    local view = build(whm, cfg, g)
    local dia, slow = row(view, 'remove', 'Dia'), row(view, 'remove', 'slow')
    eq({ dia.usable, dia.ready, dia.avail, dia.on }, { false, false, 'nothing on removes it', true })
    eq({ slow.usable, row(view, 'remove', 'Erase').on }, { true, false })  -- Esuna still does
    cfg.rows.Panacea = { on = true }
    eq(row(build(whm, cfg, g), 'remove', 'Dia').usable, true)  -- an item ticked counts
end)

test('item rows are opt-in and say how many you carry; none left when you have none', function ()
    local view = build(whm, nil, fake.snap({ { name = 'A' } }, { items = { [4151] = 12 } }))
    local echo, antidote = row(view, 'remove', 'Echo Drops'), row(view, 'remove', 'Antidote')
    eq({ echo.on, echo.count, echo.ready, echo.action }, { false, 12, true, 'Echo Drops' })
    eq({ antidote.count, antidote.ready, antidote.avail }, { 0, false, 'none left' })
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
    eq(keys(r.targets, 'label'), slot_labels())
    eq(keys(r.targets, 'on'), flags(18, 1))
    local present = { true, true, true }
    for i = 4, 18 do present[i] = false end
    eq(keys(r.targets, 'present'), present)
    eq(r.targets[2].name, 'A')
end)

test('self-only buffs have no targets', function ()
    eq(row(build(whm), 'buff', 'Protectra').targets, nil)
end)

test('a pick-one group needs a pick: no Auto, and it says so', function ()
    local r = row(build(whm), 'buff', 'barelement')
    eq({ r.label, r.choice, r.choices[1].label, r.ready, r.avail }, { 'Barelement', 'Pick one', 'Barfira', false, 'pick one' })
end)

test('BRD 75 / WHM 37: Songs under Buff, Area then each party slot; no song is a buff row', function ()
    local cat = fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo', 'Nightingale' })
    local cfg = settings.defaults()
    cfg.song.area_1, cfg.song.p1_2 = 'Valor Minuet IV', 'Mage\'s Ballad II'
    local g = fake.snap({ { name = 'A' }, { name = 'B' } }, { main = BRD, sub = WHM })
    local view = build(cat, cfg, g)
    eq({ section(view, 'song').header, section(view, 'song').on, keys(view.sections, 'id')[8] }, { 'Buff', true, 'song' })
    local s = view.song
    eq({ s.slots, s.pianissimo, s.ready, s.avail, s.timed, s.duration, s.fast }, { 2, true, true, 'ready', true, 0, false })
    eq(s.choices[1], { name = 'Army\'s Paeon', label = 'Army\'s Paeon (+Regen)' })
    eq(keys(s.sets), { 'area', 'me', 'p1', 'p2', 'p3', 'p4', 'p5' })
    eq({ s.sets[1].picks, s.sets[1].name, s.sets[3].picks, s.sets[3].name, s.sets[3].present, s.sets[5].present },
       { { 'Valor Minuet IV', '' }, nil, { '', 'Mage\'s Ballad II' }, 'A', true, false })
    -- by priority (Nightingale 100, Sneak -10, Deodorize -15, Invisible -20), then by name as shown ('Barelement')
    eq(keys(section(view, 'buff').rows), { 'Nightingale', 'Aquaveil', 'barelement', 'barstatus', 'Blink',
        'Protect', 'Protectra', 'Regen (keep up)', 'Reraise', 'Shell', 'Shellra', 'Stoneskin', 'Sneak', 'Deodorize',
        'Invisible' },
        'no song rows')
    g.main, g.sub = WHM, BRD
    eq({ build(fake.catalog(WHM, 75, BRD, 15), cfg, g).song.pianissimo, build(fake.catalog(WHM, 75, BRD, 15), cfg, g).song.timed },
       { false, false })  -- under BRD 20; Song Duration on a BRD main job alone
    eq(section(build(whm), 'song'), nil)
end)

test('the Buffs list reads in casting order: by priority, then by name, not the catalog\'s order', function ()
    local cfg = settings.defaults()
    local on = { 'Stoneskin', 'Reraise', 'Haste', 'Aquaveil', 'Shell', 'Blink', 'Protect' }
    for _, key in ipairs(on) do cfg.rows[key] = { on = true, targets = { [0] = true } } end
    local g = fake.snap({})
    local listed, cast = {}, {}
    for _, r in ipairs(section(build(whm, cfg, g), 'buff').rows) do
        if r.on then listed[#listed + 1] = r.key end
    end
    for _ = 1, #on + 1 do
        local cmd, intent = fake.decide(g, whm, cfg)
        if not cmd then break end
        cast[#cast + 1] = settings.key(intent.action)
        for _, id in ipairs(intent.action.status or {}) do g.me.buffs[id] = true end
    end
    eq(listed, { 'Haste', 'Aquaveil', 'Blink', 'Protect', 'Reraise', 'Shell', 'Stoneskin' }, 'Haste at 25, the rest at 0')
    eq(cast, listed)
end)

test('a Buffs row with a pick goes by its pick\'s priority: Addendum: White\'s 90, Black\'s 0', function ()
    local sch = fake.catalog(20, 75, RDM, 37, { 'Light Arts', 'Dark Arts', 'Sublimation' })
    local cfg = settings.defaults()
    local p = settings.buff_order(sch, cfg)
    eq(p.addendum, p.arts + 1, 'no pick: its highest, next after the Arts at 100')
    cfg.rows.addendum = { on = true, pick = 'Addendum: White' }
    eq(settings.buff_order(sch, cfg).addendum, p.arts + 1)
    cfg.rows.addendum.pick = 'Addendum: Black'
    p = settings.buff_order(sch, cfg)
    eq(p.addendum > p.Sublimation, true, 'below Sublimation at 50')
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

-- The actions on `cfg`, and how many settings writes they reported.
local function actions(cfg, st)
    local n = { 0 }
    return model.actions(cfg, st or status(), function () n[1] = n[1] + 1 end), n
end

test('row actions create a row on first touch, from its default, and report each write', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    act.pick('Protect', 'Protect III')
    eq(cfg.rows.Protect, { on = false, pick = 'Protect III' })
    act.pick('Protect', nil)
    eq(cfg.rows.Protect, { on = false })
    act.target('Haste', 2)
    eq(cfg.rows.Haste, { on = false, targets = { [0] = true, [2] = true } })
    act.target('Haste', 0)
    eq(cfg.rows.Haste.targets, { [2] = true })
    act.row('Haste', true)
    act.row('Cure', false)
    eq({ cfg.rows.Haste.on, cfg.rows.Cure }, { true, { on = false } })
    eq(writes[1], 6)
    local view = build(whm, cfg)
    eq({ row(view, 'heal', 'Cure').on, row(view, 'buff', 'Haste').on }, { false, true })
    eq(keys(row(view, 'buff', 'Haste').targets, 'on'), flags(18, 3))
end)

test('section switches and plain values, a UI\'s own under ui', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    act.section('buff', false)
    act.section('follow', true)
    act.section('rest', true)
    act.set('heal.danger', 60)
    act.set('heal.focus', 'A')
    act.set('japanese', true)
    act.set('ui.hp_width', 300)
    act.set('ui.compact', true)
    eq({ cfg.buff.on, cfg.follow.on, cfg.rest.on, cfg.heal.danger, cfg.heal.focus, cfg.ui.japanese, cfg.ui.hp_width },
       { false, true, true, 60, 'A', true, 300 })
    eq(writes[1], 8)
    local view = build(whm, cfg)
    eq({ section(view, 'buff').on, section(view, 'follow').on, section(view, 'rest').on, view.heal.danger,
         view.ui.hp_width, view.ui.compact, view.japanese }, { false, true, true, 60, 300, true, true })
    eq(view.heal.focus_names, { 'A', 'B' })
    view.ui.mp_width = 100  -- the view is a copy
    eq(cfg.ui.mp_width, 220)
end)

test('run, log and Sidekick Settings change the session only; close also remembers it in the settings', function ()
    local cfg, st = settings.defaults(), status({ open = true })
    cfg.ui.open = true
    local act, writes = actions(cfg, st)
    eq(build(whm, cfg, nil, st).ui.settings, false)  -- closed at load
    act.run(true)
    act.log(false)  -- a custom UI's switch; the standard one has none
    act.settings(true)  -- as the cog
    local view = build(whm, cfg, nil, st)
    eq({ st.running, st.log, writes[1], view.log, view.ui.settings }, { true, false, 0, false, true })
    act.close()
    eq({ st.open, cfg.ui.open, writes[1], build(whm, cfg, nil, st).ui.settings }, { false, false, 1, true })  -- apart
    act.settings(false)
    eq({ st.settings, writes[1] }, { false, 1 })
    act.hud(true)  -- as /sk hud, or Show the HUD
    eq({ st.open, cfg.ui.open, writes[1], build(whm, cfg, nil, st).ui.open }, { true, true, 2, true })
    act.hud(false)
    eq({ st.open, cfg.ui.open, writes[1] }, { false, false, 3 })
end)

test('healing skips a member by name, and takes them back', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    act.skip('A')
    eq(cfg.heal.skip, { A = true })
    local targets = build(whm, cfg).heal.targets
    eq(#targets, 18)
    eq({ targets[1].label, targets[1].on, targets[2].name, targets[2].on, targets[3].name, targets[3].on, targets[7].group },
       { 'ME', true, 'A', false, 'B', true, 'a' })
    act.skip('A')
    eq({ cfg.heal.skip, writes[1] }, { {}, 2 })
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

test('status line, stopped with Follow on: following comes first, as it goes on; once, when it is the would-do', function ()
    local cfg = settings.defaults()
    cfg.follow.on, cfg.follow.target = true, 'B'
    local e = { at = 990, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    eq(build(whm, cfg, nil, status({ intent = e })).status.text, 'following B; would: Cure IV -> A (heal: A at 62%)')
    eq(build(whm, cfg, nil, status({ why = 'nothing to do' })).status.text, 'following B; nothing to do')
    local f = { at = 990, action = 'Follow', target = 'B', behavior = 'follow', why = 'B 9.0y away' }
    eq(build(whm, cfg, nil, status({ intent = f })).status.text, 'would: Follow -> B (follow: B 9.0y away)')
    eq(build(whm, cfg, nil, status({ running = true, sent = { e } })).status.text, 'Cure IV -> A (heal: A at 62%)')
    cfg.follow.target = ''
    eq(build(whm, cfg, nil, status({ why = 'nothing to do' })).status.text, 'nothing to do')  -- no leader: no follow
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

test('party MP is low under the Recover MP line, only for those who use MP', function ()
    local g = fake.snap({ { name = 'A', mpp = 20 }, { name = 'W', mpp = 0, uses_mp = false }, { name = 'C', mpp = 30 } })
    local view = build(whm, nil, g)
    eq(keys(view.party, 'mp'), { 'ok', 'low', 'ok', 'ok' })
    eq(keys(view.party, 'uses_mp'), { true, true, false, true })
end)

test('each party line has its TP; your pet its HP %, MP % and TP, and whether it has MP', function ()
    local g = fake.snap({ { name = 'A', tp = 1500 } },
        { pet = { name = 'Ifrit', hpp = 80, mpp = 60, tp = 2100, dist = 2, uses_mp = true } })
    local view = build(whm, nil, g)
    eq(keys(view.party, 'tp'), { 0, 1500 })
    eq(view.pet, { name = 'Ifrit', hpp = 80, mpp = 60, tp = 2100, dist = '2.0y', pools = true, uses_mp = true })
    g.pet = { name = 'Wyvern', hpp = 80, mpp = 0, tp = 2100, dist = 2, uses_mp = false }
    eq(build(whm, nil, g).pet.uses_mp, false)
    eq(build(whm).pet, nil)
end)

test('the pointer, stopped: what it would do, at the card of the member it is for', function ()
    local e = { at = 990, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    eq(build(whm, nil, nil, status({ intent = e })).pointer, { text = 'Heal:Cure IV', member = 2, live = false })
    eq(build(whm).pointer, nil)  -- nothing to do
end)

test('the pointer, running: the decision, else the last send for a moment, or while it is cast', function ()
    local e = { at = 990, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    local LIVE = { text = 'Heal:Cure IV', member = 2, live = true }
    eq(build(whm, nil, nil, status({ running = true, intent = e })).pointer, LIVE)
    e.at = 999  -- sent 1s ago
    eq(build(whm, nil, nil, status({ running = true, sent = { e } })).pointer, LIVE)
    e.at = 997  -- 3s ago
    eq(build(whm, nil, nil, status({ running = true, sent = { e } })).pointer, nil)
    e.at, e.kind = 990, 'ma'  -- 10s ago, and its cast began as the server answered
    local function casting(at)
        return fake.snap({ { name = 'A' }, { name = 'B' } }, { casting = true, cast_at = at })
    end
    eq(build(whm, nil, casting(990.4), status({ running = true, sent = { e } })).pointer, LIVE)
    eq(build(whm, nil, casting(995), status({ running = true, sent = { e } })).pointer, nil)  -- a cast of your own, later
    e.kind = 'ja'  -- an ability casts nothing: the cast is yours
    eq(build(whm, nil, casting(990.4), status({ running = true, sent = { e } })).pointer, nil)
end)

test('the pointer: an action on no one (pet care, sending it in) is on yours; a target with no card is named', function ()
    local e = { at = 990, action = 'Healing Ruby', behavior = 'pet', why = 'Carbuncle 40%' }
    eq(build(whm, nil, nil, status({ intent = e })).pointer, { text = 'Pet:Healing Ruby', member = 1, live = false })
    e = { at = 990, action = 'Deploy', behavior = 'pet_send', why = 'Automaton at Crab' }
    eq(build(whm, nil, nil, status({ intent = e })).pointer, { text = 'Pet:Deploy', member = 1, live = false })
    e = { at = 990, action = 'Cure IV', target = 'Zed', behavior = 'heal', why = 'Zed at 40%' }  -- not in the party
    eq(build(whm, nil, nil, status({ intent = e })).pointer, { text = 'Heal:Cure IV -> Zed', member = 1, live = false })
end)

test('the pointer: with a pet out, its care and sending it in are for its card; anything else is not', function ()
    local g = fake.snap({ { name = 'A' } }, { pet = { name = 'Carbuncle', hpp = 40, dist = 2 } })
    for _, b in ipairs({ 'pet', 'pet_send' }) do
        local e = { at = 990, action = 'Healing Ruby', behavior = b, why = 'Carbuncle 40%' }
        eq(build(whm, nil, g, status({ intent = e })).pointer, { text = 'Pet:Healing Ruby', member = 1, live = false, pet = true })
    end
    local e = { at = 990, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    eq(build(whm, nil, g, status({ intent = e })).pointer, { text = 'Heal:Cure IV', member = 2, live = false })
end)

test('a long status list is cut short, the whole list kept for the tooltip', function ()
    local buffs = {}
    for id = 40, 47 do buffs[id] = true end
    local p = build(whm, nil, fake.snap({ { name = 'A', buffs = buffs } })).party[2]
    eq(select(2, p.buffs:gsub(', ', '')), 5)
    eq(p.buffs:match('%+%d+$'), '+2')
    eq(select(2, p.buffs_all:gsub('\n', '')), 7)
end)

-- Tracked players ----------------------------------------------------------------------

local function tracked_snap(over)
    return fake.snap({ { name = 'A' },
        { kind = 'tracked', name = 'Out', main = WHM, main_lv = 75, sub = BLM, sub_lv = 37 },
        { kind = 'tracked', name = 'Far', in_zone = false } }, over)
end

test('tracked players: tagged T1 on, their jobs once a /check answers, and among the names to pick', function ()
    local view = build(whm, nil, tracked_snap())
    eq(keys(view.party, 'tag'), { 'ME', 'P1', 'T1', 'T2' })
    local out, far = view.party[3], view.party[4]
    eq({ out.kind, out.job, out.away, out.uses_mp, far.job, far.away }, { 'tracked', 'WHM 75 / BLM 37', false, false, nil, true })
    eq(view.heal.focus_names, { 'A', 'Out', 'Far' })
    eq(view.follow.names, { 'A', 'Out', 'Far' })
    eq(keys(view.party, 'tracked'), { false, false, true, true })
    eq(build(whm, nil, fake.snap({ { name = 'A', tracked = true } })).party[2].tracked, true)  -- joined your party
end)

test('buff rows reaching outside the party get a chip per tracked player, its slot their name', function ()
    local view = build(whm, nil, tracked_snap())
    local haste = row(view, 'buff', 'Haste')
    eq(keys(haste.targets, 'label'), slot_labels({ 'T1', 'T2' }))
    eq(haste.targets[7], { slot = 6, label = 'B0', group = 'a', present = false, on = false, wrap = true })
    eq(haste.targets[19], { slot = 'Out', label = 'T1', group = 'tracked', present = true, name = 'Out', on = false, wrap = true })
    eq(#row(view, 'buff', 'Regen (keep up)').targets, 6)  -- party only
    local cfg = settings.defaults()
    model.actions(cfg, status(), function () end).target('Haste', 'Out')
    eq(cfg.rows.Haste.targets, { [0] = true, Out = true })
    eq(row(build(whm, cfg, tracked_snap()), 'buff', 'Haste').targets[19].on, true)
end)

test('Track is offered for your target only when it is a player not in the party or tracked', function ()
    local stranger = { sid = 900, tidx = 1200, name = 'Stranger' }
    eq(build(whm, nil, tracked_snap({ target = stranger })).track, { target = 'Stranger' })
    eq(build(whm, nil, tracked_snap({ target = { sid = 101, tidx = 1100, name = 'A' } })).track, {})
    eq(build(whm, nil, tracked_snap({ target = { sid = 202, tidx = 1101, name = 'Out' } })).track, {})
    eq(build(whm, nil, tracked_snap()).track, {})
end)

test('track and untrack go to the tracking functions Sidekick gives, writing no setting', function ()
    local calls, writes = {}, 0
    local act = model.actions(settings.defaults(), status(), function () writes = writes + 1 end, {
        add = function (name) calls[#calls + 1] = { 'add', name } end,
        remove = function (name) calls[#calls + 1] = { 'remove', name } end,
    })
    act.track('Stranger')
    act.track()
    act.untrack('Out')
    eq({ calls, writes }, { { { 'add', 'Stranger' }, { 'add' }, { 'remove', 'Out' } }, 0 })
end)

-- The alliance -----------------------------------------------------------------------

local function alliance_snap()
    return fake.snap({ { name = 'A' }, { kind = 'alliance', name = 'Bea' }, { kind = 'alliance', name = 'Bo', slot = 8 } })
end

test('the alliance\'s other parties are listed apart, B0-B5 and C0-C5, to focus and follow; the pointer finds them', function ()
    local view = build(whm, nil, alliance_snap())
    eq({ keys(view.party, 'tag'), keys(view.alliance, 'tag'), keys(view.alliance, 'kind') },
       { { 'ME', 'P1' }, { 'B0', 'B2' }, { 'alliance', 'alliance' } })
    eq({ view.heal.focus_names, view.follow.names }, { { 'A', 'Bea', 'Bo' }, { 'A', 'Bea', 'Bo' } })
    local function on_at(targets, slot)
        for _, c in ipairs(targets) do if c.slot == slot then return c.on end end
    end
    eq({ on_at(view.heal.targets, 0), on_at(view.heal.targets, 1), on_at(view.heal.targets, 6), on_at(view.heal.targets, 8),
         #view.heal.targets }, { true, true, true, true, 18 })
    local cfg = settings.defaults()
    cfg.heal.skip = { Bo = true }
    local g = alliance_snap()
    g.units[#g.units + 1] = fake.unit({ kind = 'alliance', name = 'Cy', slot = 12, sid = 303 })
    local targets = build(whm, cfg, g).heal.targets
    local cy
    for _, c in ipairs(targets) do if c.slot == 12 then cy = c end end
    eq({ on_at(targets, 1), on_at(targets, 6), on_at(targets, 8), cy.label, cy.group, cy.wrap, cy.name, cy.on },
       { true, true, false, 'C0', 'b', true, 'Cy', true })
    -- A member with no name yet has none on the chip, so a click can't skip '' (everyone nameless).
    g.units[#g.units + 1] = fake.unit({ kind = 'alliance', name = '', slot = 13, sid = 304 })
    local nameless
    for _, c in ipairs(build(whm, cfg, g).heal.targets) do if c.slot == 13 then nameless = c end end
    eq({ nameless.present, nameless.name, nameless.on }, { true, nil, true })
    eq(model.TAGS[17], 'C5')
    local e = { at = 990, action = 'Cure IV', target = 'Bea', behavior = 'heal', why = 'danger: Bea 45%' }
    eq(build(whm, nil, alliance_snap(), status({ intent = e })).pointer, { text = 'Heal:Cure IV', ally = 1, live = false })
end)

test('buff rows reaching outside the party get a line of chips per party of the alliance there', function ()
    local view = build(whm, nil, alliance_snap())
    local haste = row(view, 'buff', 'Haste')
    eq(keys(haste.targets, 'label'), slot_labels())
    eq(haste.targets[7], { slot = 6, label = 'B0', group = 'a', present = true, name = 'Bea', on = false, wrap = true })
    eq({ haste.targets[8].present, haste.targets[8].wrap, haste.targets[9].name, haste.targets[13].label },
       { false, nil, 'Bo', 'C0' })
    eq(#row(view, 'buff', 'Regen (keep up)').targets, 6)  -- party only
    local cfg = settings.defaults()
    local act = model.actions(cfg, status(), function () end)
    act.target('Haste', 6)
    act.target('Haste', 14)
    eq(cfg.rows.Haste.targets, { [0] = true, [6] = true, [14] = true })
    haste = row(build(whm, cfg, alliance_snap()), 'buff', 'Haste')
    eq({ haste.targets[7].on, haste.targets[13].label, haste.targets[15].on, haste.targets[15].present, haste.targets[15].group },
       { true, 'C0', true, false, 'b' })  -- an empty C slot stays listed, and a chip on it can be cleared
end)

-- Remote control -------------------------------------------------------------------

local function sessions(running)
    return { A = { running = running, members = { { sid = 101, name = 'A' } } },
             Far = { running = false, members = { { sid = 900, name = 'Far' } } } }  -- not in your party
end

test('a member who is another session says so, running or not and whether its Sidekick Settings are shown here', function ()
    local st = status({ sessions = sessions(true), watching = { A = true } })
    local view = build(whm, nil, nil, st)
    eq({ view.party[1].session, view.party[2].session, view.party[3].session },
       { nil, { name = 'A', running = true, open = true }, nil })
    eq(view.remote, { { name = 'A' } })  -- watched, no view from it yet
    st.views = { A = { job = 'RDM 75', version = model.VIEW } }
    view = build(whm, nil, nil, st)
    eq(view.remote, { { name = 'A', view = { job = 'RDM 75', version = model.VIEW, session = 'A' } } })
    st.views = { A = { job = 'RDM 75' } }  -- from a session running another version: not drawn
    eq(build(whm, nil, nil, st).remote, { { name = 'A', other = true } })
    st.watching = { Gone = true }  -- not a live session: no window for it
    eq(build(whm, nil, nil, st).remote, {})
end)

test('another session\'s action as it goes: a label at its target\'s line, else at its own player\'s, by session', function ()
    local st = status({ sessions = sessions(true) })
    eq(build(whm, nil, nil, st).others, {})  -- nothing going
    st.sessions.A.act = { behavior = 'heal', action = 'Cure IV', target = 'B' }
    eq(build(whm, nil, nil, st).others, { { session = 'A', text = 'Heal:Cure IV', member = 3 } })
    st.sessions.A.act = { behavior = 'song', action = 'Valor Minuet IV' }  -- on itself
    eq(build(whm, nil, nil, st).others, { { session = 'A', text = 'Song:Valor Minuet IV', member = 2 } })
    st.sessions.A.act = { behavior = 'pet_send', action = 'Deploy' }  -- its pet's: its own card, not yours
    eq(build(whm, nil, fake.snap({ { name = 'A' } }, { pet = { name = 'Carbuncle', hpp = 40 } }), st).others,
       { { session = 'A', text = 'Pet:Deploy', member = 2 } })
    st.sessions.A.act = { behavior = 'heal', action = 'Cure IV', target = 'Zed' }  -- no line here: named, at its own
    eq(build(whm, nil, nil, st).others, { { session = 'A', text = 'Heal:Cure IV -> Zed', member = 2 } })
    st.sessions.Far.act = { behavior = 'heal', action = 'Cure IV', target = 'Me' }  -- no line of its own, but you have one
    eq(build(whm, nil, nil, st).others, { { session = 'A', text = 'Heal:Cure IV -> Zed', member = 2 },
                                          { session = 'Far', text = 'Heal:Cure IV', member = 1 } })
    st.sessions.Far.act = { behavior = 'buff', action = 'Haste', target = 'Zed' }  -- neither has one: no label
    eq(#build(whm, nil, nil, st).others, 1)
end)

test('another session\'s action on the alliance, or from it, is at the alliance\'s row', function ()
    local st = status({ sessions = { Bea = { running = true, members = { { sid = 301, name = 'Bea' } },
                                             act = { behavior = 'heal', action = 'Cure IV', target = 'Bo' } } } })
    eq(build(whm, nil, alliance_snap(), st).others, { { session = 'Bea', text = 'Heal:Cure IV', ally = 2 } })
    st.sessions.Bea.act = { behavior = 'buff', action = 'Protect IV', target = 'A' }
    eq(build(whm, nil, alliance_snap(), st).others, { { session = 'Bea', text = 'Buff:Protect IV', member = 2 } })
    st.sessions.Bea.act = { behavior = 'buff', action = 'Protectra V' }
    eq(build(whm, nil, alliance_snap(), st).others, { { session = 'Bea', text = 'Buff:Protectra V', ally = 1 } })
end)

test('another session\'s pet is on its line: the HP % drawn, its MP % and TP from its file while it names that pet', function ()
    local st = status({ sessions = sessions(true) })
    local carbuncle = { sid = 0x1000701, tidx = 0x701, name = 'Carbuncle', hpp = 70, dist = 6 }
    local g = fake.snap({ { name = 'A', pet = carbuncle }, { name = 'B', pet = carbuncle } })  -- B is no session
    eq(build(whm, nil, g, st).party[2].pet,
       { name = 'Carbuncle', hpp = 70, dist = '6.0y', mpp = 0, tp = 0, pools = false, uses_mp = false })
    st.sessions.A.pet = { sid = 0x1000701, name = 'Carbuncle', mpp = 47, tp = 1750, uses_mp = true }
    local view = build(whm, nil, g, st)
    eq({ view.party[2].pet, view.party[3].pet, view.pet },
       { { name = 'Carbuncle', hpp = 70, dist = '6.0y', mpp = 47, tp = 1750, pools = true, uses_mp = true } })
    st.sessions.A.pet.sid = 0x1000700  -- its file still names the pet it swapped out: no one's numbers
    eq(build(whm, nil, g, st).party[2].pet.pools, false)
    st.sessions.A.pet.sid, st.sessions.A.pet.name = 0x1000701, 'Ifrit'  -- swapped out under the same id: nor here
    eq(build(whm, nil, g, st).party[2].pet.pools, false)
end)

test('another session\'s pet care, or sending it in, is at its pet\'s card while its line has one', function ()
    local st = status({ sessions = sessions(true) })
    st.sessions.A.act = { behavior = 'pet', action = 'Healing Ruby' }
    local g = fake.snap({ { name = 'A', pet = { sid = 0x1000701, name = 'Carbuncle', hpp = 40, dist = 3 } } })
    eq(build(whm, nil, g, st).others, { { session = 'A', text = 'Pet:Healing Ruby', member = 2, pet = true } })
    st.sessions.A.act = { behavior = 'pet', action = 'Healing Ruby', target = 'Me' }  -- on someone: not its pet's
    eq(build(whm, nil, g, st).others, { { session = 'A', text = 'Pet:Healing Ruby', member = 1 } })
    st.sessions.A.act = { behavior = 'heal', action = 'Cure IV' }  -- on itself: its own card
    eq(build(whm, nil, g, st).others, { { session = 'A', text = 'Heal:Cure IV', member = 2 } })
end)

test('landing: the last send for a moment, or while it is cast; nothing while stopped', function ()
    local e = { at = 999, action = 'Cure IV', target = 'A', behavior = 'heal', why = 'A at 62%' }
    local g = fake.snap({ { name = 'A' } })
    eq(model.landing(status({ running = true, sent = { e } }), g), e)
    eq(model.landing(status({ sent = { e } }), g), nil)
    eq(model.landing(status({ running = true }), g), nil)
    e.at = 997
    eq(model.landing(status({ running = true, sent = { e } }), g), nil)
end)

test('view.themes: a copy of Sidekick.lua\'s, or none; act.theme hands the key to it, no setting written', function ()
    local th = { current = 'window', list = { { key = 'window', name = 'Standard', standard = true },
                                              { key = 'classic', name = 'Classic', file = 'ui/classic.lua' } } }
    local st = status({ themes = th })
    local view = build(whm, nil, nil, st)
    eq(view.themes, th)
    view.themes.list[2].name = 'Changed'
    eq({ th.list[2].name, build(whm).themes }, { 'Classic', { list = {} } })
    local picked, writes = {}, 0
    local act = model.actions(settings.defaults(), st, function () writes = writes + 1 end, nil, nil,
        function (key) picked[#picked + 1] = key end)
    act.theme('classic')
    eq({ picked, writes }, { { 'classic' }, 0 })
    model.actions(settings.defaults(), st, function () end).theme('classic')  -- no hook: nothing
    eq(act.remote('A').theme, nil)  -- the PC's own: another session can't switch it
end)

test('a published view leaves out the HUD\'s labels and sizes and the views it shows itself', function ()
    local view = build(whm, nil, nil, status({ intent = { at = 990, action = 'Cure', target = 'A', behavior = 'heal', why = 'x' },
                                              themes = { current = 'window', list = {} } }))
    local out = model.published(view)
    eq({ out.pointer, out.others, out.ui, out.remote, out.themes, out.job, out.sections == view.sections, out.version },
       { nil, nil, nil, nil, nil, 'WHM 75 / BLM 37', true, model.VIEW })
    eq({ view.pointer ~= nil, view.others }, { true, {} })  -- the view itself is left as it was
end)

local function call(fn, ...) return { fn, n = select('#', ...), ... } end

test('act.remote sends each call to its session; act.watch shows its Sidekick Settings', function ()
    local sent, st = {}, status()
    local act = model.actions(settings.defaults(), st, function () end, nil, function (name, c) sent[#sent + 1] = { name, c } end)
    local r = act.remote('A')
    r.set('heal.danger', 60)
    r.pick('Protect', nil)
    r.run(true)
    eq(sent, { { 'A', call('set', 'heal.danger', 60) }, { 'A', call('pick', 'Protect', nil) }, { 'A', call('run', true) } })
    eq({ r.close, r.log, r.watch, r.remote }, { nil, nil, nil, nil })  -- the HUD's and the log are each session's own
    act.watch('A', true)
    eq(st.watching, { A = true })
    act.watch('A', false)
    eq(st.watching, {})
end)

test('another session\'s calls apply through act; the HUD\'s settings, the log and bad arguments never', function ()
    local cfg, st, writes = settings.defaults(), status(), 0
    local tracks = {}
    local act = model.actions(cfg, st, function () writes = writes + 1 end,
        { add = function (n) tracks[#tracks + 1] = n end, remove = function () end })
    local function apply(...) return model.apply(act, cfg, call(...), whm) end
    eq({ apply('run', true), st.running }, { true, true })
    eq({ apply('set', 'heal.danger', 60), cfg.heal.danger }, { true, 60 })
    eq({ apply('row', 'Protect', true), apply('pick', 'Protect', 'Protect II'), apply('target', 'Protect', 1, true) },
       { true, true, true })
    eq(cfg.rows.Protect, { on = true, pick = 'Protect II', targets = { [0] = true, [1] = true } })
    eq({ apply('pick', 'Protect', nil), cfg.rows.Protect.pick }, { true, nil })  -- back to Auto
    eq({ apply('section', 'buff', true), cfg.buff.on }, { true, true })
    eq({ apply('debuff', 'slow', false), cfg.remove.skip }, { true, { slow = true } })  -- everyone's
    eq({ apply('debuff', 'slow', true, 'A'), cfg.remove.own.A }, { true, { set = true, skip = {} } })
    eq({ apply('debuff', 'slow', true), cfg.remove.skip }, { true, {} })
    eq({ apply('who', 'A', false), cfg.remove.off }, { true, { A = true } })
    eq({ apply('who', 'A', true), cfg.remove.off }, { true, {} })
    eq({ apply('debuffs', { 'poison', 'paralysis' }, false, 'B'), cfg.remove.own.B.skip }, { true, { poison = true, paralysis = true } })
    eq({ apply('debuffs', { 'poison' }, true, 'B'), cfg.remove.own.B.skip }, { true, { paralysis = true } })
    eq({ apply('track', 'Out'), tracks }, { true, { 'Out' } })
    local before = writes
    for _, bad in ipairs({
        call('close'), call('log', false), call('watch', 'A', true), call('remote', 'B'), call('track', nil),  -- your target: never from afar
        call('set', 'ui.hp_width', 300), call('set', 'japanese', true), call('set', 'heal', 1), call('set', 'heal.nope', 1),
        call('set', 'heal.danger', 'high'), call('set', 'heal.skip', {}), call('set', 'danger', 1), call('section', 'ui', true),
        call('section', 'nope', true), call('section', 'heal', 'yes'), call('row', 5, true), call('target', 'Protect', true, true),
        call('target', 'Protect', 1), call('mod', 'Protect', 'Penury'), call('skip', 'A'),  -- a bare toggle: never from afar
        call('debuff', 'slow'), call('debuff', 0, 'slow', false), call('debuff', 'slow', false, ''), call('debuff', 'slow', false, 5),
        call('who', 'A'), call('who', 1, false), call('who', '', true),
        call('debuffs', { 'poison', 1 }, false), call('debuffs', { 'poison' }, false, ''), call('debuffs', 'poison', false),
        call('set', 'profiles.X.heal.danger', 50), call('set', 'parked.heal.danger', 50), call('set', 'roll.risk', 'wild'),
        call('set', 'follow.on', 1),
        { 'run', true }, { 42 },
        { 'set', 'heal.danger', 60, n = 1 }, { 'section', 'heal', true, n = 1 }, call('run', true, 'extra'),  -- n not its args
        call('pick', 'Protect', true), call('pick', 'Protect', {}), call('save_profile', 'X', 'yes'), call('profile', 5),
        call('set', 'heal.danger', 0 / 0), call('set', 'heal.danger', 1 / 0), call('target', 'Protect', 2.5),
        call('target', 'Protect', 18), { 'run', true, n = 1e8 },
        call('hold', 'Cure', true), call('target', 'Cure', 1, true), call('mod', 'Nope', 'Penury', true),  -- no such chip
    }) do
        eq(model.apply(act, cfg, bad, whm), false, tostring(bad[1]) .. ' ' .. tostring(bad[2]))
    end
    eq({ writes, cfg.ui.hp_width ~= 300, cfg.ui.japanese, st.log, cfg.heal.danger, cfg.heal.on, cfg.rows.Protect.pick },
       { before, true, false, true, 60, true, nil })
    eq(cfg.rows.Cure, nil, 'a default-on row is never made off from afar')
    eq({ apply('target', 'Protect', 'Out', true), apply('save_profile', 'X', true), apply('profile', nil) }, { true, true, true })
end)

test('a remote chip is set to the state sent, never toggled: a click twice is still on', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, status(), function () end)
    for _ = 1, 2 do
        eq({ model.apply(act, cfg, call('target', 'Haste', 2, true), whm), model.apply(act, cfg, call('mod', 'Haste', 'Penury', true), whm),
             model.apply(act, cfg, call('skip', 'A', true), whm) }, { true, true, true })
    end
    eq({ cfg.rows.Haste.targets, cfg.rows.Haste.mods, cfg.heal.skip }, { { [0] = true, [2] = true }, { Penury = true }, { A = true } })
    model.apply(act, cfg, call('target', 'Haste', 0, false), whm)
    eq(cfg.rows.Haste.targets, { [2] = true })
    act.skip('A')  -- yours, without a state, still toggles
    eq(cfg.heal.skip, {})
end)

test('a remote setting is one of the window\'s, held to its slider\'s range', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, status(), function () end)
    local function set(path, v) return model.apply(act, cfg, call('set', path, v), whm) end
    eq({ set('heal.danger', -5), cfg.heal.danger, set('recover.tp', 1e300), cfg.recover.tp, set('geo.distance', 12.7), cfg.geo.distance },
       { true, 1, true, 3000, true, 12 })
    eq({ set('roll.risk', 'highest'), cfg.roll.risk, set('buff.hold_aoe', true), cfg.buff.hold_aoe, set('heal.focus', 'A') },
       { true, 'highest', true, true, true })
    for path in pairs(model.REMOTE_SET) do  -- every one is a real setting
        local part, key = path:match('^(%w+)%.(.+)$')
        eq(cfg[part][key] ~= nil, true, path)
    end
end)

test('a row\'s gate: none at first, else the one set; one built in (Raise, an action on the enemy) is fixed', function ()
    local view = build(whm)
    local haste, raise, drain = row(view, 'buff', 'Haste'), row(view, 'revive', 'Raise'), row(view, 'heal', 'Drain')
    eq({ haste.gate, haste.gate_fixed, raise.gate, raise.gate_fixed, drain.gate, drain.gate_fixed },
       { nil, nil, 'idle', true, 'combat', true })
    local paralysis = row(view, 'remove', 'paralysis')  -- a debuff, not an action: no gate
    eq({ paralysis.debuff, paralysis.gate, paralysis.gate_fixed }, { true, nil, nil })
    local cfg = settings.defaults()
    cfg.gates.Haste, cfg.gates.Erase, cfg.gates.Raise = 'combat', 'idle', 'combat'
    view = build(whm, cfg)
    eq({ row(view, 'buff', 'Haste').gate, row(view, 'remove', 'Erase').gate, row(view, 'revive', 'Raise').gate },
       { 'combat', 'idle', 'idle' })  -- Raise's own wins
    eq({ row(view, 'buff', 'Haste').avail, row(view, 'remove', 'Erase').avail }, { 'combat only', 'ready' })
    view = build(whm, cfg, fake.snap({}, { combat = true }))
    eq({ row(view, 'buff', 'Haste').avail, row(view, 'remove', 'Erase').avail }, { 'ready', 'idle only' })
    cfg.gates.Haste = 'always'  -- not a gate: none
    eq(row(build(whm, cfg), 'buff', 'Haste').gate, nil)
end)

test('act.gate sets a row\'s gate, the other going, and clears it; no row is made, so Cure stays on', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    act.gate('Cure', 'combat')
    eq({ cfg.gates, cfg.rows.Cure }, { { Cure = 'combat' }, nil })
    act.gate('Cure', 'idle')
    eq(cfg.gates, { Cure = 'idle' })
    act.gate('Cure', nil)
    eq(cfg.gates, {})
    act.gate('Cure', 'sometimes')
    eq({ cfg.gates, writes[1] }, { {}, 4 })
    eq(row(build(whm, cfg), 'heal', 'Cure').on, true)
end)

test('a row whose key has a row under another section too names that section: one setting, both rows\'', function ()
    local view = build(fake.catalog(20, 75, WHM, 37, { 'Sublimation', 'Light Arts', 'Accession' }))
    eq({ row(view, 'buff', 'Sublimation').also, row(view, 'recover', 'Sublimation').also, row(view, 'buff', 'Protect').also,
         row(view, 'heal', 'Accession').also }, { 'Recovery', 'Buffs', nil, nil })  -- Accession's modifier is no row
    view = build(fake.catalog(2, 75, WHM, 37, { 'Chakra' }))
    eq({ row(view, 'heal', 'Chakra').also, row(view, 'remove', 'Chakra').also }, { 'Debuff removal', 'Healing' })
end)

test('another session sets a row\'s gate to the state sent; never one built in, an unknown row or another word', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, status(), function () end)
    local function apply(...) return model.apply(act, cfg, call(...), whm) end
    eq({ apply('gate', 'Haste', 'combat'), apply('gate', 'Cure', 'idle'), apply('gate', 'Cure', 'idle') }, { true, true, true })
    eq(cfg.gates, { Haste = 'combat', Cure = 'idle' })
    eq({ apply('gate', 'Haste', nil), cfg.gates }, { true, { Cure = 'idle' } })
    for _, bad in ipairs({ call('gate', 'Raise', 'combat'), call('gate', 'Drain', 'idle'), call('gate', 'Nope', 'idle'),
                           call('gate', 'Cure', 'sometimes'), call('gate', 'Cure', true), call('gate', 5, 'idle'),
                           call('gate', 'Cure', 'idle', 'extra') }) do
        eq(model.apply(act, cfg, bad, whm), false, tostring(bad[2]) .. ' ' .. tostring(bad[3]))
    end
    eq(cfg.gates, { Cure = 'idle' })
    local brd = fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo' })  -- a song has no row, so no gate; a heal does
    eq({ model.apply(act, cfg, call('gate', 'Valor Minuet', 'idle'), brd),
         model.apply(act, cfg, call('gate', 'Cure', 'combat'), brd) }, { false, true })
    eq(cfg.gates, { Cure = 'combat' })
    local sent = {}
    local mine = model.actions(cfg, status(), function () end, nil, function (name, c) sent[#sent + 1] = { name, c } end)
    mine.remote('A').gate('Haste', 'idle')
    eq(sent, { { 'A', call('gate', 'Haste', 'idle') } })
end)

test('what halts automation, in the engine\'s order, as words; a moment\'s hold (casting, moving) is none', function ()
    eq({ model.halted({ loading = true }), model.halted({ mounted = true, afk = true }), model.halted({ afk = true }),
         model.halted({ safe = true }), model.halted({ casting = true, moving = true }) },
       { 'zoning', 'mounted', 'AFK asleep', 'safe zone', nil })
end)

test('every other session is listed by name from its file, held only while running', function ()
    local st = status({ sessions = { B = { running = true, halted = 'mounted', members = { { sid = 2, name = 'B' } } },
                                     A = { running = false, halted = 'mounted', members = { { sid = 1, name = 'A' } } } },
                        watching = { B = true } })
    eq(model.sessions(st), { { name = 'A', running = false, open = false },
                             { name = 'B', running = true, halted = 'mounted', open = true } })
end)

-- On a Japanese client ---------------------------------------------------------------------

local lang = require('core.lang')
local COR, SCH, NIN = 17, 20, 13
local JA_NAMES = { job = NAMES.job, statuses = fake.res.statuses, spells = fake.res.spells, abilities = fake.res.abilities }

-- A view built on a Japanese client, a font to draw it assumed; the UI's language put back after.
local function japanese_view(cat, cfg, g, st)
    cfg = cfg or settings.defaults()
    cfg.ui.japanese = true
    local drawable = lang.drawable
    lang.drawable = true
    local ok, v = pcall(model.build, g or fake.snap({ { name = 'A' }, { name = 'B' } }), cat, cfg, st or status(), JA_NAMES)
    lang.drawable = drawable
    lang.use(false)
    if not ok then error(v, 0) end
    return v
end

test('in Japanese a row is named from the DAT, its choices and readiness in Japanese; keys and picks stay English', function ()
    local v = japanese_view(whm)
    local cure = row(v, 'heal', 'Cure')
    eq({ cure.key, cure.label, cure.avail, cure.action }, { 'Cure', 'ケアル', '使用可', 'ケアルV' })
    local protect = row(v, 'buff', 'Protect')
    eq(keys(protect.choices, 'label'), { '自動（最上位）', 'プロテス', 'プロテスII', 'プロテスIII', 'プロテスIV' })
    eq({ protect.choices[2].name, protect.choice }, { 'Protect', '自動（最上位）' })
    local bar = row(v, 'buff', 'barelement')
    eq({ bar.label, bar.choice, bar.avail }, { 'バ系（属性）', '選択してください', '要選択' })
    eq(row(v, 'buff', 'Regen (keep up)').label, 'リジェネ（維持）')
    eq(v.job, '白75/黒37')
end)

test('in Japanese the Buffs list keeps the casting order, by the English names', function ()
    eq(keys(section(japanese_view(whm), 'buff').rows), keys(section(build(whm), 'buff').rows))
end)

test('in Japanese why a row can\'t go is Japanese: a recast, MP, a pick the job lost', function ()
    local waits = { ['Cure'] = 20, ['Cure II'] = 9.2, ['Cure III'] = 30, ['Cure IV'] = 30, ['Cure V'] = 30 }
    eq(row(japanese_view(whm, nil, fake.snap({}, nil, waits)), 'heal', 'Cure').avail, 'リキャスト 10秒')
    local g = fake.snap({})
    g.me.mp = 0
    eq(row(japanese_view(whm, nil, g), 'heal', 'Cure').avail, 'MP不足')
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, pick = 'Protect V' }
    local r = row(japanese_view(whm, cfg), 'buff', 'Protect')
    eq({ r.choice, r.avail, r.pick }, { 'プロテスV（使用不可）', '使用不可', 'Protect V' })
end)

test('in Japanese a debuff is its status\'s Japanese name, switched by its English one', function ()
    local para = row(japanese_view(whm), 'remove', 'paralysis')
    eq({ para.key, para.label }, { 'paralysis', '麻痺' })
    eq(para.action:sub(1, #'パラナ、エスナ、'), 'パラナ、エスナ、')
    eq(row(japanese_view(whm), 'remove', 'poison').label, '毒')  -- the status, not the spell Poison (ポイズン)
end)

test('in Japanese the status line, the log and the HUD\'s label name the action, its target and why', function ()
    local kupipi = fake.sjis('クピピ')  -- a trust's name, as a Japanese client gives it
    local e = { at = 990, action = 'Cure IV', jp = fake.res.spells[4].jp, target = kupipi, behavior = 'heal',
                why = 'efficient: ' .. kupipi .. ' 62%' }
    local v = japanese_view(whm, nil, nil, status({ intent = e }))
    eq({ v.status.state, v.status.text }, { 'Stopped', '予定: ケアルIV → クピピ（回復: 効率: クピピ 62%）' })
    eq(v.pointer.text, '回復:ケアルIV → クピピ')  -- no card of theirs here: named
    v = japanese_view(whm, nil, nil, status({ running = true, why = 'casting', sent = { e } }))
    eq({ v.status.state, v.status.dim }, { 'Running', '詠唱中' })
    eq(v.recent, { { age = 10, text = 'ケアルIV → クピピ', why = '回復: 効率: クピピ 62%' } })
    local rest = { at = 995, action = 'Rest', behavior = 'rest', why = 'MP 40%' }  -- resting's: words, not names
    eq(japanese_view(whm, nil, nil, status({ running = true, sent = { rest } })).recent[1].text, 'ヒーリング')
    local follow = { at = 995, action = 'Follow', target = 'B', behavior = 'follow', why = 'B 12.3y away' }  -- following's too
    eq(japanese_view(whm, nil, nil, status({ running = true, sent = { follow } })).recent[1], { age = 5, text = '追従 → B',
        why = '追従: B 12.3y先' })
end)

test('in Japanese party lines list statuses by their Japanese names; flags stay words a UI compares', function ()
    local g = fake.snap({ { name = 'A', buffs = { [40] = true, [33] = true } } }, { safe = true })
    local v = japanese_view(whm, nil, g)
    eq({ v.party[2].name, v.party[2].buffs, v.flags }, { 'A', 'プロテス、ヘイスト', { 'safe zone' } })
end)

test('in Japanese a job\'s pickers are labelled from the DAT: songs, rolls, stratagem chips', function ()
    local brd = japanese_view(fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo' }))
    local valor
    for _, c in ipairs(brd.song.choices) do if c.name == 'Valor Minuet IV' then valor = c.label end end
    eq({ valor, brd.song.sets[1].label, brd.song.sets[2].label, brd.song.avail }, { '猛者のメヌエットIV（攻撃力+）', '範囲', 'ME', '使用可' })
    local cor = japanese_view(fake.catalog(COR, 75, NIN, 37, { 'Corsair\'s Roll', 'Chaos Roll', 'Phantom Roll' }))
    eq(keys(cor.roll.choices, 'label'), { 'カオスロール（攻撃力+）', 'コルセアズロール（経験値+）' })
    eq(keys(cor.roll.choices, 'name'), { 'Chaos Roll', 'Corsair\'s Roll' })
    local sch = japanese_view(fake.catalog(SCH, 75, WHM, 37, { 'Light Arts', 'Penury', 'Celerity', 'Accession' }))
    eq(keys(row(sch, 'buff', 'Protect').mods, 'label'), { '簡素清貧の章', '電光石火の章', '女神降臨の章' })
    eq(keys(row(sch, 'buff', 'Protect').mods, 'name'), { 'Penury', 'Celerity', 'Accession' })
    eq(row(sch, 'buff', 'Protect').mods[1].note, '消費MP半減')
end)

test('in Japanese no word the view asks for is missing from core/ja.lua', function ()
    lang.misses = {}
    for _, cat in ipairs({ whm, fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo', 'Nightingale' }),
                           fake.catalog(SCH, 75, WHM, 37, { 'Light Arts', 'Dark Arts', 'Penury', 'Accession', 'Sublimation' }),
                           fake.catalog(COR, 75, NIN, 37, { 'Corsair\'s Roll', 'Phantom Roll', 'Double-Up', 'Fold' }) }) do
        japanese_view(cat, nil, fake.snap({ { name = 'A' }, { name = 'B', kind = 'trust' } }, { combat = true, safe = true }),
            status({ running = true, why = 'nothing to do', sent = { { at = 999, action = 'Haste', target = 'A', behavior = 'buff',
                                                                         why = 'A lacks it' } } }))
    end
    eq(lang.misses, {})
end)

test('a heal row with more than one tier lists each, tickable on its own', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    local view = build(whm, cfg)
    eq(keys(row(view, 'heal', 'Cure').tiers, 'name'), { 'Cure', 'Cure II', 'Cure III', 'Cure IV', 'Cure V' })
    eq(keys(row(view, 'heal', 'Curaga').tiers, 'name'), { 'Curaga', 'Curaga II', 'Curaga III', 'Curaga IV' })
    eq(keys(row(view, 'heal', 'Regen').tiers, 'name'), { 'Regen', 'Regen II', 'Regen III' })
    eq({ row(view, 'heal', 'Cure').tiers[1].on, row(view, 'heal', 'Cure').tiers[1].wakes }, { true, true })
    eq(row(view, 'heal', 'Regen').tiers[1].wakes, false)  -- a Regen wakes no one
    act.heal_spell('Cure', false)
    eq({ cfg.heal.never, writes[1] }, { { Cure = true }, 1 })
    eq(row(build(whm, cfg), 'heal', 'Cure').tiers[1].on, false)
    act.heal_spell('Cure')  -- a toggle
    eq(cfg.heal.never, {})
    local remote = model.actions(cfg, status(), function () end)
    eq({ model.apply(remote, cfg, { 'heal_spell', 'Regen', false, n = 2 }, whm), cfg.heal.never }, { true, { Regen = true } })
    eq(model.apply(remote, cfg, { 'heal_spell', 'Regen', n = 1 }, whm), false)  -- a bare toggle: never from afar
end)

test('a heal row goes by the tiers left ticked; with none, it says so', function ()
    local cfg = settings.defaults()
    cfg.heal.never = { ['Cure V'] = true }
    local r = row(build(whm, cfg), 'heal', 'Cure')
    eq({ r.ready, r.action }, { true, 'Cure IV' })
    for _, n in ipairs({ 'Cure', 'Cure II', 'Cure III', 'Cure IV' }) do cfg.heal.never[n] = true end
    r = row(build(whm, cfg), 'heal', 'Cure')
    eq({ r.on, r.ready, r.avail, r.action }, { true, false, 'every tier unticked', nil })
end)

test('tiers: waltzes too; a heal alone on its row or a Ready move only once unticked', function ()
    local DNC, BST = 19, 9
    local whm_dnc = fake.catalog(WHM, 75, DNC, 37, { 'Curing Waltz', 'Curing Waltz II', 'Divine Waltz' })
    local view = build(whm_dnc)
    eq(keys(row(view, 'heal', 'Curing Waltz').tiers, 'name'), { 'Curing Waltz', 'Curing Waltz II' })
    eq(row(view, 'heal', 'Divine Waltz').tiers, nil)
    local whm_bst = fake.catalog(WHM, 75, BST, 37)
    eq(row(build(whm_bst), 'heal', 'Wild Carrot').tiers, nil)
    local cfg = settings.defaults()
    cfg.heal.never = { ['Wild Carrot'] = true, Drain = true }
    local tiers = row(build(whm_bst, cfg), 'heal', 'Wild Carrot').tiers
    eq({ keys(tiers, 'name'), tiers[1].on, tiers[1].wakes }, { { 'Wild Carrot' }, false, false })  -- unticked: listed, to tick again
    local drain = row(build(whm, cfg), 'heal', 'Drain')  -- alone on its row (BLM 37: no Drain II), unticked
    eq({ keys(drain.tiers, 'name'), drain.tiers[1].on, drain.tiers[1].wakes, drain.avail },
        { { 'Drain' }, false, false, 'every tier unticked' })
    eq(row(build(whm), 'revive', 'Raise').tiers, nil)
end)
