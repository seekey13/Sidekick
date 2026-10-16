--[[
    Rest (/heal) for MP once nothing else has happened for rest.delay seconds:
    out of combat, not moving, nothing sent and MP not full. While resting
    nothing else runs; you stand at full MP, or when the follow target gets
    further than rest.distance.
]]--

local follow = require('behaviors.follow')

return function (g, _, cfg, mem)
    local r, me = cfg.rest, g.me
    local leader = follow.leader(g, cfg.follow.target)
    local far = leader and leader.in_zone and (leader.dist or 0) > r.distance
    if g.resting then
        if me.mpp >= 100 then return { command = '/heal off', action = { name = 'Stand' }, why = 'MP full' } end
        if far then return { command = '/heal off', action = { name = 'Stand' }, why = ('%s left'):format(leader.name) } end
        return nil
    end
    if g.combat or far or me.mpp >= 100 or not me.uses_mp then return nil end
    local quiet = math.max(g.moved_at or -math.huge, mem.sent_at or -math.huge, g.finished or -math.huge)
    if g.now - quiet < r.delay then return nil end
    return { command = '/heal on', action = { name = 'Rest' }, why = ('MP %d%%'):format(me.mpp) }
end
