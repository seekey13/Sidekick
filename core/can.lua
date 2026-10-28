--[[
    The rules every behavior shares, so none re-implements them:
      can.use(a, g)            is action `a` usable right now (cost, recast, ailments, gates)
      can.reach(a, u)          can `a` land on unit `u` (target kind, alive, in range)
      can.in_party(u)          is `u` in your party: area effects from you land on no one else
      can.together(c, u)       does an area effect aimed at `c` land on `u` (the same party)
      can.command(a, u, j, bt) the chat command that does it
      can.spare_hp(a, g, cfg)  can you pay what `a` costs in HP
    `a` is a catalog record, `u` a unit and `g` the snapshot from core/game.lua.
]]--

local dnc = require('jobs.dnc')
local nin = require('jobs.nin')
local util = require('core.util')

local can = {}

can.THROTTLE = 1.1        -- the server's lockout after any action
can.SPELL_THROTTLE = 3.1  -- ...and after a spell, counted from when it lands

-- Valid-target flags (spell/ability Targets). ALLY is a player outside your
-- party, in your alliance or not: Cure, Protect, Haste, the -na spells and
-- Raise have it; Regen, Erase, Curaga don't.
local SELF, PARTY, ALLY, ENEMY, CORPSE = 1, 4, 8, 32, 128

-- Range index -> yalms: index * multiplier (the client's lookup); 13+ are self-range.
local RANGE_MULT = { [2] = 1.70, [3] = 1.490909, [4] = 1.44, [5] = 1.377778, [6] = 1.30, [7] = 1.20,
    [8] = 1.30, [9] = 1.377778, [10] = 1.45, [11] = 1.490909, [12] = 1.70 }
function can.yalms(index)
    return index * (RANGE_MULT[index] or 1)
end

local function has(flags, bit_) return bit.band(flags, bit_) ~= 0 end

-- Whether `set` (status id -> true) holds any of `ids`.
function can.any(set, ids)
    for _, id in ipairs(ids or {}) do if set[id] then return true end end
    return false
end
local any = can.any

-- Whether `u` shows none of `a`'s statuses (`status`, a list, stands in for them
-- when given); true for one with no status that can be read (Boost).
function can.lacks(a, u, status)
    return not (a.status and any(u.buffs, status or a.status))
end

