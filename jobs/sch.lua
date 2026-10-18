--[[
    Scholar: stratagems. They share one charge pool, recast timer 231, whose
    timer counts down to every charge back: the snapshot's g.stratagems is the
    charges banked (sch.read), and a stratagem's recast is the wait for one
    (sch.recast). Each stratagem changes the next spell, so it is a modifier
    (sch.knowledge): the engine fires it just before the spell a buff row
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

local function level(p)
    return p:GetMainJob() == sch.JOB and p:GetMainJobLevel() or p:GetSubJob() == sch.JOB and p:GetSubJobLevel() or 0
end

-- The snapshot's stratagem charges banked; nil off SCH.
function sch.read(g, player, timer)
    local lv = level(player)
    if lv > 0 then g.stratagems = sch.charges(timer(sch.STRATAGEMS) / 60, lv) end
end

-- A stratagem is ready while a charge is banked, though the pool's timer runs.
function sch.recast(action, seconds, player)
    if action.kind ~= 'ja' or action.recast ~= sch.STRATAGEMS then return nil end
    return sch.charge_wait(seconds, level(player))
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

local LIGHT = { 'Light Arts', 'Addendum: White' }
local DARK = { 'Dark Arts', 'Addendum: Black' }

-- The stratagems, as modifiers fired just before the spell (core/knowledge.lua says what each field means).
sch.knowledge = {
    ['Accession'] = {
        { role = 'emergency', requires = LIGHT, boost = { 'healing', area = 10, mp = 2, tiers = 4 } },
        { role = 'modifier', requires = LIGHT, applies = sch.spreads, spreads = { area = 10, mp = 2 },
          chip = 'Acc', note = 'on everyone near you, at twice the MP' },
    },
    ['Penury']      = { role = 'modifier', requires = LIGHT, applies = sch.white, chip = 'Pen', note = 'half the MP' },
    ['Celerity']    = { role = 'modifier', requires = LIGHT, applies = sch.white, chip = 'Cel', note = 'half the casting time' },
    ['Perpetuance'] = { role = 'modifier', requires = LIGHT, applies = sch.enhancing, chip = 'Per', note = 'longer duration' },
    ['Parsimony']   = { role = 'modifier', requires = DARK, applies = sch.black, chip = 'Par', note = 'half the MP' },
    ['Alacrity']    = { role = 'modifier', requires = DARK, applies = sch.black, chip = 'Ala', note = 'half the casting time' },
}

return sch
