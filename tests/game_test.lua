-- core/game.lua's read of tracked players, against a fake client: found by
-- entity index and again after zoning, as last seen out of range, a member
-- while in your party; your target when it's a player; a player by name.
local buffs = require('core.buffs')
local game = require('core.game')
local tracked = require('core.tracked')

local ME, OUT, STRANGER, PROTECT = 1, 500, 900, 40

-- The world: party members by slot (0 first), entities by index. An entity
-- stands `dist` yalms along x from you; `shown = false` is out of range.
local world
local function reset()
    world = {
        party = { { sid = ME, tidx = 0x400, name = 'Me', hpp = 100, hp = 1000, mpp = 100, mp = 500 } },
        ents = { [0x400] = { sid = ME, name = 'Me' } },
        target = 0, sub = nil,
    }
    tracked.list = {}
    buffs.clear()
end
reset()

local function ent(i) return world.ents[i] or {} end
local function member(i) return world.party[i + 1] or {} end
local function const(v) return function () return v end end

local em = {
    GetServerId = function (_, i) return ent(i).sid or 0 end,
    GetName = function (_, i) return ent(i).name or '' end,
    GetHPPercent = function (_, i) return ent(i).hpp or 0 end,
    GetStatus = function (_, i) return ent(i).status or 0 end,
    GetDistance = function (_, i) return (ent(i).dist or 0) ^ 2 end,  -- squared, as the client's
    GetLocalPositionX = function (_, i) return ent(i).dist or 0 end,
    GetLocalPositionY = const(0), GetLocalPositionZ = const(0),
    GetRenderFlags0 = function (_, i) return (world.ents[i] and world.ents[i].shown ~= false) and 0x200 or 0 end,
    GetRawEntity = function (_, i) return world.ents[i] and {} or nil end,
    GetPetTargetIndex = const(0), GetSpawnFlags = const(0),
}
local party = {
    GetMemberIsActive = function (_, i) return world.party[i + 1] and 1 or 0 end,
    GetMemberServerId = function (_, i) return member(i).sid end,
    GetMemberTargetIndex = function (_, i) return member(i).tidx end,
    GetMemberName = function (_, i) return member(i).name end,
    GetMemberHPPercent = function (_, i) return member(i).hpp end,
    GetMemberHP = function (_, i) return member(i).hp end,
    GetMemberMPPercent = function (_, i) return member(i).mpp end,
    GetMemberMP = function (_, i) return member(i).mp end,
    GetMemberTP = const(0), GetMemberZone = const(100), GetMemberMainJob = const(3), GetMemberSubJob = const(4),
}
local player = {
    GetMainJob = const(3), GetMainJobLevel = const(75), GetSubJob = const(4), GetSubJobLevel = const(37),
    GetMPMax = const(500), GetBuffs = const({}),
}
-- While you pick a sub-target, index 0 is the one being picked and 1 your target.
local target = {
    GetIsSubTargetActive = function () return world.sub and 1 or 0 end,
    GetTargetIndex = function (_, n)
        if world.sub then return n == 0 and world.sub or world.target end
        return n == 0 and world.target or 0
    end,
}
local inventory = { GetEquippedItem = const({ Index = 0 }), GetContainerCountMax = const(0) }
local mm = { GetPlayer = const(player), GetParty = const(party), GetEntity = const(em), GetTarget = const(target),
             GetInventory = const(inventory) }
rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetPointerManager = const({ Get = const(0) }) })
rawset(_G, 'ashita', { memory = { find = const(0), read_uint32 = const(0), read_uint8 = const(0) } })

local function unit(g, sid)
    for _, u in ipairs(g.units) do if u.sid == sid then return u end end
end

local now = 0
local function read(dt)
    now = now + (dt or 0.1)
    return game.read(now)
end

test('a tracked player in range: HP % from their entity, max HP from their level, else yours', function ()
    reset()
    world.ents[0x450] = { sid = OUT, name = 'Out', hpp = 60, dist = 8 }
    tracked.add(OUT, 'Out', 0x450)
    local g = read()
    local u = unit(g, OUT)
    eq({ #g.units, u.kind, u.slot, u.hpp, u.in_zone, u.dist, u.max_hp, u.hp, u.alive, u.uses_mp, g.tracks[OUT] },
       { 2, 'tracked', nil, 60, true, 8, 1000, 600, true, false, true })
    tracked.checked(OUT, 3, 75, 4, 37)
    u = unit(read(), OUT)
    eq({ u.max_hp, u.hp, u.main_lv }, { 1231, 738, 75 })
end)

test('zoning gives a new entity index: looked for again, at most once a second', function ()
    world.ents[0x450] = nil
    world.ents[0x460] = { sid = OUT, name = 'Out', hpp = 70, dist = 5 }
    eq({ unit(read(1), OUT).in_zone, tracked.list[1].tidx }, { true, 0x460 })
    world.ents[0x460] = nil
    world.ents[0x470] = { sid = OUT, name = 'Out', hpp = 80, dist = 5 }
    local u = unit(read(0.5), OUT)
    eq({ u.in_zone, u.hpp, u.alive }, { false, 70, true })  -- not yet: as last seen
    eq({ unit(read(0.6), OUT).in_zone, unit(read(), OUT).hpp }, { true, 80 })
end)

test('out of range: their HP as last seen and their statuses kept; a fallen one in range forgets them', function ()
    buffs.gain(OUT, PROTECT, now)
    world.ents[0x470].shown = false
    local u = unit(read(), OUT)
    eq({ u.in_zone, u.hpp, u.alive, u.buffs }, { false, 80, true, { [PROTECT] = true } })
    world.ents[0x470] = { sid = OUT, name = 'Out', hpp = 0, status = 3, dist = 5 }
    u = unit(read(), OUT)
    eq({ u.in_zone, u.alive, u.buffs }, { true, false, {} })
end)

test('one who joins your party is a member, marked tracked, while they stay; tracked again once they leave', function ()
    world.ents[0x470] = { sid = OUT, name = 'Out', hpp = 90, dist = 5 }
    world.party[2] = { sid = OUT, tidx = 0x470, name = 'Out', hpp = 90, hp = 900, mpp = 50, mp = 100 }
    local g = read()
    eq({ #g.units, unit(g, OUT).kind, unit(g, OUT).tracked, unit(g, ME).tracked }, { 2, 'party', true, nil })
    world.party[2] = nil
    g = read()
    eq({ #g.units, unit(g, OUT).kind }, { 2, 'tracked' })
end)

test('your target, when it is another player drawn near you, also while you pick a sub-target', function ()
    world.ents[0x480] = { sid = STRANGER, name = 'Stranger', dist = 3 }
    world.ents[0x100] = { sid = 0x1000100, name = 'Crab', dist = 3 }
    world.target = 0x480
    eq(read().target, { tidx = 0x480, sid = STRANGER, name = 'Stranger' })
    world.sub = 0x100
    eq(read().target.name, 'Stranger')
    world.sub, world.target = nil, 0x100  -- an NPC or mob
    eq(read().target, nil)
    world.target, world.ents[0x480].shown = 0x480, false
    eq(read().target, nil)
end)

test('find_player: a player drawn near you, by name in any case', function ()
    world.ents[0x480].shown = true
    eq(game.find_player('STRANGER'), { tidx = 0x480, sid = STRANGER, name = 'Stranger' })
    eq(game.find_player('Crab'), nil)  -- not a player's index
    world.ents[0x480].shown = false
    eq(game.find_player('stranger'), nil)
end)

reset()
rawset(_G, 'AshitaCore', nil)
rawset(_G, 'ashita', nil)