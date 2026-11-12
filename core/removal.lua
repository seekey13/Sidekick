--[[
    What your removers' results say about the statuses on their targets, from
    packets (core/packets.lua), when the status reading on that unit can't be
    taken at its word:
      - no effect: your remover found nothing to clear there. Someone else took it
        off and the client shows it a while yet, or it's one that remover can't take.
        Of what it clears, those the unit showed at the last read (one that landed
        since is new) are marked futile for that remover on that unit;
        behaviors/remove.lua doesn't send that remover for them until the unit is seen
        without them (a fresh one is cleared again), or HOLD seconds pass. Another
        remover may still try them. Not Doom: Cursna can fail on it.
      - Doom misses: your Cursna that landed on a Doom it didn't take off. On a
        unit whose statuses come from packets, a Doom that went unseen (removed by
        another, the unit's death) would draw Cursna until it expired
        (buffs.DOOM_SECONDS), so after cfg.remove.doom_retries + 1 misses in a row
        it's taken as gone (core/packets.lua). Your party's and your own Doom are read
        from the client, so they're tried while they show.
    core/game.lua puts the marks still holding in the snapshot (unit.futile).
]]--

local removal = {}

removal.HOLD = 60         -- seconds a no-effect mark holds while the unit still shows the status
removal.DOOM_MISSES = 6   -- Cursna misses in a row on one Doom before it's taken as gone, by default
removal.MAX_RETRIES = 10  -- cfg.remove.doom_retries' top

local DOOM = 15
local marks = {}   -- [sid] = { [remover's observed.key] = { [status id] = marked at } }
local misses = {}  -- [sid] = Cursna misses on the Doom there now
local seen = {}    -- [sid] = its statuses at the last read (removal.futile's `shown`)

-- cfg.remove.doom_retries as a whole number in 0..MAX_RETRIES; the default for one missing or not a number.
function removal.retries(v)
    v = tonumber(v)
    if not v or v ~= v then return removal.DOOM_MISSES - 1 end
    return math.min(math.max(math.floor(v), 0), removal.MAX_RETRIES)
end

-- Your remover `key` (observed.key) had no effect on sid: the statuses `ids` it
-- clears, but Doom, are futile for it there. Only those sid showed at the last
-- read: one that lands with the no effect, its icon not read yet, is new.
function removal.no_effect(sid, key, ids, now)
    local shown = seen[sid]
    if not shown then return end
    for _, id in ipairs(ids) do
        if id ~= DOOM and shown[id] then
            marks[sid] = marks[sid] or {}
            marks[sid][key] = marks[sid][key] or {}
            marks[sid][key][id] = now
        end
    end
end

-- { [remover's observed.key] = { [status id] = true } }: those marked on sid that it
-- still shows (`shown`, its statuses read now). A mark on a status it no longer
-- shows, or past HOLD, goes.
function removal.futile(sid, shown, now)
    seen[sid] = shown
    local mine, out = marks[sid], {}
    if not mine then return out end
    for key, ids in pairs(mine) do
        for id, at in pairs(ids) do
            if shown[id] and now - at <= removal.HOLD then
                out[key] = out[key] or {}
                out[key][id] = true
            else
                ids[id] = nil
            end
        end
        if next(ids) == nil then mine[key] = nil end
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
