--[[
    Picks by slot: a settings section holding one action name per slot, as
    `<prefix>_<n>` ('' for none): Runes (cfg.rune.idle_1), Songs (cfg.song.p3_2)
    and Maneuvers (cfg.maneuver.slot_1).
]]--

local slots = {}

-- The settings path of slot `i`: slots.path('rune', 'idle', 1) is 'rune.idle_1'.
function slots.path(section, prefix, i) return ('%s.%s_%d'):format(section, prefix, i) end

-- The names in slots 1 to `n`.
function slots.names(section, prefix, n)
    local out = {}
    for i = 1, n do out[i] = section[prefix .. '_' .. i] end
    return out
end

-- The catalog's actions of `role`, by name.
function slots.by_name(cat, role)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == role then out[a.name] = a end
    end
    return out
end

-- The actions picked in slots 1 to `n`, in slot order: a slot with none (or one
-- you lack) is skipped, not the end. With `once`, an action picked twice is one.
function slots.picked(section, prefix, by_name, n, once)
    local out, seen = {}, {}
    for i = 1, n do
        local a = by_name[section[prefix .. '_' .. i]]
        if a and not (once and seen[a]) then seen[a] = true; out[#out + 1] = a end
    end
    return out
end

return slots
