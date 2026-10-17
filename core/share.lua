--[[
    Sessions on one PC (boxing), as v2's party_share: every Sidekick session
    publishes a session file, config/addons/sidekick3/session_<Name>.txt, and
    reads the others'. No network: the files are the whole channel.

    session = { name, heartbeat = os.time() of the last write, running,
                members = { you first, then your party's players (trusts left out):
                            { sid, name, main, main_lv, sub, sub_lv, hpp, hp, max_hp, mpp, mp, here } } }
    max_hp is 0 when unknown: a member not yet seen at full HP. `here`: in the
    owner's zone, so their HP is current (a member elsewhere has stale HP).
    The file ends with an `end` line: one without it was cut short.

    Auto-track: each session tracks the players other sessions list (core/tracked.lua,
    `auto` = the owner's name), but those in its own party or alliance, with no /check:
    the level and max HP come from the file. A file not written for STALE seconds (a
    session closed, crashed or logged out) or one that no longer lists a player drops
    its auto entries; hand-tracked players are never dropped, nor one declined (untracked by hand) added.
]]--

local tracked = require('core.tracked')

local share = {
    STALE = 5,  -- seconds without a write before a session counts as gone
    EVERY = 1,  -- seconds between publishing and reading
}

local VERSION = 'sk3 session 1'

-- The file's text for a roster (share.roster), whether it runs, and the os.time() written at.
function share.encode(members, running, heartbeat)
    local lines = { VERSION, ('%d %d'):format(heartbeat, running and 1 or 0) }
    for _, m in ipairs(members) do
        lines[#lines + 1] = ('%d %d %d %d %d %d %d %d %d %d %d %s'):format(m.sid, m.main or 0, m.main_lv or 0,
            m.sub or 0, m.sub_lv or 0, m.hpp or 0, m.hp or 0, m.max_hp or 0, m.mpp or 0, m.mp or 0,
            m.here and 1 or 0, m.name)
    end
    lines[#lines + 1] = 'end'
    return table.concat(lines, '\n') .. '\n'
end

-- A session from a file's text; nil for none, another version, or one caught mid-write.
function share.decode(text)
    if not text then return nil end
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do lines[#lines + 1] = line end
    if lines[1] ~= VERSION or not lines[2] or lines[#lines] ~= 'end' then return nil end
    local beat, running = lines[2]:match('^(%d+) ([01])$')
    if not beat then return nil end
    local s = { heartbeat = tonumber(beat), running = running == '1', members = {} }
    for i = 3, #lines - 1 do
        local f = { lines[i]:match('^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) ([01]) (.+)$') }
        if not f[1] then return nil end
        s.members[#s.members + 1] = {
            sid = tonumber(f[1]), main = tonumber(f[2]), main_lv = tonumber(f[3]), sub = tonumber(f[4]),
            sub_lv = tonumber(f[5]), hpp = tonumber(f[6]), hp = tonumber(f[7]), max_hp = tonumber(f[8]),
            mpp = tonumber(f[9]), mp = tonumber(f[10]), here = f[11] == '1', name = f[12],
        }
    end
    if not s.members[1] then return nil end
    s.name = s.members[1].name
    return s
end

-- What your session publishes: you and your party's players, from the snapshot.
-- A member's max HP only when seen (yours always is). One the client hasn't
-- filled in yet (no server id or name: just joined, zoning) is left out.
function share.roster(g)
    local out = {}
    for _, u in ipairs(g.units) do
        if (u.kind == 'self' or u.kind == 'party') and (u.sid or 0) > 0 and (u.name or '') ~= '' then
            local j = u.jobs or {}
            out[#out + 1] = { sid = u.sid, name = u.name, hpp = u.hpp, hp = u.hp, mpp = u.mpp, mp = u.mp,
                              max_hp = u.max_known and u.max_hp or 0, here = u.in_zone == true,
                              main = j[1], main_lv = j[2], sub = j[3], sub_lv = j[4] }
        end
    end
    return out
end

-- The other sessions still alive at os.time() `now`, by name.
function share.live(sessions, now)
    local out = {}
    for name, s in pairs(sessions) do
        if now - s.heartbeat <= share.STALE then out[name] = s end
    end
    return out
end

-- Bring the tracked list in line with the live sessions: add who they list
-- (as `auto`), refresh what each file says of anyone tracked, and drop the auto
-- entries no live session lists. `listed` = { [sid] = true }: you, your party and
-- alliance, never tracked from a file; one dropped for joining them keeps the
-- statuses seen on them. A player several files list is taken from their own
-- session's file, else the first owner by name, so the owner stays put.
function share.sync(live, listed)
    local owners = {}
    for owner in pairs(live) do owners[#owners + 1] = owner end
    table.sort(owners)
    local wanted = {}  -- [sid] = { member, owner name }
    for _, owner in ipairs(owners) do
        for i, m in ipairs(live[owner].members) do
            local w = wanted[m.sid]
            if not listed[m.sid] and (not w or i == 1 and not w.own) then
                wanted[m.sid] = { m = m, owner = owner, own = i == 1 }
            end
        end
    end
    for i = #tracked.list, 1, -1 do
        local t = tracked.list[i]
        if t.auto and not wanted[t.sid] then tracked.drop(t.sid, listed[t.sid]) end
        if not wanted[t.sid] then t.max_hp, t.shared_hpp = nil, nil end  -- hand-tracked: no file says now
    end
    for sid, w in pairs(wanted) do
        local m, t = w.m, tracked.find(sid)
        if not t and not tracked.declined[sid] then
            tracked.add(sid, m.name, nil, w.owner)
            t = tracked.find(sid)
        end
        if t then
            if t.auto then t.auto = w.owner end
            if m.main_lv > 0 then t.main, t.main_lv, t.sub, t.sub_lv = m.main, m.main_lv, m.sub, m.sub_lv end
            t.max_hp = m.max_hp > 0 and m.max_hp or t.max_hp
            t.shared_hpp = m.here and m.hpp or nil
        end
    end
end

-- A player some live session lists, or nil: a hand track needs no /check for them.
function share.known(live, sid)
    for _, s in pairs(live) do
        for _, m in ipairs(s.members) do
            if m.sid == sid and m.main_lv > 0 then return m end
        end
    end
end

-- A player some live session lists by `name` (any case), as { sid, name }, or nil:
-- one out of your sight can still be tracked by name.
function share.named(live, name)
    name = name:lower()
    for _, s in pairs(live) do
        for _, m in ipairs(s.members) do
            if m.name:lower() == name then return { sid = m.sid, name = m.name } end
        end
    end
end

-- In game -----------------------------------------------------------------------

share.sessions = {}   -- the other live sessions, by owner name
local sessions = {}   -- [owner name] = the last session read whole from their file
local roster          -- what you last published: kept up while loading (zoning)
local mine            -- your file's path while one is written
local next_at = 0

local function dir() return ('%s\\config\\addons\\sidekick3\\'):format(AshitaCore:GetInstallPath()) end
local function path(name) return ('%ssession_%s.txt'):format(dir(), name) end

-- Swap the file in whole: a reader catching the gap reads nothing and keeps
-- what it read last (os.rename can't replace a file on Windows).
local function write(file, text)
    local tmp = file .. '.tmp'
    local f = io.open(tmp, 'w')
    if not f then return false end
    local ok = f:write(text)
    if not f:close() or not ok then os.remove(tmp); return false end
    os.remove(file)
    if os.rename(tmp, file) then return true end
    os.remove(tmp)
    return false
end

local function read_others(me)
    local ok, files = pcall(ashita.fs.get_dir, dir(), '.*', true)
    if not ok or not files then return end
    for _, file in ipairs(files) do
        local owner = tostring(file):match('^session_(.+)%.txt$')
        if owner and owner ~= me then
            local f = io.open(path(owner), 'r')
            local s = f and share.decode(f:read('*a'))
            if f then f:close() end
            if s then sessions[owner] = s end
        end
    end
end

-- Publish, read and sync, at most every EVERY seconds. `g` is the snapshot (a
-- loading one republishes the last roster, so a zone isn't taken for a session gone).
function share.tick(g, running, clock)
    if clock < next_at then return share.sessions end
    next_at = clock + share.EVERY
    if not g.loading then roster = share.roster(g) end
    if not roster then return share.sessions end
    local me = roster[1].name
    local file = path(me)
    if mine and mine ~= file then os.remove(mine) end  -- another character now
    if write(file, share.encode(roster, running, os.time())) then mine = file end
    read_others(me)
    local live = share.live(sessions, os.time())
    sessions, share.sessions = live, live
    if g.loading then return live end
    local listed = {}
    for _, u in ipairs(g.units) do
        if u.kind ~= 'tracked' then listed[u.sid] = true end
    end
    share.sync(live, listed)
    return live
end

-- Remove your file on unload, so no closed session's file is left behind (the
-- others still keep its last read until it goes stale).
function share.close()
    if mine then os.remove(mine); mine = nil end
end

return share
