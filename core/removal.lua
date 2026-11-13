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
        remover may still try them. Not Doom: Cursna can fail on it. On a unit whose
        statuses come from packets, Doom is held while its counter runs (core/buffs.lua),
        so a miss shows by the count going on; yours and your party's show in the client.
    core/game.lua puts the marks still holding in the snapshot (unit.futile).
]]--

local removal = {}

removal.HOLD = 60  -- seconds a no-effect mark holds while the unit still shows the status

local DOOM = 15
local marks = {}  -- [sid] = { [remover's observed.key] = { [status id] = marked at } }
local seen = {}   -- [sid] = its statuses at the last read (removal.futile's `shown`)

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

function removal.clear() marks, seen = {}, {} end

return removal
