--[[
    Debuff removal. For each member carrying something a removal clears, the most
    specific remover first: a targeted -na spell, then Erase (strips any one
    erasable status), then Esuna (an area cast on you, reaching those near you),
    then an item on you (Echo Drops, Remedy...; opt-in, they cost gil). A remover
    only ever on you with no area (Chakra, items) clears only your own; Esuna
    reaches your party only, so the alliance's other parties and tracked
    players get a -na spell or nothing.
    Items go by what they'd clear on you now: Doom first (it kills), then Silence
    if you cast, then the most of your statuses in one use; then cheap and
    specific first. An /item the server never answers (a locked or bazaar stack)
    holds items back ITEM_WAIT seconds instead of going out every throttle.
]]--

local can = require('core.can')
local settings = require('core.settings')

local ESUNA_RADIUS = 10  -- yalms around you
local ITEM_WAIT = 4      -- seconds, as v2's item cooldown
local DOOM, SILENCE = 15, 6

local function rank(a)
    if a.kind == 'item' then return 3 end
    if can.self_only(a) then return 2 end
    return #a.removes > 6 and 1 or 0
end

local function clears(a, u)
    for _, id in ipairs(a.removes) do if u.buffs[id] then return true end end
    return false
end

-- What item `a` would do for you now: Doom weighs most, then Silence if you cast,
-- then one per status it clears. One that clears a single status at random
-- (Remedy Ointment) is sure only when you have just one of its.
local function worth(a, me)
    local w, n = 0, 0
    for _, id in ipairs(a.removes) do
        if me.buffs[id] then
            n = n + 1
            w = w + (id == DOOM and 1000 or id == SILENCE and me.uses_mp and 100 or 1)
        end
    end
    return a.one_of and n > 1 and 1 or w
end

return function (g, cat, cfg, mem)
    local removers, worths = settings.enabled(cat, cfg, 'remove'), {}
    for _, a in ipairs(removers) do worths[a] = a.kind == 'item' and worth(a, g.me) or 0 end
    table.sort(removers, function (a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if worths[a] ~= worths[b] then return worths[a] > worths[b] end
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    -- The last /item, while nothing has come back from it (a finish or an interrupt).
    local unanswered = mem.item_at and (g.finished or -math.huge) < mem.item_at and g.now - mem.item_at < ITEM_WAIT
    for _, u in ipairs(g.units) do
        if u.alive and u.in_zone then
            for _, a in ipairs(removers) do
                if clears(a, u) and not (unanswered and a.kind == 'item') and can.use(a, g) then
                    if can.self_only(a) then
                        if u.kind == 'self' and a.area == 0 then
                            local intent = { action = a, why = u.name }
                            if a.kind == 'item' then intent.sent = function (now) mem.item_at = now end end
                            return intent
                        elseif a.area > 0 and can.in_party(u) and (u.dist or math.huge) <= ESUNA_RADIUS then
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
