-- What the engine and UI tests share: a real catalog from the dumped client
-- data (tests/data), and fake snapshots shaped like core/game.lua's.
local catalog = require('core.catalog')
local engine = require('core.engine')
local K = require('core.knowledge')
local settings = require('core.settings')

local fake = {}

fake.res = {
    spells = dofile('tests/data/spells.lua'),
    abilities = dofile('tests/data/abilities.lua'),
    statuses = dofile('tests/data/statuses.lua'),
}

-- Catalog for main/sub at these levels: every spell learned, abilities only those named in `jas`.
function fake.catalog(main, main_lv, sub, sub_lv, jas)
    local has = {}
    for _, n in ipairs(jas or {}) do has[n] = true end
    return catalog.build(fake.res, {
        main = main, main_lv = main_lv, sub = sub, sub_lv = sub_lv,
        has_spell = function () return true end,
        has_ability = function (id) return has[fake.res.abilities[id].en] == true end,
    }, K)
end

-- A unit; HP defaults to a 1000 max at its hpp, and everyone stands together.
function fake.unit(t)
    local u = { kind = 'party', in_zone = true, alive = true, dist = 5, pos = { 0, 0, 0 }, buffs = {},
                hpp = 100, mpp = 100, mp = 0, tp = 0, uses_mp = true }
    for k, v in pairs(t) do u[k] = v end
    u.alive = t.alive ~= false and u.hpp > 0
    u.max_hp = t.max_hp or (t.hp and u.hpp > 0 and math.floor(t.hp * 100 / u.hpp)) or 1000
    u.hp = t.hp or math.floor(u.max_hp * u.hpp / 100)
    return u
end

-- Snapshot: you (WHM 75 / BLM 37, 1000 MP) plus `others` in slots 1..n (a
-- tracked player has none, and no MP; the alliance's take slots 6 on, server
-- ids 301 on); `over` sets snapshot fields; `waits` = { [action name] = seconds of recast }.
function fake.snap(others, over, waits)
    local units = { fake.unit({ kind = 'self', slot = 0, sid = 1, name = 'Me', dist = 0, mp = 1000, tp = 0 }) }
    local allied = 0
    for i, o in ipairs(others or {}) do
        if o.kind == 'tracked' then
            o.sid, o.mpp, o.uses_mp = o.sid or 200 + i, 0, false
        elseif o.kind == 'alliance' then
            allied = allied + 1
            o.slot, o.sid = o.slot or 5 + allied, o.sid or 300 + allied
        else
            o.slot, o.sid = o.slot or i, o.sid or 100 + i
        end
        units[#units + 1] = fake.unit(o)
    end
    local g = { now = 1000, me = units[1], units = units, combat = false, learned = {},
        main = 3, main_lv = 75, sub = 4, sub_lv = 37,
        recast = function (a) return (waits or {})[a.name] or 0 end }
    for k, v in pairs(over or {}) do g[k] = v end
    return g
end

-- The action in `list` named `name` (of `role`, when given), else nil.
function fake.named(list, name, role)
    for _, a in ipairs(list) do
        if a.name == name and (not role or a.role == role) then return a end
    end
end

-- The engine's decision on `g` from catalog `cat` (`cfg` the defaults, `mem` a fresh
-- one when nil): the command it would send and the intent, or nil and why not.
function fake.decide(g, cat, cfg, mem)
    cfg = cfg or settings.defaults()
    local intent, why = engine.decide(g, cat, cfg, mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg), intent
end

-- fake.decide, then its send recorded (engine.sent) when there was one, as in game.
function fake.step(g, cat, cfg, mem)
    local cmd, intent = fake.decide(g, cat, cfg, mem)
    if cmd then engine.sent(intent, g, mem) end
    return cmd, intent
end

return fake
