--[[
    End-to-end tests in game (issue #56). A scenario (tests/e2e/<name>.lua) sets a scene with GM commands
    (tools/gm.lua), lets Sidekick act on it, and checks what it sent and what landed. The runner lives in Sidekick's
    own state, started and read through the VanaCore MCP's `lua` tool (or tools/e2e.mjs from a terminal):

        lua  addon = "Sidekick"  code = "return require('tools.e2e').run('heal')"     ('all': the suite)
        lua  addon = "Sidekick"  code = "return require('tools.e2e').status()"        (while it runs)
        lua  addon = "Sidekick"  code = "return require('tools.e2e').report()"        (each scenario's result)

    Nothing in Sidekick requires this file, and release zips leave tools/ out. Once loaded it watches, until
    Sidekick unloads (or e2e.unwatch()):
      - Sidekick itself, as it hands things on: `status` from share.tick (automation running, its intent and why, the
        sends it made, in English) and from engine.decide the snapshot, catalog and settings it decided on. Both are
        wrapped where they live, in their modules, and passed on untouched;
      - what went to the server: your actions (0x01A), item uses (0x037) and /heal (0x0E8);
      - what came back for your own actions (0x028): a cast or item begun, finished, interrupted, on whom;
      - while a scenario runs, the chat log's lines (the server's answers to GM commands).
    Everything a scene changes is undone after it, whatever the result (see `t.gm`), unless Sidekick unloads first.
]]--

local catalog = require('core.catalog')
local engine = require('core.engine')
local gm = require('tools.gm')
local settings = require('core.settings')
local share = require('core.share')
local tracked = require('core.tracked')

local e2e = {}

e2e.KEPT = 400        -- events kept
e2e.TIMEOUT = 120     -- seconds a scenario may take, its cleanup aside
e2e.CLEANUP = 90      -- ...and its cleanup
e2e.SUITE = 'tests.e2e.'
e2e.say = print       -- each scenario's result, as it finishes: the chat log

local TRUST = 0x1000000         -- server ids from here up are NPCs: a trust in a party slot
local INTERRUPT = 28787         -- 0x028's param for a cancelled action (core/packets.lua)
local BEGIN = { [8] = true, [9] = true }                 -- 0x028 categories: casting, using an item
local FINISH_OF = { ma = { [4] = true }, ja = { [6] = true, [14] = true, [15] = true }, item = { [5] = true } }
local ACTIONS = { [0x02] = 'attack', [0x03] = 'ma', [0x04] = 'attack_off', [0x07] = 'ws', [0x09] = 'ja',
                  [0x0D] = 'raise_menu', [0x10] = 'shoot' }  -- 0x01A's ActionID
local CAMP = { [0] = 'toggle', [1] = 'on', [2] = 'off' }     -- 0x0E8's Mode

local function clock() return vana and vana.time and vana.time.clock() or os.clock() end

---------------------------------------------------------------------------------------------------------------------
-- The event log

local log, seq = {}, 0

local function record(ev)
    seq = seq + 1
    ev.seq, ev.at = seq, ev.at or clock()
    log[#log + 1] = ev
    if #log > e2e.KEPT then table.remove(log, 1) end
    return ev
end

-- The events after sequence number `since` (0: all kept), of kind `kind` if given, oldest first.
function e2e.events(since, kind)
    local out = {}
    for _, ev in ipairs(log) do
        if ev.seq > (since or 0) and (not kind or ev.type == kind) then out[#out + 1] = ev end
    end
    return out
end

---------------------------------------------------------------------------------------------------------------------
-- Watching Sidekick

-- What Sidekick holds, caught as it hands it on: status (share.tick), and the snapshot `g`, catalog `list` and
-- settings `cfg` it last decided on (engine.decide).
local seen = {}
e2e.seen = seen

local known = setmetatable({}, { __mode = 'k' })  -- the entries of status.sent already recorded

local function watch()
    share.e2e_tick = share.e2e_tick or share.tick
    engine.e2e_decide = engine.e2e_decide or engine.decide
    local tick, decide = share.e2e_tick, engine.e2e_decide
    share.tick = function (g, now, status, hooks)
        if not seen.status then for _, s in ipairs(status.sent) do known[s] = true end end  -- no history
        seen.status = status
        return tick(g, now, status, hooks)
    end
    engine.decide = function (g, list, cfg, mem)
        seen.g, seen.list, seen.cfg = g, list, cfg
        return decide(g, list, cfg, mem)
    end
end

-- Text from the game (Shift-JIS) as UTF-8, for reports.
local function utf8(s)
    if s and vana and vana.encoding then return vana.encoding.from_shift_jis(s) end
    return s
end

-- Sidekick's new sends, oldest first, as `sent` events: its action's English name, kind, target, behavior and why.
local function new_sends()
    local sent = seen.status and seen.status.sent or {}
    for i = #sent, 1, -1 do
        local s = sent[i]
        if not known[s] then
            known[s] = true
            record({ type = 'sent', action = s.action, kind = s.kind, target = s.target, behavior = s.behavior,
                     why = s.why, command = utf8(s.command) })
        end
    end
end

-- The client's answer to a command it won't take (a spelling, a target it can't find), and the server's to an action
-- it won't let you do ("Dev cannot cast Arise.": a spell the client's data has at a lower level than the server's).
local REFUSED = 'A command error occurred'
local DENIED = { 'cannot cast', 'Unable to cast', 'cannot use', 'Unable to use' }
local function denied(text)
    for _, s in ipairs(DENIED) do if text:find(s, 1, true) then return true end end
end

local function u16(d, o) return d:byte(o + 1) + d:byte(o + 2) * 256 end
local function u32(d, o) return u16(d, o) + u16(d, o + 2) * 65536 end

local function name_at(index)
    local n = index > 0 and AshitaCore:GetMemoryManager():GetEntity():GetName(index)
    return n and n ~= '' and n or nil
end

local function my_sid() return AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) end

-- What went to the server: an action (0x01A), an item's use (0x037), /heal (0x0E8).
function e2e.packet_out(e)
    local d = e.data
    if e.id == 0x01A and #d >= 0x10 then
        local index, action = u16(d, 0x08), u16(d, 0x0A)
        record({ type = 'act', kind = ACTIONS[action] or action, id = u32(d, 0x0C), target = u32(d, 0x04),
                 index = index, name = name_at(index) })
    elseif e.id == 0x037 and #d >= 0x14 then
        local index, slot, bag = u16(d, 0x0C), d:byte(0x0E + 1), u32(d, 0x10)
        local item = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(bag, slot)
        record({ type = 'act', kind = 'item', id = item and item.Id or 0, target = u32(d, 0x04), index = index,
                 name = name_at(index) })
    elseif e.id == 0x0E8 and #d >= 0x08 then
        record({ type = 'camp', mode = CAMP[u32(d, 0x04)] or u32(d, 0x04) })
    end
end

-- 0x028, bit-packed as core/packets.lua reads it: your own actions only, each target's first result.
local raw, at, limit
local function bits(n)
    if at + n > limit then limit = 0; return 0 end
    local v = ashita.bits.unpack_be(raw, 0, at, n)
    at = at + n
    return v
end

function e2e.packet_in(e)
    if e.id ~= 0x028 then return end
    raw, at, limit = e.data_raw, 40, e.size * 8
    local actor = bits(32)
    if actor ~= my_sid() then return end
    local count = bits(6)
    bits(4)
    local category = bits(4)
    if category == 1 then return end  -- an auto-attack
    local param = bits(16)
    bits(16); bits(32)                -- recast
    local targets = {}
    for _ = 1, count do
        local t = { id = bits(32) }
        for k = 1, bits(4) do
            bits(17)                  -- resolution, kind, animation
            bits(5); bits(5)          -- info; scale, knockback
            local p, m = bits(17), bits(10)
            bits(31)                  -- flags
            if k == 1 then t.param, t.message = p, m end
            if bits(1) == 1 then bits(37) end  -- additional effect
            if bits(1) == 1 then bits(34) end  -- spikes
        end
        targets[#targets + 1] = t
    end
    if limit == 0 then return end
    local kind = param == INTERRUPT and 'interrupt' or BEGIN[category] and 'begin' or 'finish'
    -- What was cast or used: a finish names it in its param, a begin in its target's.
    local id = kind == 'finish' and param or targets[1] and targets[1].param
    record({ type = kind, category = category, id = id, targets = targets })
end

---------------------------------------------------------------------------------------------------------------------
-- Scenarios

local Stop = {}  -- the metatable of what t.fail and t.skip raise

local queue, run, results = {}, nil, {}

local function stop(kind, fmt, ...)
    error(setmetatable({ kind = kind, why = select('#', ...) > 0 and fmt:format(...) or fmt }, Stop), 0)
end

-- What a send should be: behavior, on (a name, any case; a send with no target is on you), action (its English
-- name), family (Cure for Cure III), kind ('ma', 'ja', 'item'...). Fields left out match anything.
local function matches(ev, want)
    return (not want.behavior or ev.behavior == want.behavior)
        and (not want.on or (ev.target or gm.me()):lower() == want.on:lower())
        and (not want.action or ev.action == want.action)
        and (not want.family or catalog.split(ev.action or '') == want.family)
        and (not want.kind or ev.kind == want.kind)
end

local function describe(want)
    local parts = {}
    for _, k in ipairs({ 'behavior', 'action', 'family', 'kind', 'on' }) do
        if want[k] then parts[#parts + 1] = k .. '=' .. tostring(want[k]) end
    end
    return '{' .. table.concat(parts, ' ') .. '}'
end

-- The context a scenario's run(t) gets.
local function context(r)
    local t = { name = r.name }

    -- Waiting: each a frame at a time, never past the scenario's time (or its cleanup's), nor an abort.
    local function frame()
        if r.aborted and not r.cleaning then stop(r.fault and 'error' or 'fail', r.fault or 'aborted') end
        if clock() > r.deadline then stop('fail', r.cleaning and 'cleanup ran out of time' or 'ran out of time') end
        coroutine.yield()
    end
    function t.wait(seconds)
        local til = clock() + seconds
        while clock() < til do frame() end
    end
    -- Until pred() gives a true value (returned, with the seconds it took), else a failure naming `what` (and the
    -- error pred last raised, if it did).
    function t.wait_for(pred, timeout, what)
        local start = clock()
        while true do
            local ok, v = pcall(pred)
            if ok and v then return v, clock() - start end
            if clock() - start >= timeout then
                stop('fail', '%s: not within %gs%s', what, timeout, ok and '' or ' (' .. tostring(v) .. ')')
            end
            frame()
        end
    end

    function t.fail(fmt, ...) stop('fail', fmt, ...) end
    function t.skip(fmt, ...) stop('skip', fmt, ...) end
    function t.check(ok, fmt, ...) if not ok then stop('fail', fmt, ...) end end
    function t.need(ok, fmt, ...) if not ok then stop('skip', fmt, ...) end end
    function t.note(fmt, ...) r.notes[#r.notes + 1] = select('#', ...) > 0 and fmt:format(...) or fmt end
    function t.time(label, seconds) r.timings[label] = math.floor(seconds * 1000 + 0.5) / 1000 end
    -- `fn` after the scenario, whatever its result; the last registered runs first.
    function t.finally(fn) r.undo[#r.undo + 1] = fn end

    -- Who's who: you, the first other player of your party, of the alliance's other parties, the first tracked
    -- player near you. A scenario that needs one there isn't skips.
    function t.me() return gm.me() end
    local function slot(first, last, what)
        local party = AshitaCore:GetMemoryManager():GetParty()
        local zone = party:GetMemberZone(0)
        for i = first, last do
            if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) < TRUST and party:GetMemberZone(i) == zone then
                return party:GetMemberName(i)
            end
        end
        t.skip('no %s in your zone', what)
    end
    function t.member() return slot(1, 5, 'other player in your party') end
    function t.ally() return slot(6, 17, 'player in the alliance\'s other parties') end
    function t.tracked()
        for _, x in ipairs(tracked.list) do
            local u = gm.who(x.name)
            if u and not u.slot then return x.name end
        end
        t.skip('no tracked player near you (/sk track <name>)')
    end
    function t.who(name) return gm.who(name) end
    function t.sid(name)
        local u = gm.who(name)
        if not u then t.fail('%s isn\'t near you', name) end
        return u.sid
    end

    -- Sidekick as it sees things: its settings, its catalog's action named `name` (else nil), its unit for a name.
    function t.cfg()
        if not seen.cfg then
            t.sk('plan')  -- decides once, which shows them
            t.wait_for(function () return seen.cfg end, 3, 'Sidekick\'s settings')
        end
        return seen.cfg
    end
    -- A setting for this scenario only: `path` 'rest.on', or a list of keys ({ 'rows', 'Protect' }) for a key with a
    -- dot or space in it. Set in Sidekick's own settings, which it reads as it decides, but not saved: a scenario cut
    -- short (Sidekick reloaded) leaves the file as it was. The value it had is put back after, and saved, in case
    -- something else saved meanwhile.
    function t.setting(path, value)
        local keys = type(path) == 'table' and path or {}
        if type(path) == 'string' then for k in path:gmatch('[^.]+') do keys[#keys + 1] = k end end
        local parent = t.cfg()
        for i = 1, #keys - 1 do parent = parent[keys[i]] end
        local last, old = keys[#keys], parent[keys[#keys]]
        parent[last] = value
        t.finally(function () parent[last] = old; settings.save() end)
        t.note('%s set for this scenario', table.concat(keys, '.'))
    end
    function t.actions()
        if not seen.list then t.cfg() end
        return seen.list or {}
    end
    function t.action(name)
        for _, a in ipairs(t.actions()) do if a.name == name then return a end end
    end
    function t.unit(name)
        for _, u in ipairs(seen.g and seen.g.units or {}) do
            if (u.name or ''):lower() == name:lower() then return u end
        end
    end
    function t.status() return seen.status end

    -- A /sk command, as typed.
    function t.sk(args) AshitaCore:GetChatManager():QueueCommand(1, '/sk ' .. args) end
    -- Automation on, from now (a start wakes AFK sleep too); off again afterwards if it was.
    function t.start()
        local s = t.wait_for(function () return seen.status end, 3, 'Sidekick\'s status')
        if not s.running then t.finally(function () t.sk('stop') end) end
        t.sk('start')
        t.wait_for(function () return s.running end, 3, 'automation on')
    end
    -- Until Sidekick has sent nothing for `quiet` seconds (3).
    function t.idle(quiet, timeout)
        quiet = quiet or 3
        local start = clock()
        t.wait_for(function ()
            local last = start
            for _, ev in ipairs(e2e.events(r.first, 'sent')) do last = math.max(last, ev.at) end
            return clock() - last >= quiet
        end, timeout or 30, ('Sidekick quiet for %gs'):format(quiet))
    end

    -- The scene: tools/gm.lua's commands, each the moment Sidekick's answer is timed from (t.since), and each undone
    -- after the scenario: HP and MP back to full (a death revived first), a status given taken off (and its death, a
    -- Doom's, undone), immortal toggled back, a mob brought or spawned gone.
    local function restore(who)
        return function ()
            local u = gm.who(who)
            if u and u.dead then t.revive(who) end
            gm.full(who)
        end
    end
    local UNDO = {
        hp = restore, mp = restore, tp = restore, kill = restore, hp_pct = restore, mp_pct = restore,
        effect = function (who, e)
            local back = restore(who)
            return function () gm.uneffect(who, e); back() end
        end,
        immortal = function (who) return function () gm.immortal(who) end end,
        mobhere = function (id) return function () gm.despawn(id) end end,
        spawn = function (id) return function () gm.despawn(id) end end,
    }
    local READS = { who = true, mob = true, cursor = true, me = true, present = true }  -- no scene: as they are
    t.gm = setmetatable({}, { __index = function (_, k)
        local f = gm[k]
        if type(f) ~= 'function' or READS[k] then return f end
        return function (...)
            local out = f(...)
            if UNDO[k] then t.finally(UNDO[k](...)) end
            t.since = clock()
            record({ type = 'gm', lines = type(out) == 'table' and out or { out } })
            return out
        end
    end })
    t.since = clock()

    -- A dead player on their feet again where they stood: their home point revives them (a warp, at full HP and MP),
    -- then !bring fetches them back. The raise menu is theirs to take, from their own game.
    function t.revive(who)
        local function back() local u = gm.who(who); return u and not u.dead and t.here(who) end
        gm.homepoint(who)
        t.wait(12)  -- warped, and loaded there
        gm.bring(who)
        if not pcall(t.wait_for, back, 15, who .. ' back') then  -- still loading at their home point: once more
            gm.bring(who)
            t.wait_for(back, 20, who .. ' back')
        end
    end
    -- Whether `who` stands near you (the client draws them).
    function t.here(who)
        local u = gm.who(who)
        return u ~= nil and u.index ~= nil and u.index > 0 and gm.present(AshitaCore:GetMemoryManager():GetEntity(), u.index)
    end

    -- Everyone near at full HP and MP, then Sidekick quiet: a scene starts from nothing to do.
    function t.settle()
        local names = { gm.me() }
        local party = AshitaCore:GetMemoryManager():GetParty()
        for i = 1, 17 do
            if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) < TRUST then names[#names + 1] = party:GetMemberName(i) end
        end
        for _, x in ipairs(tracked.list) do names[#names + 1] = x.name end
        for _, n in ipairs(names) do
            local u = gm.who(n)
            if u and not u.dead then gm.full(n) end
        end
        t.idle(3, 30)
        t.since = clock()
    end

    -- Sidekick's next send matching `want` since the scene changed (t.since), within `timeout` seconds; its time
    -- after the scene is timed as `label` (want.label, else the behavior).
    function t.expect(want, timeout)
        local ev, took = t.wait_for(function ()
            for _, x in ipairs(e2e.events(r.first, 'sent')) do
                if x.at >= t.since and matches(x, want) then return x end
            end
        end, timeout or 15, 'a send ' .. describe(want))
        ev.after = ev.at - t.since
        t.time(want.label or want.behavior or 'sent', ev.after)
        t.note('sent %s on %s (%s: %s) %.2fs after the scene', ev.action, tostring(ev.target), ev.behavior, ev.why,
            ev.after)
        return ev, took
    end
    -- Every event since the scenario began, oldest first, of `kind` if given (sent, act, begin, finish, interrupt,
    -- camp, gm, line).
    function t.events(kind) return e2e.events(r.first, kind) end
    -- Every send matching `want` since the scenario began, oldest first.
    function t.sends(want)
        local out = {}
        for _, x in ipairs(e2e.events(r.first, 'sent')) do if matches(x, want) then out[#out + 1] = x end end
        return out
    end
    -- Nothing matching `want` sent for `seconds` after the scene changed.
    function t.expect_none(want, seconds)
        local til = t.since + seconds
        while clock() < til do
            for _, x in ipairs(e2e.events(r.first, 'sent')) do
                if x.at >= t.since and matches(x, want) then
                    t.fail('sent %s on %s (%s: %s), expected none %s', x.action, tostring(x.target), x.behavior,
                        x.why, describe(want))
                end
            end
            frame()
        end
    end
    -- The send `ev` landing: your 0x028 finish of that kind on its target, within `timeout`; the client refusing the
    -- command, the server refusing the action or the cast interrupted fails it. Timed as `label` from the send.
    function t.lands(ev, timeout, label)
        local sid = t.sid(ev.target or gm.me())
        local finish = FINISH_OF[ev.kind]
        local done = t.wait_for(function ()
            for _, x in ipairs(e2e.events(ev.seq)) do
                if x.type == 'interrupt' then return x end
                if x.type == 'line' and (x.text:find(REFUSED, 1, true) or denied(x.text)) then return x end
                if x.type == 'finish' and (not finish or finish[x.category]) then
                    for _, tg in ipairs(x.targets) do if tg.id == sid then return x end end
                end
            end
        end, timeout or 20, ('%s landing on %s'):format(tostring(ev.action), tostring(ev.target)))
        t.check(done.type ~= 'line' or not done.text:find(REFUSED, 1, true), 'the client refused %s ("%s")',
            tostring(ev.command), REFUSED)
        t.check(done.type ~= 'line', 'the server refused %s on %s: %s', tostring(ev.action), tostring(ev.target),
            done.text and done.text:match('^[^\n]*'))
        t.check(done.type == 'finish', '%s on %s was interrupted', tostring(ev.action), tostring(ev.target))
        t.time(label or 'landed', done.at - ev.at)
        t.note('%s landed on %s %.2fs after the send (message %s)', ev.action, tostring(ev.target), done.at - ev.at,
            tostring(done.targets[1] and done.targets[1].message))
        return done
    end

    return t
end

local function start(name)
    local r = { name = name, notes = {}, timings = {}, undo = {}, began = clock(), first = seq }
    r.deadline = r.began + e2e.TIMEOUT
    package.loaded[e2e.SUITE .. name] = nil
    local ok, sc = pcall(require, e2e.SUITE .. name)
    if not ok or type(sc) ~= 'table' or type(sc.run) ~= 'function' then
        r.result, r.why = 'error', ok and 'no run(t) in tests/e2e/' .. name .. '.lua' or tostring(sc)
        return r
    end
    r.about = sc.about
    if sc.timeout then r.deadline = r.began + sc.timeout end
    local t = context(r)
    r.co = coroutine.create(function ()
        local okr, err = xpcall(sc.run, function (x)
            return getmetatable(x) == Stop and x or { kind = 'error', why = debug.traceback(tostring(x), 2) }
        end, t)
        if okr then r.result = 'pass' else r.result, r.why = err.kind, err.why end
        if r.result ~= 'pass' then
            -- What led up to it, before the cleanup: the last events, and what Sidekick thought then.
            local trail = e2e.events(r.first)
            r.trail = { unpack(trail, math.max(1, #trail - 14)) }
            local s = seen.status
            r.sidekick = s and { running = s.running, why = s.why, intent = s.intent and s.intent.action } or nil
        end
        r.cleaning, r.deadline = true, clock() + e2e.CLEANUP
        for i = #r.undo, 1, -1 do
            local ok_undo, e = pcall(r.undo[i])
            if not ok_undo then
                local why = getmetatable(e) == Stop and e.why or tostring(e)
                r.notes[#r.notes + 1] = 'cleanup: ' .. why
                if r.result == 'pass' then r.result, r.why = 'error', 'cleanup: ' .. why end
            end
        end
    end)
    return r
end

local function finish(r)
    if r.fault and r.result == 'pass' then r.result, r.why = 'error', r.fault end  -- a fault in its cleanup
    local out = { name = r.name, about = r.about, result = r.result, why = r.why, notes = r.notes, timings = r.timings,
                  seconds = math.floor((clock() - r.began) * 10 + 0.5) / 10, trail = r.trail, sidekick = r.sidekick }
    if r.result ~= 'pass' and not out.trail then  -- it never ran (it didn't load), or the runner failed it
        local trail = e2e.events(r.first)
        out.trail = { unpack(trail, math.max(1, #trail - 14)) }
    end
    r.co, r.undo = nil, nil
    results[#results + 1] = out
    e2e.say(('[e2e] %s: %s%s'):format(r.name, r.result, r.why and (' - ' .. r.why:match('^[^\n]*')) or ''))
end

-- Each frame: Sidekick's new sends, then the scenario running (or the next one queued) a step on.
local function step()
    new_sends()
    if not run then
        local name = table.remove(queue, 1)
        if not name then return end
        run = start(name)
        if not run.co then finish(run); run = nil; return end
    end
    local ok, err = coroutine.resume(run.co)
    if not ok then run.result, run.why = 'error', tostring(err) end
    if not ok or coroutine.status(run.co) == 'dead' then
        finish(run)
        run = nil
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Control

-- The suite's scenarios, in order (tests/e2e/suite.lua).
function e2e.suite()
    package.loaded[e2e.SUITE .. 'suite'] = nil
    return require(e2e.SUITE .. 'suite')
end

-- The suite's scenarios with what each checks: { { name, about } ... }.
function e2e.list()
    local out = {}
    for i, name in ipairs(e2e.suite()) do
        package.loaded[e2e.SUITE .. name] = nil
        local ok, sc = pcall(require, e2e.SUITE .. name)
        out[i] = { name = name, about = ok and type(sc) == 'table' and sc.about or ('does not load: ' .. tostring(sc)) }
    end
    return out
end

-- Queue scenarios by name ('all': the suite) to run one after another; the queue as it stands.
function e2e.run(...)
    for _, name in ipairs({ ... }) do
        if name == 'all' then
            for _, n in ipairs(e2e.suite()) do queue[#queue + 1] = n end
        else
            queue[#queue + 1] = name
        end
    end
    return { running = run and run.name, queued = { unpack(queue) } }
end

-- Stop: the queue emptied, the scenario running failed at its next wait (its cleanup still runs).
function e2e.abort()
    queue = {}
    if run then run.aborted = true end
end

-- What's running: the scenario, for how long, its latest notes; what's queued; how many have finished.
function e2e.status()
    return { running = run and run.name, cleaning = run and run.cleaning or nil,
             seconds = run and math.floor(clock() - run.began) or nil,
             notes = run and { unpack(run.notes, math.max(1, #run.notes - 4)) } or nil,
             queued = { unpack(queue) }, finished = #results }
end

-- The finished scenarios' results, oldest first (from the `from`th; all by default): result (pass, fail, skip,
-- error), why, seconds, notes, timings; for one that didn't pass, its last events and what Sidekick thought.
function e2e.report(from)
    return { unpack(results, from or 1) }
end

function e2e.clear() results = {} end

-- Unhook: Sidekick's functions back as they were, the events dropped; true when done. Not while a scenario runs,
-- whose cleanup needs the frames: it's aborted instead, and false returned. Unwatch again once status() shows none.
function e2e.unwatch()
    e2e.abort()
    if run then return false end
    if share.e2e_tick then share.tick, share.e2e_tick = share.e2e_tick, nil end
    if engine.e2e_decide then engine.decide, engine.e2e_decide = engine.e2e_decide, nil end
    for _, ev in ipairs({ 'packet_in', 'packet_out', 'text_in', 'd3d_present' }) do
        pcall(ashita.events.unregister, ev, 'sidekick_e2e_' .. ev)
    end
    return true
end

-- A step that fails ends the scenario running as an error, never the game's frame: an error a frame for five
-- seconds would unload Sidekick (VanaCore's rule). The scenario fails at its next wait, so its cleanup still runs;
-- should the frame's own step (`drives`) fail again, as it would every frame, it ends there, its cleanup cut short.
local function guarded(fn, drives)
    return function (...)
        local ok, err = pcall(fn, ...)
        if ok or not run then return end
        if drives and run.fault then
            run.result, run.why, run.co = 'error', run.fault, nil
            finish(run)
            run = nil
        elseif not run.fault then
            run.fault, run.aborted = 'runner: ' .. tostring(err), true
        end
    end
end

if ashita and ashita.events then
    watch()
    ashita.events.register('packet_in', 'sidekick_e2e_packet_in', guarded(e2e.packet_in))
    ashita.events.register('packet_out', 'sidekick_e2e_packet_out', guarded(e2e.packet_out))
    ashita.events.register('text_in', 'sidekick_e2e_text_in', guarded(function (e)
        if run then record({ type = 'line', mode = bit.band(e.mode, 0xFF), text = (e.message:gsub('[\30\31\127].', '')) }) end
    end))
    ashita.events.register('d3d_present', 'sidekick_e2e_d3d_present', guarded(step, true))
end

return e2e
