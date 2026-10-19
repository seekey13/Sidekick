--[[
    AFK sleep, as v2's: automation sleeps once no one in your party (you, its
    players and trusts, slots 0-5) has moved and you have been out of combat for
    cfg.afk.minutes, and wakes when you move. A pause, not a stop: automation
    stays running and nothing is saved.

    Only your own movement wakes it, as v2: a pull is no proof you're back, so a
    party that fights while you're away leaves you asleep. One exception: with
    Follow on, the leader getting further than its distance wakes it, so
    following goes on (asleep, nothing would send /follow; v2 then stopped
    following once the game's own /follow was lost).

    Its memory (`st`) is the caller's: when you were last seen active, the
    minutes counted with, and whether asleep. Sidekick3.lua keeps it in the
    engine's memory, so a job change starts a full wait, and drops it on a start
    and while automation is stopped, so a start does too. Changing the minutes
    starts the wait over too, as v2 (a slider dragged down never sleeps at once).
]]--

local follow = require('behaviors.follow')

local afk = {}

afk.MIN, afk.MAX = 1, 60  -- minutes: the slider's range

-- Whether anyone in your party moved: you, or a player or trust the client
-- draws (one out of sight has no position, so never counts).
local function moved(g)
    if g.moving then return true end
    for _, u in ipairs(g.units) do
        if u.slot and u.slot <= 5 and u.moving then return true end
    end
    return false
end

-- Whether automation sleeps now, and the line to print when that just changed.
function afk.update(g, cfg, st)
    if not cfg.afk.on then
        st.still, st.asleep = nil, nil  -- turned on again: a full wait
        return false
    end
    if st.asleep then
        local leaving = not g.moving and cfg.follow.on and follow.want(g, nil, cfg)
        if not (g.moving or leaving) then return true end
        st.still, st.asleep = g.now, nil
        if leaving then return false, ('AFK: %s is leaving. Automation resumed to follow.'):format(leaving.target.name) end
        return false, 'AFK: you moved. Automation resumed.'
    end
    if st.minutes ~= cfg.afk.minutes then st.still, st.minutes = nil, cfg.afk.minutes end
    if not st.still or g.combat or moved(g) then st.still = g.now; return false end
    if g.now - st.still < cfg.afk.minutes * 60 then return false end
    st.asleep = true
    return true, ('AFK: no movement or combat for %d min. Automation asleep: move to wake.'):format(cfg.afk.minutes)
end

-- Seconds until it sleeps; nil while off, asleep or not counting.
function afk.left(g, cfg, st)
    if not (cfg.afk.on and st.still) or st.asleep then return nil end
    return math.max(0, cfg.afk.minutes * 60 - (g.now - st.still))
end

return afk
