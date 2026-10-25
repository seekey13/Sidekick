--[[
    Rune Fencer: runes (v2's lib/actions/rune.lua). The eight runes share one
    5s recast and stand together, as many as your RUN level allows (main or
    sub: 1 at 5, 2 at 35, 3 at 65); a new one pushes the oldest out. Under
    Runes (cfg.rune) each set picks a rune per slot, by name ('' for none; the
    same rune twice keeps two up):
      - Idle: what's kept up the rest of the time.
      - a set per ward, Vallation, Valiance and Pflug (role 'ward', in their
        priority order): once the ward is ready (its row on, off recast, not
        blocked), it takes the slots, its runes go up one at a time, and in
        combat it fires (out of combat its set waits up, so the ward is ready
        for the pull, but a 300s recast isn't spent on nothing). None of the
        three spends a rune, so Idle takes the slots back once it's on recast.
        A set with nothing picked takes nothing.
    Vallation and Valiance are blocked by each other and by Liement
    (core/knowledge.lua): Valiance does nothing on you under Vallation, and
    Vallation would replace a party-wide Valiance with less (v2's rule).
    Lunge, Swipe, Gambit and Rayke spend runes: they are yours to use; the
    runes are put back after. Nothing goes while you're Invisible
    (core/engine.lua).
]]--

local can = require('core.can')
local settings = require('core.settings')
local slots = require('core.slots')
local util = require('core.util')

local run = {}

run.JOB = 22
run.SLOTS = 3  -- the most runes that stand at once
-- Each rune: what it adds to your attacks, the element it resists, the
-- ailments it defends against (v2's labels), as the sets show it.
run.RUNES = {
    { 'Ignis', 'Fire', 'Ice', 'Paralyze / Bind' },
    { 'Gelus', 'Ice', 'Wind', 'Silence / Weight' },
    { 'Flabra', 'Wind', 'Earth', 'Petrify / Slow' },
    { 'Tellus', 'Earth', 'Lightning', 'Stun' },
    { 'Sulpor', 'Lightning', 'Water', 'Poison' },
    { 'Unda', 'Water', 'Fire', 'Amnesia / Plague' },
    { 'Lux', 'Light', 'Dark', 'Blind / Curse / Sleep' },
    { 'Tenebrae', 'Dark', 'Light', 'Charm / Sleep' },
}
-- The sets, by settings key: Idle shows what a rune adds, the wards what it
-- resists (Vallation, Valiance) or the ailments (Pflug).
run.SETS = { { key = 'idle', label = 'Idle', shows = 'element' },
             { key = 'vallation', ward = 'Vallation', shows = 'resist' },
             { key = 'valiance', ward = 'Valiance', shows = 'resist' },
             { key = 'pflug', ward = 'Pflug', shows = 'ailments' } }

-- How many runes stand at once at RUN level `lv`.
function run.slots(lv)
    return lv >= 65 and 3 or lv >= 35 and 2 or 1
end

-- The first rune of `want` not standing, counting each pick: the same rune
-- twice wants two up. nil when the set stands.
function run.missing(want, me)
    local used = {}
    for _, a in ipairs(want) do
        local id = a.status[1]
        local up = (me.stacks or {})[id] or (me.buffs[id] and 1 or 0)
        used[id] = (used[id] or 0) + 1
        if used[id] > up then return a end
    end
end

-- Your runes by name, and the wards in priority order (Vallation, Valiance, Pflug).
function run.actions(cat)
    local wards = {}
    for _, a in ipairs(cat) do
        if a.role == 'ward' then wards[#wards + 1] = a end
    end
    table.sort(wards, function (x, y) return x.priority > y.priority end)
    return slots.by_name(cat, 'rune'), wards
end

function run.want(g, cat, cfg)
    local lv = util.level(g, run.JOB)
    if lv == 0 then return nil end
    local runes, wards = run.actions(cat)
    local n = run.slots(lv)
    for _, w in ipairs(wards) do
        if settings.row(cfg, w).on and can.use(w, g) then
            local want = slots.picked(cfg.rune, w.family:lower(), runes, n)
            if want[1] then
                local missing = run.missing(want, g.me)
                if missing then
                    -- The shared recast: wait for it rather than let Idle swap the set back.
                    if not can.use(missing, g) then return nil end
                    return { action = missing, why = 'for ' .. w.name }
                end
                if not g.combat then return nil end  -- the set waits up for the pull
                return { action = w, why = 'runes up' }
            end
        end
    end
    local missing = run.missing(slots.picked(cfg.rune, 'idle', runes, n), g.me)
    if missing and can.use(missing, g) then return { action = missing, why = 'idle' } end
end

return run
