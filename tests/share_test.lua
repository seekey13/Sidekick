-- Sessions on one PC (core/share.lua): the session file's text, staleness, and
-- auto-track syncing the tracked list with what other sessions list.
local buffs = require('core.buffs')
local share = require('core.share')
local tracked = require('core.tracked')
local fake = require('tests.fake')

local WHM, BLM, RDM, WAR, PROTECT = 3, 4, 5, 1, 40

local function member(sid, name, over)
    local m = { sid = sid, name = name, main = WHM, main_lv = 75, sub = BLM, sub_lv = 37,
                hpp = 80, hp = 800, max_hp = 1000, mpp = 50, mp = 400, here = true }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

local function session(name, beat, members)
    return { name = name, heartbeat = beat, running = false, members = members }
end

local function reset() tracked.list, tracked.declined = {}, {} end

-- The file -----------------------------------------------------------------------

test('a session file reads back as written: running, heartbeat, you first, names with spaces', function ()
    local text = share.encode({ member(10, 'Box'), member(11, 'Two Words', { max_hp = 0 }) }, true, 1700000000)
    local s = share.decode(text)
    eq({ s.name, s.heartbeat, s.running, #s.members }, { 'Box', 1700000000, true, 2 })
    eq(s.members[2], member(11, 'Two Words', { max_hp = 0 }))
end)

test('a file caught mid-write, empty or of another version reads as nothing', function ()
    local text = share.encode({ member(10, 'Box') }, false, 5)
    eq(share.decode(nil), nil)
    eq(share.decode(''), nil)
    eq(share.decode(text:sub(1, #text - 12)), nil)  -- the last line cut short
    eq(share.decode(text:sub(1, #text - 6)), nil)   -- cut after the name: the end line is missing
    eq(share.decode((text:gsub('session 3', 'session 2'))), nil)
    eq(share.decode('sk3 session 3\n5 0 0\nend\n'), nil)  -- no members
    eq(share.decode((text:gsub('\nend', '\nwhat 1\nend'))), nil)  -- a line of no kind it knows
end)

test('what its automation just sent reads back, no target when on itself; one that won\'t read is left out', function ()
    local act = { behavior = 'heal', action = 'Cure IV', target = 'Two Words' }
    local text = share.encode({ member(10, 'Box') }, true, 5, { act = act })
    eq(share.decode(text).act, act)
    local song = { behavior = 'song', action = 'Valor Minuet IV' }
    eq(share.decode(share.encode({ member(10, 'Box') }, true, 5, { act = song })).act, song)
    eq(share.decode(share.encode({ member(10, 'Box') }, true, 5)).act, nil)
    for _, bad in ipairs({ 'act {1="heal"', 'act {behavior="heal"}', 'act {behavior="heal",action="Cure",target=3}', 'act 42' }) do
        local s = share.decode((text:gsub('act [^\n]+', bad)))
        eq({ s.name, s.act }, { 'Box', nil }, bad)
    end
end)

test('remote control lines read back: who it watches, its calls and its acknowledgements, its epoch', function ()
    local calls = { { to = 'Two', epoch = 7, n = 3, call = { 'set', n = 2, 'heal.danger', 60 } },
                    { to = 'Two', epoch = 7, n = 4, call = { 'pick', n = 2, 'Protect' } } }  -- Auto: a nil after the key
    local text = share.encode({ member(10, 'Box') }, false, 5,
        { epoch = 1234, watch = { Two = true, Three = true }, calls = calls, acks = { Two = { epoch = 9, n = 12 }, Idle = { epoch = 1, n = 0 } } })
    local s = share.decode(text)
    eq({ s.epoch, s.watch, s.calls, s.acks }, { 1234, { Two = true, Three = true }, calls, { Two = { epoch = 9, n = 12 } } })
    eq(share.decode((text:gsub('do Two 7 4 [^\n]+', 'do Two 7 4 {1="pick",2="Prot'))).calls, { calls[1] })  -- one cut short: skipped
end)

test('pack and unpack: nested plain data round trips, quotes, backslashes and new lines in strings', function ()
    local v = { 1, -2.5, 'a "q" \\ b\nc', true, false, { x = { [3] = 'y' }, ['k=v,}'] = 1e20 }, n = 6 }
    eq(share.unpack(share.pack(v)), v)
    eq(share.pack('a\nb'):find('\n'), nil)  -- one line, whatever the strings hold
    eq(share.unpack(share.pack({ f = print, k = 1 })), { k = 1 })  -- a function is left out
    for _, bad in ipairs({ '', '{', '{1=}', '{1=2', '"abc', '{1=2}x', 'return 1', '{["a"]=1}', 'os.exit()', 42 }) do
        eq(share.unpack(bad), nil, tostring(bad))
    end
    eq(share.unpack(('{1='):rep(100000)), nil)  -- nested past the stack: nothing, no error
    eq({ share.pack(1 / 0), share.pack(0 / 0), share.unpack(share.pack({ 'set', 1 / 0, -1 / 0, 0 / 0, 5 })) },
       { nil, nil, { 'set', [5] = 5 } })  -- no text reads back as them: left out
end)

test('a call that won\'t read is skipped, the rest of its file still read', function ()
    local calls = { { to = 'Two', epoch = 7, n = 3, call = { 'run', n = 1, true } } }
    local text = share.encode({ member(10, 'Box') }, false, 5, { epoch = 1, calls = calls })
    local s = share.decode((text:gsub('\nend', '\ndo Two 7 2 {1="run",2=inf}\nend')))
    eq({ s.name, s.calls }, { 'Box', calls })
end)

test('the roster is you and your party\'s players with their jobs; a max HP only once known', function ()
    local g = fake.snap({ { name = 'P1', jobs = { RDM, 70, WAR, 35 }, max_known = true },
                          { name = 'Trust', kind = 'trust' },
                          { name = 'B0', kind = 'alliance' },
                          { name = 'Out', kind = 'tracked' },
                          { name = 'P2', hpp = 40, in_zone = false },
                          { name = '' } })  -- not filled in yet: left out, not a file no one can read
    g.me.jobs, g.me.max_known = { WHM, 75, BLM, 37 }, true
    local r = share.roster(g)
    eq(#r, 3)
    eq({ r[1].name, r[1].main, r[1].main_lv, r[1].max_hp }, { 'Me', WHM, 75, 1000 })
    eq({ r[2].name, r[2].main, r[2].sub_lv, r[2].max_hp }, { 'P1', RDM, 35, 1000 })
    eq({ r[3].name, r[3].hpp, r[3].max_hp, r[3].main, r[3].here, r[2].here }, { 'P2', 40, 0, nil, false, true })
    eq(share.decode(share.encode(r, false, 1)).members[3].main_lv, 0)  -- unknown jobs as 0
end)

test('a session is live until STALE seconds pass without a write', function ()
    local all = { A = session('A', 100, {}), B = session('B', 94, {}) }
    local live = share.live(all, 100 + share.STALE - 1)
    eq({ live.A ~= nil, live.B ~= nil }, { true, false })
end)

-- Auto-track ---------------------------------------------------------------------

test('auto-track: another session\'s party is tracked with its levels and max HP, no /check needed', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { main = RDM, max_hp = 0 }) }) }, { [1] = true }, 0)
    eq(#tracked.list, 2)
    local t = tracked.find(501)
    eq({ t.name, t.auto, t.main, t.main_lv, t.max_hp, t.shared_hpp }, { 'Mate', 'Box', RDM, 75, nil, 80 })
    eq(tracked.find(500).max_hp, 1000)
    eq(share.known({ Box = session('Box', 1, { member(500, 'Box') }) }, 500).main_lv, 75)
    eq(share.known({ Box = session('Box', 1, { member(500, 'Box', { main_lv = 0 }) }) }, 500), nil)  -- /anon
    reset()
end)

test('auto-track: nobody in your own party or alliance, you included', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(1, 'Me'), member(101, 'P1') }) },
        { [1] = true, [101] = true }, 0)
    eq({ #tracked.list, tracked.list[1].sid }, { 1, 500 })
    -- Box joins your party: their entry goes, they're a member now
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, { [1] = true, [500] = true }, 0)
    eq(#tracked.list, 0)
    reset()
end)

test('auto-track: a player no live session lists is dropped after GRACE seconds, statuses and all', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate') }) }, {}, 0)
    buffs.gain(501, PROTECT, 0)
    local short = { Box = session('Box', 2, { member(500, 'Box') }) }  -- Mate left Box's party, or a short roster
    share.sync(short, {}, 1)
    eq({ #tracked.list, tracked.find(501).shared_hpp, buffs.of(501, 1) }, { 2, nil, { [PROTECT] = true } })
    share.sync({ Box = session('Box', 3, { member(500, 'Box'), member(501, 'Mate') }) }, {}, 5)  -- back: kept
    share.sync(short, {}, 6)
    share.sync(short, {}, 6 + share.GRACE - 1)
    eq(#tracked.list, 2)
    share.sync(short, {}, 6 + share.GRACE)
    eq({ #tracked.list, tracked.find(501), buffs.of(501, 1) }, { 1, nil, {} })
    share.sync({}, {}, 30)  -- Box's session gone
    share.sync({}, {}, 30 + share.GRACE)
    eq(#tracked.list, 0)
    reset()
end)

test('auto-track: hand-tracked players are never dropped, and get what the file says', function ()
    reset()
    tracked.add(501, 'Mate', 1100)
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { main = RDM }) }) }, {}, 0)
    local t = tracked.find(501)
    eq({ t.auto, t.main, t.max_hp }, { nil, RDM, 1000 })
    share.sync({}, {}, 0)
    share.sync({}, {}, share.GRACE)
    eq({ #tracked.list, tracked.list[1].sid }, { 1, 501 })
    reset()
end)

test('auto-track: tracking one by hand makes them yours, kept when the file stops listing them', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {}, 0)
    eq(tracked.add(500, 'Box', 1100), false)  -- already tracked
    eq(tracked.find(500).auto, nil)
    share.sync({}, {}, 0)
    eq(#tracked.list, 1)
    reset()
end)

test('auto-track: one untracked by hand stays off until tracked by hand again', function ()
    reset()
    local live = { Box = session('Box', 1, { member(500, 'Box') }) }
    share.sync(live, {}, 0)
    eq(tracked.remove('box').auto, 'Box')
    share.sync(live, {}, 0)
    eq(#tracked.list, 0)
    tracked.add(500, 'Box', 1100)
    share.sync(live, {}, 0)
    eq({ #tracked.list, tracked.list[1].auto }, { 1, nil })
    reset()
end)

test('auto-track: an /anon member\'s level from the file (0) never hides one known', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {}, 0)
    share.sync({ Box = session('Box', 2, { member(500, 'Box', { main = 0, main_lv = 0, sub = 0, sub_lv = 0, max_hp = 0 }) }) }, {}, 0)
    local t = tracked.find(500)
    eq({ t.main, t.main_lv, t.max_hp }, { WHM, 75, 1000 })
    reset()
end)

test('auto-track: one who joins your alliance keeps the statuses seen on them', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {}, 0)
    buffs.gain(500, PROTECT, 0)
    share.sync({ Box = session('Box', 2, { member(500, 'Box') }) }, { [500] = true }, 0)
    eq({ #tracked.list, buffs.of(500, 1) }, { 0, { [PROTECT] = true } })
    buffs.clear()
    reset()
end)

test('auto-track: HP from a file only for a member in its owner\'s zone; dropped when no file lists them', function ()
    reset()
    tracked.add(501, 'Mate', 1100)
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { here = false }) }) }, {}, 0)
    local t = tracked.find(501)
    eq({ t.shared_hpp, t.max_hp, tracked.find(500).shared_hpp }, { nil, 1000, 80 })
    share.sync({}, {}, 0)  -- hand-tracked, no file lists them now: nothing of the file's kept
    eq({ t.shared_hpp, t.max_hp, t.main_lv }, { nil, nil, 75 })
    reset()
end)

test('auto-track: a player two sessions list comes from their own session\'s file, whatever the order', function ()
    reset()
    local live = { A = session('A', 1, { member(500, 'A'), member(600, 'B', { hpp = 10 }) }),
                   B = session('B', 1, { member(600, 'B', { hpp = 90 }), member(500, 'A', { hpp = 20 }) }) }
    share.sync(live, {}, 0)
    eq({ tracked.find(500).auto, tracked.find(500).shared_hpp, tracked.find(600).auto, tracked.find(600).shared_hpp },
       { 'A', 80, 'B', 90 })
    reset()
end)

test('a player a session lists can be found by name, in any case, out of sight', function ()
    local live = { Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate') }) }
    eq(share.named(live, 'mate'), { sid = 501, name = 'Mate' })
    eq(share.named(live, 'nobody'), nil)
end)

test('a /check at another level drops the max HP a file gave', function ()
    reset()
    tracked.add(501, 'Mate', 1100)
    local t = tracked.find(501)
    t.main_lv, t.max_hp = 75, 2000
    tracked.checked(501, WHM, 75, BLM, 37)
    eq(t.max_hp, 2000)
    tracked.checked(501, WHM, 60, BLM, 30)
    eq(t.max_hp, nil)
    reset()
end)

-- Remote control ----------------------------------------------------------------

local function call(fn, ...) return { fn, n = select('#', ...), ... } end

test('/sk3 start|stop reaches you, a session by name in any case, or you and every session with all', function ()
    local live = { Beta = session('Beta', 1, { member(2, 'Beta') }), Gamma = session('Gamma', 1, { member(3, 'Gamma') }) }
    eq({ share.reach(live, 'Alpha', nil) }, { true, {} })
    eq({ share.reach(live, 'Alpha', 'alpha') }, { true, {} })
    eq({ share.reach(live, 'Alpha', 'gAMMA') }, { false, { 'Gamma' } })
    eq({ share.reach(live, 'Alpha', 'ALL') }, { true, { 'Beta', 'Gamma' } })
    eq({ share.reach({}, 'Alpha', 'all') }, { true, {} })
    eq({ select('#', share.reach(live, 'Alpha', 'Nobody')), share.reach(live, 'Alpha', 'Nobody') }, { 2 })
    eq({ share.reach(live, 'All', 'all') }, { true, {} })  -- you, named All: this session alone
    live.All = session('All', 1, { member(4, 'All') })  -- a character named All is that session
    eq({ share.reach(live, 'Alpha', 'all') }, { false, { 'All' } })
end)

test('a slider\'s drag queues only its latest value; anything between keeps both', function ()
    local pending = {}
    share.queue(pending, 'Two', 7, call('set', 'heal.danger', 50), 1)
    share.queue(pending, 'Three', 8, call('set', 'heal.danger', 10), 2)  -- another session's
    share.queue(pending, 'Two', 7, call('set', 'heal.danger', 55), 3)
    eq({ #pending, pending[2].n, pending[2].call[3] }, { 2, 3, 55 })
    share.queue(pending, 'Two', 7, call('save_profile', 'X'), 4)
    share.queue(pending, 'Two', 7, call('set', 'heal.danger', 60), 5)  -- after a save: the save keeps 55
    share.queue(pending, 'Two', 7, call('row', 'Cure', true), 6)
    share.queue(pending, 'Two', 7, call('row', 'Cure', false), 7)  -- toggles are never merged
    local ns = {}
    for i, p in ipairs(pending) do ns[i] = p.n end
    eq(ns, { 2, 3, 4, 5, 6, 7 })
end)

test('a call goes once: applied in order, acknowledged, then dropped by its sender', function ()
    local applied, pending = {}, {}
    share.queue(pending, 'Two', 70, call('row', 'Cure', false), 1)
    share.queue(pending, 'Two', 70, call('run', true), 2)
    share.queue(pending, 'Three', 80, call('run', true), 3)
    local box = session('Box', 1, { member(500, 'Box') })
    box.epoch, box.calls, box.watch, box.acks = 11, pending, {}, {}
    local got = share.inbox({ Box = box }, 'Two', 70, applied)
    eq({ #got, got[1].from, got[1].call[1], got[2].call[1] }, { 2, 'Box', 'row', 'run' })
    eq(share.inbox({ Box = box }, 'Two', 70, applied), {})  -- read again: nothing new
    eq(share.inbox({ Box = box }, 'Two', 71, {}), {})       -- Two reloaded since: not its calls
    local two = session('Two', 1, { member(600, 'Two') })
    two.epoch, two.calls, two.watch, two.acks = 70, {}, {}, { Box = applied.Box }
    local three = session('Three', 1, { member(700, 'Three') })
    three.epoch, three.calls, three.watch, three.acks = 80, {}, {}, {}
    share.settle(pending, { Two = two, Three = three }, 'Box', 11)
    eq({ #pending, pending[1].to }, { 1, 'Three' })
    three.epoch = 81  -- reloaded before it took it: dropped, never sent to the new load
    share.settle(pending, { Two = two, Three = three }, 'Box', 11)
    eq(#pending, 0)
    share.queue(pending, 'Gone', 1, call('run', true), 4)
    share.settle(pending, {}, 'Box', 11)
    eq(#pending, 0)
end)

test('a sender\'s reload starts its calls again from the first; an ack for its old load drops nothing', function ()
    local applied = {}
    local box = session('Box', 1, { member(500, 'Box') })
    box.epoch, box.watch, box.acks = 11, {}, {}
    box.calls = { { to = 'Two', epoch = 70, n = 5, call = call('run', true) } }
    eq(#share.inbox({ Box = box }, 'Two', 70, applied), 1)
    box.epoch, box.calls = 12, { { to = 'Two', epoch = 70, n = 1, call = call('run', false) } }
    local got = share.inbox({ Box = box }, 'Two', 70, applied)
    eq({ #got, got[1].call[2], applied.Box }, { 1, false, { epoch = 12, n = 1 } })
    local pending = { { to = 'Two', epoch = 70, n = 1, call = call('run', true) } }
    local two = session('Two', 1, { member(600, 'Two') })
    two.epoch, two.calls, two.watch, two.acks = 70, {}, {}, { Box = { epoch = 11, n = 5 } }
    share.settle(pending, { Two = two }, 'Box', 12)
    eq(#pending, 1)
end)

test('a session is watched while one has its SK Settings open, and busy while calls for it wait', function ()
    local box = session('Box', 1, { member(500, 'Box') })
    box.watch, box.calls = {}, {}
    eq({ share.watched({ Box = box }, 'Two') }, { false, false })
    box.calls = { { to = 'Two', epoch = 1, n = 1, call = call('run', true) } }
    eq({ share.watched({ Box = box }, 'Two') }, { false, true })
    box.watch = { Two = true }
    eq({ share.watched({ Box = box }, 'Two') }, { true, true })
end)

-- Two sessions over an in-memory filesystem, share.tick's files end to end: fn(a, b, files, DIR),
-- `a` and `b` each a core/share.lua of its own.
local function two_sessions(fn)
    local files = {}
    local real = { open = io.open, remove = os.remove, rename = os.rename, AshitaCore = rawget(_G, 'AshitaCore'),
                   ashita = rawget(_G, 'ashita') }
    local DIR = 'X:\\config\\addons\\sidekick3\\'
    rawset(io, 'open', function (p, mode)
        if mode == 'r' and not files[p] then return nil end
        local buf = {}
        return { write = function (_, t) buf[#buf + 1] = t; return true end, read = function () return files[p] end,
                 close = function () if mode == 'w' then files[p] = table.concat(buf) end; return true end }
    end)
    rawset(os, 'remove', function (p) files[p] = nil end)
    rawset(os, 'rename', function (a, b)
        if not files[a] or files[b] then return nil end
        files[b], files[a] = files[a], nil
        return true
    end)
    rawset(_G, 'AshitaCore', { GetInstallPath = function () return 'X:' end })
    rawset(_G, 'ashita', { fs = { get_dir = function ()
        local out = {}
        for p in pairs(files) do out[#out + 1] = p:sub(#DIR + 1) end
        return out
    end } })
    local original = package.loaded['core.share']
    local ok, err = pcall(function ()
        package.loaded['core.share'] = nil
        local a = require('core.share')
        package.loaded['core.share'] = nil
        local b = require('core.share')
        b.epoch = a.epoch + 1
        fn(a, b, files, DIR)
    end)
    rawset(io, 'open', real.open)
    rawset(os, 'remove', real.remove)
    rawset(os, 'rename', real.rename)
    rawset(_G, 'AshitaCore', real.AshitaCore)
    rawset(_G, 'ashita', real.ashita)
    package.loaded['core.share'] = original
    reset()
    assert(ok, err)
end

local function in_game(sid, name) return { loading = false, units = { fake.unit({ kind = 'self', slot = 0, sid = sid, name = name }) } } end
local function idle() return nil end

test('two sessions: a call goes, is applied once and acknowledged; a watched session publishes its view', function ()
    two_sessions(function (a, b, files, DIR)
        local ga, gb = in_game(1, 'Alpha'), in_game(2, 'Beta')
        local sa, sb = { running = false, open = true, watching = {} }, { running = false, open = true, watching = {} }
        local got = {}
        local fail = false
        local hb = { apply = function (from, c) got[#got + 1] = { from, c[1] }; sb.running = c[2] end,
                     view = function ()
                         if fail then error('no view') end
                         return { job = 'WHM 75', sections = { { id = 'heal', on = true } } }
                     end, act = idle }
        local ha = { apply = function () error('nothing is sent to Alpha') end, view = function () error('nobody watches Alpha') end,
                     act = idle }
        local clock = 0
        local function both() clock = clock + 1; a.tick(ga, clock, sa, ha); b.tick(gb, clock, sb, hb) end
        both(); both()
        eq({ a.sessions.Beta ~= nil, b.sessions.Alpha ~= nil, a.send('Nobody', { 'run', n = 1, true }) }, { true, true, false })
        eq({ a.me(), b.me() }, { 'Alpha', 'Beta' })  -- /sk3 stop reaches others while loading by it
        eq(a.send('Beta', { 'run', n = 1, true }), true)
        both()
        eq({ got, sb.running }, { { { 'Alpha', 'run' } }, true })
        eq(share.decode(files[DIR .. 'session_Beta.txt']).running, true)
        both(); both()
        eq({ #got, #share.decode(files[DIR .. 'session_Alpha.txt']).calls }, { 1, 0 })  -- acknowledged: no longer sent
        sa.watching.Beta, sa.open = true, false  -- the HUD closed: its windows with it, so not watched
        both(); both()
        eq({ share.decode(files[DIR .. 'session_Alpha.txt']).watch, files[DIR .. 'view_Beta.txt'] }, { {}, nil })
        sa.open = true
        both(); both()
        eq(a.views.Beta, { job = 'WHM 75', sections = { { id = 'heal', on = true } } })
        fail = true  -- its view fails while still watched: the file goes, and isn't kept as if current
        both()
        fail = false
        clock = clock + 1
        a.tick(ga, clock, sa, ha)
        eq(a.views.Beta, nil)
        b.tick(gb, clock, sb, hb)
        both()
        eq(a.views.Beta ~= nil, true)
        sa.watching.Beta = nil
        both(); both()
        eq({ a.views.Beta, files[DIR .. 'view_Beta.txt'] }, { nil, nil })
        b.close()
        eq({ files[DIR .. 'session_Beta.txt'], files[DIR .. 'session_Alpha.txt'] ~= nil }, { nil, true })
        a.close()
        eq(a.me(), nil)
    end)
end)

test('two sessions: what one\'s automation sends is in its file at once, read four times a second while the other\'s HUD shows', function ()
    two_sessions(function (a, b, files, DIR)
        local ga, gb = in_game(1, 'Alpha'), in_game(2, 'Beta')
        local sa, sb = { running = false, open = true, watching = {} }, { running = true, open = false, watching = {} }
        local acting
        local ha = { apply = function () end, view = function () end, act = idle }
        local hb = { apply = function () end, view = function () end, act = function () return acting end }
        a.tick(ga, 1, sa, ha); b.tick(gb, 1, sb, hb)
        a.tick(ga, 2, sa, ha); b.tick(gb, 2, sb, hb)  -- each has read the other: Beta runs, and Alpha's HUD shows
        acting = { behavior = 'heal', action = 'Cure IV', target = 'Alpha' }
        b.tick(gb, 2.1, sb, hb)  -- not due for a second, but it acted
        eq(share.decode(files[DIR .. 'session_Beta.txt']).act, acting)
        a.tick(ga, 2.25, sa, ha)
        eq(a.sessions.Beta.act, acting)
        acting = nil
        b.tick(gb, 2.3, sb, hb)  -- done: off at once too
        eq(share.decode(files[DIR .. 'session_Beta.txt']).act, nil)
        sa.open = false  -- Alpha's HUD closed: read every second again
        a.tick(ga, 2.5, sa, ha)
        acting = { behavior = 'song', action = 'Valor Minuet IV' }
        b.tick(gb, 2.6, sb, hb)
        a.tick(ga, 3, sa, ha)
        eq(a.sessions.Beta.act, nil)
        a.tick(ga, 3.5, sa, ha)
        eq(a.sessions.Beta.act, acting)
        a.close()
        b.close()
    end)
end)
