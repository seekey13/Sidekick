-- Puppetmaster (jobs/pup.lua): maneuvers kept up while the automaton is out,
-- through the engine; the oil pet care equips (behaviors/pet.lua); and the
-- Maneuvers section in ui/model.lua.
local engine = require('core.engine')
local packets = require('core.packets')
local pup = require('jobs.pup')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local PUP, WAR, BST, WHM = 18, 1, 9, 3
local FIRE, LIGHT, OVERLOAD, INVISIBLE, POISON = 300, 306, 299, 69, 3
local OIL, OIL1, OIL3, BISCUIT = 18731, 18732, 19185, 17016
local JAS = { 'Fire Maneuver', 'Ice Maneuver', 'Light Maneuver', 'Repair', 'Maintenance', 'Role Reversal', 'Deploy' }
local cat = fake.catalog(PUP, 75, WHM, 37, JAS)

local named = fake.named

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

local function decide(g, cfg, list, mem) return fake.decide(g, list or cat, cfg, mem) end

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
    eq({ decide(snap({ [INVISIBLE] = 1 }), cfg) }, { nil, 'invisible' })
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

-- A 0x044 as the server builds it: the job at 0x04, the automaton's name at 0x58.
local function job_packet(job, name)
    local b = {}
    for i = 1, 0x58 + 16 + 64 do b[i] = 0 end
    b[0x04 + 1] = job
    for i = 1, #name do b[0x58 + i] = name:byte(i) end
    return { id = 0x044, data = string.char(unpack(b)) }
end

