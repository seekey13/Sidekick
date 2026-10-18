-- Puppetmaster (jobs/pup.lua): maneuvers kept up while the automaton is out,
-- through the engine; the oil pet care equips (behaviors/pet.lua); and the
-- Maneuvers section in ui/model.lua.
local engine = require('core.engine')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local PUP, WAR, BST, WHM = 18, 1, 9, 3
local FIRE, LIGHT, OVERLOAD, INVISIBLE, POISON = 300, 306, 299, 69, 3
local OIL, OIL1, OIL3, BISCUIT = 18731, 18732, 19185, 17016
local JAS = { 'Fire Maneuver', 'Ice Maneuver', 'Light Maneuver', 'Repair', 'Maintenance', 'Role Reversal', 'Deploy' }
local cat = fake.catalog(PUP, 75, WHM, 37, JAS)

local function named(list, name)
    for _, a in ipairs(list) do if a.name == name then return a end end
end

local function automaton(t)
    local p = { name = 'Automaton', hpp = 100, dist = 3, status = 0, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

-- PUP 75 / WHM 37 with the automaton out (or `over`'s), these statuses on you,
-- counted: { [id] = n }.
local function snap(stacks, over, waits)
    local o = { main = PUP, main_lv = 75, sub = WHM, sub_lv = 37, pet = automaton() }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap({}, o, waits)
    g.me.stacks = {}
    for id, n in pairs(stacks or {}) do g.me.buffs[id], g.me.stacks[id] = true, n end
    return g
end

local function cfg_with(picks)
    local cfg = settings.defaults()
    for i, name in ipairs(picks or {}) do cfg.maneuver['slot_' .. i] = name end
    return cfg
end

local function decide(g, cfg, list, mem)
    local intent, why = engine.decide(g, list or cat, cfg or settings.defaults(), mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg or settings.defaults()), intent
end

-- What you hold where ammo can be worn from: { [id] = { en, level, jobs, bag } }.
local PUP_ONLY = bit.lshift(1, PUP)
local function owned(items)
    return function (ids)
        local out = {}
        for _, id in ipairs(ids) do
            local it = items[id]
            if it then
                out[#out + 1] = { id = id, en = it[1], jp = it.jp, level = it[2], jobs = it[3] or PUP_ONLY, bag = it[4] or 0 }
            end
        end
        return out
    end
end

test('catalog: the maneuvers go on you through /pet, blocked by Overload, with an automaton out', function ()
    local fire = named(cat, 'Fire Maneuver')
    eq({ fire.role, fire.kind, fire.status, fire.blocked_by, fire.pet }, { 'maneuver', 'pet', { FIRE }, { OVERLOAD }, true })
    eq(decide(snap(), cfg_with({ 'Fire Maneuver' })), '/pet "Fire Maneuver" <me>')
end)

test('the slots are kept up, the same one twice meaning two; an empty slot is skipped', function ()
    local cfg = cfg_with({ 'Fire Maneuver', '', 'Fire Maneuver' })
    local _, intent = decide(snap(), cfg)
    eq({ intent.behavior, intent.why }, { 'maneuver', 'Automaton' })
    eq(decide(snap({ [FIRE] = 1 }), cfg), '/pet "Fire Maneuver" <me>')
    eq({ decide(snap({ [FIRE] = 2 }), cfg) }, { nil, 'nothing to do' })
    cfg.maneuver.slot_2 = 'Light Maneuver'
    eq(decide(snap({ [FIRE] = 2 }), cfg), '/pet "Light Maneuver" <me>')
    eq({ decide(snap({ [FIRE] = 2, [LIGHT] = 1 }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(), cfg_with()) }, { nil, 'nothing to do' })  -- none picked: none at first
end)

test('none without an automaton, under Overload, while Invisible, on recast or switched off', function ()
    local cfg = cfg_with({ 'Fire Maneuver' })
    eq({ decide(snap(nil, { pet = false }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, { pet = automaton({ hpp = 0 }) }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap({ [OVERLOAD] = 1 }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap({ [INVISIBLE] = 1 }), cfg) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, nil, { ['Fire Maneuver'] = 4 }), cfg) }, { nil, 'nothing to do' })
    local g = snap()
    g.amnesia = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
    cfg.maneuver.on = false
    eq({ decide(snap(), cfg) }, { nil, 'nothing to do' })
end)

test('a PUP subjob keeps them up too, as v2 (this server lets it call an automaton)', function ()
    local war = fake.catalog(WAR, 75, PUP, 37, { 'Fire Maneuver' })
    eq(decide(snap(nil, { main = WAR, sub = PUP, sub_lv = 37 }), cfg_with({ 'Fire Maneuver' }), war),
       '/pet "Fire Maneuver" <me>')
end)

test('pet care comes first: Repair before a maneuver; one goes while a cure is held for', function ()
    local cfg = cfg_with({ 'Fire Maneuver' })
    eq(decide(snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL }), cfg), '/ja "Repair" <me>')
    local waits = {}
    for _, a in ipairs(cat) do if a.role == 'heal' then waits[a.name] = 1 end end
    local g = fake.snap({ { name = 'A', hpp = 45 } }, { main = PUP, main_lv = 75, sub = WHM, sub_lv = 37, pet = automaton() }, waits)
    eq(decide(g, cfg), '/pet "Fire Maneuver" <me>')
end)

-- Ammo -----------------------------------------------------------------------------

test('Repair with no oil worn equips the best one you hold that your main job wears', function ()
    local items = { [OIL] = { 'Automaton Oil', 1, nil, 0 }, [OIL1] = { 'Automat. Oil +1', 1, nil, 2 } }
    local g = snap(nil, { pet = automaton({ hpp = 40 }), owned = owned(items) })
    local cmd, intent = decide(g)
    eq({ cmd, intent.behavior, intent.why }, { '/equip ammo "Automat. Oil +1" 2', 'pet', 'for Repair: Automaton 40%' })
    items[OIL3] = { 'Automat. Oil +3', 80 }  -- above your level
    eq(decide(g), '/equip ammo "Automat. Oil +1" 2')
    g.main_lv = 80
    eq(decide(g), '/equip ammo "Automat. Oil +3" 0')
    g.ammo = OIL
    eq(decide(g), '/ja "Repair" <me>')  -- one worn: it goes, not another equip
end)

test('the oil is equipped only when Repair could then go, and once in a while', function ()
    local items = { [OIL] = { 'Automaton Oil', 1 } }
    eq({ decide(snap(nil, { pet = automaton({ hpp = 60 }), owned = owned(items) })) }, { nil, 'nothing to do' })
    eq(decide(snap(nil, { pet = automaton({ hpp = 40, dist = 25 }), owned = owned(items) })), '/ja "Role Reversal" <me>')  -- too far for Repair
    eq(decide(snap(nil, { pet = automaton({ hpp = 40 }), owned = owned(items) }, { Repair = 30 })),
       '/ja "Role Reversal" <me>')  -- Repair on recast: the next row, no equip
    local mem, cfg = {}, settings.defaults()
    local g = snap(nil, { pet = automaton({ hpp = 40 }), owned = owned(items) })
    local _, intent = decide(g, cfg, cat, mem)
    engine.sent(intent, g, mem)
    g.now = g.now + 2
    eq({ decide(g, cfg, cat, mem) }, { nil, 'nothing to do' }, 'not again, nor Role Reversal, while it shows')
    g.now = g.now + 2
    eq(decide(g, cfg, cat, mem), '/equip ammo "Automaton Oil" 0')
end)

test('none held, or none your main job wears: the row is skipped (PUP sub: oils are PUP main only)', function ()
    eq(decide(snap(nil, { pet = automaton({ hpp = 40 }), owned = owned({}) })), '/ja "Role Reversal" <me>')
    local war = fake.catalog(WAR, 75, PUP, 37, { 'Repair' })
    local g = snap(nil, { main = WAR, sub = PUP, sub_lv = 37, pet = automaton({ hpp = 40 }),
                          owned = owned({ [OIL] = { 'Automaton Oil', 1 } }) })
    eq({ decide(g, nil, war) }, { nil, 'nothing to do' })
end)

test('Maintenance equips its oil only when the automaton has something it clears', function ()
    local items = { [OIL] = { 'Automaton Oil', 1 } }
    eq({ decide(snap(nil, { owned = owned(items) })) }, { nil, 'nothing to do' })
    eq(decide(snap(nil, { pet = automaton({ buffs = { [POISON] = true } }), owned = owned(items) })),
       '/equip ammo "Automaton Oil" 0')
end)

test('Reward equips pet food the same way; a Japanese client gets its Japanese name', function ()
    local bst = fake.catalog(BST, 75, WHM, 37, { 'Reward' })
    local food = { [BISCUIT] = { 'Pet Fd. Alpha', 1, bit.lshift(1, BST), 1, jp = '\131y\131b' } }
    local g = snap(nil, { main = BST, pet = automaton({ name = 'Crab', hpp = 30 }), owned = owned(food) })
    eq(decide(g, nil, bst), '/equip ammo "Pet Fd. Alpha" 1')
    local cfg = settings.defaults()
    cfg.ui.japanese = true
    eq(decide(g, cfg, bst), '/equip ammo "\131y\131b" 1')
    food[BISCUIT].jp = ''  -- none in the DAT: sent in English, flagged so it's warned about
    local _, intent = decide(g, cfg, bst)
    eq({ engine.command(intent, cfg) }, { '/equip ammo "Pet Fd. Alpha" 1', true })
end)

-- UI -------------------------------------------------------------------------------

local NAMES = { job = function (id) return ({ [18] = 'PUP', [3] = 'WHM' })[id] end, statuses = fake.res.statuses }
local function status() return { running = false, open = true, log = false, sent = {} } end

test('ui: Maneuvers under Pet, a PUP\'s alone: each by its element, the slots\' picks, whether they can go', function ()
    local cfg = cfg_with({ 'Fire Maneuver', '', 'Light Maneuver' })
    local view = model.build(snap(nil, nil, { ['Fire Maneuver'] = 7.2 }), cat, cfg, status(), NAMES)
    local ids = {}
    for _, s in ipairs(view.sections) do ids[s.id] = s.header end
    eq(ids.maneuver, 'Pet')
    eq(view.maneuver.choices, { { name = 'Fire Maneuver', label = 'Fire' }, { name = 'Ice Maneuver', label = 'Ice' },
                                { name = 'Light Maneuver', label = 'Light' } })
    eq({ view.maneuver.picks, view.maneuver.ready, view.maneuver.avail }, { { 'Fire Maneuver', '', 'Light Maneuver' }, false, 'recast 8s' })
    eq(model.build(snap(nil, { pet = false }), cat, cfg, status(), NAMES).maneuver.avail, 'no pet')
    local whm = model.build(fake.snap(), fake.catalog(WHM, 75, nil, 0), cfg, status(), NAMES)
    for _, s in ipairs(whm.sections) do eq(s.id ~= 'maneuver', true, 'no Maneuvers off PUP') end
end)

test('ui: a slot set from another session takes a name only', function ()
    local cfg, st = settings.defaults(), status()
    local act = model.actions(cfg, st, function () end)
    eq(model.apply(act, cfg, { 'set', n = 2, 'maneuver.slot_2', 'Ice Maneuver' }, cat), true)
    eq(cfg.maneuver.slot_2, 'Ice Maneuver')
    eq(model.apply(act, cfg, { 'set', n = 2, 'maneuver.slot_2', 5 }, cat), false)
    eq(model.apply(act, cfg, { 'set', n = 2, 'maneuver.slot_2', 'Cure' }, cat), false)
    eq(cfg.maneuver.slot_2, 'Ice Maneuver')
    eq(model.apply(act, cfg, { 'set', n = 2, 'maneuver.slot_2', '' }, cat), true)
    eq(cfg.maneuver.slot_2, '')
end)

test('ui: a bool set from another session can be switched off as well as on', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, status(), function () end)
    eq({ model.apply(act, cfg, { 'set', n = 2, 'buff.gather', false }, cat), cfg.buff.gather }, { true, false })
    eq({ model.apply(act, cfg, { 'set', n = 2, 'buff.gather', true }, cat), cfg.buff.gather }, { true, true })
end)
