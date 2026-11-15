-- The abilities added together (issues #101-#107): Restraint, Saboteur, Double Shot, Issekigan and Spur as buffs,
-- Mana Wall as your own guard at critical HP, Divine Caress fired before a -na spell.
local model = require('ui.model')
local settings = require('core.settings')
local fake = require('tests.fake')

local WAR, WHM, BLM, RDM, BST, RNG, NIN = 1, 3, 4, 5, 9, 11, 13
local POISON, PARALYSIS, DOOM, MANA_WALL, CARESS = 3, 4, 15, 437, 453
local snap, named = fake.snap, fake.named

local function on(...)
    local cfg = settings.defaults()
    for _, key in ipairs({ ... }) do cfg.rows[key] = { on = true } end
    return cfg
end

test('Restraint, Saboteur, Double Shot and Issekigan: combat-only self buffs, by their own status', function ()
    for job, t in pairs({ [WAR] = { 'Restraint', 435 }, [RDM] = { 'Saboteur', 454 }, [RNG] = { 'Double Shot', 433 },
                          [NIN] = { 'Issekigan', 484 } }) do
        local name, id = t[1], t[2]
        local cat = fake.catalog(job, 75, nil, 0, { name })
        local a = named(cat, name)
        eq({ a.role, a.gate, a.status }, { 'buff', 'combat', { id } })
        local cfg = on(name)
        for _, x in ipairs(cat) do if x.role ~= 'buff' then cfg.rows[settings.key(x)] = { on = false } end end
        eq({ fake.decide(snap(), cat, cfg) }, { nil, 'nothing to do' })
        eq(fake.decide(snap(nil, { combat = true }), cat, cfg), ('/ja "%s" <me>'):format(name))
        local g = snap(nil, { combat = true })
        g.me.buffs[id] = true
        eq({ fake.decide(g, cat, cfg) }, { nil, 'nothing to do' })
    end
end)

local function jug(t)
    local p = { name = 'KeenearedSteffi', hpp = 100, dist = 3, pos = { 0, 0, 0 }, status = 1, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

test('Spur: a pet command, in combat, only while your pet fights; again whenever it is off recast', function ()
    local cat = fake.catalog(BST, 75, WAR, 37, { 'Spur' })
    local spur = named(cat, 'Spur')
    eq({ spur.kind, spur.role, spur.gate, spur.status, spur.pet, spur.pet_fights }, { 'pet', 'buff', 'combat', nil, true, true })
    local cfg = on('Spur')
    local function g(pet, waits) return snap(nil, { main = BST, sub = WAR, combat = true, pet = pet }, waits) end
    eq(fake.decide(g(jug()), cat, cfg), '/pet "Spur" 1')
    eq({ fake.decide(g(jug({ status = 0 })), cat, cfg) }, { nil, 'nothing to do' })  -- out, not fighting
    eq({ fake.decide(g(nil), cat, cfg) }, { nil, 'nothing to do' })
    eq({ fake.decide(g(jug(), { Spur = 120 }), cat, cfg) }, { nil, 'nothing to do' })
    eq({ require('core.can').use(spur, g(jug({ status = 0 }))) }, { false, 'pet not fighting' })
    local out = snap(nil, { main = BST, sub = WAR, pet = jug() })
    eq({ fake.decide(out, cat, cfg) }, { nil, 'nothing to do' })  -- out of combat
end)

-- Mana Wall ----------------------------------------------------------------------------

local function hurt(hpp, others, over, waits)
    local g = snap(others, over or { combat = true }, waits)
    g.me.hpp, g.me.hp = hpp, hpp * 10
    return g
end

test('Mana Wall: when you are critical yourself, in combat, ahead of the heal and with no heal at all', function ()
    local blm = fake.catalog(BLM, 75, WHM, 37, { 'Mana Wall' })
    local wall = named(blm, 'Mana Wall')
    eq({ wall.role, wall.guards, wall.gate, wall.status }, { 'emergency', true, 'combat', { MANA_WALL } })
    local cmd, intent = fake.decide(hurt(20), blm)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Mana Wall" <me>', 'heal', 'critical: Me 20%' })
    -- Up, or on recast: the cure.
    local g = hurt(20)
    g.me.buffs[MANA_WALL] = true
    eq(fake.decide(g, blm):match('^/ma "Cure'), '/ma "Cure')
    eq(fake.decide(hurt(20, nil, nil, { ['Mana Wall'] = 300 }), blm):match('^/ma "Cure'), '/ma "Cure')
    -- With a boost already up and no cure to send (silenced), still.
    local whm = fake.catalog(WHM, 75, BLM, 37, { 'Mana Wall', 'Divine Seal' })
    g = hurt(20, nil, { combat = true, silenced = true })
    g.me.buffs[78] = true
    eq(fake.decide(g, whm), '/ja "Mana Wall" <me>')
    -- A BLM with no heal still guards.
    local alone = fake.catalog(BLM, 75, NIN, 37, { 'Mana Wall' })
    eq(fake.decide(hurt(20), alone), '/ja "Mana Wall" <me>')
end)

test('Mana Wall: not for a member\'s critical HP, not in danger only, not out of combat, not with its row off', function ()
    local blm = fake.catalog(BLM, 75, WHM, 37, { 'Mana Wall' })
    eq(fake.decide(snap({ { name = 'A', hpp = 20 } }, { combat = true }), blm):match('^/ma "Cure'), '/ma "Cure')
    eq(fake.decide(hurt(40), blm):match('^/ma "Cure'), '/ma "Cure')
    eq(fake.decide(hurt(20, nil, { combat = false }), blm):match('^/ma "Cure'), '/ma "Cure')
    local cfg = settings.defaults()
    cfg.rows['Mana Wall'] = { on = false }
    eq(fake.decide(hurt(20), blm, cfg):match('^/ma "Cure'), '/ma "Cure')
end)

-- Divine Caress ------------------------------------------------------------------------

local whm = fake.catalog(WHM, 75, BLM, 37, { 'Divine Caress' })
local function caress_fits(name) return named(whm, 'Divine Caress').applies(named(whm, name)) end

test('Divine Caress: opt-in; fired before a -na spell, which then goes; skipped while it can\'t go', function ()
    local caress = named(whm, 'Divine Caress')
    eq({ caress.role, caress.status }, { 'remove_mod', { CARESS } })
    local sick = function (waits) return snap({ { name = 'A', buffs = { [PARALYSIS] = true } } }, nil, waits) end
    eq(fake.decide(sick(), whm), '/ma "Paralyna" 101')  -- off by default
    local cfg, mem = on('Divine Caress'), {}
    local cmd, intent = fake.step(sick(), whm, cfg, mem)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Divine Caress" <me>', 'remove', 'for Paralyna -> A: A' })
    eq(fake.decide(sick(), whm, cfg, mem), '/ma "Paralyna" 101')  -- its status expected
    eq(fake.decide(sick({ ['Divine Caress'] = 40 }), whm, cfg), '/ma "Paralyna" 101')  -- no hold
    cfg.gates['Divine Caress'] = 'combat'
    eq(fake.decide(sick(), whm, cfg), '/ma "Paralyna" 101')  -- gated to combat: the -na goes without it
    local me = snap()
    me.me.buffs[PARALYSIS] = true
    eq(fake.decide(me, whm, on('Divine Caress')), '/ja "Divine Caress" <me>')  -- for your own too
end)

test('Divine Caress: not before Erase or Esuna, nor for someone Doomed', function ()
    local cfg = on('Divine Caress')
    local bio = 135
    eq(fake.decide(snap({ { name = 'A', buffs = { [bio] = true } } }), whm, cfg), '/ma "Erase" 101')
    eq(fake.decide(snap({ { name = 'A', buffs = { [DOOM] = true } } }), whm, cfg), '/ma "Cursna" 101')
    eq(fake.decide(snap({ { name = 'A', buffs = { [DOOM] = true, [POISON] = true } } }), whm, cfg):match('^/ma'), '/ma')
    for _, name in ipairs({ 'Poisona', 'Paralyna', 'Blindna', 'Silena', 'Stona', 'Viruna', 'Cursna' }) do
        eq(caress_fits(name), true)
    end
    eq({ caress_fits('Erase'), caress_fits('Esuna') }, { false, false })
end)

test('Divine Caress: a row of its own under Debuff removal, after the removers, off until switched on', function ()
    local view = model.build(snap({ { name = 'A' } }), whm, settings.defaults(), { running = false, log = true, sent = {} },
        { job = function () return 'WHM' end, statuses = fake.res.statuses })
    local rows
    for _, s in ipairs(view.sections) do if s.id == 'remove' then rows = s.rows end end
    local at, last
    for i, r in ipairs(rows) do
        if r.key == 'Divine Caress' then at = i end
        if r.remover then last = i end
    end
    local r = rows[at]
    eq({ r.label, r.on, r.remover, r.mod, r.shared }, { 'Divine Caress (before a -na spell)', false, true, true, nil })
    eq({ rows[at - 1].key, at == last, rows[at + 1].debuff }, { 'Erase', true, true })  -- then the debuffs, then the items
    eq(rows[at - 1].mod, nil)
end)
