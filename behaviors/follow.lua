--[[
    /follow the member named in follow.target once they're further than
    follow.distance. Low in priority, so support goes first; while you move the
    engine waits anyway, so it isn't sent again until you stop. Only your
    party has <p1>-<p5>: the alliance and tracked players are followed by name.
]]--

local can = require('core.can')

local follow = {}

-- The unit named `name` (any case), not you; nil when there's none.
function follow.leader(g, name)
    if name == '' then return nil end
    for _, u in ipairs(g.units) do
        if u.kind ~= 'self' and u.name:lower() == name:lower() then return u end
    end
end

function follow.want(g, _, cfg)
    local f = cfg.follow
    local u = follow.leader(g, f.target)
    if not (u and u.in_zone and u.dist) or u.dist <= f.distance then return nil end
    local who = can.in_party(u) and ('<p%d>'):format(u.slot) or u.name
    return { command = '/follow ' .. who, action = { name = 'Follow' }, target = u,
             why = ('%s %.1fy away'):format(u.name, u.dist) }
end

return follow
