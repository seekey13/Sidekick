--[[
    One read of the game: you, your party and trusts, then the players you track
    (core/tracked.lua), as one list of units; your battle target and pet, and
    the flags that stop automation (casting, moving, mounted, dead,
    incapacitated, safe zone...). The engine decides from this snapshot alone,
    so tests can hand it a fake one.

    unit = { slot, sid, tidx, name, kind = 'self'|'party'|'trust'|'tracked', hpp, hp, max_hp,
             mpp, mp, tp, uses_mp (yours: max MP > 0; others: seen with MP on these jobs),
             in_zone, dist, pos = { x, y, z },
             status (entity), alive, buffs = { [id] = true },
             hot = HP still to come from your Regen, nil if none }
    A tracked player has no slot and no MP; in_zone while the client draws them
    (in range), max_hp estimated from their /check level (else yours), and
    main, main_lv, sub, sub_lv once a /check has answered.
    The pet is { sid, tidx, name, hpp, dist, pos, status (1 engaged), buffs }.
    `target` is your current target when it's another player: { tidx, sid, name }.
    Plus when your cast began (cast_at, while casting);
    what healing scores with: learned potency, the day and the weather;
    the item in your ammo slot and what's in your inventory; when you last moved and
    last had a battle target.
]]--

local ffi = require('ffi')
local buffs = require('core.buffs')
local can = require('core.can')
local observed = require('core.observed')
local packets = require('core.packets')
local tracked = require('core.tracked')

local game = {}

local TRUST = 0x1000000  -- server ids from here up are NPCs; in a party slot, a trust
local DEAD, MOUNTED_STATUS, RESTING = 3, 5, 33  -- entity status
local MOUNTED_BUFF, AMNESIA, REGEN = 252, 16, 42
local SILENCED = { 6, 29 }                          -- Silence, Mute
local INCAPACITATED = { 2, 7, 10, 14, 17, 19, 28 }  -- Sleep, Petrify, Stun, Charm x2, Sleep II, Terror
local COMBAT_GRACE = 5      -- seconds "in combat" lasts after the battle target goes (multi-mob pulls)
local MOVE_SAMPLE = 0.25    -- seconds between position samples
local READY_DELAY = 0.5     -- a recast reading 0 is trusted only after this (server lag)
local SCH, STRATAGEMS = 20, 231
local PC_FIRST, PC_LAST = 0x400, 0x6FF  -- players' entity indexes (the server's range for them)
local RESCAN = 1            -- seconds between looks for a tracked player not where last seen
-- Stratagem charges by SCH level (CatsEyeXI, from v2): { level, charges, seconds per charge }.
local STRATAGEM_TIERS = { { 75, 5, 48 }, { 65, 4, 60 }, { 50, 3, 80 }, { 30, 2, 120 }, { 10, 1, 240 } }

-- Towns, ships and the like: no combat, so no automation.
local SAFE_ZONES = {}
for _, z in ipairs({
    230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246,
    80, 87, 94, 48, 50, 53, 26, 247, 248, 249, 250, 252, 256, 257, 280, 46, 47, 220, 221,
    223, 224, 225, 226, 227, 228, 70, 251, 284,
}) do SAFE_ZONES[z] = true end

ffi.cdef[[
    typedef struct { uint8_t padding00[116]; uint32_t GuideNo; uint32_t UniqueNo; } sk3_battle_actor;
    typedef sk3_battle_actor* (__stdcall* sk3_seek_battle_actor)(void);
]]

-- Client functions found once, on first read (none of this exists offline).
local seek_bt, event_ptr, weather_ptr, clock_ptr  -- false / 0 when the signature isn't found
local function init()
    if seek_bt ~= nil then return end
    local bt = ashita.memory.find('FFXiMain.dll', 0, '66A1????????83EC186685C053565774??0FBFC08B0C85', 0, 0)
    seek_bt = bt and bt ~= 0 and ffi.cast('sk3_seek_battle_actor', bt) or false
    event_ptr = ashita.memory.find('FFXiMain.dll', 0,
        'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 0) or 0
    -- The same signatures as LuAshitacast and v2's lib/core/vanadiel.lua.
    weather_ptr = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0) or 0
    clock_ptr = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0) or 0
end

-- The zone's weather id (16 Auras, 17 Stellar Glare, 18 Gloom, 19 Darkness...), 0 unknown.
local function weather()
    local ptr = weather_ptr ~= 0 and ashita.memory.read_uint32(weather_ptr + 0x02) or 0
    return ptr ~= 0 and ashita.memory.read_uint8(ptr) or 0
end

