--[[
    Rest (/heal) for MP once it's under rest.mp: out of combat, not moving (the
    engine's gate), and no behavior busy with a step due soon (mem.busy_until: a
    Corsair's Double-Up), and not with a pet out as a SMN, main or sub (an avatar
    or spirit: the server takes no /heal then). Only once you've stood still and
    nothing was sent for SETTLE seconds: while resting nothing else runs, so a
    moment between things (a follower's short stop, an ammo equip yet to show)
    isn't sat through. You stand at full MP, or when the follow target gets
    further than rest.distance. A /heal on that didn't sit you down goes again
    only after RETRY seconds.
]]--

local follow = require('behaviors.follow')

local RETRY = 5
local SETTLE = 3  -- covers ammo.WAIT
local SMN = 15  -- job id

return function (g, _, cfg, mem)
    local r, me = cfg.rest, g.me
    local leader = follow.leader(g, cfg.follow.target)
    local far = leader and leader.in_zone and (leader.dist or 0) > r.distance
    if g.resting then
        if me.mpp >= 100 then return { command = '/heal off', action = { name = 'Stand' }, why = 'MP full' } end
        if far then return { command = '/heal off', action = { name = 'Stand' }, why = ('%s left'):format(leader.name) } end
        return nil
    end
    if g.combat or far or me.mpp >= r.mp or not me.uses_mp or g.now < (mem.busy_until or -math.huge)
        or g.now - (mem.rested_at or -math.huge) < RETRY or g.pet and (g.main == SMN or g.sub == SMN)
        or g.now - math.max(g.moved_at or -math.huge, mem.sent_at or -math.huge) < SETTLE then
        return nil
    end
    return { command = '/heal on', action = { name = 'Rest' }, why = ('MP %d%%'):format(me.mpp),
             sent = function (now) mem.rested_at = now end }
end
