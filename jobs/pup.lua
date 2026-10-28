--[[
    Puppetmaster: maneuvers. The eight go on you, not the automaton (it reads them
    off you), share one recast and stand three at once; a new one pushes the oldest
    out. Under Maneuvers (cfg.maneuver) each of the three slots picks one by name
    ('' for none; the same one twice keeps two up), kept up while your automaton is
    out, main or sub, never under Overload. Only on the automaton: any other pet
    would refuse them. Its name comes in the server's job packet (0x044,
    pup.extended), and the snapshot carries it (g.automaton, pup.read); until then
    the pet is taken for it on a PUP main job, or a PUP subjob under a job with no
    pet of its own.
]]--

local can = require('core.can')
local lang = require('core.lang')
local slots = require('core.slots')
local run = require('jobs.run')

local pup = {}

pup.JOB = 18
pup.SLOTS = 3

local PET_JOBS = { [9] = true, [14] = true, [15] = true, [21] = true }  -- BST, DRG, SMN, GEO
local NAME, NAME_LEN = 0x58, 16  -- 0x044: the automaton's name, NUL-padded (none when it's 16 long)

local automaton  -- your automaton's name, once the server has said it

-- From the 0x044 packet: '' (none sent) leaves it unknown.
function pup.named(name) automaton = name ~= '' and name or nil end
function pup.automaton() return automaton end

-- 0x044, PUP's extended job data (core/packets.lua).
function pup.extended(d)
    if #d >= NAME + NAME_LEN then pup.named((d:sub(NAME + 1, NAME + NAME_LEN):match('^[^%z]*'))) end
end

function pup.read(g) g.automaton = automaton end

-- Whether your pet is your automaton (g.automaton: its name, nil until known).
function pup.is_automaton(g)
    if not (g.pet and g.pet.hpp > 0) then return false end
    if g.automaton then return g.pet.name == g.automaton end
    return g.main == pup.JOB or not PET_JOBS[g.main]
end

function pup.want(g, cat, cfg)
    if not pup.is_automaton(g) then return nil end
    -- Counted as runes are: the same maneuver twice wants two up.
    local missing = run.missing(slots.picked(cfg.maneuver, 'slot', slots.by_name(cat, 'maneuver'), pup.SLOTS), g.me)
    if missing and can.use(missing, g) then return { action = missing, why = g.pet.name } end
end

-- Knowledge (core/knowledge.lua says what each field means) --------------------

-- Each shows the status named like it; Overload stops them all.
pup.knowledge = {}
for _, e in ipairs({ 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' }) do
    local name = e .. ' Maneuver'
    pup.knowledge[name] = { role = 'maneuver', pet = true, status = name, blocked_by = 'Overload', learn = { [pup.JOB] = 1 } }
end

pup.behaviors = { { name = 'maneuver', run = pup.want, before = 'last', quick = true } }

-- The maneuver per slot, by name ('' for none). Every slot starts empty.
pup.settings = { maneuver = { on = true } }
for i = 1, pup.SLOTS do pup.settings.maneuver['slot_' .. i] = '' end

-- Sidekick Settings: Maneuvers, for a Puppetmaster, main or sub (ui/model.lua).
pup.ui = { section = { id = 'maneuver', title = 'Maneuvers', header = 'Pet', before = 'recover' }, set = {} }
for i = 1, pup.SLOTS do pup.ui.set[slots.path('maneuver', 'slot', i)] = 'maneuver' end

-- The view's `maneuver`: the maneuvers to pick from, by element, and each slot's
-- pick; and whether it's shown.
function pup.ui.view(cat, cfg, g, help)
    local out, first = { choices = {}, picks = slots.names(cfg.maneuver, 'slot', pup.SLOTS) }, nil
    for _, a in ipairs(cat) do  -- in id order: the game's element order
        if a.role == 'maneuver' then
            out.choices[#out.choices + 1] = { name = a.name, label = lang.t((a.name:gsub(' Maneuver$', ''))) }
            first = first or a
        end
    end
    -- They share one recast and every gate, so one says whether they can go.
    if first then out.ready, out.avail = help.ready({ first }, {}, g) end
    return out, first ~= nil
end

return pup
