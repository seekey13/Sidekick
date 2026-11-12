--[[
    Statuses on units the client keeps no readable list for (trusts, your pet,
    the alliance's other parties, tracked players), pieced together from packets
    by core/packets.lua. You and your party's players are read from memory
    instead (core/game.lua).
]]--

local buffs = {}

-- Wear-off packets go missing (out of range, zoning), so every status expires on
-- its own: after its known duration, else after this long.
buffs.DEFAULT_SECONDS = 300
-- Doom ends by then however it came (taken off, or its count runs out and kills):
-- one whose end went unseen draws Cursna no longer.
buffs.DOOM_SECONDS = 45

local DOOM = 15
local store = {}  -- [server id] = { [status id] = expires at (os.clock seconds) }

-- `stacks`: several of it can stand at once (your songs: two Marches are one id),
-- so it lasts as long as the one that wears last.
function buffs.gain(sid, status, now, seconds, stacks)
    store[sid] = store[sid] or {}
    if status == DOOM then seconds = math.min(seconds or buffs.DOOM_SECONDS, buffs.DOOM_SECONDS) end
    local expires = now + (seconds or buffs.DEFAULT_SECONDS)
    store[sid][status] = stacks and math.max(store[sid][status] or expires, expires) or expires
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
