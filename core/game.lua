--[[
    One read of the game: you, your party and trusts as one list of units, your
    battle target and pet, and the flags that stop automation (casting, moving,
    mounted, dead, incapacitated, safe zone...). The engine decides from this
    snapshot alone, so tests can hand it a fake one.

    unit = { slot, sid, tidx, name, kind = 'self'|'party'|'trust', hpp, hp, max_hp,
             mpp, mp, tp, in_zone, dist, status (entity), alive, buffs = { [id] = true } }
]]--

local ffi = require('ffi')
local buffs = require('core.buffs')
local packets = require('core.packets')

local game = {}

local TRUST = 0x1000000  -- server ids from here up are NPCs; in a party slot, a trust
local DEAD, MOUNTED_STATUS, RESTING = 3, 5, 33  -- entity status
local MOUNTED_BUFF, AMNESIA = 252, 16
local SILENCED = { 6, 29 }                          -- Silence, Mute
local INCAPACITATED = { 2, 7, 10, 14, 17, 19, 28 }  -- Sleep, Petrify, Stun, Charm x2, Sleep II, Terror
local COMBAT_GRACE = 5      -- seconds "in combat" lasts after the battle target goes (multi-mob pulls)
local MOVE_SAMPLE = 0.25    -- seconds between position samples
local READY_DELAY = 0.5     -- a recast reading 0 is trusted only after this (server lag)

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
local seek_bt, event_ptr  -- false / 0 when the signature isn't found
local function init()
    if seek_bt ~= nil then return end
    local bt = ashita.memory.find('FFXiMain.dll', 0, '66A1????????83EC186685C053565774??0FBFC08B0C85', 0, 0)
    seek_bt = bt and bt ~= 0 and ffi.cast('sk3_seek_battle_actor', bt) or false
    event_ptr = ashita.memory.find('FFXiMain.dll', 0,
        'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0, 0) or 0
end

local max_hp = {}  -- [sid] = HP seen at 100%: heal sizing needs the deficit
local move = { at = -math.huge, moved = -math.huge }
local last_combat = -math.huge
local ready_since = {}  -- [recast key] = when its timer first read 0

local function set_of(list)
    local s = {}
    for _, id in ipairs(list) do if id > 0 and id ~= 255 then s[id] = true end end
    return s
end

local function any(set, ids)
    for _, id in ipairs(ids) do if set[id] then return true end end
    return false
end

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
    }
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

-- Seconds until `action` (a catalog record) is off recast; 0 = ready.
function game.recast(action)
    local recast = AshitaCore:GetMemoryManager():GetRecast()
    local key, timer = action.kind .. action.recast, 0
    if action.kind == 'ma' then
        timer = recast:GetSpellTimer(action.recast)
    elseif action.recast and action.recast > 0 then
        for i = 0, 31 do
            if recast:GetAbilityTimerId(i) == action.recast then timer = recast:GetAbilityTimer(i); break end
        end
    end
    if timer > 0 then ready_since[key] = nil; return timer / 60 end
    ready_since[key] = ready_since[key] or os.clock()
    return math.max(0, READY_DELAY - (os.clock() - ready_since[key]))
end

-- Forget `action`'s ready stamp once it's sent, so its next recast gets the full delay.
function game.sent(action)
    ready_since[action.kind .. action.recast] = nil
end

-- The snapshot. { loading = true } until the client has the player's job.
function game.read(now)
    init()
    local mm = AshitaCore:GetMemoryManager()
    local player, party, em = mm:GetPlayer(), mm:GetParty(), mm:GetEntity()
    local zone = party:GetMemberZone(0)
    if player:GetMainJobLevel() == 0 or zone == 0 then return { loading = true, now = now } end

    local units, tracks = {}, {}
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 then
            local sid, tidx = party:GetMemberServerId(i), party:GetMemberTargetIndex(i)
            local u = {
                slot = i, sid = sid, tidx = tidx, name = party:GetMemberName(i),
                kind = i == 0 and 'self' or sid >= TRUST and 'trust' or 'party',
                hpp = party:GetMemberHPPercent(i), hp = party:GetMemberHP(i),
                mpp = party:GetMemberMPPercent(i), mp = party:GetMemberMP(i), tp = party:GetMemberTP(i),
                in_zone = party:GetMemberZone(i) == zone,
            }
            if u.hpp == 100 and u.hp > 0 then max_hp[sid] = u.hp end
            u.max_hp = max_hp[sid]
            if u.in_zone and tidx > 0 then
                u.status = em:GetStatus(tidx)
                u.dist = i == 0 and 0 or math.sqrt(em:GetDistance(tidx))
            end
            u.alive = u.hpp > 0 and u.status ~= DEAD
            if u.kind == 'self' then u.buffs = own_buffs(player)
            elseif u.kind == 'trust' then u.buffs = buffs.of(sid, now); tracks[sid] = true
            else u.buffs = party_buffs(sid) end
            units[#units + 1] = u
        end
    end

    local me = units[1]
    local bt = battle_target(em)
    if bt and bt.mob then last_combat = now end
    local event = event_ptr ~= 0 and ashita.memory.read_uint32(event_ptr + 1) or 0

    return {
        now = now, zone = zone, me = me, units = units, tracks = tracks, bt = bt,
        pet = entity(em, em:GetPetTargetIndex(me.tidx)),
        main = player:GetMainJob(), main_lv = player:GetMainJobLevel(),
        sub = player:GetSubJob(), sub_lv = player:GetSubJobLevel(),
        casting = packets.casting(now),
        moving = moving(em, me.tidx, now),
        combat = now - last_combat < COMBAT_GRACE,
        safe = SAFE_ZONES[zone] == true or (event ~= 0 and ashita.memory.read_uint8(event) == 1),
        mounted = me.status == MOUNTED_STATUS or me.buffs[MOUNTED_BUFF] == true,
        dead = not me.alive,
        resting = me.status == RESTING,
        incapacitated = any(me.buffs, INCAPACITATED),
        silenced = any(me.buffs, SILENCED),
        amnesia = me.buffs[AMNESIA] == true,
        recast = game.recast,
    }
end

return game