-- Yalms between two units (or a unit and the pet); unknown positions are far apart.
function can.dist(a, b)
    if a == b then return 0 end
    if not (a.pos and b.pos) then return math.huge end
    local dx, dy, dz = a.pos[1] - b.pos[1], a.pos[2] - b.pos[2], a.pos[3] - b.pos[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Whether `u` is within `radius` yalms of you: you always are, one not drawn never.
function can.near(u, radius) return u.kind == 'self' or (u.dist or math.huge) <= radius end

-- Whether you can pay `a`'s HP price: one that costs HP (Devotion, Spirit Link)
-- only over your danger line, one that trades HP for MP (Convert) only while it gains.
function can.spare_hp(a, g, cfg)
    if a.costs_hp and g.me.hpp < cfg.heal.danger then return false end
    return not a.swaps or g.me.hp > g.me.mp
end

-- Aimed at your battle target (Drain, Aspir, Absorb-): the effect lands on you.
function can.at_enemy(a) return a.targets == ENEMY end
-- Only ever on you (Protectra, Esuna, most job abilities).
function can.self_only(a) return a.targets == SELF end
-- Can go on a player outside your party (the alliance's other parties, a tracked player).
function can.outside(a) return has(a.targets, ALLY) end

-- Which party of the alliance `u` is in: 1 yours (you, members, trusts, your
-- pet), 2 for slots 6-11, 3 for 12-17; nil for a tracked player, whose party
-- is unknown.
function can.party(u)
    if u.kind == 'tracked' then return nil end
    return u.kind == 'alliance' and (u.slot < 12 and 2 or 3) or 1
end

function can.in_party(u) return can.party(u) == 1 end

-- An area effect lands on the target's party: one from you or a member
-- (Curaga, Esuna, Protectra) never reaches the alliance's other parties or a
-- tracked player; one aimed at someone else (a Cure spread by Majesty or
-- Accession, a -na by Divine Veil) lands on their party alone.
function can.together(centre, u)
    local p = can.party(centre)
    return p ~= nil and p == can.party(u)
end

-- Whether `a` can be used now, else false and why.
function can.use(a, g)
    if a.kind == 'ma' and g.silenced then return false, 'silenced' end
    if (a.kind == 'ja' or a.kind == 'pet') and g.amnesia then return false, 'amnesia' end
    if (a.mp or 0) > g.me.mp then return false, 'MP' end
    if dnc.tp(a, g) > g.me.tp then return false, 'TP' end
    if a.ammo and not util.contains(a.ammo, g.ammo) then return false, 'no ammo' end
    if a.tool and nin.tools(a, g) == 0 then return false, 'no tools' end
    if a.kind == 'item' and not (g.items and g.items[a.id]) then return false, 'none left' end
    -- An Addendum spell can go through Enlightenment instead (core/catalog.lua), fired first by the engine.
    if a.requires and not any(g.me.buffs, a.requires) and not (a.via and can.use(a.via, g)) then
        return false, 'needs ' .. (a.names and a.names[a.requires[1]] or 'a status')
    end
    for _, id in ipairs(a.blocked_by or {}) do
        if g.me.buffs[id] then return false, 'blocked by ' .. (a.names and a.names[id] or 'a status') end
    end
    if a.gate == 'combat' and not g.combat then return false, 'combat only' end
    if a.gate == 'idle' and g.combat then return false, 'idle only' end
    if a.pet then
        if not g.pet then return false, 'no pet' end
        if a.pet_range and (g.pet.dist or math.huge) > a.pet_range then return false, 'pet too far' end
        if type(a.pet) == 'table' and not util.contains(a.pet, g.pet.name) then return false, 'wrong pet' end
    end
    -- Catalogued by level though the server lists it only at times (core/catalog.lua):
    -- goes only once the client lists it (a jug's Ready move it lacks, a merit not taken).
    if a.hidden and g.listed and not g.listed(a) then return false, 'not listed' end
    if can.at_enemy(a) then
        if not (g.bt and g.bt.mob) then return false, 'no battle target' end
        if g.bt.dist > can.yalms(a.range) then return false, 'target out of range' end
    end
    local wait = g.recast(a)
    if wait > 0 then return false, ('recast %.1fs'):format(wait), wait end
    return true
end

-- Whether `a` can land on unit `u`. Revives want a corpse; everything else the living.
function can.reach(a, u)
    if not u.in_zone then return false end
    if can.at_enemy(a) then return u.kind == 'self' end  -- Drain heals the caster
    if a.role == 'revive' then
        if u.alive or not has(a.targets, CORPSE) then return false end
    elseif not u.alive then
        return false
    end
    if u.kind == 'self' then return has(a.targets, SELF) end
    return has(a.targets, can.in_party(u) and PARTY or ALLY) and can.near(u, can.yalms(a.range))
end

-- '/ma "Cure IV" 12345678': party members by server id, you as <me>, enemies as
-- <bt>; by server id when the client has none for it (`bt` claimed by another
-- party of the alliance, core/game.lua). In Japanese, the name is the DAT's
-- Japanese one; the second result is true when there is none, so the English
-- one went instead (the Japanese client won't take it).
function can.command(a, u, japanese, bt)
    local name, english = util.spelled(a.name, a.jp, japanese)
    local enemy = bt and bt.claimed and tostring(bt.sid) or '<bt>'
    local target = can.at_enemy(a) and enemy or (u == nil or u.kind == 'self') and '<me>' or tostring(u.sid)
    return ('/%s "%s" %s'):format(a.kind, name, target), english
end

return can
