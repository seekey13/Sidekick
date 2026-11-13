--[[
    Weather matching: a buff row whose spells carry an element (RDM's enspells,
    SCH's storms) can follow the sky instead of a fixed pick. With its Match on
    (rows[key].match), the row's action is the tier whose DAT element matches the
    sky, and its own pick is only the fallback for when none does.

    It is worked out from the snapshot each decision, never written into the
    settings: the pick you chose stays yours, nothing saves as the weather turns,
    and the Buffs list shows what it matched and why.

    The sky, by each family's `match` (core/knowledge.lua):
      'weather'  the zone's weather alone (storms): a storm is what the row casts,
                 so the storm on you would only feed its last cast back to it.
                 No elemental weather, no match. On LandSandBoat a storm of the
                 zone's single weather makes it double for its target, double
                 weather of its element outlasts it, and any other storm
                 replaces the zone's weather (battleutils GetWeather), so the
                 matching storm is the one that can't cost the sky anything.
      'element'  the element your weather and the day favor most (enspells), by
                 LandSandBoat's enspell damage (CalculateEnspellDamage): your
                 weather's element +10%, +25% double, -10% / -25% for the
                 element it beats; the day's +10%, -10% for the one it beats.
                 Your weather is the zone's under a storm on you, as above. So
                 Hot Spell on Watersday is Enwater (+10) over Enfire (+10 -10),
                 while Heat Wave keeps Enfire (+25 -10). A tie goes to the
                 weather. Light and Dark have no enspell, so Lightsday under
                 clear skies or Auroras falls through to the fallback.
                 A storm on you that lapses turns the row to the day's enspell
                 until it's recast, and back: two casts each time, left as is.

    Elements are the DAT's: 0 Fire, 1 Ice, 2 Wind, 3 Earth, 4 Thunder, 5 Water,
    6 Light, 7 Dark. Pure: tests drive it from fake snapshots.
]]--

local sky = {}

-- Weather id -> element, two ids each (single, double): 4/5 Hot Spell .. 18/19 Gloom.
-- 0-3 (Clear, Sunshine, Clouds, Fog) are no element.
local WEATHER = { [2] = 0, [3] = 5, [4] = 3, [5] = 2, [6] = 1, [7] = 4, [8] = 6, [9] = 7 }

-- Vana'diel day (0 Firesday .. 7 Darksday) -> element.
local DAY = { [0] = 0, [1] = 3, [2] = 5, [3] = 2, [4] = 1, [5] = 4, [6] = 6, [7] = 7 }

-- Element -> its single weather id (4 Hot Spell .. 18 Gloom); its double is one more.
local SINGLE = {}
for i, e in pairs(WEATHER) do SINGLE[e] = i * 2 end

-- Element -> the one strong against it, whose day and weather cut its damage: Water over Fire, Fire over Ice ...
local BANE = { [0] = 5, [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 7, [7] = 6 }

-- Storm statuses, in element order: 178 Firestorm .. 185 Voidstorm, and the II's at 589.
local STORMS = { 178, 589 }

-- The element of weather id `w`, nil for none.
function sky.weather(w) return w and WEATHER[math.floor(w / 2)] end

-- Your weather id under a storm of element `storm` on you (nil: the zone's `w`), as
-- LandSandBoat's GetWeather: a storm of the zone's single weather doubles it, the
-- zone's double of its element outlasts it, and any other storm replaces it.
function sky.yours(w, storm)
    if not storm then return w end
    local single = SINGLE[storm]
    if w == single then return single + 1 end
    if w == single + 1 then return w end
    return single
end

-- What weather id `w` and day `d` add to element `e`'s damage, in percent (an
-- enspell's, CalculateEnspellDamage: each applies one hit in three, or always with its obi).
function sky.bonus(e, w, d)
    local we, de, n = sky.weather(w), sky.day(d), 0
    local strong = w and w % 2 == 1 and 25 or 10
    if we == e then n = n + strong elseif we and BANE[e] == we then n = n - strong end
    if de == e then n = n + 10 elseif de and BANE[e] == de then n = n - 10 end
    return n
end

-- The element of day `d`, nil for unknown.
function sky.day(d) return d and DAY[d] end

-- The element of a storm in `buffs` ({ [status id] = true }), nil for none.
function sky.storm(buffs)
    for _, first in ipairs(STORMS) do
        for e = 0, 7 do
            if buffs[first + e] then return e end
        end
    end
end

-- The elements `rule` reads off snapshot `g`, best first, each with why: { { element, 'weather' }, ... }.
function sky.wants(rule, g)
    local out = {}
    local function add(e, why) if e then out[#out + 1] = { e, why } end end
    if rule == 'weather' then
        add(sky.weather(g.weather), 'weather')
    elseif rule == 'element' then
        -- Only the weather's and the day's elements can come out ahead; either, only when it does.
        local storm = sky.storm(g.me and g.me.buffs or {})
        local w = sky.yours(g.weather, storm)
        local we, de = sky.weather(w), sky.day(g.day)
        local wb, db = we and sky.bonus(we, w, g.day) or 0, de and sky.bonus(de, w, g.day) or 0
        if wb > 0 and wb >= db then add(we, storm and 'storm' or 'weather') end
        if db > 0 and de ~= we then add(de, 'day') end
        if wb > 0 and wb < db then add(we, storm and 'storm' or 'weather') end
    end
    return out
end

-- Whether a row of `acts` can match the sky.
function sky.can(acts)
    for _, a in ipairs(acts) do
        if a.match and a.element then return true end
    end
    return false
end

-- With `row`'s Match on, the name of the tier of `acts` the sky matches (the highest
-- level one of the best element it has), and why ('storm', 'weather', 'day'); nil when
-- it's off or nothing matches, and the row's pick goes. Only what the catalog holds: tiers your
-- level and job have, so a level 50 RDM in fire weather gets Enfire, not Enfire II.
function sky.pick(row, acts, g)
    if not (row.match and sky.can(acts)) then return nil end
    local rule = acts[1].match
    for _, want in ipairs(sky.wants(rule, g)) do
        local best
        for _, a in ipairs(acts) do
            if a.element == want[1] and a.match == rule and (not best or (a.level or 0) > (best.level or 0)) then best = a end
        end
        if best then return best.name, want[2] end
    end
end

return sky
