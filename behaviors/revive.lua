--[[
    Raise fallen party and alliance members, and tracked players, with the best
    raise you have. One just raised is left a minute to accept before being
    raised again.
]]--

local can = require('core.can')
local settings = require('core.settings')
local util = require('core.util')

local RAISE_WAIT = 60

return function (g, cat, cfg, mem)
    mem.raised = mem.raised or {}
    local raises = settings.enabled(cat, cfg, 'revive')
    table.sort(raises, util.by_level)  -- Arise, Raise III, II, I
    for _, u in ipairs(g.units) do
        if u.alive then
            mem.raised[u.sid] = nil
        elseif u.kind ~= 'self' and g.now - (mem.raised[u.sid] or -math.huge) > RAISE_WAIT then
            for _, a in ipairs(raises) do
                if can.reach(a, u) and can.use(a, g) then
                    return { action = a, target = u, why = u.name,
                             sent = function (now) mem.raised[u.sid] = now end }
                end
            end
        end
    end
end
