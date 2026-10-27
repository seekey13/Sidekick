--[[
    Scholar: stratagems, sharing one charge pool, recast timer 231 (core/charges.lua).
    Each changes the next spell, so it is a modifier the engine fires just before
    the spell a buff row turned it on for; these say which spells each fits.
    Enlightenment opens the Addendum spells without the Addendum (core/catalog.lua).
]]--

local charges = require('core.charges')

local sch = {}

sch.JOB = 20
-- Stratagem charges by SCH level (CatsEyeXI, from v2): { level, charges, seconds per charge }.
sch.POOL = charges.pool({ job = sch.JOB, kind = 'ja', recast = 231,
    tiers = { { 75, 5, 48 }, { 65, 4, 60 }, { 50, 3, 80 }, { 30, 2, 120 }, { 10, 1, 240 } } })

-- Whether a buff row may spend stratagem action `a` (a modifier, an Addendum):
-- with heal.reserve on, the last charge is kept for healing's Accession and Rapture.
function sch.spare(a, g, cfg)
    if not (cfg.heal.reserve and sch.POOL:spends(a)) then return true end
    return g.stratagems == nil or g.stratagems > 1
end

local WHITE, BLACK = 1, 2  -- spell types
local ENHANCING = 34       -- spell skill

function sch.white(a) return a.kind == 'ma' and a.type == WHITE end
function sch.black(a) return a.kind == 'ma' and a.type == BLACK end
-- Perpetuance lengthens white enhancing magic only (not Blaze Spikes, which is black).
function sch.enhancing(a) return sch.white(a) and a.skill == ENHANCING end

-- What Accession spreads, as the server flags it (spell_list AOE 4, v2's list):
-- the buffs among it here, by family or pick-one group. Not Raise, Reraise, Haste,
-- Flurry or anything already an area spell.
local SPREAD = {}
for _, f in ipairs({ 'Protect', 'Shell', 'Blink', 'Stoneskin', 'Aquaveil', 'Phalanx', 'Regen', 'Refresh',
    'Invisible', 'Sneak', 'Deodorize', 'Adloquium', 'Embrava', 'Animus Augeo', 'Animus Minuo' }) do
    SPREAD[f] = true
end
local SPREAD_GROUPS = { storm = true, enspell = true, barelement = true, barstatus = true }

function sch.spreads(a)
    return sch.white(a) and a.area == 0 and (SPREAD[a.family] or SPREAD_GROUPS[a.pick_one]) == true
end

return sch
