--[[
    What your removers' results say about the statuses on their targets, from
    packets (core/packets.lua), when the status reading on that unit can't be
    taken at its word:
      - no effect: your remover found nothing to clear, so what it clears is gone
        (someone else took it off, or it wore off), whatever the unit still shows.
        Those it showed at the last read are marked futile on that unit (one that
        landed since is new); behaviors/remove.lua leaves
        them be until the unit is seen without them (a fresh one is cleared again),
        or HOLD seconds pass. Not Doom: Cursna can fail on it.
      - Doom misses: your Cursna that landed on a Doom it didn't take off. On a
        unit whose statuses come from packets, a Doom that went unseen (its wearing
        off, the unit's death) would draw Cursna until its 300 seconds ran out, so
        after DOOM_MISSES misses in a row it's taken as gone (core/packets.lua). Your
        party's and your own Doom are read from the client, so they're tried while
        they show.
    core/game.lua puts the marks still holding in the snapshot (unit.futile).
]]--

local removal = {}

removal.HOLD = 60         -- seconds a no-effect mark holds while the unit still shows the status
removal.DOOM_MISSES = 3   -- Cursna misses in a row on one Doom before it's taken as gone

removal.MAX_RETRIES = 10 -- cfg.remove.doom_retries' top

local DOOM = 15
local marks = {}   -- [sid] = { [status id] = marked at }
local misses = {}  -- [sid] = Cursna misses on the Doom there now
local seen = {}    -- [sid] = its statuses at the last read (removal.futile's `shown`)

-- cfg.remove.doom_retries as a whole number in 0..MAX_RETRIES; the default for one missing or not a number.
function removal.retries(v)
    v = tonumber(v)
    if not v or v ~= v then return removal.DOOM_MISSES - 1 end
    return math.min(math.max(math.floor(v), 0), removal.MAX_RETRIES)
end

-- Your remover had no effect on sid: the statuses `ids` it clears are gone, but Doom.
-- Only those sid showed at the last read: one that lands with the no effect, its icon
-- not read yet, is new, and cleared.
function removal.no_effect(sid, ids, now)
    local shown = seen[sid]
    if not shown then return end
    for _, id in ipairs(ids) do
        if id ~= DOOM and shown[id] then
            marks[sid] = marks[sid] or {}
            marks[sid][id] = now
        end
    end
end

-- { [status id] = true }: those marked on sid that it still shows (`shown`, its
-- statuses read now). A mark on a status it no longer shows, or past HOLD, goes.
function removal.futile(sid, shown, now)
    seen[sid] = shown
    local mine, out = marks[sid], {}
    if not mine then return out end
    for id, at in pairs(mine) do
        if shown[id] and now - at <= removal.HOLD then out[id] = true else mine[id] = nil end
    end
    if next(mine) == nil then marks[sid] = nil end
    return out
end

-- Your Cursna missed the Doom on sid: the misses on it so far.
function removal.doom_missed(sid)
    misses[sid] = (misses[sid] or 0) + 1
    return misses[sid]
end

-- The Doom on sid is new, or gone: its misses start over.
function removal.doom_reset(sid) misses[sid] = nil end

function removal.clear() marks, misses, seen = {}, {}, {} end

return removal
