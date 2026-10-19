--[[
    Small table helpers shared by every layer. Pure: no game state.
]]--

local util = {}

-- A deep copy of `v`: tables all the way down, anything else as is.
function util.copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = util.copy(x) end
    return out
end

-- The keys of `t` (nil: none), sorted.
function util.keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- The first entry of `list` whose `name` is `name` in any case; nil for none, and for ''.
function util.named(list, name)
    if not name or name == '' then return nil end
    name = name:lower()
    for _, x in ipairs(list) do
        if x.name:lower() == name then return x end
    end
end

function util.clamp(v, min, max) return math.min(math.max(v, min), max) end

return util
