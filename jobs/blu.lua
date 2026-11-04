--[[
    Blue Mage: the set spells, and Diffusion. Blue magic is learned (HasSpell) but
    castable only while set: the server sends the set in its job packet (0x044,
    blu.extended) on login, zoning, a job change and a set change, and the
    catalog takes only the set ones (core/catalog.lua); until a packet has said,
    none, as one cast while not set is refused over and over. The Unbridled spells
    (knowledge's `unbridled`) are never set: they go through Unbridled Learning,
    which the engine fires first, as Enlightenment for an Addendum spell. Diffusion
    is a modifier: fired before a blue magic buff that goes on you alone, it spreads
    it to your party near you, as SCH's Accession does (behaviors/buff.lua), but
    only while someone but you lacks it.
]]--

local blu = {}

blu.JOB = 16
blu.MAGIC = 6           -- spell type
blu.SLOTS = 20
local SET = 0x08          -- 0x044: the set slots, a byte each
local SPELL_BASE = 0x200  -- a set slot holds spell id - 0x200; 0 for an empty slot
local SELF = 1            -- valid-target flag

local set, version = nil, 0

-- From the 0x044 packet: the 20 slots' bytes.
function blu.slots(bytes)
    set = {}
    for _, b in ipairs(bytes) do
        if b ~= 0 then set[b + SPELL_BASE] = true end
    end
    version = version + 1
end

-- 0x044, BLU's extended job data (core/packets.lua).
function blu.extended(d)
    if #d >= SET + blu.SLOTS then blu.slots({ d:byte(SET + 1, SET + blu.SLOTS) }) end
end

-- The set spells by id, nil until the server has said; and a count that changes with each.
function blu.set() return set end
function blu.version() return version end

-- What Diffusion spreads: blue magic that goes on you alone (not one already
-- an area spell, Diamondhide; the knowledge table's area 0 keeps Battery Charge in).
-- v2's list (its D button), to check in game against the server's.
function blu.diffuses(a)
    return a.kind == 'ma' and a.type == blu.MAGIC and a.targets == SELF and a.area == 0
end

-- Knowledge (core/knowledge.lua says what each field means): fired before a blue
-- magic buff on you alone, Diffusion lands it on your party near you.
blu.knowledge = {
    ['Diffusion'] = { role = 'modifier', applies = blu.diffuses, spreads = { area = 10, mp = 1, others = true }, note = 'on everyone near you' },
}

return blu