test('maneuvers go only on your automaton: named by the server, else guessed from your jobs', function ()
    local cfg = cfg_with({ 'Fire Maneuver' })
    packets.handle(job_packet(PUP, 'Sharpshot'), {}, 0)
    eq(pup.automaton(), 'Sharpshot')
    packets.handle(job_packet(BST, 'Ignored'), {}, 0)  -- another job's: not the automaton's
    eq(pup.automaton(), 'Sharpshot')
    eq(decide(snap(nil, { automaton = 'Sharpshot', pet = automaton({ name = 'Sharpshot' }) }), cfg), '/pet "Fire Maneuver" <me>')
    eq({ decide(snap(nil, { automaton = 'Sharpshot', pet = automaton({ name = 'FunguarFamiliar' }) }), cfg) },
       { nil, 'nothing to do' })
    packets.handle(job_packet(PUP, 'SixteenCharName!'), {}, 0)  -- 16 long: no NUL
    eq(pup.automaton(), 'SixteenCharName!')
    packets.handle(job_packet(PUP, ''), {}, 0)
    eq(pup.automaton(), nil)
    -- Not named yet: a PUP main's pet is it; a PUP sub's, unless the main job has a pet of its own.
    local bst = fake.catalog(BST, 75, PUP, 37, { 'Fire Maneuver' })
    eq({ decide(snap(nil, { main = BST, sub = PUP, sub_lv = 37 }), cfg, bst) }, { nil, 'nothing to do' })
    local war = fake.catalog(WAR, 75, PUP, 37, { 'Fire Maneuver' })
    eq(decide(snap(nil, { main = WAR, sub = PUP, sub_lv = 37 }), cfg, war), '/pet "Fire Maneuver" <me>')
    eq(decide(snap(nil, { main = BST, sub = PUP, sub_lv = 37, automaton = 'Automaton' }), cfg, bst),
       '/pet "Fire Maneuver" <me>')
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

test('an equip that never shows is given up on after 3, so the next row goes, until the slot or the count changes', function ()
    local items = { [OIL] = { 'Automaton Oil', 1 } }
    local mem, cfg = {}, settings.defaults()
    local g = snap(nil, { pet = automaton({ hpp = 40 }), owned = owned(items) })
    for _ = 1, 3 do
        local cmd, intent = decide(g, cfg, cat, mem)
        eq(cmd, '/equip ammo "Automaton Oil" 0')
        engine.sent(intent, g, mem)
        g.now = g.now + 3
    end
    eq(decide(g, cfg, cat, mem), '/ja "Role Reversal" <me>')
    g.ammo = 12345  -- something else went on: worth trying again
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
    -- Every element, including ones the client isn't listing (no automaton out when the catalog was built).
    eq(view.maneuver.choices, { { name = 'Fire Maneuver', label = 'Fire' }, { name = 'Ice Maneuver', label = 'Ice' },
                                { name = 'Wind Maneuver', label = 'Wind' }, { name = 'Earth Maneuver', label = 'Earth' },
                                { name = 'Thunder Maneuver', label = 'Thunder' }, { name = 'Water Maneuver', label = 'Water' },
                                { name = 'Light Maneuver', label = 'Light' }, { name = 'Dark Maneuver', label = 'Dark' } })
    eq({ view.maneuver.picks, view.maneuver.ready, view.maneuver.avail }, { { 'Fire Maneuver', '', 'Light Maneuver' }, false, 'recast 8s' })
    eq(model.build(snap(nil, { pet = false }), cat, cfg, status(), NAMES).maneuver.avail, 'no pet')
    local whm = model.build(fake.snap(), fake.catalog(WHM, 75, nil, 0), cfg, status(), NAMES)
    for _, s in ipairs(whm.sections) do eq(s.id ~= 'maneuver', true, 'no Maneuvers off PUP') end
end)

test('ui: Maneuvers stay up with the automaton dismissed, and none goes until it is out', function ()
    local bare = fake.catalog(PUP, 75, WHM, 37, {})  -- the client lists no pet commands
    local cfg = cfg_with({ 'Wind Maneuver' })
    local view = model.build(snap(nil, { pet = false }), bare, cfg, status(), NAMES)
    local shown = false
    for _, s in ipairs(view.sections) do shown = shown or s.id == 'maneuver' end
    eq({ shown, #view.maneuver.choices, view.maneuver.avail }, { true, 8, 'no pet' })
    eq({ decide(snap(nil, { pet = false }), cfg, bare) }, { nil, 'nothing to do' })
    eq(decide(snap(), cfg, bare), '/pet "Wind Maneuver" <me>')
end)

test('ui: a care row whose ammo you hold says it equips it', function ()
    local g = snap(nil, { owned = owned({ [OIL] = { 'Automaton Oil', 1 } }) })
    local view = model.build(g, cat, settings.defaults(), status(), NAMES)
    local rows = {}
    for _, sec in ipairs(view.sections) do for _, r in ipairs(sec.rows or {}) do rows[r.key] = r end end
    eq({ rows.Repair.ready, rows.Repair.avail }, { true, 'equips Automaton Oil' })
    g.owned = owned({})
    view = model.build(g, cat, settings.defaults(), status(), NAMES)
    for _, sec in ipairs(view.sections) do for _, r in ipairs(sec.rows or {}) do rows[r.key] = r end end
    eq({ rows.Repair.ready, rows.Repair.avail }, { false, 'no ammo' })
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

-- The client lists pet commands only while the pet is out: Deploy is on the Pet
-- page anyway, waiting on the automaton, as the SMN's Assault and pacts are on theirs.
test('ui: Deploy, Assault and the pacts are in settings with no pet out, each waiting on it', function ()
    local SMN = 15
    local function rows(g, list)
        local out = {}
        for _, s in ipairs(model.build(g, list, settings.defaults(), status(), NAMES).sections) do
            for _, r in ipairs(s.rows or {}) do out[r.key] = r end
        end
        return out
    end
    local r = rows(snap(nil, { pet = false }), fake.catalog(PUP, 75, WHM, 37, {}))
    eq({ r.Deploy.ready, r.Deploy.avail, r.Deploy.on }, { false, 'no pet', false })
    local smn = fake.catalog(SMN, 75, WHM, 37, {})
    r = rows(fake.snap({}, { main = SMN, sub = WHM }), smn)
    eq({ r.Assault.avail, r['Avatar\'s Favor'].avail, r['Healing Ruby'].avail, r['Shining Ruby'].avail },
       { 'no pet', 'no pet', 'no pet', 'no pet' })
    -- Out, but the client doesn't list it (Ifrit's pacts aren't Carbuncle's): wrong pet first, else not listed.
    local g = fake.snap({}, { main = SMN, sub = WHM, pet = automaton({ name = 'Ifrit' }) })
    g.listed = function () return false end
    r = rows(g, smn)
    eq({ r['Healing Ruby'].avail, r.Assault.avail }, { 'wrong pet', 'not listed' })
    g.listed = function () return true end
    eq(rows(g, smn).Assault.avail, 'no battle target')  -- listed: on to the next gate
end)

test('a maneuver the client doesn\'t list is never sent (the pet out isn\'t the automaton it thought)', function ()
    local cfg = cfg_with({ 'Fire Maneuver' })
    local g = snap()
    g.listed = function () return false end
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
    g.listed = function () return true end
    eq(decide(g, cfg), '/pet "Fire Maneuver" <me>')
end)
