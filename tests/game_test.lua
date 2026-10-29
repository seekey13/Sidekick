-- core/game.lua's read of tracked players, against a fake client: found by
-- entity index and again after zoning, as last seen out of range, a member
-- while in your party or alliance; the alliance's other parties; your target
-- when it's a player; a player by name.
local ffi = require('ffi')
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
    -- `world.pet` is yours; `world.pets` = { [owner's index] = its pet's } another player's.
    GetPetTargetIndex = function (_, i) return (world.pets or {})[i] or i == member(0).tidx and world.pet or 0 end,
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
    GetMemberTP = const(0), GetMemberZone = const(100),
    GetMemberMainJob = function (_, i) return member(i).main or 3 end,  -- WHM75/BLM37 unless set
    GetMemberSubJob = function (_, i) return member(i).sub or 4 end,
    GetMemberMainJobLevel = const(75), GetMemberSubJobLevel = function (_, i) return member(i).sub_lv or 37 end,
}
local player = {
    GetMainJob = function () return world.main end, GetMainJobLevel = const(75), GetSubJob = const(4), GetSubJobLevel = const(37),
    GetMPMax = const(500), GetHPMax = function () return world.hp_max or 0 end, GetBuffs = function () return world.buffs or {} end,
    GetPetMPPercent = function () return world.pet_mpp or 0 end, GetPetTP = function () return world.pet_tp or 0 end,
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
-- Ability timers by recast id, in seconds (the client's are in 60ths).
local recast = {
    GetAbilityTimerId = function (_, i) return (world.timers or {})[i + 1] and world.timers[i + 1][1] or 0 end,
    GetAbilityTimer = function (_, i) return (world.timers or {})[i + 1] and world.timers[i + 1][2] * 60 or 0 end,
    GetSpellTimer = function (_, id) return ((world.spell_timers or {})[id] or 0) * 60 end,
}
local mm = { GetPlayer = const(player), GetParty = const(party), GetEntity = const(em), GetTarget = const(target),
             GetInventory = const(inventory), GetRecast = const(recast) }
-- The client's <bt> (SeekBattleActor): the entity `world.bt`, each ask counted in
-- `world.asked`. A callback can't be called from compiled code: no JIT in this file.
jit.off()
local actor = ffi.new('sk3_battle_actor[1]')
local seek_bt = ffi.cast('sk3_seek_battle_actor', function ()
    world.asked = (world.asked or 0) + 1
    if not world.bt then return nil end
    actor[0].GuideNo = world.bt
    return actor
end)
local BT_SIG = '66A1????????83EC186685C053565774??0FBFC08B0C85'
local function find(_, _, sig) return sig == BT_SIG and tonumber(ffi.cast('uintptr_t', seek_bt)) or 0 end
rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetPointerManager = const({ Get = const(0) }) })
rawset(_G, 'ashita', { memory = { find = find, read_uint32 = const(0), read_uint8 = const(0) } })

local function unit(g, sid)
    for _, u in ipairs(g.units) do if u.sid == sid then return u end end
end

local now = 1000  -- past other files' zone packets (cor_test.lua): not zoning here
local function read(dt, idle)
    now = now + (dt or 0.1)
    return game.read(now, idle)
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

test('your pet: its HP % from its entity, its MP % and TP as the client reads them for you', function ()
    reset()
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Ifrit', hpp = 80, dist = 2 }
    world.pet_mpp, world.pet_tp = 60, 1500
    local p = read().pet
    eq({ p.name, p.hpp, p.mpp, p.tp }, { 'Ifrit', 80, 60, 1500 })
end)

test('your pet has MP once seen with some: a wyvern\'s 0% is none, a spent one\'s still some; the next starts again', function ()
    reset()
    read()  -- no pet
    world.pet, world.ents[0x700], world.pet_mpp = 0x700, { sid = PET, name = 'Wyvern', hpp = 100, dist = 2 }, 0
    eq(read().pet.uses_mp, false)
    world.pet = nil
    read()
    world.pet, world.ents[0x700], world.pet_mpp = 0x700, { sid = PET, name = 'Ifrit', hpp = 100, dist = 2 }, 60
    eq(read().pet.uses_mp, true)
    world.pet_mpp = 0  -- spent
    eq(read().pet.uses_mp, true)
    world.pet = nil
    read()
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Wyvern', hpp = 100, dist = 2 }  -- the same id again
    eq(read().pet.uses_mp, false)
end)

