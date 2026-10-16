--[[
    Debuff removal. For each member carrying something a removal clears, the most
    specific remover first: a targeted -na spell, then Erase (strips any one
    erasable status), then Esuna (an area cast on you, reaching those near you),
    then an item on you (Echo Drops, Remedy...; opt-in, they cost gil). A remover
    only ever on you with no area (Chakra, items) clears only your own.
]]--

local can = require('core.can')
local settings = require('core.settings')

local ESUNA_RADIUS = 10  -- yalms around you

local function rank(a)
    if a.kind == 'item' then return 3 end
    if can.self_only(a) then return 2 end
    return #a.removes > 6 and 1 or 0
end

local function clears(a, u)
    for _, id in ipairs(a.removes) do if u.buffs[id] then return true end end
    return false
end

return function (g, cat, cfg)
    local removers = settings.enabled(cat, cfg, 'remove')
    table.sort(removers, function (a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    for _, u in ipairs(g.units) do
        if u.alive and u.in_zone then
            for _, a in ipairs(removers) do
                if clears(a, u) and can.use(a, g) then
                    if can.self_only(a) then
                        if u.kind == 'self' and a.area == 0 then
                            return { action = a, why = u.name }
                        elseif a.area > 0 and (u.dist or math.huge) <= ESUNA_RADIUS then
                            return { action = a, why = ('%s near you'):format(u.name) }
                        end
                    elseif can.reach(a, u) then
                        return { action = a, target = u, why = u.name }
                    end
                end
            end
        end
    end
end
