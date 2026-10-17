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
    eq(share.decode((text:gsub('session 1', 'session 2'))), nil)
    eq(share.decode('sk3 session 1\n5 0\n'), nil)  -- no members
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
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { main = RDM, max_hp = 0 }) }) }, { [1] = true })
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
        { [1] = true, [101] = true })
    eq({ #tracked.list, tracked.list[1].sid }, { 1, 500 })
    -- Box joins your party: their entry goes, they're a member now
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, { [1] = true, [500] = true })
    eq(#tracked.list, 0)
    reset()
end)

test('auto-track: a player no live session lists any more is dropped, statuses and all', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate') }) }, {})
    buffs.gain(501, PROTECT, 0)
    share.sync({ Box = session('Box', 2, { member(500, 'Box') }) }, {})  -- Mate left Box's party
    eq({ #tracked.list, tracked.find(501), buffs.of(501, 1) }, { 1, nil, {} })
    share.sync({}, {})  -- Box's session gone
    eq(#tracked.list, 0)
    reset()
end)

test('auto-track: hand-tracked players are never dropped, and get what the file says', function ()
    reset()
    tracked.add(501, 'Mate', 1100)
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { main = RDM }) }) }, {})
    local t = tracked.find(501)
    eq({ t.auto, t.main, t.max_hp }, { nil, RDM, 1000 })
    share.sync({}, {})
    eq({ #tracked.list, tracked.list[1].sid }, { 1, 501 })
    reset()
end)

test('auto-track: tracking one by hand makes them yours, kept when the file stops listing them', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {})
    eq(tracked.add(500, 'Box', 1100), false)  -- already tracked
    eq(tracked.find(500).auto, nil)
    share.sync({}, {})
    eq(#tracked.list, 1)
    reset()
end)

test('auto-track: one untracked by hand stays off until tracked by hand again', function ()
    reset()
    local live = { Box = session('Box', 1, { member(500, 'Box') }) }
    share.sync(live, {})
    eq(tracked.remove('box').auto, 'Box')
    share.sync(live, {})
    eq(#tracked.list, 0)
    tracked.add(500, 'Box', 1100)
    share.sync(live, {})
    eq({ #tracked.list, tracked.list[1].auto }, { 1, nil })
    reset()
end)

test('auto-track: an /anon member\'s level from the file (0) never hides one known', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {})
    share.sync({ Box = session('Box', 2, { member(500, 'Box', { main = 0, main_lv = 0, sub = 0, sub_lv = 0, max_hp = 0 }) }) }, {})
    local t = tracked.find(500)
    eq({ t.main, t.main_lv, t.max_hp }, { WHM, 75, 1000 })
    reset()
end)

test('auto-track: one who joins your alliance keeps the statuses seen on them', function ()
    reset()
    share.sync({ Box = session('Box', 1, { member(500, 'Box') }) }, {})
    buffs.gain(500, PROTECT, 0)
    share.sync({ Box = session('Box', 2, { member(500, 'Box') }) }, { [500] = true })
    eq({ #tracked.list, buffs.of(500, 1) }, { 0, { [PROTECT] = true } })
    buffs.clear()
    reset()
end)

test('auto-track: HP from a file only for a member in its owner\'s zone; dropped when no file lists them', function ()
    reset()
    tracked.add(501, 'Mate', 1100)
    share.sync({ Box = session('Box', 1, { member(500, 'Box'), member(501, 'Mate', { here = false }) }) }, {})
    local t = tracked.find(501)
    eq({ t.shared_hpp, t.max_hp, tracked.find(500).shared_hpp }, { nil, 1000, 80 })
    share.sync({}, {})  -- hand-tracked, no file lists them now: nothing of the file's kept
    eq({ t.shared_hpp, t.max_hp, t.main_lv }, { nil, nil, 75 })
    reset()
end)

test('auto-track: a player two sessions list comes from their own session\'s file, whatever the order', function ()
    reset()
    local live = { A = session('A', 1, { member(500, 'A'), member(600, 'B', { hpp = 10 }) }),
                   B = session('B', 1, { member(600, 'B', { hpp = 90 }), member(500, 'A', { hpp = 20 }) }) }
    share.sync(live, {})
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
