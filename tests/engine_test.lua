-- core/engine.lua and the behaviors, on fake snapshots over a real catalog
-- (WHM 75 / BLM 37 from the dumped client data).
local catalog = require('core.catalog')
local engine = require('core.engine')
local settings = require('core.settings')
local K = require('core.knowledge')
local res = {
    spells = dofile('tests/data/spells.lua'),
    abilities = dofile('tests/data/abilities.lua'),
    statuses = dofile('tests/data/statuses.lua'),
}

local JAS = { ['Divine Seal'] = true, ['Martyr'] = true }
local cat = catalog.build(res, {
    main = 3, main_lv = 75, sub = 4, sub_lv = 37,
    has_spell = function () return true end,
    has_ability = function (id) return JAS[res.abilities[id].en] == true end,
}, K)

local function unit(t)
    local u = { kind = 'party', in_zone = true, alive = true, dist = 5, buffs = {}, hpp = 100, mpp = 100, mp = 0, tp = 0 }
    for k, v in pairs(t) do u[k] = v end
    u.alive = t.alive ~= false and u.hpp > 0
    return u
end

-- Snapshot: you (WHM, 1000 MP) plus `others`; `waits` = { [action name] = seconds of recast }.
local function snap(others, over, waits)
    local me = unit({ kind = 'self', slot = 0, sid = 1, name = 'Me', dist = 0, mp = 1000, tp = 0 })
    local units = { me }
    for i, o in ipairs(others or {}) do
        o.slot, o.sid = o.slot or i, o.sid or 100 + i
        units[#units + 1] = unit(o)
    end
    local g = { now = 1000, me = units[1], units = units, combat = false,
        recast = function (a) return (waits or {})[a.name] or 0 end }
    for k, v in pairs(over or {}) do g[k] = v end
    return g
end

local function decide(g, cfg, mem)
    local intent, why = engine.decide(g, cat, cfg or settings.defaults(), mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg or settings.defaults()), intent
end

test('heals the lowest member, sized to the HP missing', function ()
    local g = snap({ { name = 'A', hpp = 70, hp = 700, max_hp = 1000 }, { name = 'B', hpp = 65, hp = 650, max_hp = 1000 } })
    eq(decide(g), '/ma "Cure III" 102')  -- 350 missing: Cure III (200) is the biggest that fits
end)

test('without a known max HP, the strongest cure', function ()
    eq(decide(snap({ { name = 'A', hpp = 50, hp = 500 } })), '/ma "Cure V" 101')
end)

test('a member out of range is skipped, not the end of healing', function ()
    local g = snap({ { name = 'Far', hpp = 20, hp = 1, dist = 30 }, { name = 'Near', hpp = 60, hp = 600 } })
    eq(decide(g), '/ma "Cure V" 102')
end)

test('short on MP: the biggest cure still affordable', function ()
    local g = snap({ { name = 'A', hpp = 50, hp = 500 } })
    g.me.mp = 60
    eq(decide(g), '/ma "Cure III" 101')
end)

test('the focus target goes first, under its own threshold', function ()
    local cfg = settings.defaults()
    cfg.heal.focus = 'Tank'
    local g = snap({ { name = 'A', hpp = 60, hp = 600 }, { name = 'Tank', hpp = 80, hp = 800 } })
    eq(decide(g, cfg), '/ma "Cure V" 102')
end)

test('critical HP: Divine Seal first, Martyr once it is down', function ()
    local g = snap({ { name = 'A', hpp = 20, hp = 200 } })
    eq(decide(g), '/ja "Divine Seal" <me>')
    g = snap({ { name = 'A', hpp = 20, hp = 200 } }, nil, { ['Divine Seal'] = 600 })
    eq(decide(g), '/ja "Martyr" 101')
end)

test('a cure nearly off recast holds buffs and raises, not debuff removal', function ()
    local waits = {}
    for _, a in ipairs(cat) do if a.role == 'heal' then waits[a.name] = 5 end end
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, targets = { [1] = true } }
    local g = snap({ { name = 'A', hpp = 50, hp = 500 } }, nil, waits)
    eq({ decide(g, cfg) }, { nil, 'waiting for a cure' })
    g.units[2].buffs[3] = true  -- poisoned
    eq(decide(g, cfg), '/ma "Poisona" 101')
end)

test('removal: the specific -na first, Erase for what only it clears', function ()
    local g = snap({ { name = 'A', buffs = { [4] = true, [13] = true } } })  -- Paralysis, Slow
    eq(decide(g), '/ma "Paralyna" 101')
    g = snap({ { name = 'A', buffs = { [13] = true } } })
    eq(decide(g), '/ma "Erase" 101')
end)

test('revive: the best raise, idle only, and not again while they decide', function ()
    local mem = {}
    local g = snap({ { name = 'Dead', hpp = 0 } })
    local cmd, intent = decide(g, nil, mem)
    eq(cmd, '/ma "Arise" 101')
    engine.sent(intent, g, mem)
    eq({ decide(g, nil, mem) }, { nil, 'nothing to do' })
    eq({ decide(snap({ { name = 'Dead', hpp = 0 } }, { combat = true })) }, { nil, 'nothing to do' })
end)

test('buffs are opt-in, and go only where they are missing', function ()
    local g = snap({ { name = 'A' } })
    eq({ decide(g) }, { nil, 'nothing to do' })
    local cfg = settings.defaults()
    cfg.rows.Protect = { on = true, targets = { [1] = true } }
    eq(decide(g, cfg), '/ma "Protect IV" 101')
    g.units[2].buffs[40] = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
end)

test('a pick_one group casts only its pick; an area buff covers those near you', function ()
    local cfg = settings.defaults()
    cfg.rows.barelement = { on = true }
    local g = snap({ { name = 'A' } })
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
    cfg.rows.barelement.pick = 'Barfira'
    eq(decide(g, cfg), '/ma "Barfira" <me>')
end)

test('gates stop everything', function ()
    eq({ decide(snap({ { name = 'A', hpp = 50, hp = 500 } }, { casting = true })) }, { nil, 'casting' })
    eq({ decide(snap({ { name = 'A', hpp = 50, hp = 500 } }, { silenced = true })) }, { nil, 'nothing to do' })
end)

test('throttle: 1.1s after anything, 3.1s after a spell lands', function ()
    local mem = { sent_at = 100 }
    eq(engine.ready({ now = 101 }, mem), false)
    eq(engine.ready({ now = 101.2 }, mem), true)
    eq(engine.ready({ now = 103, finished = 100.5, spell_finish = true }, mem), false)
    eq(engine.ready({ now = 103.7, finished = 100.5, spell_finish = true }, mem), true)
end)
