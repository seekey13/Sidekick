--[[
    Debuff removal. For each member carrying something a removal clears, the most
    specific remover first: a targeted -na spell, then Erase, then Esuna (an area
    cast on you, clearing on those near you only what you have too), then an item
    on you (opt-in: they cost gil). A remover only ever on you with no area
    (Chakra, items) clears only your own; Esuna reaches your party only. A slot in
    cfg.remove.off is left alone. Debuffs are switched by name (cfg.remove.skip:
    those left on everyone, unless that player has cfg.remove.own[slot]; never Doom,
    which kills). Items go by what they'd clear on you now: Doom first, then Silence if you cast,
    then the most of your statuses in one use; then cheap and specific first. An
    /item the server never answers (a locked or bazaar stack) holds items back
    ITEM_WAIT seconds.
]]--

local can = require('core.can')
local settings = require('core.settings')
local status = require('core.status')

local ESUNA_RADIUS = 10  -- yalms around you
local ITEM_WAIT = 4      -- seconds, as v2's item cooldown
local DOOM, SILENCE = status.DOOM, 6

-- A unit's removal key: its party or alliance slot, else a tracked player's name.
local function key_of(u)
    if u.slot ~= nil then return u.slot end
    return u.name
end

-- Removal runs on a unit until its slot is switched off.
local function served(rm, u)
    return (rm.off or {})[key_of(u)] ~= true
end

-- The statuses left on `u`: their own set when they have one, else the global skip.
local function skip_of(rm, u)
    local mine = (rm.own or {})[key_of(u)]
    if type(mine) == 'table' and mine.set then return mine.skip or {} end
    return rm.skip or {}
end

local function rank(a)
    if a.kind == 'item' then return 3 end
    if can.self_only(a) then return 2 end
    return #a.removes > 6 and 1 or 0
end

-- Whether `a` clears status `id` and it's one to remove on `u`.
local function wanted(a, id, u, skip)
    return u.buffs[id] and (id == DOOM or not skip[a.debuffs[id]])
end

-- Whether `a` clears something on `u` that's to be removed. Esuna clears on those
-- near you only what you have too (server esuna.lua), so it's for those alone.
local function clears(a, u, skip, me)
    local shared = can.self_only(a) and a.area > 0
    for _, id in ipairs(a.removes) do
        if wanted(a, id, u, skip) and not (shared and not me.buffs[id]) then return true end
    end
    return false
end

-- What item `a` would do for you now: Doom weighs most, then Silence if you cast,
-- then one per status it clears. One that clears a single status at random
-- (Remedy Ointment) is sure only when you have just one of its; with more, it's
-- worth the share of them that are to be removed (one left on may be what it takes).
local function worth(a, me, skip)
    local w, n, m = 0, 0, 0
    for _, id in ipairs(a.removes) do
        if me.buffs[id] then n = n + 1 end
        if wanted(a, id, me, skip) then
            m = m + 1
            w = w + (id == DOOM and 1000 or id == SILENCE and me.uses_mp and 100 or 1)
        end
    end
    return a.one_of and n > 1 and m / n or w
end

return function (g, cat, cfg, mem)
    local rm = cfg.remove or {}
    local removers, worths = settings.enabled(cat, cfg, 'remove'), {}
    local mine = skip_of(rm, g.me)
    for _, a in ipairs(removers) do worths[a] = a.kind == 'item' and worth(a, g.me, mine) or 0 end
    table.sort(removers, function (a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if worths[a] ~= worths[b] then return worths[a] > worths[b] end
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    -- The last /item, while nothing has come back from it (a finish or an interrupt).
    local unanswered = mem.item_at and (g.finished or -math.huge) < mem.item_at and g.now - mem.item_at < ITEM_WAIT
    for _, u in ipairs(g.units) do
        if u.alive and u.in_zone and served(rm, u) then
            local skip = skip_of(rm, u)
            for _, a in ipairs(removers) do
                if clears(a, u, skip, g.me) and not (unanswered and a.kind == 'item') and can.use(a, g) then
                    if can.self_only(a) then
                        if u.kind == 'self' and a.area == 0 then
                            local intent = { action = a, why = u.name }
                            if a.kind == 'item' then intent.sent = function (now) mem.item_at = now end end
                            return intent
                        elseif a.area > 0 and can.in_party(u) and can.near(u, ESUNA_RADIUS) then
                            return { action = a, why = ('%s near you'):format(u.name) }
                        end
                    elseif can.reach(a, u) then
                        return { action = a, target = u, why = u.name }
                    end
                end
            end
        end
    end
end
