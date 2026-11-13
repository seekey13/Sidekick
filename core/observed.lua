--[[
    What your own heals turned out to do, from packets (core/packets.lua):
      - learned potency: the HP a heal really restores, so a leveling character
        with low MND isn't scored at the table's caps,
      - your Regens still ticking, so the HP on its way isn't cured twice.
    Healing says at send time what it expects (observed.sent); core/game.lua puts
    the results in the snapshot, so the engine still decides from it alone.
]]--

local observed = {}

observed.TICK = 3  -- seconds between Regen ticks
local WAIT = 16       -- seconds a heal sent may take to land (cast, pet wind-up); then a stale guess

observed.learned = {}  -- ['ma4'] = base HP (no boosts), this session only
local expect = {}      -- ['ma4'] = { need = { [sid] = HP missing }, mult, at, per_tick, seconds }
local hots = {}        -- [sid] = { ends, per_tick }

-- The key a heal's results come back under from core/packets.lua: kind and catalog
-- id (an ability's is its packet id + 512). A jug pet's move sends its mob skill id.
function observed.key(a) return a.kind .. (a.mob_skill and a.mob_skill + 512 or a.id) end

function observed.sent(key, e) expect[key] = e end

-- What the heal sent as `key` expects, while it can still be landing.
local function expected(key, now)
    local e = expect[key]
    return e and now - e.at <= WAIT and e or nil
end

-- A heal of yours (or your pet's) restored `amount` on sid. A reading capped by
-- the target's max HP says nothing about potency; the rest feed an average.
-- `missing`: HP sid is missing as it lands, when the client shows it. Someone
-- else's cure or a Regen tick may have topped them up since the send, capping
-- the heal below what was missing then. The client may show the HP before this
-- heal or after it: either way the lower of the two only throws more readings
-- out, never lets a capped one in. A top-up the client hasn't shown yet (another
-- healer's, its HP update still on the way) still gets through, as before.
function observed.healed(key, sid, amount, now, missing)
    local e = expected(key, now)
    local need = e and e.need[sid]
    if need and missing then need = math.min(need, missing) end
    if not need or amount <= 0 or amount >= need then return end
    local r, old = amount / e.mult, observed.learned[key]
    observed.learned[key] = old and (0.7 * old + 0.3 * r) or r
end

-- A spell of yours gave sid a status: if it was a Regen healing sent, it ticks from now.
function observed.landed(key, sid, now)
    local e = expected(key, now)
    if e and e.per_tick then hots[sid] = { ends = now + e.seconds, per_tick = e.per_tick } end
end

-- The action `key` resolved: its expectation is spent, so a later cast by hand
-- isn't read against HP missing back then.
function observed.done(key) expect[key] = nil end

-- HP still to come from your Regen on sid: 0 on its last tick, or past the table's
-- duration while the status holds (gear stretched it); nil when the Regen there
-- isn't yours. `up`: sid shows a Regen. Gone after its time, yours is over.
function observed.hot(sid, now, up)
    local h = hots[sid]
    if h and not up and now >= h.ends then hots[sid] = nil end
    if not (h and up) then return nil end
    return h.per_tick * math.max(0, math.floor((h.ends - now) / observed.TICK))
end

function observed.clear() hots, expect = {}, {} end

return observed
