--[[
    Scholar: stratagems, sharing one charge pool, recast timer 231 (sch.POOL,
    core/charges.lua): the snapshot's g.stratagems is the charges banked (sch.read).
    Each changes the next spell, so it is a modifier (sch.knowledge) the engine
    fires just before the spell a buff row turned it on for; these say which
    spells each fits.
    Enlightenment opens the Addendum spells without the Addendum (core/catalog.lua).
]]--

local charges = require('core.charges')

local sch = {}

sch.JOB = 20
-- Stratagem charges by SCH level (CatsEyeXI, from v2): { level, charges, seconds per charge }.
sch.POOL = charges.pool({ job = sch.JOB, kind = 'ja', recast = 231,
    tiers = { { 75, 5, 48 }, { 65, 4, 60 }, { 50, 3, 80 }, { 30, 2, 120 }, { 10, 1, 240 } } })

-- The snapshot's stratagem charges banked; nil off SCH.
function sch.read(g, timer) g.stratagems = sch.POOL:now(g, timer) end

-- Whether `a` spends a stratagem charge, which heal.reserve keeps the last of.
function sch.reserves(a) return sch.POOL:spends(a) end

-- Whether a buff row may spend stratagem action `a` (a modifier, an Addendum):
-- with heal.reserve on, the last charge is kept for healing's Accession and Rapture.
function sch.spare(a, g, cfg)
    if not (cfg.heal.reserve and sch.reserves(a)) then return true end
    return g.stratagems == nil or g.stratagems > 1
end

-- Of the modifiers a buff row fires together, the first stratagem when there are
-- more to fire than charges to spend (as v2's Hold for Stratagem).
function sch.short(mods, g, cfg)
    local n, first = 0, nil
    for _, m in ipairs(mods) do
        if sch.reserves(m) then n, first = n + 1, first or m end
    end
    local spare = g.stratagems and g.stratagems - (cfg.heal.reserve and 1 or 0)
    if spare and n > spare then return first end
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
local SCH = sch.JOB
sch.knowledge = {
    ['Accession'] = {
        { role = 'emergency', requires = LIGHT, boost = { 'healing', area = 10, mp = 2, tiers = 4 }, learn = { [SCH] = 40 } },
        { role = 'modifier', requires = LIGHT, applies = sch.spreads, spreads = { area = 10, mp = 2 },
          note = 'on everyone near you, at twice the MP', learn = { [SCH] = 40 } },
    },
    ['Penury']      = { role = 'modifier', requires = LIGHT, applies = sch.white, note = 'half the MP', learn = { [SCH] = 10 } },
    ['Celerity']    = { role = 'modifier', requires = LIGHT, applies = sch.white, note = 'half the casting time', learn = { [SCH] = 25 } },
    ['Perpetuance'] = { role = 'modifier', requires = LIGHT, applies = sch.enhancing, note = 'longer duration', learn = { [SCH] = 87 } },
    ['Parsimony']   = { role = 'modifier', requires = DARK, applies = sch.black, note = 'half the MP', learn = { [SCH] = 10 } },
    ['Alacrity']    = { role = 'modifier', requires = DARK, applies = sch.black, note = 'half the casting time', learn = { [SCH] = 25 } },
}

return sch
