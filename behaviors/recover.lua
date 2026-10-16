--[[
    Get MP and TP back with the recovery rows that are on: under your MP line,
    Convert, Aspir, Sublimation, Chivalry...; under it for a member, Devotion on
    the lowest; under your TP line in combat, Meditate or Reverse Flourish.
    Highest priority first, then the best tier. Whatever costs HP waits while
    you're under your danger line.
]]--

local can = require('core.can')
local settings = require('core.settings')

-- The member under the MP line with the least, that `a` can reach.
local function drained(a, g, line)
    local pick
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and u.uses_mp and u.mpp < line and can.reach(a, u) and (not pick or u.mpp < pick.mpp) then
            pick = u
        end
    end
    return pick
end

return function (g, cat, cfg)
    local r = cfg.recover
    local list = settings.enabled(cat, cfg, 'recover')
    table.sort(list, function (a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return (a.level or 0) > (b.level or 0)
    end)
    for _, a in ipairs(list) do
        if can.use(a, g) and can.spare_hp(a, g, cfg) then
            if a.gives == 'tp' then
                if g.combat and g.me.tp < r.tp then return { action = a, why = ('TP %d'):format(g.me.tp) } end
            elseif can.self_only(a) or can.at_enemy(a) then
                if g.me.mpp < r.mp then return { action = a, why = ('MP %d%%'):format(g.me.mpp) } end
            else
                local u = drained(a, g, r.mp)
                if u then return { action = a, target = u, why = ('%s MP %d%%'):format(u.name, u.mpp) } end
            end
        end
    end
end