test('a party member\'s pet and a tracked player\'s: the entity drawn, HP % alone; none at 0%, or not drawn', function ()
    reset()
    world.party[2] = { sid = 101, tidx = 0x401, name = 'Box', hpp = 100, hp = 1000, mpp = 50, mp = 100 }
    world.ents[0x401] = { sid = 101, name = 'Box', dist = 5 }
    world.pets, world.ents[0x701] = { [0x401] = 0x701 }, { sid = PET + 1, name = 'Carbuncle', hpp = 70, dist = 6 }
    local g = read()
    local p = unit(g, 101).pet
    eq({ p.sid, p.tidx, p.name, p.hpp, p.dist, p.mpp, unit(g, ME).pet, g.pet }, { PET + 1, 0x701, 'Carbuncle', 70, 6 })
    world.ents[0x701].hpp = 0  -- dead or dismissed: it lingers a while
    eq(unit(read(), 101).pet, nil)
    world.ents[0x701].hpp, world.ents[0x701].shown = 70, false
    eq(unit(read(), 101).pet, nil)
    world.ents[0x701].shown, world.ents[0x401].shown = nil, false  -- its owner out of range
    eq(unit(read(), 101).pet, nil)
    world.party[2], world.ents[0x401].shown = nil, nil  -- left the party, and tracked
    tracked.add(101, 'Box', 0x401)
    eq(unit(read(), 101).pet.name, 'Carbuncle')
    world.ents[0x401].shown = false
    eq(unit(read(), 101).pet, nil)
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

test('no battle target looked for while automation is stopped or asleep, nor in a safe zone', function ()
    reset()
    world.ents[0x100] = { sid = 0x1000010, name = 'Crab', hpp = 80, dist = 10, flags = 0x10, claim = 600 }
    world.party[7] = { sid = 600, tidx = 0x500, name = 'Bea', hpp = 100, hp = 1000, mpp = 0, mp = 0 }
    eq({ read(1, true).bt, read(1).bt.name }, { nil, 'Crab' })
    local zone = party.GetMemberZone
    party.GetMemberZone = const(230)  -- Southern San d'Oria
    eq(read(1).bt, nil)
    party.GetMemberZone = zone
end)

test('a trust in another party of the alliance: the client\'s <bt> isn\'t asked (it crashes), the alliance\'s claim stands in', function ()
    reset()
    world.ents[0x100] = { sid = 0x1000010, name = 'Crab', hpp = 80, dist = 10, flags = 0x10, claim = ME }
    world.bt, world.asked = 0x100, 0
    local g = read(1)
    eq({ g.bt.name, g.bt.claimed, world.asked }, { 'Crab', nil, 1 })  -- your party's: the client's <bt>
    -- Called past a full party: slot 6, B0, not drawn (in another zone).
    world.party[7] = { sid = TRUST, tidx = 0x101, name = 'Kupipi', hpp = 100, hp = 900, mpp = 100, mp = 500 }
    g = read(1)
    eq({ g.bt.name, g.bt.claimed, world.asked }, { 'Crab', true, 1 })
    world.party[7] = nil
    eq({ read(1).bt.claimed, world.asked }, { nil, 2 })
    -- Active there before its id is read (zoning in): it may be a trust, so not asked either.
    world.party[7] = { sid = 0, tidx = 0, name = '', hpp = 0, hp = 0, mpp = 0, mp = 0 }
    eq({ read(1).bt.claimed, world.asked }, { true, 2 })
end)

test('a party member has MP on a job with it, main or sub, at 0 MP too; on others once seen with some', function ()
    reset()
    local WAR, WHM = 1, 3
    local function uses_mp(main, sub, sub_lv, mp)
        world.party[2] = { sid = 101, tidx = 0x401, name = 'A', main = main, sub = sub, sub_lv = sub_lv, hpp = 100,
                           hp = 1000, mpp = mp > 0 and 50 or 0, mp = mp }
        return unit(read(), 101).uses_mp
    end
    eq({ uses_mp(WHM, WAR, 37, 0), uses_mp(WAR, WHM, 37, 0), uses_mp(WAR, WHM, 0, 0), uses_mp(WAR, WAR, 37, 0) },
       { true, true, false, false })
    eq({ uses_mp(WAR, WAR, 37, 200), uses_mp(WAR, WAR, 37, 0) }, { true, true })  -- seen with some: kept
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

test('you moving: a zone or teleport isn\'t, so it never wakes AFK sleep', function ()
    reset()
    read(1)
    world.ents[0x400].dist = 3
    eq(read(1).moving, true)
    eq(read(1).moving, false)
    local zone = party.GetMemberZone
    party.GetMemberZone = const(101)
    world.ents[0x400].dist = 50  -- Teleport-Holla: somewhere else
    eq(read(1).moving, false)
    world.ents[0x400].dist = 51
    eq(read(1).moving, true)  -- walking in the new zone still is
    party.GetMemberZone = zone
end)

test('a GEO\'s luopan gone: its auras are forgotten on those whose statuses come from packets', function ()
    reset()
    world.main = 21
    local kupipi = { sid = TRUST, tidx = 0x100, name = 'Kupipi', hpp = 100, hp = 900, mpp = 100, mp = 500 }
    world.party[2], world.ents[0x100] = kupipi, { sid = TRUST, name = 'Kupipi', hpp = 100, dist = 3 }
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Luopan', hpp = 100, dist = 2 }
    buffs.gain(TRUST, 580, now)   -- Geo-Haste's aura
    buffs.gain(TRUST, PROTECT, now)
    local first = read()
    eq(unit(first, TRUST).buffs, { [580] = true, [PROTECT] = true })
    eq({ first.pet.since, read().pet.since }, { first.now, first.now })  -- when it was first seen
    world.pet = nil
    eq(unit(read(), TRUST).buffs, { [PROTECT] = true })  -- on the read that finds it gone
    -- Off GEO (pet_auras is the main job's): another pet gone leaves the same status be.
    world.main = 15
    world.pet, world.ents[0x700] = 0x700, { sid = PET, name = 'Carbuncle', hpp = 100, dist = 2 }
    buffs.gain(TRUST, 580, now)
    read()
    world.pet = nil
    eq(unit(read(), TRUST).buffs, { [580] = true, [PROTECT] = true })
end)

reset()
-- Last: your max HP read whole stays in game.lua's memory.
test('sessions: your max HP read whole and your party\'s jobs, for the session file', function ()
    reset()
    world.hp_max = 1234
    world.party[1].hp = 600
    world.party[2] = { sid = 150, tidx = 0x401, name = 'P1', hpp = 50, hp = 500, mpp = 50, mp = 100 }
    world.ents[0x401] = { sid = 150, name = 'P1', dist = 3 }
    local g = read()
    local me, p1 = unit(g, ME), unit(g, 150)
    eq({ me.max_hp, me.max_known, me.jobs }, { 1234, true, { 3, 75, 4, 37 } })
    eq({ p1.max_known, p1.jobs }, { false, { 3, 75, 4, 37 } })
end)

test('sessions: a player another session lists has its max HP, and its HP while not drawn', function ()
    reset()
    tracked.add(OUT, 'Out', nil, 'Box')
    local t = tracked.list[1]
    t.max_hp, t.main_lv, t.shared_hpp = 1500, 75, 40
    local u = unit(read(), OUT)
    eq({ u.in_zone, u.hpp, u.alive, u.max_hp, u.hp, u.auto }, { false, 40, true, 1500, 600, 'Box' })
    world.ents[0x450] = { sid = OUT, name = 'Out', hpp = 90, dist = 5 }
    t.tidx = 0x450
    eq(unit(read(), OUT).hpp, 90)  -- drawn: their entity, not the file
end)

test('your statuses: a set, and how many of each stand (runes stack); empty slots counted as none', function ()
    reset()
    world.buffs = { 523, 523, 524, 0, 255, -1 }
    local me = unit(read(), ME)
    eq({ me.buffs, me.stacks }, { { [523] = true, [524] = true }, { [523] = 2, [524] = 1 } })
end)

test('a party player\'s statuses from the status-icon block, and their stacks: two songs of one kind stand twice', function ()
    reset()
    world.ents[0x450] = { sid = OUT, name = 'Out', hpp = 90, dist = 5 }
    world.party[2] = { sid = OUT, tidx = 0x450, name = 'Out', hpp = 90, hp = 900, mpp = 50, mp = 100 }
    -- Entry 1 is theirs: March (214) twice, Minuet (198), and 300 (high bits 1, low 44); the rest empty (255).
    local POINTER, BASE = 0x10, 0x1000
    local entry, bytes = BASE + 0x30, {}
    for j, id in ipairs({ 214, 214, 198, 300 }) do
        local k = j - 1
        bytes[entry + 16 + k] = id % 256
        local at = entry + 8 + math.floor(k / 4)
        bytes[at] = (bytes[at] or 0) + math.floor(id / 256) * 4 ^ (k % 4)
    end
    for k = 4, 31 do bytes[entry + 16 + k] = 255 end
    local core, ash = rawget(_G, 'AshitaCore'), rawget(_G, 'ashita')
    rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetPointerManager = const({ Get = const(POINTER) }) })
    rawset(_G, 'ashita', { memory = { find = const(0),
        read_uint32 = function (addr) return addr == POINTER and BASE or addr == entry and OUT or 0 end,
        read_uint8 = function (addr) return bytes[addr] or 0 end } })
    local u = unit(read(), OUT)
    rawset(_G, 'AshitaCore', core)
    rawset(_G, 'ashita', ash)
    eq({ u.buffs, u.stacks }, { { [214] = true, [198] = true, [300] = true }, { [214] = 2, [198] = 1, [300] = 1 } })
end)

test('BST: Ready charges from the pool timer; a Ready move waits only for the charges it costs', function ()
    reset()
    world.main, world.timers = 9, { { 102, 45 } }  -- one charge back in 15s: 1 banked
    local g = read()
    eq(g.ready, 1)
    -- A charge back waits the half-second delay a recast run out does, then reads ready.
    local function soon(a) local w = game.recast(a); return w > 0 and w <= 0.5 end
    eq({ soon({ kind = 'pet', recast = 102, charges = 1 }), game.recast({ kind = 'pet', recast = 102, charges = 2 }) },
        { true, 15 })
    eq(soon({ kind = 'pet', recast = 102 }), true)  -- Sic: one charge
    world.spell_timers = { [102] = 8 }
    eq(game.recast({ kind = 'ma', recast = 102 }), 8)  -- Enaero, spell 102: its own recast, no charges
    world.main = 3
    eq(read().ready, nil)  -- off BST
end)

test('the job modules\' reads: SCH\'s stratagems, COR\'s last roll and totals, PUP\'s automaton', function ()
    reset()
    local cor, pup = require('jobs.cor'), require('jobs.pup')
    world.main, world.timers = 20, { { 231, 60 } }  -- five at 75, one back each 48s: 3 banked
    cor.clear()
    cor.rolled(98, 5, 420, now, 5)  -- a roll (message 420) of 5
    pup.named('Ziggy')
    local g = read()
    eq({ g.stratagems, g.roll.id, g.roll.total, g.roll_totals, g.automaton }, { 3, 98, 5, { [98] = 5 }, 'Ziggy' })
    world.main = 3
    eq(read().stratagems, nil)  -- off SCH
    cor.clear()
    pup.named('')
end)

rawset(_G, 'AshitaCore', nil)
rawset(_G, 'ashita', nil)

test('owned ammo: your bag before the wardrobes, by the number /equip names each, its DAT level and jobs', function ()
    local bags = { [0] = { { Id = 18731, Count = 0 } }, [8] = { { Id = 18731, Count = 3 } },
                   [10] = { { Id = 18731, Count = 1 }, { Id = 19185, Count = 2 } } }
    local items = { [18731] = { Name = { 'Automaton Oil', 'oil' }, Level = 1, Jobs = 2 ^ 18 },
                    [19185] = { Name = { 'Automat. Oil +3', 'oil3' }, Level = 1, Jobs = 2 ^ 18 } }
    inventory.GetContainerCountMax = function (_, c) return bags[c] and #bags[c] or 0 end
    inventory.GetContainerItem = function (_, c, i) return bags[c] and bags[c][i] end
    local core = rawget(_G, 'AshitaCore')
    rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetResourceManager = const({ GetItemById = function (_, id) return items[id] end }) })
    eq(game.owned({ 19185, 17016, 18731 }), {
        { id = 19185, en = 'Automat. Oil +3', jp = 'oil3', level = 1, jobs = 2 ^ 18, bag = 2, count = 2 },  -- Mog Wardrobe 2
        { id = 18731, en = 'Automaton Oil', jp = 'oil', level = 1, jobs = 2 ^ 18, bag = 1, count = 4 },  -- the empty stack in your bag skipped
    })
    local ids = { 18731 }
    eq(#game.owned(ids), 1)
    bags[10] = {}
    eq(#game.owned(ids), 1, 'kept a second')
    inventory.GetContainerCountMax, inventory.GetContainerItem = const(0), nil
    rawset(_G, 'AshitaCore', core)
end)

jit.on()
