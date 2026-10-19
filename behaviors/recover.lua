--[[
    Get MP and TP back with the recovery rows that are on: under your MP line,
    Convert, Aspir, Sublimation, Chivalry (once you have recover.min_tp TP)...;
    under it for a member, Devotion on the lowest; under your TP line in combat,
    Meditate or Reverse Flourish.
    Highest priority first, then the best tier. Whatever costs HP waits while
    you're under your danger line. Radial Arcana spends the luopan, so
    jobs/geo.lua says when and how.
]]--

local can = require('core.can')
local catalog = require('core.catalog')
local geo = require('jobs.geo')
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

return function (g, cat, cfg, mem)
    local r = cfg.recover
    for _, a in ipairs(settings.enabled(cat, cfg, 'recover', catalog.by_priority)) do
        if a.luopan then
            local intent = geo.arcana(a, g, cat, cfg, mem)
            if intent then return intent end
        elseif can.use(a, g) and can.spare_hp(a, g, cfg) then
            if a.gives == 'tp' then
                if g.combat and g.me.tp < r.tp then return { action = a, why = ('TP %d'):format(g.me.tp) } end
            elseif can.self_only(a) or can.at_enemy(a) then
                if g.me.mpp < r.mp and (not a.spends_tp or g.me.tp >= r.min_tp) then
                    return { action = a, why = ('MP %d%%'):format(g.me.mpp) }
                end
            else
                local u = drained(a, g, r.mp)
                if u then return { action = a, target = u, why = ('%s MP %d%%'):format(u.name, u.mpp) } end
            end
        end
    end
end
