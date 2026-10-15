--[[
    What your own heals turned out to do, from packets (core/packets.lua):
      - learned potency: the HP a heal really restores, so a leveling character
        with low MND isn't scored at the table's caps,
      - your Regens still ticking, so the HP on its way isn't cured twice.
    Healing says at send time what it expects (observed.sent); core/game.lua puts
    the results in the snapshot, so the engine still decides from it alone.
]]--

local observed = {}

local TICK = 3  -- seconds between Regen ticks

observed.learned = {}  -- ['ma4'] = base HP (no boosts), this session only
local expect = {}      -- ['ma4'] = { need = { [sid] = HP missing }, mult, per_tick, seconds }
local hots = {}        -- [sid] = { ends, per_tick }

function observed.sent(key, e) expect[key] = e end

-- A heal of yours (or your pet's) restored `amount` on sid. A reading capped by
-- the target's max HP says nothing about potency; the rest feed an average.
function observed.healed(key, sid, amount)
    local e = expect[key]
    local need = e and e.need[sid]
    if not need or amount <= 0 or amount >= need then return end
    local r, old = amount / e.mult, observed.learned[key]
    observed.learned[key] = old and (0.7 * old + 0.3 * r) or r
end

-- A spell of yours gave sid a status: if it was a Regen healing sent, it ticks from now.
function observed.landed(key, sid, now)
    local e = expect[key]
    if e and e.per_tick then hots[sid] = { ends = now + e.seconds, per_tick = e.per_tick } end
end

-- HP still to come from your Regen on sid.
function observed.hot(sid, now)
    local h = hots[sid]
    if not h then return 0 end
    if h.ends <= now then hots[sid] = nil; return 0 end
    return h.per_tick * math.floor((h.ends - now) / TICK)
end

function observed.clear() hots = {} end

return observed
