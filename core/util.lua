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

-- `t`'s keys, sorted; none for nil.
function util.sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- table.sort order for catalog records: higher priority first, then the higher level.
function util.by_priority(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return (a.level or 0) > (b.level or 0)
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
