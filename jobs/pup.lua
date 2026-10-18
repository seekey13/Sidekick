--[[
    Puppetmaster: maneuvers (v2's lib/actions/pet.lua). The eight elemental
    maneuvers go on you, not the automaton (it reads them off you, as retail),
    share one recast and stand three at once; a new one pushes the oldest out.
    Under Maneuvers (cfg.maneuver) each of the three slots picks one by name
    ('' for none; the same one twice keeps two up), kept up while an automaton
    is out, main or sub (this server lets a PUP subjob call one). None goes
    under Overload (it would only add to it), and none while you're Invisible.
]]--

local can = require('core.can')
local run = require('jobs.run')

local pup = {}

pup.SLOTS = 3

local INVISIBLE = 69

-- The settings path of slot `i`: 'maneuver.slot_1'.
function pup.path(i) return ('maneuver.slot_%d'):format(i) end

-- Your maneuvers by name.
function pup.actions(cat)
    local out = {}
    for _, a in ipairs(cat) do
        if a.role == 'maneuver' then out[a.name] = a end
    end
    return out
end

-- The maneuvers picked, as catalog records in slot order: a slot with none (or
-- one you lack) is skipped.
function pup.picked(cfg, mine)
    local out = {}
    for i = 1, pup.SLOTS do
        local a = mine[cfg.maneuver['slot_' .. i]]
        if a then out[#out + 1] = a end
    end
    return out
end

function pup.want(g, cat, cfg)
    if not (g.pet and g.pet.hpp > 0) or g.me.buffs[INVISIBLE] then return nil end
    -- Counted as runes are: the same maneuver twice wants two up.
    local missing = run.missing(pup.picked(cfg, pup.actions(cat)), g.me)
    if missing and can.use(missing, g) then return { action = missing, why = g.pet.name } end
end

return pup
