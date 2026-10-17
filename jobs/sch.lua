--[[
    Scholar: stratagems. They share one charge pool, recast timer 231, whose
    timer counts down to every charge back; core/game.lua reads it through
    sch.charge_wait. Each stratagem changes the next spell, so it is a modifier
    (core/knowledge.lua): the engine fires it just before the spell a buff row
    turned it on for (core/engine.lua), and these say which spells it fits.
    Enlightenment opens the Addendum spells without the Addendum (core/catalog.lua).
]]--

local sch = {}

sch.JOB, sch.STRATAGEMS = 20, 231

-- Stratagem charges by SCH level (CatsEyeXI, from v2): { level, charges, seconds per charge }.
local TIERS = { { 75, 5, 48 }, { 65, 4, 60 }, { 50, 3, 80 }, { 30, 2, 120 }, { 10, 1, 240 } }

-- The wait for one charge, from the pool timer's seconds and your SCH level.
function sch.charge_wait(seconds, sch_lv)
    for _, t in ipairs(TIERS) do
        if sch_lv >= t[1] then return math.max(0, seconds - (t[2] - 1) * t[3]) end
    end
    return seconds
end

-- Charges banked, from the pool timer's seconds and your SCH level.
function sch.charges(seconds, sch_lv)
    for _, t in ipairs(TIERS) do
        if sch_lv >= t[1] then return math.max(0, t[2] - math.ceil(seconds / t[3])) end
    end
    return 0
end

-- Whether a buff row may spend stratagem action `a` (a modifier, an Addendum):
-- with heal.reserve on, the last charge is kept for healing's Accession and Rapture.
function sch.spare(a, g, cfg)
    if not (cfg.heal.reserve and a.kind == 'ja' and a.recast == sch.STRATAGEMS) then return true end
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
