--[[
    Statuses on units the client keeps no readable list for (trusts and your pet now;
    alliance and tracked targets later), pieced together from packets by core/packets.lua.
    You and your party's players are read from memory instead (core/game.lua).
]]--

local buffs = {}

-- Wear-off packets go missing (out of range, zoning), so every status expires on
-- its own: after its known duration, else after this long.
buffs.DEFAULT_SECONDS = 300

local store = {}  -- [server id] = { [status id] = expires at (os.clock seconds) }

function buffs.gain(sid, status, now, seconds)
    store[sid] = store[sid] or {}
    store[sid][status] = now + (seconds or buffs.DEFAULT_SECONDS)
end

function buffs.lose(sid, status)
    if store[sid] then store[sid][status] = nil end
end

-- { [status id] = true } on sid right now.
function buffs.of(sid, now)
    local out, mine = {}, store[sid]
    for status, expires in pairs(mine or {}) do
        if expires > now then out[status] = true else mine[status] = nil end
    end
    return out
end

-- Everything known about sid: it died or left, and those statuses went silently.
function buffs.forget(sid) store[sid] = nil end

function buffs.clear() store = {} end

return buffs
