--[[
    Rune Fencer: runes. The eight share one 5s recast and stand together, as many
    as your RUN level allows (run.slots); a new one pushes the oldest out. Under
    Runes (cfg.rune) each set picks a rune per slot, by name ('' for none; the same
    rune twice keeps two up): Idle, kept up the rest of the time, and one per ward
    (Vallation, Valiance, Pflug, in priority order). A ready ward (its row on, off
    recast, not blocked) takes the slots: its runes go up one at a time, then it
    fires in combat; out of combat its set waits up for the pull. Once it's on
    recast Idle takes the slots back, and a set with nothing picked takes nothing.
    Lunge, Swipe, Gambit and Rayke are yours to use: the runes go back up after.
]]--

local can = require('core.can')
local lang = require('core.lang')
local sch = require('jobs.sch')
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

-- Knowledge (core/knowledge.lua says what each field means) --------------------

local K = {
    -- The wards read the runes up, in priority order as v2. Valiance does nothing on
    -- you under Vallation; Vallation would replace a party-wide Valiance with less
    -- (v2's rule); Liement stops both.
    ['Vallation'] = { role = 'ward', priority = 3, status = 'Vallation', blocked_by = { 'Valiance', 'Liement' } },
    ['Valiance']  = { role = 'ward', priority = 2, status = 'Valiance', blocked_by = { 'Vallation', 'Liement' } },
    ['Pflug']     = { role = 'ward', priority = 1, status = 'Pflug' },
    -- Fired before white enhancing magic, as a stratagem (not the Spikes, which are black).
    ['Embolden']  = { role = 'modifier', applies = sch.enhancing, chip = 'Emb', note = 'more potent' },
}
-- The runes: each shows the status named like it.
for _, r in ipairs(run.RUNES) do
    K[r[1]] = { role = 'rune', status = r[1], rune = { element = r[2], resist = r[3], ailments = r[4] } }
end
run.knowledge = K

-- Runes before the luopan, as v2.
run.behaviors = { { name = 'rune', run = run.want, before = 'geo', quick = true } }

-- Each set's rune per slot, by name ('' for none): idle_1..3, then vallation_,
-- valiance_ and pflug_. Every slot starts empty.
run.settings = { rune = { on = true } }
for _, set in ipairs(run.SETS) do
    for i = 1, run.SLOTS do run.settings.rune[set.key .. '_' .. i] = '' end
end

-- Sidekick Settings: Runes, for a job with runes (ui/model.lua).
run.ui = { section = { id = 'rune', title = 'Runes', header = 'Buff', before = 'pet' }, set = {} }
for _, set in ipairs(run.SETS) do
    for i = 1, run.SLOTS do run.ui.set[slots.path('rune', set.key, i)] = 'name' end
end

-- The view's `rune`: the runes to pick from, and each set's picks: Idle, then each
-- ward you have, with its switch (its row) and whether it's ready; and whether it's shown.
function run.ui.view(cat, cfg, g, help)
    local mine, wards = run.actions(cat)
    local lv = util.level(g, run.JOB)
    local out = { slots = lv > 0 and run.slots(lv) or 0, runes = {}, sets = {} }
    for _, r in ipairs(run.RUNES) do
        local a = mine[r[1]]
        if a then
            out.runes[#out.runes + 1] = { name = a.name, label = lang.name(a.name, a.jp), element = lang.t(a.rune.element),
                                          resist = lang.t(a.rune.resist), ailments = lang.t(a.rune.ailments) }
        end
    end
    if not out.runes[1] then return out, false end
    local ward = {}
    for _, w in ipairs(wards) do ward[w.name] = w end
    for _, set in ipairs(run.SETS) do
        local w = set.ward and ward[set.ward]
        if not set.ward or w then
            local e = { key = set.key, label = set.label and lang.t(set.label) or lang.name(w.name, w.jp), shows = set.shows, ward = w and w.name,
                        picks = slots.names(cfg.rune, set.key, run.SLOTS) }
            if w then
                local r = settings.row(cfg, w)
                e.on = r.on == true
                e.ready, e.avail = help.ready({ w }, r, g)
            end
            out.sets[#out.sets + 1] = e
        end
    end
    return out, true
end

return run
