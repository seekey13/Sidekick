--[[
    Puppetmaster: maneuvers (v2's lib/actions/pet.lua). The eight elemental
    maneuvers go on you, not the automaton (it reads them off you, as retail),
    share one recast and stand three at once; a new one pushes the oldest out.
    Under Maneuvers (cfg.maneuver) each of the three slots picks one by name
    ('' for none; the same one twice keeps two up), kept up while an automaton
    is out, main or sub (this server lets a PUP subjob call one). They're listed
    for the job even while it's dismissed (the client drops these pet commands
    from its ability list then), so Maneuvers stays on the Pet page. None goes
    under Overload (it would only add to it), and none while you're
    Invisible or under Sneak (core/engine.lua).
    Only on the automaton: a jug pet, avatar, wyvern or luopan (BST/PUP...) would
    refuse them. Your automaton's name comes in the server's job packet (0x044,
    core/packets.lua) on login, zoning and job changes; until one has, the pet is
    taken for it on a PUP main job, or a PUP subjob under a job with no pet of its own.
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
