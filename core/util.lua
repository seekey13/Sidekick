--[[
    Small helpers more than one module needs, so none keeps its own copy.
    Pure: no game client.
]]--

local util = {}

-- A deep copy of `v` (tables copied all the way down; anything else as is).
function util.copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = util.copy(x) end
    return out
end

-- A copy of table `t`, its values shared.
function util.shallow(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- `over` laid on `base`: its own fields, else base's. A view of `base` with some
-- fields changed, for one decision, that leaves `base` as it is.
function util.overlay(base, over) return setmetatable(over, { __index = base }) end

-- `t`'s keys, sorted; none for nil.
function util.sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Whether `list` holds `x`.
function util.contains(list, x)
    for _, v in ipairs(list) do if v == x then return true end end
    return false
end

function util.clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end

function util.round(x) return math.floor(x + 0.5) end

-- `s` with its first letter a capital.
function util.capitalize(s) return (s:gsub('^%l', string.upper)) end

-- table.sort orders for catalog records: the higher level first; higher priority first, then the higher level.
function util.by_level(a, b) return (a.level or 0) > (b.level or 0) end

function util.by_priority(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return util.by_level(a, b)
end

-- The first of `list` whose `name` is `name` in any case, else nil. `skip`, when
-- given, leaves that one out (you, when looking for someone else).
function util.named(list, name, skip)
    if not name or name == '' then return nil end
    name = name:lower()
    for _, x in ipairs(list) do
        if x ~= skip and x.name:lower() == name then return x end
    end
end

-- Your level in `job` (main or sub) from anything with main, main_lv, sub, sub_lv; 0 off it.
function util.level(p, job)
    if p.main == job then return p.main_lv end
    return p.sub == job and p.sub_lv or 0
end

-- The name to send for something with an English and a Japanese spelling: the
-- Japanese one on a Japanese client when there is one. The second result is
-- true when a Japanese client gets the English one (it has none), which that
-- client won't take.
function util.spelled(en, jp, japanese)
    local english = japanese and (jp or '') == ''
    return japanese and not english and jp or en, english
end

return util
