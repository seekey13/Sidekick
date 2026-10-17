--[[
    Players outside your party you look after too (/sk3 track), this session
    only, as in v2. core/game.lua makes each a unit of kind 'tracked': healed,
    cleared, woken, raised, followed and buffed like a member, with what reaches
    outside the party (Cure, Curing Waltz, Protect, Haste, the -na spells, Raise;
    not Regen, Erase, or an area spell cast from you or a member, which lands
    on your own party only).

    entry = { sid, name, tidx = entity index last seen at, hpp, status = as last seen there,
              main, main_lv, sub, sub_lv = from a /check (packet 0x0C9), nil until one answers }
    Only their HP % can be read: their max HP is estimated from that level.
]]--

local buffs = require('core.buffs')

local tracked = { list = {} }

-- Average max HP at a level over every race and job: v2's table, which is this line.
function tracked.max_hp(level) return math.floor(54 + 15.7 * level) end

function tracked.find(sid)
    for _, t in ipairs(tracked.list) do if t.sid == sid then return t end end
end

-- Track a player; false when they already are.
function tracked.add(sid, name, tidx)
    if tracked.find(sid) then return false end
    tracked.list[#tracked.list + 1] = { sid = sid, name = name, tidx = tidx }
    return true
end

-- Stop tracking `name` (any case), forgetting their statuses; the entry, or nil.
function tracked.remove(name)
    for i, t in ipairs(tracked.list) do
        if t.name:lower() == name:lower() then
            buffs.forget(t.sid)
            return table.remove(tracked.list, i)
        end
    end
end

-- A /check's answer: jobs and levels, all 0 for a player who is /anon.
function tracked.checked(sid, main, main_lv, sub, sub_lv)
    local t = tracked.find(sid)
    if not t or main_lv == 0 then return end
    t.main, t.main_lv, t.sub, t.sub_lv = main, main_lv, sub, sub_lv
end

return tracked