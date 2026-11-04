-- tools/gm.lua against a fake client: the line each command sends, the arguments it refuses before anything goes out,
-- what it reads of players and mobs, and the cursor commands held until the server has heard of the target.
local saved = { AshitaCore = rawget(_G, 'AshitaCore'), ashita = rawget(_G, 'ashita'), vana = rawget(_G, 'vana') }

local MOB = 0x10
local said, handlers, targeted = {}, {}, {}
local world = {
    party = {  -- by slot, 0 (you) first
        { name = 'Dev', sid = 1, tidx = 0x400, hp = 900, hpp = 100, mp = 400, mpp = 100, tp = 0 },
        { name = 'Test', sid = 2, tidx = 0x401, hp = 600, hpp = 50, mp = 300, mpp = 75, tp = 1000 },
    },
    ents = {
        [0x400] = { name = 'Dev', hpp = 100 }, [0x401] = { name = 'Test', hpp = 50 },
        [0x450] = { name = 'Tracked', sid = 3, hpp = 80 },
        [0x020] = { name = 'Forest Hare', sid = 17187100, hpp = 100, dist = 12, flags = MOB },
        [0x030] = { name = 'Forest Hare', sid = 17187101, hpp = 100, dist = 5, flags = MOB },
        [0x040] = { name = 'Forest Hare', sid = 17187102, hpp = 0, dist = 2, flags = MOB },   -- dead
        [0x050] = { name = 'Forest Hare', sid = 17187103, hpp = 100, dist = 1 },              -- an NPC
    },
    target = 0, sub = nil, max_hp = 900, max_mp = 400,
}

local function const(v) return function () return v end end
local function ent(i) return world.ents[i] or {} end
local function member(i) return world.party[i + 1] or {} end

