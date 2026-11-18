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
-- Doom shows by its counter (core/packets.lua): the server ticks effects every 3 s, zone-wide
-- (zone_entities.cpp), so its first count comes 3 to 6 s after it lands, then one every 3 s.
-- Doom lasts this long past its gain or its last count: one that ended with nothing seen to
-- end it (out of range, a removal that names it to no one) draws Cursna no longer. It covers
-- the first count and one count lost.
buffs.DOOM_HOLD = 8
-- A player's Charm wears off with word to them alone (status_effect_container.cpp), so it ends
-- when their update says (core/packets.lua: 0x00D), else after the longest a mob's charm lasts
-- (scripts/actions/mobskills/charm.lua: 180 s): one that ended out of sight leaves them out of
-- support no longer.
buffs.CHARM_HOLD = 180

local DOOM = 15
local CHARM = {}
for _, id in ipairs(require('core.status').CHARM) do CHARM[id] = true end
local store = {}  -- [server id] = { [status id] = expires at (os.clock seconds) }

-- `stacks`: several of it can stand at once (your songs: two Marches are one id),
-- so it lasts as long as the one that wears last.
function buffs.gain(sid, status, now, seconds, stacks)
    store[sid] = store[sid] or {}
    if status == DOOM then seconds = buffs.DOOM_HOLD elseif CHARM[status] then seconds = buffs.CHARM_HOLD end
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
