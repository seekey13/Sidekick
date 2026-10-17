--[[
    Keep the buffs you turned on up on the targets you picked. A row's action is
    its picked tier, else the best tier you can cast now; a pick_one group
    (bar-elements, enspells...) needs a pick. Self-only buffs go on you; an area
    self-cast (Protectra) is recast when anyone in your party near you lacks it.
    A row's targets are party slots and tracked players' names. Statuses that
    can't be read (Boost) are recast whenever they're off recast.
    Songs, rolls and the like belong to job modules, not here.
]]--

local can = require('core.can')
local settings = require('core.settings')

local INVISIBLE = 69
local AREA_RADIUS = 10  -- yalms around you

local function lacks(a, u)
    if not a.status then return true end
    for _, id in ipairs(a.status) do if u.buffs[id] then return false end end
    return true
end

-- Each row's action, best tier first, highest priority rows first.
local function chosen(cat, cfg, g)
    local by_key, keys = {}, {}
    for _, a in ipairs(settings.enabled(cat, cfg, 'buff')) do
        local key = settings.key(a)
        if not by_key[key] then by_key[key] = {}; keys[#keys + 1] = key end
        table.insert(by_key[key], a)
    end
    local out = {}
    for _, key in ipairs(keys) do
        local list = by_key[key]
        local row = settings.row(cfg, list[1])
        table.sort(list, function (a, b) return (a.level or 0) > (b.level or 0) end)
        local pick
        for _, a in ipairs(list) do
            if row.pick == a.name or (not row.pick and not a.pick_one and can.use(a, g)) then pick = a; break end
        end
        if pick then out[#out + 1] = { action = pick, targets = row.targets or { [0] = true } } end
    end
    table.sort(out, function (x, y) return x.action.priority > y.action.priority end)
    return out
end

return function (g, cat, cfg)
    local invisible = g.me.buffs[INVISIBLE]
    for _, c in ipairs(chosen(cat, cfg, g)) do
        local a = c.action
        if (a.travel or not invisible) and can.use(a, g) then
            if can.self_only(a) then
                local around = a.area > 0 and AREA_RADIUS or 0
                for _, u in ipairs(g.units) do
                    if u.kind == 'self' or (can.in_party(u) and u.alive and u.in_zone and (u.dist or math.huge) <= around) then
                        if lacks(a, u) then return { action = a, why = ('%s lacks it'):format(u.name) } end
                    end
                end
            else
                for _, u in ipairs(g.units) do
                    if c.targets[u.slot or u.name] and can.reach(a, u) and lacks(a, u) then
                        return { action = a, target = u, why = u.name }
                    end
                end
            end
        end
    end
end