local party = {
    GetMemberIsActive = function (_, i) return world.party[i + 1] and 1 or 0 end,
    GetMemberName = function (_, i) return member(i).name end,
    GetMemberServerId = function (_, i) return member(i).sid end,
    GetMemberTargetIndex = function (_, i) return member(i).tidx end,
    GetMemberHP = function (_, i) return member(i).hp end,
    GetMemberHPPercent = function (_, i) return member(i).hpp end,
    GetMemberMP = function (_, i) return member(i).mp end,
    GetMemberMPPercent = function (_, i) return member(i).mpp end,
    GetMemberTP = function (_, i) return member(i).tp end,
}
local em = {
    GetName = function (_, i) return ent(i).name end,
    GetServerId = function (_, i) return ent(i).sid or 0 end,
    GetHPPercent = function (_, i) return ent(i).hpp or 0 end,
    GetStatus = const(0),
    GetDistance = function (_, i) return (ent(i).dist or 0) ^ 2 end,  -- squared, as the client's
    GetSpawnFlags = function (_, i) return ent(i).flags or 0 end,
    GetRenderFlags0 = function (_, i) return world.ents[i] and 0x200 or 0 end,
    GetRawEntity = function (_, i) return world.ents[i] and {} or nil end,
}
local player = { GetHPMax = function () return world.max_hp end, GetMPMax = function () return world.max_mp end }
-- While you pick a sub-target, index 0 is the one being picked and 1 your target.
local target = {
    GetIsSubTargetActive = function () return world.sub and 1 or 0 end,
    GetTargetIndex = function (_, n)
        if world.sub then return n == 0 and world.sub or world.target end
        return n == 0 and world.target or 0
    end,
}
local mm = { GetParty = const(party), GetEntity = const(em), GetPlayer = const(player), GetTarget = const(target) }
local pm = { AddOutgoingPacket = function (_, id, bytes) said[#said + 1] = { id, bytes } end }
rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetPacketManager = const(pm) })
rawset(_G, 'ashita', { events = { register = function (event, _, fn) handlers[event] = fn end } })
local in_range = true
rawset(_G, 'vana', { game = { set_target = function (i) targeted[#targeted + 1] = i; return in_range end } })

package.loaded['tools.gm'] = nil
local gm = require('tools.gm')

-- The text of each chat packet sent since the last call.
local function sent()
    local out = {}
    for i, s in ipairs(said) do
        local chars = {}
        for k = 7, #s[2] do
            if s[2][k] == 0 then break end
            chars[#chars + 1] = string.char(s[2][k])
        end
        out[i] = table.concat(chars)
    end
    said = {}
    return out
end

local function refused(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then error('sent: ' .. tostring(err), 2) end
    return err
end

-- Your position packet (0x015), its target index at 0x16.
local function pos_packet(index)
    local b = {}
    for k = 1, 0x1C do b[k] = 0 end
    b[0x16 + 1], b[0x16 + 2] = index % 256, math.floor(index / 256)
    return { id = 0x015, data = string.char(unpack(b)) }
end

test('a line goes as a say chat packet: its size in 4-byte units, the text ended and padded with zeros', function ()
    sent()
    gm.hp('Test', 0)  -- '!hp 0 Test': 10 bytes after 6 of header, kind and padding, one zero, 4 more to 20
    eq(said, { { 0xB5, { 0xB5, 10, 0, 0, 0, 0, 33, 104, 112, 32, 48, 32, 84, 101, 115, 116, 0, 0, 0, 0 } } })
    gm.uneffect('Test', 3)  -- '!deleffect Test 3': 17 bytes, 23 with the zero, padded to 24
    eq({ #said[2][2], said[2][2][2], said[2][2][24] }, { 24, 12, 0 })
    sent()
end)

test('vitals name the player, yours as "me"', function ()
    sent()
    eq({ gm.hp('Test', 0), gm.mp('me', 50), gm.tp('Test', 1000), gm.kill('Tracked') },
       { '!hp 0 Test', '!mp 50 Dev', '!tp 1000 Test', '!hp 0 Tracked' })
    eq(gm.full('Test'), { '!hp 99999 Test', '!mp 99999 Test' })
    eq(sent(), { '!hp 0 Test', '!mp 50 Dev', '!tp 1000 Test', '!hp 0 Tracked', '!hp 99999 Test', '!mp 99999 Test' })
    eq(said, {})
end)

test('a bad argument sends nothing: the server would read it as 0', function ()
    sent()
    eq(refused(gm.hp, 'Test', 'abc'), 'HP: a whole number from 0 to 99999, not abc')
    refused(gm.hp, 'Test', 1.5)
    refused(gm.hp, 'Test', -1)
    refused(gm.tp, 'Test', 3001)
    eq(refused(gm.hp, nil, 50), 'name a player (\'me\' for yourself)')
    refused(gm.hp, 'Te st', 50)
    refused(gm.hp, 'Xy', 50)
    refused(gm.hp, 'Abcdefghijklmnop', 50)
    refused(gm.raise, 'Test', 4)
    eq(refused(gm.effect, 'Test', 'nosuch'), 'no status "nosuch" here: give its id (xi.effect) or add it to gm.EFFECTS')
    refused(gm.uneffect, 'Test', 0)
    eq(refused(gm.job, 'XYZ', 75), 'no job "XYZ"')
    refused(gm.pos, 'Test', 0 / 0, 1, 2)
    eq(sent(), {})
end)

test('statuses go as their ids: !deleffect with a name reads only numbers', function ()
    sent()
    eq({ gm.effect('Test', 'Poison', 10, 120), gm.effect('Test', 'sleep'), gm.effect('me', 540, 5, 30) },
       { '!addeffect Test 3 10 120', '!addeffect Test 2 1 60', '!addeffect Dev 540 5 30' })
    eq({ gm.uneffect('Test', 'paralysis'), gm.uneffect('Test', 'PROTECT'), gm.effects('Test') },
       { '!deleffect Test 4', '!deleffect Test 40', '!geteffects Test' })
end)

test('% of the max: yours exact, a member\'s from HP and HP %, else refused', function ()
    sent()
    eq({ gm.hp_pct('me', 50), gm.hp_pct('Test', 40), gm.hp_pct('Test', 1), gm.mp_pct('Test', 10), gm.hp_pct('test', 0) },
       { '!hp 450 Dev', '!hp 480 Test', '!hp 12 Test', '!mp 40 Test', '!hp 0 Test' })
    -- Outside the alliance the client has HP % only: the server sets it from its own max.
    eq(gm.hp_pct('Tracked', 40), '!exec local p=GetPlayerByName(\'Tracked\') p:setHP(math.ceil(p:getMaxHP()*40/100))')
    eq(gm.mp_pct('Tracked', 5), '!exec local p=GetPlayerByName(\'Tracked\') p:setMP(math.ceil(p:getMaxMP()*5/100))')
    eq(refused(gm.hp_pct, 'Nobody', 50), 'Nobody isn\'t in your party or near you')
    refused(gm.hp_pct, 'Test', 101)
    eq(#sent(), 7)
end)

test('raise, immortal, recasts, levels, spells and items', function ()
    eq({ gm.raise('Test'), gm.raise('Test', 1), gm.immortal('Test'), gm.reset('me'), gm.level('Test', 75) },
       { '!raise 3 Test', '!raise 1 Test', '!immortal Test', '!reset Dev', '!setplayerlevel Test 75' })
    eq({ gm.spells('Test'), gm.trusts('me'), gm.spell('Test', 106), gm.item(4148, 12), gm.give('Test', 4151) },
       { '!addallspells Test', '!addalltrusts Dev', '!addspell 106 Test', '!additem 4148 12', '!giveitem Test 4151 1' })
end)

test('jobs: yours by command, another player\'s through !exec', function ()
    eq(gm.job('whm', 75, 'BLM', 37), { '!changejob WHM 75', '!changesjob BLM 37' })
    eq(gm.job(20, 99), { '!changejob SCH 99' })
    eq(gm.job_of('Test', 'RDM', 75, 'whm', 37),
       { '!exec local p=GetPlayerByName(\'Test\') p:changeJob(5) p:setLevel(75)',
         '!exec local p=GetPlayerByName(\'Test\') p:changesJob(3) p:setsLevel(37)' })
end)

test('moving people and mobs', function ()
    eq({ gm.pos('Test', -76.5, 32, -4), gm.pos('me', 1, 2, 3, 178), gm.zone(230), gm.bring('Test'), gm.go('Test'),
         gm.homepoint('Test') },
       { '!pos -76.5 32 -4 Test', '!pos 1 2 3 178 Dev', '!zone 230', '!bring Test', '!goto Test', '!homepoint Test' })
    eq(gm.pos('Test', 1234.5678, -0.25, 100), '!pos 1234.5678 -0.25 100 Test')  -- 4 places, as !pos prints them
    eq({ gm.spawn(17187111), gm.mobhere(17187111), gm.despawn(17187111) },
       { '!spawnmob 17187111', '!mobhere 17187111', '!despawnmob 17187111' })
end)

test('server Lua: one line, no <t> for the client to fill in, within what the server reads', function ()
    sent()
    eq(gm.exec('player:setHP(1)'), '!exec player:setHP(1)')
    refused(gm.exec, 'target:setHP(0) -- <t>')
    refused(gm.exec, 'a=1\nb=2')
    eq(refused(gm.exec, 'print("\226\152\133")'), 'ASCII only: !exec print("\226\152\133")')
    eq(refused(gm.exec, ('x'):rep(gm.MAX_LINE)), ('%d bytes, more than the server reads whole (%d): !exec %s')
        :format(gm.MAX_LINE + 6, gm.MAX_LINE, ('x'):rep(gm.MAX_LINE)))
    eq(gm.probe(), { '!where', '!exec player:printToPlayer(\'Sidekick gm: level 4 or more\')' })
    eq(#sent(), 3)
end)

test('who: a member in points and %, a player near you by HP % alone', function ()
    eq(gm.who('test'), { name = 'Test', slot = 1, sid = 2, index = 0x401, hp = 600, hpp = 50, mp = 300, mpp = 75, tp = 1000,
                         dead = false, max_hp = 1200, max_mp = 400 })
    eq(gm.who('me'), { name = 'Dev', slot = 0, sid = 1, index = 0x400, hp = 900, hpp = 100, mp = 400, mpp = 100, tp = 0,
                       dead = false, max_hp = 900, max_mp = 400 })
    eq(gm.who('Tracked'), { name = 'Tracked', sid = 3, index = 0x450, hpp = 80, dead = false })
    eq(gm.who('Nobody'), nil)
end)

test('mob: the nearest live one of that name, never an NPC', function ()
    eq(gm.mob('forest hare'), { index = 0x030, id = 17187101, name = 'Forest Hare', hpp = 100, dist = 5 })
    eq(gm.mob('Goblin'), nil)
end)

test('target: a player or a mob by name, or an index, as the game targets', function ()
    targeted = {}
    eq({ gm.target('Test'), gm.target('Forest Hare'), gm.target(0x020), gm.target('me') }, { 0x401, 0x030, 0x020, 0x400 })
    eq(targeted, { 0x401, 0x030, 0x020, 0x400 })
    eq(refused(gm.target, 'Goblin'), 'no "Goblin" near you')
    in_range = false
    eq(refused(gm.target, 0x030), 'can\'t target entity 48: out of range?')
    in_range = true
    local v = rawget(_G, 'vana')
    rawset(_G, 'vana', nil)
    eq(refused(gm.target, 0x030), 'targeting needs VanaCore (vana.game.set_target)')
    rawset(_G, 'vana', v)
end)

test('a command on the targeted mob waits for the server to hear of it', function ()
    sent()
    world.target = 0x030
    eq(gm.cursor(), { index = 0x030, name = 'Forest Hare', mob = true, ready = false })
    eq(refused(gm.mob_hp, 0), 'the server hasn\'t heard of your target yet (it has nil): try again')
    handlers.packet_out({ id = 0x016, data = pos_packet(0x030).data })  -- not a position packet
    eq(gm.cursor().ready, false)
    handlers.packet_out(pos_packet(0x030))
    eq(gm.cursor(), { index = 0x030, name = 'Forest Hare', mob = true, heard = 0x030, ready = true })
    eq({ gm.mob_hp(0), gm.mob_level(1) }, { '!hp 0', '!setmoblevel 1' })
    world.sub = 0x401  -- picking a sub-target: the server's may not be the one shown
    eq(gm.cursor().ready, false)
    world.sub = nil
    world.target = 0x401  -- a player: !hp with no name would be theirs, or yours
    handlers.packet_out(pos_packet(0x401))
    eq(refused(gm.mob_hp, 0), 'target a mob first (gm.target)')
    world.target = 0
    refused(gm.mob_level, 1)
    eq(sent(), { '!hp 0', '!setmoblevel 1' })
end)

package.loaded['tools.gm'] = nil
for k, v in pairs(saved) do rawset(_G, k, v) end
