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

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

test('WHM 75 / BLM 37: every section, in order, each under its header, then UI / Log', function ()
    local view = build(whm)
    eq(view.job, 'WHM 75 / BLM 37')
    eq(keys(view.sections, 'id'), { 'follow', 'heal', 'revive', 'wake', 'remove', 'buff', 'recover', 'rest', 'track', 'ui' })
    eq(keys(view.sections, 'title'), { 'Follow', 'Healing', 'Revive', 'Wake sleepers', 'Debuff removal', 'Buffs',
        'Recovery', 'Resting', 'Tracked players', 'UI / Log' })
    eq(keys(view.sections, 'header'), { 'Follow', 'Heal', 'Heal', 'Remove', 'Remove', 'Buff', 'Recover', 'Recover',
        'Tracked', 'UI / Log' })
    eq(keys(view.sections, 'on'), { false, true, true, true, true, true, true, false })  -- Tracked, UI / Log: no switch
    eq({ section(view, 'track').on, section(view, 'ui').on }, { nil, nil })
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
    eq(keys(view.sections, 'id'), { 'follow', 'heal', 'remove', 'buff', 'recover', 'rest', 'track', 'ui' })
    eq(keys(section(view, 'remove').rows), { 'Antidote', 'Eye Drops', 'Echo Drops', 'Holy Water', 'Tincture',
        'Hallowed Water', 'Remedy Ointment', 'Remedy', 'Panacea' })
end)

test('item rows are opt-in and say how many you carry; none left when you have none', function ()
    local view = build(whm, nil, fake.snap({ { name = 'A' } }, { items = { [4151] = 12 } }))
    local echo, antidote = row(view, 'remove', 'Echo Drops'), row(view, 'remove', 'Antidote')
    eq({ echo.on, echo.count, echo.ready, echo.action }, { false, 12, true, 'Echo Drops' })
    eq({ antidote.count, antidote.ready, antidote.avail }, { 0, false, 'none left' })
    eq(row(view, 'remove', 'Poisona').count, nil)
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
    eq(keys(row(view, 'buff', 'Haste').targets, 'on'), { false, false, true, false, false, false })
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
    eq({ cfg.buff.on, cfg.follow.on, cfg.rest.on, cfg.heal.danger, cfg.heal.focus, cfg.japanese, cfg.ui.hp_width },
       { false, true, true, 60, 'A', true, 300 })
    eq(writes[1], 8)
    local view = build(whm, cfg)
    eq({ section(view, 'buff').on, section(view, 'follow').on, section(view, 'rest').on, view.heal.danger,
         view.ui.hp_width, view.ui.compact, view.japanese }, { false, true, true, 60, 300, true, true })
    eq(view.heal.focus_names, { 'A', 'B' })
    view.ui.mp_width = 100  -- the view is a copy
    eq(cfg.ui.mp_width, 220)
end)

test('run and log change the session only; close also remembers it in the settings', function ()
    local cfg, st = settings.defaults(), status({ open = true })
    cfg.ui.open = true
    local act, writes = actions(cfg, st)
    act.run(true)
    act.log(false)
    eq({ st.running, st.log, writes[1] }, { true, false, 0 })
    act.close()
    eq({ st.open, cfg.ui.open, writes[1] }, { false, false, 1 })
end)

test('healing skips a member by name, and takes them back', function ()
    local cfg = settings.defaults()
    local act, writes = actions(cfg)
    act.skip('A')
    eq(cfg.heal.skip, { A = true })
    eq(build(whm, cfg).heal.members, { { name = 'A', healed = false }, { name = 'B', healed = true } })
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
end)

test('buff rows reaching outside the party get a chip per tracked player, its slot their name', function ()
    local view = build(whm, nil, tracked_snap())
    local haste = row(view, 'buff', 'Haste')
    eq(keys(haste.targets, 'label'), { 'ME', 'P1', 'P2', 'P3', 'P4', 'P5', 'T1', 'T2' })
    eq(haste.targets[7], { slot = 'Out', label = 'T1', present = true, name = 'Out', on = false })
    eq(#row(view, 'buff', 'Regen (keep up)').targets, 6)  -- party only
    local cfg = settings.defaults()
    model.actions(cfg, status(), function () end).target('Haste', 'Out')
    eq(cfg.rows.Haste.targets, { [0] = true, Out = true })
    eq(row(build(whm, cfg, tracked_snap()), 'buff', 'Haste').targets[7].on, true)
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