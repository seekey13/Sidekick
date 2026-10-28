--[[
    Wake sleeping members with a heal that wakes (Cure, Curaga, waltzes...): the
    healing rows that are on. Two or more asleep together get an area heal aimed
    to cover the most; otherwise the cheapest heal that reaches the first sleeper.
    The focus member is woken first. An area heal wakes its target's party
    only: you or a member yours, so the alliance's other parties and tracked
    players need one aimed at them.
]]--

local can = require('core.can')
local settings = require('core.settings')
local status = require('core.status')

local function cost(a, g) return (a.mp or 0) + can.tp(a, g) end

-- Sleepers you can help, the focus member first.
local function sleepers(g, cfg)
    local out = {}
    local focus = cfg.heal.focus:lower()
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and u.alive and u.in_zone and can.any(u.buffs, status.SLEEP) then
            if focus ~= '' and u.name:lower() == focus then table.insert(out, 1, u) else out[#out + 1] = u end
        end
    end
    return out
end

-- Where `a` goes to land on `u`: aimed at them, or (an area cast on you) from
-- where you stand; false when it can't.
local function aim(a, u, g)
    if can.self_only(a) then return a.area > 0 and can.in_party(u) and can.dist(g.me, u) <= can.yalms(a.area) and g.me end
    return can.reach(a, u) and u
end

-- How many sleepers an area heal centred on `centre` covers: those of its party near it.
local function covered(list, centre, radius)
    local n = 0
    for _, u in ipairs(list) do if can.together(centre, u) and can.dist(centre, u) <= radius then n = n + 1 end end
    return n
end

return function (g, cat, cfg)
    local list = sleepers(g, cfg)
    if not list[1] then return nil end
    local heals = {}
    for _, a in ipairs(settings.enabled(cat, cfg, 'heal')) do
        if a.wakes and not a.pet and not can.at_enemy(a) and can.use(a, g) then heals[#heals + 1] = a end
    end
    table.sort(heals, function (a, b) return cost(a, g) < cost(b, g) end)

    if list[2] then
        local best, most
        for _, a in ipairs(heals) do
            if a.area > 0 then
                local radius = can.yalms(a.area)
                for _, u in ipairs(list) do
                    local c = aim(a, u, g)
                    local n = c and covered(list, c, radius) or 0
                    if n >= 2 and (not most or n > most) then best, most = { action = a, centre = c }, n end
                end
            end
        end
        if best then
            local a, c = best.action, best.centre
            return { action = a, target = c ~= g.me and c or nil, why = ('%d asleep'):format(most) }
        end
    end

    for _, u in ipairs(list) do
        for _, a in ipairs(heals) do
            local c = aim(a, u, g)
            if c then return { action = a, target = c ~= g.me and c or nil, why = ('%s asleep'):format(u.name) } end
        end
    end
end
