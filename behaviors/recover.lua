--[[
    Get MP and TP back with the recovery rows that are on: under your MP line,
    Convert, Aspir, Sublimation, Chivalry (once you have recover.min_tp TP)...;
    under it for a member, Devotion on the lowest, or only on recover.target when
    one is named; under your TP line in combat, Meditate or Reverse Flourish.
    Highest priority first, then the best tier. Whatever costs HP waits while
    you're under your danger line. A row with its own `decide` (Radial Arcana,
    which spends the luopan) says itself when and what to send.
]]--

local can = require('core.can')
local settings = require('core.settings')
local util = require('core.util')

-- The member under the MP line with the least, that `a` can reach: only `only` when
-- it names one, in any case, as focus and Entrust are ('' for anyone).
local function drained(a, g, line, only)
    only = only:lower()
    local pick
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and (only == '' or u.name:lower() == only) and u.uses_mp and u.mpp < line and can.reach(a, u)
            and (not pick or u.mpp < pick.mpp) then
            pick = u
        end
    end
    return pick
end

return function (g, cat, cfg, mem)
    local r = cfg.recover
    local list = settings.enabled(cat, cfg, 'recover')
    table.sort(list, util.by_priority)
    for _, a in ipairs(list) do
        if a.decide then
            local intent = a.decide(a, g, cat, cfg, mem)
            if intent then return intent end
        elseif can.use(a, g) and can.spare_hp(a, g, cfg) then
            if a.gives == 'tp' then
                if g.combat and g.me.tp < r.tp then return { action = a, why = ('TP %d'):format(g.me.tp) } end
            elseif can.self_only(a) or can.at_enemy(a) then
                if g.me.mpp < r.mp and (not a.spends_tp or g.me.tp >= r.min_tp) then
                    return { action = a, why = ('MP %d%%'):format(g.me.mpp) }
                end
            else
                local u = drained(a, g, r.mp, r.target or '')
                if u then return { action = a, target = u, why = ('%s MP %d%%'):format(u.name, u.mpp) } end
            end
        end
    end
end
