--[[
    Sessions on one PC (boxing), as v2's party_share: every Sidekick session
    publishes a session file, config/addons/sidekick3/session_<Name>.txt, and
    reads the others'. No network: the files are the whole channel.

    session = { name, heartbeat = os.time() of the last write, running, epoch (its load's),
                members = { you first, then your party's players (trusts left out):
                            { sid, name, main, main_lv, sub, sub_lv, hpp, hp, max_hp, mpp, mp, here } },
                watch, calls, acks (remote control, below) }
    max_hp is 0 when unknown: a member not yet seen at full HP. `here`: in the
    owner's zone, so their HP is current (a member elsewhere has stale HP).
    The file ends with an `end` line: one without it was cut short.

    Auto-track: each session tracks the players other sessions list (core/tracked.lua,
    `auto` = the owner's name), but those in its own party or alliance, with no /check:
    the level and max HP come from the file. A file not written for STALE seconds (a
    session closed, crashed or logged out) or one that no longer lists a player drops
    its auto entries; hand-tracked players are never dropped, nor one declined (untracked by hand) added.

    Remote control: any session controls any other. A controller's file lists the
    sessions whose SK Settings it has open (`watch`) and the `act` calls it sent
    them (`do`, numbered, each addressed to its target's epoch: a reload starts a
    new one, and calls to the old one are dropped). The target applies each call
    once, in order, through its own model.actions (ui/model.lua says which it takes),
    and acknowledges the last in its own file (`ack`), which ends the controller's
    resending. A watched session also writes its view, view_<Name>.txt, for the
    controller to draw: only the target can build its catalog.
]]--

local tracked = require('core.tracked')

local share = {
    STALE = 5,      -- seconds without a write before a session counts as gone
    EVERY = 1,      -- seconds between publishing and reading...
    FAST = 0.25,    -- ...while one session watches or controls another
    GRACE = 15,     -- seconds an auto entry no file lists is kept before it's dropped
    LOADING = 60,   -- seconds a loading session (zoning, logged out) keeps its last roster up
    PRUNE = 3600,   -- seconds after which a file no one wrote (a crashed session's) is deleted
}

local VERSION = 'sk3 session 2'

-- Plain data (strings, numbers, booleans and tables of them) as one line of text,
-- and back: `act` calls and views go through files. Read with a parser of its
-- own, never run as Lua. A string's quotes, backslashes and control characters as \ddd.
function share.pack(v)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[%c"\\]', function (c) return ('\\%03d'):format(c:byte()) end) .. '"'
    elseif t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return nil end  -- no text reads back as it
        return v == math.floor(v) and math.abs(v) < 2 ^ 53 and ('%d'):format(v) or ('%.17g'):format(v)
    elseif t == 'boolean' then
        return v and 't' or 'f'
    elseif t == 'table' then
        local out = {}
        for k, x in pairs(v) do
            local key, value = share.pack(k), share.pack(x)
            if key and value then out[#out + 1] = key .. '=' .. value end
        end
        return '{' .. table.concat(out, ',') .. '}'
    end
end  -- anything else (a function, a number not finite) is left out of its table

-- The value at `s` position i, and the position after it; nil for none.
local function parse(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        local j = s:find('"', i + 1, true)
        if not j then return nil end
        return (s:sub(i + 1, j - 1):gsub('\\(%d%d%d)', function (d) return string.char(tonumber(d) % 256) end)), j + 1
    elseif c == 't' or c == 'f' then
        return c == 't', i + 1
    elseif c == '{' then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= '}' do
            local k, v
            k, i = parse(s, i)
            if k == nil or s:sub(i, i) ~= '=' then return nil end
            v, i = parse(s, i + 1)
            if v == nil then return nil end
            t[k] = v
            if s:sub(i, i) == ',' then i = i + 1 elseif s:sub(i, i) ~= '}' then return nil end
        end
        return t, i + 1
    end
    local n = s:match('^-?[%d.]+[eE]?[-+]?%d*', i)
    if not n or not tonumber(n) then return nil end
    return tonumber(n), i + #n
end

-- share.pack's text back as the value; nil for text cut short or not its own.
function share.unpack(s)
    if type(s) ~= 'string' then return nil end
    local ok, v, i = pcall(parse, s, 1)  -- a table nested past the C stack is no value either
    if ok and i == #s + 1 then return v end
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- The file's text for a roster (share.roster), whether it runs, and the os.time()
-- written at. `extra` (optional): { epoch, watch = { [name] = true }, calls (share.queue's
-- list), acks = { [sender] = { epoch, n } } }.
function share.encode(members, running, heartbeat, extra)
    extra = extra or {}
    local lines = { VERSION, ('%d %d %d'):format(heartbeat, running and 1 or 0, extra.epoch or 0) }
    for _, m in ipairs(members) do
        lines[#lines + 1] = ('%d %d %d %d %d %d %d %d %d %d %d %s'):format(m.sid, m.main or 0, m.main_lv or 0,
            m.sub or 0, m.sub_lv or 0, m.hpp or 0, m.hp or 0, m.max_hp or 0, m.mpp or 0, m.mp or 0,
            m.here and 1 or 0, m.name)
    end
    for _, name in ipairs(sorted_keys(extra.watch)) do lines[#lines + 1] = 'watch ' .. name end
    for _, c in ipairs(extra.calls or {}) do
        lines[#lines + 1] = ('do %s %d %d %s'):format(c.to, c.epoch, c.n, share.pack(c.call))
    end
    for _, name in ipairs(sorted_keys(extra.acks)) do
        local a = extra.acks[name]
        if a.n > 0 then lines[#lines + 1] = ('ack %s %d %d'):format(name, a.epoch, a.n) end
    end
    lines[#lines + 1] = 'end'
    return table.concat(lines, '\n') .. '\n'
end

-- A session from a file's text; nil for none, another version, or one caught mid-write.
-- Besides share.encode's fields: watch = { [name] = true }, calls = { { to, epoch, n, call } },
-- acks = { [sender] = { epoch, n } }.
function share.decode(text)
    if not text then return nil end
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do lines[#lines + 1] = line end
    if lines[1] ~= VERSION or not lines[2] or lines[#lines] ~= 'end' then return nil end
    local beat, running, epoch = lines[2]:match('^(%d+) ([01]) (%d+)$')
    if not beat then return nil end
    local s = { heartbeat = tonumber(beat), running = running == '1', epoch = tonumber(epoch), members = {},
                watch = {}, calls = {}, acks = {} }
    for i = 3, #lines - 1 do
        local line = lines[i]
        local f = { line:match('^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) ([01]) (.+)$') }
        local watch = line:match('^watch (%S+)$')
        local to, to_epoch, n, call = line:match('^do (%S+) (%d+) (%d+) (.+)$')
        local from, from_epoch, acked = line:match('^ack (%S+) (%d+) (%d+)$')
        if f[1] then
            s.members[#s.members + 1] = {
                sid = tonumber(f[1]), main = tonumber(f[2]), main_lv = tonumber(f[3]), sub = tonumber(f[4]),
                sub_lv = tonumber(f[5]), hpp = tonumber(f[6]), hp = tonumber(f[7]), max_hp = tonumber(f[8]),
                mpp = tonumber(f[9]), mp = tonumber(f[10]), here = f[11] == '1', name = f[12],
            }
        elseif watch then
            s.watch[watch] = true
        elseif to then  -- one that won't read is skipped: the next call's ack covers its number
            call = share.unpack(call)
            if type(call) == 'table' then
                s.calls[#s.calls + 1] = { to = to, epoch = tonumber(to_epoch), n = tonumber(n), call = call }
            end
        elseif from then
            s.acks[from] = { epoch = tonumber(from_epoch), n = tonumber(acked) }
        else
            return nil
        end
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
-- entries no live session has listed for GRACE seconds (at clock `now`), so a
-- hitch or a short roster doesn't forget a party's statuses. `listed` = { [sid] = true }:
-- you, your party and alliance, never tracked from a file; one dropped at once for
-- joining them keeps the statuses seen on them. A player several files list is taken from their own
-- session's file, else the first owner by name, so the owner stays put.
function share.sync(live, listed, now)
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
        if wanted[t.sid] then
            t.unlisted_at = nil
        else
            t.max_hp, t.shared_hpp = nil, nil  -- no file says now
            t.unlisted_at = t.unlisted_at or now
            if t.auto and (listed[t.sid] or now - t.unlisted_at >= share.GRACE) then tracked.drop(t.sid, listed[t.sid]) end
        end
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

-- Remote control ----------------------------------------------------------------

-- Queue `call` ({ fn, n = #args, args... }), numbered `n`, for the session `to` at its
-- `epoch`, on `pending`. A `set` straight after one of the same path for the same
-- session replaces it: a slider's drag sends only its latest value.
function share.queue(pending, to, epoch, call, n)
    for i = #pending, 1, -1 do
        local p = pending[i]
        if p.to == to then
            if call[1] == 'set' and p.call[1] == 'set' and p.call[2] == call[2] then table.remove(pending, i) end
            break
        end
    end
    pending[#pending + 1] = { to = to, epoch = epoch, n = n, call = call }
end

-- Drop the pending calls their session acknowledged (`me` at `epoch` sent them),
-- and those for a session gone or reloaded since (another epoch): never sent twice.
function share.settle(pending, live, me, epoch)
    for i = #pending, 1, -1 do
        local p = pending[i]
        local s = live[p.to]
        local ack = s and s.acks[me]
        if not s or s.epoch ~= p.epoch or ack and ack.epoch == epoch and ack.n >= p.n then table.remove(pending, i) end
    end
end

-- The calls live sessions sent `me` (at `epoch`) not applied yet, in order, as
-- { from, call }; `applied` = { [sender] = { epoch, n } } moves past them. A sender's
-- new epoch (a reload) starts again from its first call.
function share.inbox(live, me, epoch, applied)
    local out = {}
    for _, from in ipairs(sorted_keys(live)) do
        local s = live[from]
        local a = applied[from]
        if not a or a.epoch ~= s.epoch then a = { epoch = s.epoch, n = 0 }; applied[from] = a end
        local mine = {}
        for _, c in ipairs(s.calls) do
            if c.to == me and c.epoch == epoch and c.n > a.n then mine[#mine + 1] = c end
        end
        table.sort(mine, function (x, y) return x.n < y.n end)
        for _, c in ipairs(mine) do
            out[#out + 1] = { from = from, call = c.call }
            a.n = c.n
        end
    end
    return out
end

-- Whether a live session has `me`'s SK Settings open, or calls for `me` waiting.
function share.watched(live, me)
    for _, s in pairs(live) do
        if s.watch[me] then return true, true end
        for _, c in ipairs(s.calls) do
            if c.to == me then return false, true end
        end
    end
    return false, false
end

-- In game -----------------------------------------------------------------------

share.sessions = {}   -- the other live sessions, by owner name
share.views = {}      -- [owner name] = the view their session last published, for each one you watch
-- This load's epoch: calls sent before a reload are never applied after it.
share.epoch = os.time() * 1000 + math.floor(os.clock() * 1000) % 1000
local sessions = {}   -- [owner name] = the last session read whole from their file
local roster          -- what you last published: kept up while loading (zoning), LOADING seconds at most
local roster_at = 0   -- the clock when it was read
local mine            -- your name while your file is written
local next_at = 0
local pending, sent_n = {}, 0  -- calls sent to other sessions not acknowledged yet, and the last call's number
local applied = {}             -- [sender] = { epoch, n }: the last call applied from each
local published = true         -- your view's file may exist (one left by a crash is removed at the first tick)
local view_text                -- what it holds
local views_read = {}          -- [owner name] = the text of their view last read

local function dir() return ('%s\\config\\addons\\sidekick3\\'):format(AshitaCore:GetInstallPath()) end
local function path(name) return ('%ssession_%s.txt'):format(dir(), name) end
local function view_path(name) return ('%sview_%s.txt'):format(dir(), name) end

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

local function read(file)
    local f = io.open(file, 'r')
    if not f then return nil end
    local text = f:read('*a')
    f:close()
    return text
end

local function read_others(me)
    local ok, files = pcall(ashita.fs.get_dir, dir(), '.*', true)
    if not ok or not files then return end
    for _, file in ipairs(files) do
        local owner = tostring(file):match('^session_(.+)%.txt$')
        if owner and owner ~= me then
            local s = share.decode(read(path(owner)))
            if s and os.time() - s.heartbeat > share.PRUNE then
                os.remove(path(owner))  -- left by a session that crashed
                os.remove(view_path(owner))
            elseif s then
                sessions[owner] = s
            end
        end
    end
end

-- Your view in its file while another session watches you (nil: no one does,
-- and the file goes).
local function publish(name, view)
    local text = view and share.pack(view)
    if text then
        if text ~= view_text and write(view_path(name), text) then view_text, published = text, true end
    elseif published then
        os.remove(view_path(name))
        view_text, published = nil, false
    end
end

-- The views of the live sessions in `watching`, parsed only when changed; a file
-- caught mid-write keeps the last read, one gone (its session no longer sends it) is forgotten.
local function read_views(watching, live)
    for name in pairs(share.views) do
        if not (watching[name] and live[name]) then share.views[name], views_read[name] = nil, nil end
    end
    for name in pairs(watching) do
        if live[name] then
            local text = read(view_path(name))
            if not text then
                share.views[name], views_read[name] = nil, nil
            elseif text ~= views_read[name] then
                local v = share.unpack(text)
                if type(v) == 'table' then share.views[name], views_read[name] = v, text end
            end
        end
    end
end

-- Send `call` ({ fn, n = #args, args... }, an `act` call) to the live session `to`:
-- it goes in your file at the next write, and stays until `to` acknowledges it.
function share.send(to, call)
    local s = share.sessions[to]
    if not s then return false end
    if not pending[1] then next_at = 0 end  -- a first click goes at once; a drag rides FAST
    sent_n = sent_n + 1
    share.queue(pending, to, s.epoch, call, sent_n)
    return true
end

-- Publish, read and sync, at most every EVERY seconds (FAST while watching or
-- watched, or while calls wait either way). `g` is the snapshot (a loading one republishes the last roster, so a
-- zone isn't taken for a session gone, for LOADING seconds: past that, as after a
-- logout, your file is deleted). `status` gives `running`, `open` and `watching` (the
-- sessions whose SK Settings you have open: watched only while the HUD is); `hooks.apply(from, call)` applies a
-- call another session sent (never while loading), `hooks.view()` builds the view
-- a watcher draws.
function share.tick(g, clock, status, hooks)
    if clock < next_at then return share.sessions end
    next_at = clock + share.EVERY
    if not g.loading then
        roster, roster_at = share.roster(g), clock
    elseif roster and clock - roster_at > share.LOADING then
        roster = nil
        share.close()
    end
    if not roster then return share.sessions end
    local me = roster[1].name
    if mine and mine ~= me then share.close() end  -- another character now
    read_others(me)
    local live = share.live(sessions, os.time())
    sessions, share.sessions = live, live
    if not g.loading then
        for _, c in ipairs(share.inbox(live, me, share.epoch, applied)) do hooks.apply(c.from, c.call) end
    end
    share.settle(pending, live, me, share.epoch)
    local acks, watch = {}, {}
    for from, a in pairs(applied) do
        if live[from] then acks[from] = a end
    end
    for name in pairs(status.open and status.watching or {}) do
        if live[name] then watch[name] = true end
    end
    if write(path(me), share.encode(roster, status.running, os.time(),
            { epoch = share.epoch, watch = watch, calls = pending, acks = acks })) then
        mine = me
    end
    local watched, called = share.watched(live, me)
    if not g.loading then  -- a zone leaves the last view up
        local ok, view = true, nil
        if watched then ok, view = pcall(hooks.view) end
        publish(me, ok and view or nil)
    end
    read_views(watch, live)
    if pending[1] or next(watch) or watched or called then next_at = clock + share.FAST end
    if g.loading then return live end
    local listed = {}
    for _, u in ipairs(g.units) do
        if u.kind ~= 'tracked' then listed[u.sid] = true end
    end
    share.sync(live, listed, clock)
    return live
end

-- Remove your files on unload, so no closed session's file is left behind (the
-- others still keep its last read until it goes stale).
function share.close()
    if mine then
        os.remove(path(mine))
        os.remove(view_path(mine))
        mine, published, view_text = nil, false, nil
    end
end

return share
