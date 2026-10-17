-- What the engine and UI tests share: a real catalog from the dumped client
-- data (tests/data), and fake snapshots shaped like core/game.lua's.
local catalog = require('core.catalog')
local K = require('core.knowledge')

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
-- tracked player has none, and no MP); `over` sets snapshot fields;
-- `waits` = { [action name] = seconds of recast }.
function fake.snap(others, over, waits)
    local units = { fake.unit({ kind = 'self', slot = 0, sid = 1, name = 'Me', dist = 0, mp = 1000, tp = 0 }) }
    for i, o in ipairs(others or {}) do
        if o.kind == 'tracked' then
            o.sid, o.mpp, o.uses_mp = o.sid or 200 + i, 0, false
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

return fake
