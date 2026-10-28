--[[
    Puppetmaster: maneuvers. The eight go on you, not the automaton (it reads them
    off you), share one recast and stand three at once; a new one pushes the oldest
    out. Under Maneuvers (cfg.maneuver) each of the three slots picks one by name
    ('' for none; the same one twice keeps two up), kept up while your automaton is
    out, main or sub, never under Overload. Only on the automaton: any other pet
    would refuse them. Its name comes in the server's job packet (0x044,
    core/packets.lua); until then the pet is taken for it on a PUP main job, or a
    PUP subjob under a job with no pet of its own.
]]--

local can = require('core.can')
local slots = require('core.slots')
local run = require('jobs.run')

local pup = {}

pup.JOB = 18
pup.SLOTS = 3

local PET_JOBS = { [9] = true, [14] = true, [15] = true, [21] = true }  -- BST, DRG, SMN, GEO

local automaton  -- your automaton's name, once the server has said it

-- From the 0x044 packet: '' (none sent) leaves it unknown.
function pup.named(name) automaton = name ~= '' and name or nil end
function pup.automaton() return automaton end

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

return pup