-- The Vana'diel day, 0 Firesday .. 6 Lightsday, 7 Darksday; nil unknown.
local function day()
    local ptr = clock_ptr ~= 0 and ashita.memory.read_uint32(clock_ptr + 0x34) or 0
    if ptr == 0 then return nil end
    return math.floor((ashita.memory.read_uint32(ptr + 0x0C) + 92514960) / 3456) % 8
end

local max_hp = {}  -- [sid] = HP seen at 100%: heal sizing needs the deficit
local has_mp = {}  -- ['sid main/sub'] = true once seen with MP on those jobs: a WAR's 0% isn't an empty tank
local move = { at = -math.huge, moved = -math.huge }
local last_combat = -math.huge
local pet_sid  -- the live pet last seen: its statuses are forgotten once it's gone or dead
local ready_since = {}  -- [recast key] = when its timer first read 0
local rescan_at = -math.huge

local function set_of(list)
    local s = {}
    for _, id in ipairs(list) do if id > 0 and id ~= 255 then s[id] = true end end
    return s
end

local any = can.any

-- A party player's statuses, from the client's party status-icon block
-- (5 entries of 0x30 bytes: server id, 2 high bits per icon, 32 low bytes).
local function party_buffs(sid)
    local base = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('party.statusicons'))
    if base == 0 then return {} end
    for i = 0, 4 do
        local entry = base + 0x30 * i
        if ashita.memory.read_uint32(entry) == sid then
            local list = {}
            for j = 0, 31 do
                local high = bit.band(bit.rshift(ashita.memory.read_uint8(entry + 8 + math.floor(j / 4)), (j % 4) * 2), 3)
                list[#list + 1] = high * 256 + ashita.memory.read_uint8(entry + 16 + j)
            end
            return set_of(list)
        end
    end
    return {}
end

-- The item id in your ammo slot, 0 for none. The equipment entry's Index packs
-- where the item is: container in the high byte, slot in the low.
local function ammo()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local eq = inv:GetEquippedItem(3)
    if not eq or not eq.Index or eq.Index == 0 then return 0 end
    local item = inv:GetContainerItem(math.floor(eq.Index / 256), eq.Index % 256)
    local id = item and item.Id or 0
    return (id == -1 or id == 65535) and 0 or id
end

-- What's in your inventory: { [item id] = count }. Slot 0 is gil.
local function inventory()
    local inv, out = AshitaCore:GetMemoryManager():GetInventory(), {}
    for i = 1, inv:GetContainerCountMax(0) do
        local item = inv:GetContainerItem(0, i)
        if item and item.Id ~= 0 and item.Id ~= 65535 and item.Count > 0 then
            out[item.Id] = (out[item.Id] or 0) + item.Count
        end
    end
    return out
end

local function own_buffs(player)
    local raw, list = player:GetBuffs(), {}
    for i = 1, 32 do list[i] = raw[i] or 0 end
    return set_of(list)
end

local function entity(em, tidx)
    if not tidx or tidx == 0 then return nil end
    return {
        tidx = tidx, sid = em:GetServerId(tidx), name = em:GetName(tidx), hpp = em:GetHPPercent(tidx),
        dist = math.sqrt(em:GetDistance(tidx)), status = em:GetStatus(tidx),
        pos = { em:GetLocalPositionX(tidx), em:GetLocalPositionY(tidx), em:GetLocalPositionZ(tidx) },
    }
end

-- An entity the client is drawing: spawned near you, not hidden.
local function present(em, i)
    local flags = em:GetRenderFlags0(i)
    return em:GetRawEntity(i) ~= nil and bit.band(flags, 0x200) ~= 0 and bit.band(flags, 0x4000) == 0
end

local function player_at(em, i)
    return { tidx = i, sid = em:GetServerId(i), name = em:GetName(i) }
end

-- Another player near you named `name` (any case), else nil.
function game.find_player(name)
    local em = AshitaCore:GetMemoryManager():GetEntity()
    name = name:lower()
    for i = PC_FIRST, PC_LAST do
        local n = em:GetName(i)
        if n and n:lower() == name and present(em, i) then return player_at(em, i) end
    end
end

-- Your current target (not one being picked) when it's a player.
local function player_target(mm, em)
    local t = mm:GetTarget()
    local i = t:GetTargetIndex(t:GetIsSubTargetActive() == 0 and 0 or 1)
    if i < PC_FIRST or i > PC_LAST or not present(em, i) then return nil end
    return player_at(em, i)
end

-- Whether tracked player `t` is at the entity index they were last seen at.
local function here(em, t)
    return t.tidx ~= nil and em:GetServerId(t.tidx) == t.sid and present(em, t.tidx)
end

-- Zoning (theirs or yours) gives everyone a new entity index: while a tracked
-- player isn't where they were, look for them again, at most once a second.
local function relocate(em, now)
    if now - rescan_at < RESCAN then return end
    local lost = {}
    for _, t in ipairs(tracked.list) do
        if not here(em, t) then lost[t.sid] = t end
    end
    if not next(lost) then return end
    rescan_at = now
    for i = PC_FIRST, PC_LAST do
        local t = lost[em:GetServerId(i)]
        if t and present(em, i) then t.tidx = i end
    end
end

-- A tracked player as a unit. Only HP % can be read, so HP comes from the max
-- estimated by level, or yours while the level is unknown (/anon, no /check).
local function tracked_unit(em, t, me, now)
    local u = { sid = t.sid, name = t.name, kind = 'tracked', hpp = 0, mpp = 0, mp = 0, tp = 0, uses_mp = false,
                in_zone = here(em, t), main = t.main, main_lv = t.main_lv, sub = t.sub, sub_lv = t.sub_lv }
    if u.in_zone then
        local i = t.tidx
        u.tidx, u.hpp, u.status = i, em:GetHPPercent(i), em:GetStatus(i)
        u.dist = math.sqrt(em:GetDistance(i))
        u.pos = { em:GetLocalPositionX(i), em:GetLocalPositionY(i), em:GetLocalPositionZ(i) }
    end
    u.max_hp = t.main_lv and tracked.max_hp(t.main_lv) or me.max_hp
    u.hp = u.max_hp and math.floor(u.max_hp * u.hpp / 100) or 0
    u.alive = u.hpp > 0 and u.status ~= DEAD
    if u.in_zone and not u.alive then buffs.forget(t.sid) end  -- a death clears statuses silently
    u.buffs = buffs.of(t.sid, now)
    u.hot = observed.hot(t.sid, now, u.buffs[REGEN])
    return u
end

local function battle_target(em)
    if not seek_bt then return nil end
    local actor = seek_bt()
    if actor == nil then return nil end  -- NULL pointer: no battle target
    local bt = entity(em, actor.GuideNo)
    if bt then bt.mob = bit.band(em:GetSpawnFlags(bt.tidx), 0x10) ~= 0 end
    return bt
end

local function moving(em, tidx, now)
    if now - move.at < MOVE_SAMPLE then return now - move.moved < MOVE_SAMPLE end
    local x, y, z = em:GetLocalPositionX(tidx), em:GetLocalPositionY(tidx), em:GetLocalPositionZ(tidx)
    if move.x and (x ~= move.x or y ~= move.y or z ~= move.z) then move.moved = now end
    move.at, move.x, move.y, move.z = now, x, y, z
    return now - move.moved < MOVE_SAMPLE
end

-- Stratagems share one timer that counts down to every charge back: the wait
-- for one charge, from that timer's seconds and your SCH level.
function game.charge_wait(seconds, sch_lv)
    for _, t in ipairs(STRATAGEM_TIERS) do
        if sch_lv >= t[1] then return math.max(0, seconds - (t[2] - 1) * t[3]) end
    end
    return seconds
end

-- Seconds until `action` (a catalog record) is off recast; 0 = ready.
function game.recast(action)
    if not action.recast then return 0 end  -- items
    local mm = AshitaCore:GetMemoryManager()
    local recast = mm:GetRecast()
    local key, timer = action.kind .. action.recast, 0
    if action.kind == 'ma' then
        timer = recast:GetSpellTimer(action.recast)
    elseif action.recast and action.recast > 0 then
        for i = 0, 31 do
            if recast:GetAbilityTimerId(i) == action.recast then timer = recast:GetAbilityTimer(i); break end
        end
    end
    if timer > 0 then
        ready_since[key] = nil
        if action.kind ~= 'ja' or action.recast ~= STRATAGEMS then return timer / 60 end
        local p = mm:GetPlayer()
        return game.charge_wait(timer / 60, p:GetMainJob() == SCH and p:GetMainJobLevel()
            or p:GetSubJob() == SCH and p:GetSubJobLevel() or 0)
    end
    ready_since[key] = ready_since[key] or os.clock()
    return math.max(0, READY_DELAY - (os.clock() - ready_since[key]))
end

-- Forget `action`'s ready stamp once it's sent, so its next recast gets the full delay.
function game.sent(action)
    if not action.recast then return end  -- /heal, /follow: no recast
    ready_since[action.kind .. action.recast] = nil
end

-- The snapshot. { loading = true } until the client has the player's job.
function game.read(now)
    init()
    local mm = AshitaCore:GetMemoryManager()
    local player, party, em = mm:GetPlayer(), mm:GetParty(), mm:GetEntity()
    local zone = party:GetMemberZone(0)
    if player:GetMainJobLevel() == 0 or zone == 0 then return { loading = true, now = now } end

    local units, tracks, in_party = {}, {}, {}
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            local sid, tidx = party:GetMemberServerId(i), party:GetMemberTargetIndex(i)
            in_party[sid] = true
            local u = {
                slot = i, sid = sid, tidx = tidx, name = party:GetMemberName(i),
                kind = i == 0 and 'self' or sid >= TRUST and 'trust' or 'party',
                hpp = party:GetMemberHPPercent(i), hp = party:GetMemberHP(i),
                mpp = party:GetMemberMPPercent(i), mp = party:GetMemberMP(i), tp = party:GetMemberTP(i),
                in_zone = party:GetMemberZone(i) == zone,
            }
            if u.hpp == 100 and u.hp > 0 then max_hp[sid] = u.hp end
            if i == 0 then
                u.uses_mp = player:GetMPMax() > 0
            else
                local jobs = ('%d %d/%d'):format(sid, party:GetMemberMainJob(i), party:GetMemberSubJob(i))
                if u.mp > 0 then has_mp[jobs] = true end
                u.uses_mp = has_mp[jobs] == true
            end
            -- Never seen at full: estimate from HP%. Rough at low HP, good enough to score.
            u.max_hp = max_hp[sid] or (u.hpp > 0 and u.hp > 0 and math.floor(u.hp * 100 / u.hpp)) or nil
            if u.in_zone and tidx > 0 then
                u.status = em:GetStatus(tidx)
                u.dist = i == 0 and 0 or math.sqrt(em:GetDistance(tidx))
                u.pos = { em:GetLocalPositionX(tidx), em:GetLocalPositionY(tidx), em:GetLocalPositionZ(tidx) }
            end
            u.alive = u.hpp > 0 and u.status ~= DEAD
            if u.kind == 'self' then u.buffs = own_buffs(player)
            elseif u.kind == 'trust' then
                if not u.alive then buffs.forget(sid) end  -- a death clears statuses silently
                u.buffs = buffs.of(sid, now); tracks[sid] = true
            else u.buffs = party_buffs(sid) end
            u.hot = observed.hot(sid, now, u.buffs[REGEN])
            units[#units + 1] = u
        end
    end

    local me = units[1]
    relocate(em, now)
    for _, t in ipairs(tracked.list) do
        if not in_party[t.sid] then  -- one who joined your party is a member while they stay
            units[#units + 1] = tracked_unit(em, t, me, now)
            tracks[t.sid] = true
        end
    end

    local bt = battle_target(em)
    if bt and bt.mob then last_combat = now end
    local is_moving = moving(em, me.tidx, now)  -- before moved_at is read
    local pet = entity(em, em:GetPetTargetIndex(me.tidx))
    -- A pet's statuses go silently when it dies or is dismissed, and the next may reuse its id.
    if pet_sid and not (pet and pet.sid == pet_sid and pet.hpp > 0) then buffs.forget(pet_sid) end
    pet_sid = pet and pet.hpp > 0 and pet.sid or nil
    if pet then pet.buffs = buffs.of(pet.sid, now); tracks[pet.sid] = true end
    local event = event_ptr ~= 0 and ashita.memory.read_uint32(event_ptr + 1) or 0
    local finished, spell_finish = packets.last_finish()
    local casting, cast_at = packets.casting(now)

    return {
        finished = finished, spell_finish = spell_finish,
        now = now, zone = zone, me = me, units = units, tracks = tracks, bt = bt, target = player_target(mm, em),
        pet = pet, ammo = ammo(), items = inventory(),
        main = player:GetMainJob(), main_lv = player:GetMainJobLevel(),
        sub = player:GetSubJob(), sub_lv = player:GetSubJobLevel(),
        casting = casting, cast_at = cast_at,
        moving = is_moving, moved_at = move.moved,
        combat = now - last_combat < COMBAT_GRACE, combat_at = last_combat,
        safe = SAFE_ZONES[zone] == true or (event ~= 0 and ashita.memory.read_uint8(event) == 1),
        mounted = me.status == MOUNTED_STATUS or me.buffs[MOUNTED_BUFF] == true,
        dead = not me.alive,
        resting = me.status == RESTING,
        incapacitated = any(me.buffs, INCAPACITATED),
        silenced = any(me.buffs, SILENCED),
        amnesia = me.buffs[AMNESIA] == true,
        recast = game.recast,
        learned = observed.learned, day = day(), weather = weather(),
    }
end

return game
