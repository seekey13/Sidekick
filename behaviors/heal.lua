--[[
    Single-target healing, with the critical-HP boosts that go with it.
      1. Someone under the critical threshold: a boost for the cure about to land
         (Divine Seal, Contradance) or an aimed save (Martyr).
      2. Your focus target, under its own threshold.
      3. Everyone else, lowest HP first.
    Each cure is sized to the HP missing: the biggest that doesn't overheal, else
    the smallest. A member out of reach is skipped, never the end of the tick.
]]--

local can = require('core.can')
local settings = require('core.settings')

-- A cure this close to ready is worth waiting for: slower actions (buffs, raises) hold.
local HOLD_MAX = 15

local function potency(a, s)
    local pct = (a.tp or 0) > 0 and s.waltz_potency or s.cure_potency
    return (a.potency or 0) * (1 + (pct or 0) / 100)
end

-- The cure for `u`: usable and in reach, sized to the HP missing.
local function cure_for(heals, u, g, s)
    local fits, smallest
    local deficit = u.max_hp and (u.max_hp - u.hp) or 0
    for _, a in ipairs(heals) do  -- strongest first
        if can.reach(a, u) and can.use(a, g) then
            if deficit <= 0 then return a end
            local p = potency(a, s)
            if p > 0 and p <= deficit then fits = fits or a end
            smallest = a
        end
    end
    return fits or smallest
end

local function focus_of(g, s)
    if s.focus == '' then return nil end
    for _, u in ipairs(g.units) do if u.name:lower() == s.focus:lower() then return u end end
end

return function (g, cat, cfg)
    local s = cfg.heal
    local heals = settings.enabled(cat, cfg, 'heal')
    table.sort(heals, function (a, b)
        if potency(a, s) ~= potency(b, s) then return potency(a, s) > potency(b, s) end
        return (a.mp or 0) > (b.mp or 0)
    end)

    -- Who needs a cure, focus first then lowest HP.
    local focus = focus_of(g, s)
    local hurt = {}
    for _, u in ipairs(g.units) do
        local limit = u == focus and s.focus_threshold or s.threshold
        if u.alive and u.in_zone and u.hpp < limit then hurt[#hurt + 1] = u end
    end
    table.sort(hurt, function (a, b)
        if (a == focus) ~= (b == focus) then return a == focus end
        return a.hpp < b.hpp
    end)

    -- 1. Critical HP.
    for _, u in ipairs(hurt) do
        if u.hpp < s.critical then
            local cure = cure_for(heals, u, g, s)
            for _, e in ipairs(settings.enabled(cat, cfg, 'emergency')) do
                if can.use(e, g) then
                    if can.self_only(e) and cure then
                        return { action = e, why = ('boost for %s (%d%%)'):format(u.name, u.hpp) }
                    elseif not can.self_only(e) and u.kind ~= 'self' and can.reach(e, u) then
                        return { action = e, target = u, why = ('%s at %d%%'):format(u.name, u.hpp) }
                    end
                end
            end
        end
    end

    -- 2-3. Cures.
    for _, u in ipairs(hurt) do
        local cure = cure_for(heals, u, g, s)
        if cure then
            return { action = cure, target = u, why = ('%s at %d%%'):format(u.name, u.hpp) }
        end
    end

    -- Nothing castable, but a cure for someone in reach is nearly off recast: hold.
    for _, u in ipairs(hurt) do
        for _, a in ipairs(heals) do
            local ok, _, wait = can.use(a, g)
            if not ok and wait and wait <= HOLD_MAX and can.reach(a, u) then return { hold = true } end
        end
    end
end
