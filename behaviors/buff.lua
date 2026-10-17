--[[
    Keep the buffs you turned on up on the targets you picked. A row's action is
    its picked tier, else the best tier you can cast now; a pick_one group
    (bar-elements, enspells...) needs a pick. Self-only buffs go on you; an area
    self-cast (Protectra) is recast when anyone in your party near you lacks it.
    With buff.hold_aoe on, an area spell is held while a player in your party
    who lacks it is out of its reach (or not drawn), so nobody is left out: it
    goes out once they gather, and mem.gather says what waits on whom (the engine
    asks the party to gather when someone near lacks it too; otherwise it waits
    quietly). Trusts follow you and never hold it.
    A row's targets are party and alliance slots (0-17) and tracked players'
    names. Statuses that can't be read (Boost) are recast whenever they're off
    recast.
    A row's modifiers (SCH's stratagems) go with its spell: the engine fires
    each first (core/engine.lua). Accession instead spreads the spell from you
    to the row's targets in your party near you, at twice the MP, whenever one
    there lacks it (as v2), and is held for the group like an area spell. With
    heal.reserve on, buff rows never spend the last stratagem charge (jobs/sch.lua).
    Songs are kept up here until the BRD module takes them (phase 4); rolls and
    the like belong to job modules.
]]--

local can = require('core.can')
local sch = require('jobs.sch')
local settings = require('core.settings')

local INVISIBLE = 69
local AREA_RADIUS = 10  -- yalms around you

local function lacks(a, u)
    if not a.status then return true end
    for _, id in ipairs(a.status) do if u.buffs[id] then return false end end
    return true
end

-- Each row's action, best tier first, highest priority rows first.
local function chosen(cat, cfg, g)
    local by_key, keys = {}, {}
    for _, a in ipairs(settings.enabled(cat, cfg, 'buff')) do
        local key = settings.key(a)
        if not by_key[key] then by_key[key] = {}; keys[#keys + 1] = key end
        table.insert(by_key[key], a)
    end
    local out = {}
    for _, key in ipairs(keys) do
        local list = by_key[key]
        local row = settings.row(cfg, list[1])
        table.sort(list, function (a, b) return (a.level or 0) > (b.level or 0) end)
        local pick
        for _, a in ipairs(list) do
            if row.pick == a.name or (not row.pick and not a.pick_one and can.use(a, g)) then pick = a; break end
        end
        if pick then
            out[#out + 1] = { action = pick, targets = row.targets or { [0] = true }, mods = settings.mods(cat, cfg, pick) }
        end
    end
    table.sort(out, function (x, y) return x.action.priority > y.action.priority end)
    return out
end

-- For an area self-cast: who near you lacks it (the first, and how many), and,
-- holding for the group, the first player in your party who lacks it out of its
-- reach. `wanted` (a row's targets) narrows who counts.
local function area(a, g, hold, wanted)
    local near, count, away = nil, 0, nil
    for _, u in ipairs(g.units) do
        local here = u.kind == 'self' or (u.dist or math.huge) <= AREA_RADIUS
        if (u.kind == 'self' or can.in_party(u) and u.alive and u.in_zone) and lacks(a, u)
            and (not wanted or wanted[u.slot]) then
            if here then near, count = near or u, count + 1
            elseif hold and u.kind == 'party' and not away then away = u end
        end
    end
    return near, away, count
end

-- Holding `a` for `away` to gather: ask the party only when someone near needs
-- it too; one who stays away (a puller) is waited for silently.
local function wait_for(mem, a, near, away)
    if not mem.gather or (near and not mem.gather.ask) then
        mem.gather = { action = a, who = away, ask = near ~= nil }
    end
end

-- A row's Accession, split from its other modifiers (those it may spend), when
-- it can spread `a` now: up on you already, or spare and usable with the MP for
-- the doubled spell.
local function spreading(c, g, cfg)
    local others, acc = {}, nil
    for _, m in ipairs(c.mods) do
        if m.spreads then acc = m elseif sch.spare(m, g, cfg) then others[#others + 1] = m end
    end
    local a = c.action
    if acc and not can.reach(a, g.me) then acc = nil end
    if acc and not can.any(g.me.buffs, acc.status) and not (sch.spare(acc, g, cfg) and can.use(acc, g)
        and (a.mp or 0) * acc.spreads.mp <= g.me.mp) then acc = nil end
    return acc, others
end

return function (g, cat, cfg, mem)
    local invisible = g.me.buffs[INVISIBLE]
    local hold = cfg.buff.hold_aoe
    for _, c in ipairs(chosen(cat, cfg, g)) do
        local a = c.action
        if (a.travel or not invisible) and can.use(a, g) and sch.spare(a, g, cfg) then
            local acc, mods = spreading(c, g, cfg)
            local near, away, count
            if acc then near, away, count = area(a, g, hold, not can.self_only(a) and c.targets or nil) end
            if away then
                wait_for(mem, a, near, away)
            elseif acc and count >= 1 then
                table.insert(mods, acc)
                local why = count > 1 and ('%s +%d lack it'):format(near.name, count - 1) or ('%s lacks it'):format(near.name)
                return { action = a, mods = mods, why = why }
            elseif can.self_only(a) and a.area > 0 then
                near, away = area(a, g, hold and a.kind == 'ma')
                if away then
                    wait_for(mem, a, near, away)
                elseif near then
                    return { action = a, mods = mods, why = ('%s lacks it'):format(near.name) }
                end
            elseif can.self_only(a) then
                if lacks(a, g.me) then return { action = a, mods = mods, why = ('%s lacks it'):format(g.me.name) } end
            else
                for _, u in ipairs(g.units) do
                    if c.targets[u.slot or u.name] and can.reach(a, u) and lacks(a, u) then
                        return { action = a, target = u, mods = mods, why = u.name }
                    end
                end
            end
        end
    end
end
