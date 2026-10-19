--[[
    Players outside your party and alliance you look after too (/sk3 track),
    this session only, as in v2. core/game.lua makes each a unit of kind
    'tracked': healed, cleared, woken, raised, followed and buffed like a member,
    with what reaches outside the party (Cure, Curing Waltz, Protect, Haste, the
    -na spells, Raise; not Regen, Erase, or an area spell cast from you or a
    member, which lands on your own party only).

    entry = { sid, name, tidx = entity index last seen at, hpp, status = as last seen there,
              main, main_lv, sub, sub_lv = from a /check (packet 0x0C9), nil until one answers,
              auto = the owner's name when core/share.lua tracks them for another session,
              max_hp, shared_hpp = from a session file listing them (core/share.lua) }
    Only their HP % can be read: their max HP is estimated from that level, unless
    a session file gives the real one.
    An auto entry untracked by hand is `declined`: not tracked again by a session
    file until tracked by hand.
]]--

local buffs = require('core.buffs')
local util = require('core.util')

local tracked = { list = {}, declined = {} }

-- Average max HP at a level over every race and job: v2's table, which is this line.
function tracked.max_hp(level) return math.floor(54 + 15.7 * level) end

function tracked.find(sid)
    for _, t in ipairs(tracked.list) do if t.sid == sid then return t end end
end

-- Track a player; false when they already are. By hand (no `auto`), one a
-- session file tracked becomes your own, and one declined may come back.
function tracked.add(sid, name, tidx, auto)
    local t = tracked.find(sid)
    if not auto then tracked.declined[sid] = nil end
    if t then
        if not auto then t.auto = nil end
        return false
    end
    tracked.list[#tracked.list + 1] = { sid = sid, name = name, tidx = tidx, auto = auto }
    return true
end

-- Stop tracking server id `sid`, forgetting their statuses unless `keep` (one who
-- joined your party or alliance: still seen by the same packets); the entry, or nil.
function tracked.drop(sid, keep)
    for i, t in ipairs(tracked.list) do
        if t.sid == sid then
            if not keep then buffs.forget(sid) end
            return table.remove(tracked.list, i)
        end
    end
end

-- Stop tracking `name` (any case) by hand; the entry, or nil.
function tracked.remove(name)
    local t = util.named(tracked.list, name)
    if not t then return nil end
    if t.auto then tracked.declined[t.sid] = true end
    return tracked.drop(t.sid)
end

-- A /check's answer: jobs and levels, all 0 for a player who is /anon.
function tracked.checked(sid, main, main_lv, sub, sub_lv)
    local t = tracked.find(sid)
    if not t or main_lv == 0 then return end
    if main_lv ~= t.main_lv then t.max_hp = nil end  -- a session file's, for other jobs
    t.main, t.main_lv, t.sub, t.sub_lv = main, main_lv, sub, sub_lv
end

return tracked