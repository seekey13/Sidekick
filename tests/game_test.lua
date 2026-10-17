-- core/game.lua's read of tracked players, against a fake client: found by
-- entity index and again after zoning, as last seen out of range, a member
-- while in your party or alliance; the alliance's other parties; your target
-- when it's a player; a player by name.
local buffs = require('core.buffs')
local can = require('core.can')
local game = require('core.game')
local tracked = require('core.tracked')

local ME, OUT, STRANGER, PROTECT = 1, 500, 900, 40
local TRUST, PET = 0x1000005, 0x1000700

-- The world: party members by slot (0 first), entities by index. An entity
-- stands `dist` yalms along x from you; `shown = false` is out of range.
local world
local function reset()
    world = {
        party = { { sid = ME, tidx = 0x400, name = 'Me', hpp = 100, hp = 1000, mpp = 100, mp = 500 } },
        ents = { [0x400] = { sid = ME, name = 'Me' } },
        target = 0, sub = nil, pet = nil, main = 3,
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
    GetPetTargetIndex = function () return world.pet or 0 end,
    GetSpawnFlags = function (_, i) return ent(i).flags or 0 end,
    GetClaimStatus = function (_, i) return ent(i).claim or 0 end,
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
    GetMainJob = function () return world.main end, GetMainJobLevel = const(75), GetSubJob = const(4), GetSubJobLevel = const(37),
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

test('the alliance\'s other parties: slots 6-17, statuses from packets, forgotten once they leave', function ()
    reset()
    local bea = { sid = 600, tidx = 0x500, name = 'Bea', hpp = 50, hp = 500, mpp = 80, mp = 400 }
    world.party[7] = bea                                                                          -- slot 6: B0
    world.party[13] = { sid = 601, tidx = 0x501, name = 'Cal', hpp = 100, hp = 1200, mpp = 0, mp = 0 }  -- slot 12: C0
    world.ents[0x500] = { sid = 600, name = 'Bea', hpp = 50, dist = 7 }
    world.ents[0x501] = { sid = 601, name = 'Cal', hpp = 100, dist = 9 }
    buffs.gain(600, PROTECT, now)
    local g = read()
    local b, c = unit(g, 600), unit(g, 601)
    eq({ #g.units, b.kind, b.slot, b.hpp, b.max_hp, b.dist, b.uses_mp, b.buffs, g.tracks[600] },
       { 3, 'alliance', 6, 50, 1000, 7, true, { [PROTECT] = true }, true })
    eq({ c.kind, c.slot, c.max_hp, c.uses_mp, g.tracks[601] }, { 'alliance', 12, 1200, false, true })
    world.party[7] = nil  -- Bea leaves, and the wear-off packets go with her
    g = read()
    eq({ #g.units, g.tracks[600] }, { 2, nil })
    world.party[7] = bea
    eq(unit(read(), 600).buffs, {})  -- back, with nothing stale
end)

test('a tracked player who joins the alliance is a member of it while they stay, marked tracked', function ()
    reset()
    world.ents[0x450] = { sid = OUT, name = 'Out', hpp = 90, dist = 5 }
    tracked.add(OUT, 'Out', 0x450)
    world.party[7] = { sid = OUT, tidx = 0x450, name = 'Out', hpp = 90, hp = 900, mpp = 50, mp = 100 }
    local g = read()
    eq({ #g.units, unit(g, OUT).kind, unit(g, OUT).slot, unit(g, OUT).tracked }, { 2, 'alliance', 6, true })
    world.party[7] = nil
    eq(unit(read(), OUT).kind, 'tracked')
end)

test('an alliance member the client isn\'t drawing is out of reach, not 0 yalms away; the alliance comes last', function ()
    reset()
    world.party[7] = { sid = 600, tidx = 0x500, name = 'Bea', hpp = 40, hp = 400, mpp = 80, mp = 400 }  -- no entity
    world.ents[0x450] = { sid = OUT, name = 'Out', hpp = 90, dist = 5 }
    tracked.add(OUT, 'Out', 0x450)
    local g = read()
    local b = unit(g, 600)
    eq({ b.in_zone, b.dist, b.pos, b.alive }, { true, nil, nil, true })
    eq(can.reach({ kind = 'ma', role = 'heal', targets = 63, range = 12 }, b), false)  -- Cure
    eq({ g.units[2].kind, g.units[3].kind }, { 'tracked', 'alliance' })  -- as v2: party, tracked, alliance
    world.ents[0x500] = { sid = 600, name = 'Bea', hpp = 40, dist = 7 }
    eq(unit(read(), 600).dist, 7)
end)

test('a trust\'s and the pet\'s statuses last across reads; a trust dismissed is forgotten', function ()
    reset()
    local kupipi = { sid = TRUST, tidx = 0x100, name = 'Kupipi', hpp = 100, hp = 900, mpp = 100, mp = 500 }
    world.party[2], world.ents[0x100] = kupipi, { sid = TRUST, name = 'Kupipi', hpp = 100, dist = 3 }
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Carbuncle', hpp = 100, dist = 2 }
    buffs.gain(TRUST, PROTECT, now)
    buffs.gain(PET, PROTECT, now)
    read()
    local g = read()
    eq({ unit(g, TRUST).kind, unit(g, TRUST).buffs, g.pet.buffs }, { 'trust', { [PROTECT] = true }, { [PROTECT] = true } })
    world.party[2] = nil
    read()
    world.party[2] = kupipi  -- called again, with the same id
    eq({ unit(read(), TRUST).buffs, read().pet.buffs }, { {}, { [PROTECT] = true } })
end)

test('with no <bt>, a mob another party of the alliance claimed is your battle target: the nearest in 21y', function ()
    reset()
    local function mob(name, dist, claimer) return { sid = 0x1000000 + dist, name = name, hpp = 80, dist = dist, flags = 0x10, claim = claimer } end
    world.ents[0x100], world.ents[0x101], world.ents[0x102] = mob('Crab', 10, 600), mob('Bat', 5, 999), mob('Worm', 30, 600)
    eq(read(1).bt, nil)  -- no alliance: no look
    world.party[7] = { sid = 600, tidx = 0x500, name = 'Bea', hpp = 100, hp = 1000, mpp = 0, mp = 0 }
    local g = read(1)
    eq({ g.bt.name, g.bt.tidx, g.bt.mob, g.bt.claimed, g.combat }, { 'Crab', 0x100, true, true, true })  -- Bat: a stranger's; Worm: too far
    world.ents[0x103] = mob('Snail', 4, 600)
    eq(read().bt.name, 'Crab')  -- looked for again at most every 0.5s
    eq(read(0.5).bt.name, 'Snail')
    world.ents[0x103].hpp = 0
    eq({ read().bt, read(0.5).bt.name }, { nil, 'Crab' })  -- dead: dropped at once, the next look finds another
end)

test('another unit moving: for half a second after its position last changed; seen first, it stands', function ()
    reset()
    world.party[2] = { sid = 101, tidx = 0x401, name = 'Tank', hpp = 100, hp = 1000, mpp = 0, mp = 0 }
    world.ents[0x401] = { sid = 101, name = 'Tank', hpp = 100, dist = 5 }
    eq(unit(read(), 101).moving, false)
    world.ents[0x401].dist = 6
    eq(unit(read(), 101).moving, true)
    eq(unit(read(0.3), 101).moving, true)   -- no new position yet: their packets come apart
    eq(unit(read(0.3), 101).moving, false)
    eq(unit(read(), ME).moving, nil)  -- you: the moving gate
end)

test('a GEO\'s luopan gone: its auras are forgotten on those whose statuses come from packets', function ()
    reset()
    world.main = 21
    local kupipi = { sid = TRUST, tidx = 0x100, name = 'Kupipi', hpp = 100, hp = 900, mpp = 100, mp = 500 }
    world.party[2], world.ents[0x100] = kupipi, { sid = TRUST, name = 'Kupipi', hpp = 100, dist = 3 }
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Luopan', hpp = 100, dist = 2 }
    buffs.gain(TRUST, 580, now)   -- Geo-Haste's aura
    buffs.gain(TRUST, PROTECT, now)
    eq(unit(read(), TRUST).buffs, { [580] = true, [PROTECT] = true })
    world.pet = nil
    read()
    eq(unit(read(), TRUST).buffs, { [PROTECT] = true })
end)

reset()
rawset(_G, 'AshitaCore', nil)
rawset(_G, 'ashita', nil)