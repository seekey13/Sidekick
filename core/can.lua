--[[
    The rules every behavior shares, so none re-implements them:
      can.use(a, g)      is action `a` usable right now (cost, recast, ailments, gates)
      can.reach(a, u)    can `a` land on unit `u` (target kind, alive, in range)
      can.command(a, u)  the chat command that does it
    `a` is a catalog record, `u` a unit and `g` the snapshot from core/game.lua.
]]--

local can = {}

-- Valid-target flags (spell/ability Targets).
local SELF, PARTY, ENEMY, CORPSE = 1, 4, 32, 128

-- Range index -> yalms: index * multiplier (the client's lookup); 13+ are self-range.
local RANGE_MULT = { [2] = 1.70, [3] = 1.490909, [4] = 1.44, [5] = 1.377778, [6] = 1.30, [7] = 1.20,
    [8] = 1.30, [9] = 1.377778, [10] = 1.45, [11] = 1.490909, [12] = 1.70 }
function can.yalms(index)
    return index * (RANGE_MULT[index] or 1)
end

local function has(flags, bit_) return bit.band(flags, bit_) ~= 0 end

local function any(set, ids)
    for _, id in ipairs(ids or {}) do if set[id] then return true end end
    return false
end

-- Aimed at your battle target (Drain, Aspir, Absorb-): the effect lands on you.
function can.at_enemy(a) return a.targets == ENEMY end
-- Only ever on you (Protectra, Esuna, most job abilities).
function can.self_only(a) return a.targets == SELF end

-- Whether `a` can be used now, else false and why.
function can.use(a, g)
    if a.kind == 'ma' and g.silenced then return false, 'silenced' end
    if a.kind ~= 'ma' and g.amnesia then return false, 'amnesia' end
    if (a.mp or 0) > g.me.mp then return false, 'MP' end
    if (a.tp or 0) > 0 and a.tp > g.me.tp then return false, 'TP' end
    if a.requires and not any(g.me.buffs, a.requires) then return false, 'needs a status' end
    if any(g.me.buffs, a.blocked_by) then return false, 'blocked by a status' end
    if a.gate == 'combat' and not g.combat then return false, 'combat only' end
    if a.gate == 'idle' and g.combat then return false, 'idle only' end
    if a.pet then
        if not g.pet then return false, 'no pet' end
        if type(a.pet) == 'table' then
            local named = false
            for _, n in ipairs(a.pet) do named = named or n == g.pet.name end
            if not named then return false, 'wrong pet' end
        end
    end
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
    if not has(a.targets, PARTY) then return false end
    return (u.dist or math.huge) <= can.yalms(a.range)
end

-- '/ma "Cure IV" 12345678': party members by server id, you as <me>, enemies as <bt>.
function can.command(a, u, japanese)
    local name = japanese and a.jp ~= '' and a.jp or a.name
    local target = can.at_enemy(a) and '<bt>' or (u == nil or u.kind == 'self') and '<me>' or tostring(u.sid)
    return ('/%s "%s" %s'):format(a.kind, name, target)
end

return can
