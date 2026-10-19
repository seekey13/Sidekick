--[[
    One read of the game: you, your party and trusts, the players you track
    (core/tracked.lua), then your alliance's other two parties, as one list of
    units (behaviors go down it in that order, as v2 did); your battle target
    and pet, and the flags that stop automation
    (casting, moving, mounted, dead, incapacitated, safe zone...). The engine
    decides from this snapshot alone, so tests can hand it a fake one.

    unit = { slot, sid, tidx, name, kind = 'self'|'party'|'trust'|'alliance'|'tracked', hpp, hp, max_hp,
             mpp, mp, tp, uses_mp (yours: max MP > 0; others: seen with MP on these jobs),
             max_known (max_hp is real: yours, or seen at full HP),
             jobs = { main, main_lv, sub, sub_lv } (you and your party's players),
             in_zone, dist, pos = { x, y, z },
             status (entity), alive, buffs = { [id] = true },
             stacks = { [id] = how many stand } (you and your party's players: runes
             and songs of one kind stack; nil for a player the client's list has no entry for yet),
             moving (others: moved in the last half second),
             hot = HP still to come from your Regen, nil if none }
    Slots: 0 you, 1-5 your party, 6-11 and 12-17 the alliance's other parties
    (kind 'alliance', their statuses from packets as a trust's).
    A tracked player has no slot and no MP; in_zone while the client draws them
    (in range; out of it, their HP and status as last seen, or as a session file
    says), max_hp from a session file, else estimated from their /check level (else
    yours), and main, main_lv, sub, sub_lv once a /check or a session file has
    answered; `auto` names the session whose file tracks them (core/share.lua). A member (or alliance member) you also track has tracked = true.
    The pet is { sid, tidx, name, hpp, dist, pos, status (1 engaged), buffs, since (first seen) }; the
    battle target `bt` { sid, tidx, name, hpp, dist, pos, mob, claimed, moving }, `claimed`
    when it's a mob another party of the alliance claimed (the client has no <bt>).
    `target` is your current target when it's another player: { tidx, sid, name }.
    Plus when your cast began (cast_at, while casting);
    what healing scores with: learned potency, the day and the weather;
    the item in your ammo slot and what's in your inventory (and `owned`, the ammo
    you hold where it can be worn from, read when asked); when you last moved and
    last had a battle target; your last Phantom Roll's total (`roll`, jobs/cor.lua);
    your automaton's name (`automaton`, jobs/pup.lua), nil until the server says it.
]]--

local ffi = require('ffi')
local buffs = require('core.buffs')
local bst = require('jobs.bst')
local cor = require('jobs.cor')
local geo = require('jobs.geo')
local pup = require('jobs.pup')
local sch = require('jobs.sch')
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
local MOVE_GRACE = 0.5      -- seconds another stays "moving": their position comes only with their packets
local READY_DELAY = 0.5     -- a recast reading 0 is trusted only after this (server lag)
local PC_FIRST, PC_LAST = 0x400, 0x6FF  -- players' entity indexes (the server's range for them)
local RESCAN = 1            -- seconds between looks for a tracked player not where last seen
local MOB_FIRST, MOB_LAST = 1, 0x3FF  -- mobs' and NPCs' entity indexes
local MOB = 0x10            -- spawn flag
local CLAIM_RANGE = 21      -- yalms: a mob the alliance claimed this close is your battle target...
local CLAIM_SCAN = 0.5      -- ...looked for at most this often

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
local move = { at = -math.huge, moved = -math.huge }  -- your position, sampled: { at, pos, moved, zone }
local motion = {}  -- [sid] = { pos, moved }: where each other unit and the battle target last were
local last_combat = -math.huge
local pet_sid  -- the live pet last seen: its statuses are forgotten once it's gone or dead
local pet_since  -- when that pet was first seen: a new one (it may reuse the id) comes after a read without one
local ready_since = {}  -- [recast key] = when its timer first read 0
local rescan_at = -math.huge
local claim = { at = -math.huge, tidx = nil }  -- the last look for an alliance-claimed mob
local fed = {}  -- [sid] = true: last read's units whose statuses come from packets

local any = can.any

-- A list of status ids as a set, and how many of each stand (runes stack:
-- jobs/run.lua; so do songs of one kind: jobs/brd.lua).
local function counted(list)
    local set, stacks = {}, {}
    for _, id in ipairs(list) do
        if id > 0 and id ~= 255 then set[id], stacks[id] = true, (stacks[id] or 0) + 1 end
    end
    return set, stacks
end

local function pos(em, i) return { em:GetLocalPositionX(i), em:GetLocalPositionY(i), em:GetLocalPositionZ(i) } end
local function dist(em, i) return math.sqrt(em:GetDistance(i)) end

-- A party player's statuses and their stacks, from the client's party status-icon
-- block (5 entries of 0x30 bytes: server id, 2 high bits per icon, 32 low bytes);
-- no stacks while they aren't in it yet (just joined, just zoned), so nothing
-- reads that as every status gone (jobs/brd.lua's stamps).
local function party_buffs(sid)
    local base = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('party.statusicons'))
    if base == 0 then return {}, nil end
    for i = 0, 4 do
        local entry = base + 0x30 * i
        if ashita.memory.read_uint32(entry) == sid then
            local list = {}
            for j = 0, 31 do
                local high = bit.band(bit.rshift(ashita.memory.read_uint8(entry + 8 + math.floor(j / 4)), (j % 4) * 2), 3)
                list[#list + 1] = high * 256 + ashita.memory.read_uint8(entry + 16 + j)
            end
            return counted(list)
        end
    end
    return {}, nil
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

-- Where ammo can be worn from: your bag, then the Mog Wardrobes, each as
-- { container, the number /equip names it by }.
local EQUIP_FROM = { { 0, 0 }, { 8, 1 }, { 10, 2 }, { 11, 3 }, { 12, 4 }, { 13, 5 }, { 14, 6 }, { 15, 7 }, { 16, 8 } }

-- The items of `ids` you hold where they can be worn from, in the order of `ids`:
-- { { id, en, jp, level, jobs (bit n: job n wears it), bag (for /equip), count (all bags) }, ... }.
-- Read when asked (rows wanting their ammo: pet care's, Sange), not every tick: it
-- walks every bag, so a list's answer is kept OWNED_KEPT seconds (as v2 kept its counts).
local OWNED_KEPT = 1
local owned_cache = setmetatable({}, { __mode = 'k' })
function game.owned(ids)
    local now = os.clock()
    local hit = owned_cache[ids]
    if hit and now - hit.at < OWNED_KEPT then return hit.out end
    local inv, rm, want, bag, count = AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager(), {}, {}, {}
    for _, id in ipairs(ids) do want[id] = true end
    for _, c in ipairs(EQUIP_FROM) do
        for i = 1, inv:GetContainerCountMax(c[1]) do
            local item = inv:GetContainerItem(c[1], i)
            if item and want[item.Id] and item.Count > 0 then
                bag[item.Id] = bag[item.Id] or c[2]
                count[item.Id] = (count[item.Id] or 0) + item.Count
            end
        end
    end
    local out = {}
    for _, id in ipairs(ids) do
        local r = bag[id] and rm:GetItemById(id)
        if r then
            out[#out + 1] = { id = id, en = r.Name[1], jp = r.Name[2], level = r.Level, jobs = r.Jobs, bag = bag[id],
                              count = count[id] }
        end
    end
    owned_cache[ids] = { at = now, out = out }
    return out
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

-- Your statuses, and how many of each stand.
local function own_buffs(player)
    local raw, list = player:GetBuffs(), {}
    for i = 1, 32 do list[i] = raw[i] or 0 end
    return counted(list)
end

local function entity(em, tidx)
    if not tidx or tidx == 0 then return nil end
    return { tidx = tidx, sid = em:GetServerId(tidx), name = em:GetName(tidx), hpp = em:GetHPPercent(tidx),
             dist = dist(em, tidx), status = em:GetStatus(tidx), pos = pos(em, tidx) }
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
-- player outside your alliance isn't where they were, look for them again, at
-- most once a second.
local function relocate(em, now, listed)
    if now - rescan_at < RESCAN then return end
    local lost = {}
    for _, t in ipairs(tracked.list) do
        if not (listed[t.sid] or here(em, t)) then lost[t.sid] = t end
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
-- Out of range, their HP and status are as last seen, as a member's in another zone.
local function tracked_unit(em, t, me, now)
    local u = { sid = t.sid, name = t.name, kind = 'tracked', mpp = 0, mp = 0, tp = 0, uses_mp = false,
                in_zone = here(em, t), main = t.main, main_lv = t.main_lv, sub = t.sub, sub_lv = t.sub_lv,
                auto = t.auto }
    if u.in_zone then
        local i = t.tidx
        t.hpp, t.status = em:GetHPPercent(i), em:GetStatus(i)
        u.tidx, u.dist, u.pos = i, dist(em, i), pos(em, i)
    elseif t.shared_hpp then  -- not drawn: their own session's client still reads them
        t.hpp, t.status = t.shared_hpp, nil
    end
    u.hpp, u.status = t.hpp or 0, t.status
    u.max_hp = t.max_hp or t.main_lv and tracked.max_hp(t.main_lv) or me.max_hp
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
    if bt then bt.mob = bit.band(em:GetSpawnFlags(bt.tidx), MOB) ~= 0 end
    return bt
end

-- The client's <bt> is only a mob your own party claimed: one another party of
-- the alliance claimed has none, though you fight it too. Then, as v2 did, the
-- nearest live mob in CLAIM_RANGE claimed by anyone in the alliance (`listed`,
-- by server id), marked `claimed`: commands name it by server id, not <bt>.
-- Claims are compared on their low word, in case ClaimStatus holds only that.
-- ponytail: nearest wins; if multi-mob pulls pick the wrong one, prefer the tank's mob
local function claimed_target(em, listed, now)
    local claimers = {}
    for sid in pairs(listed) do claimers[bit.band(sid, 0xFFFF)] = true end
    local function fought(i)
        local c = bit.band(em:GetClaimStatus(i), 0xFFFF)
        return c ~= 0 and claimers[c] and em:GetHPPercent(i) > 0 and bit.band(em:GetSpawnFlags(i), MOB) ~= 0
            and present(em, i)
    end
    if now - claim.at >= CLAIM_SCAN then
        claim.at, claim.tidx = now, nil
        local best = CLAIM_RANGE
        for i = MOB_FIRST, MOB_LAST do
            if fought(i) then
                local d = dist(em, i)
                if d <= best then best, claim.tidx = d, i end
            end
        end
    elseif claim.tidx and not fought(claim.tidx) then
        claim.tidx = nil  -- dead or gone since the last look
    end
    local bt = entity(em, claim.tidx)
    if bt then bt.mob, bt.claimed = true, true end
    return bt
end

-- `m` (a move record) now at `p`: its `moved` is `now` when that isn't where it last
-- was. A first sighting reads as standing still.
local function step(m, p, now)
    local q = m.pos
    if q and (p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3]) then m.moved = now end
    m.pos = p
end

-- Whether you moved, your position sampled every MOVE_SAMPLE.
local function moving(em, tidx, now)
    if now - move.at >= MOVE_SAMPLE then
        move.at = now
        step(move, pos(em, tidx), now)
    end
    return now - move.moved < MOVE_SAMPLE
end

-- Whether `e` (a unit or the battle target) moved within MOVE_GRACE: a luopan
-- stays where it lands (jobs/geo.lua).
local function on_the_move(seen, e, now)
    if not e.pos then return nil end
    local m = motion[e.sid] or { moved = -math.huge }
    step(m, e.pos, now)
    seen[e.sid] = m
    return now - m.moved < MOVE_GRACE
end

local function ability_timer(recast, id)
    for i = 0, 31 do
        if recast:GetAbilityTimerId(i) == id then return recast:GetAbilityTimer(i) end
    end
    return 0
end

local function sch_level(p)
    return p:GetMainJob() == sch.JOB and p:GetMainJobLevel() or p:GetSubJob() == sch.JOB and p:GetSubJobLevel() or 0
end

-- Stratagem charges banked now; nil off SCH.
local function stratagems(mm, player)
    local lv = sch_level(player)
    if lv == 0 then return nil end
    return sch.charges(ability_timer(mm:GetRecast(), sch.STRATAGEMS) / 60, lv)
end

-- Ready charges banked now; nil off BST.
local function ready_charges(mm, player)
    if player:GetMainJob() ~= bst.JOB and player:GetSubJob() ~= bst.JOB then return nil end
    return bst.charges(ability_timer(mm:GetRecast(), bst.READY) / 60)
end

-- The key `action`'s ready stamp is kept under: a charge pool's per charge count.
local function recast_key(action)
    return action.kind .. action.recast .. (action.charges and ':' .. action.charges or '')
end

-- Seconds until `action` (a catalog record) is off recast; 0 = ready.
function game.recast(action)
    if not action.recast then return 0 end  -- items
    local mm = AshitaCore:GetMemoryManager()
    local recast = mm:GetRecast()
    local timer = 0
    if action.kind == 'ma' then
        timer = recast:GetSpellTimer(action.recast)
    elseif action.recast > 0 then
        timer = ability_timer(recast, action.recast)
    end
    local wait = timer / 60
    -- Charge pools: usable once the charges it costs are back, not the whole pool,
    -- and then after the same delay as a recast run out.
    if timer > 0 and action.kind == 'ja' and action.recast == sch.STRATAGEMS then
        wait = sch.charge_wait(wait, sch_level(mm:GetPlayer()))
    elseif timer > 0 and action.kind == 'pet' and action.recast == bst.READY then
        wait = bst.charge_wait(wait, action.charges)
    end
    local key = recast_key(action)
    if wait > 0 then
        ready_since[key] = nil
        return wait
    end
    ready_since[key] = ready_since[key] or os.clock()
    return math.max(0, READY_DELAY - (os.clock() - ready_since[key]))
end

-- Forget `action`'s ready stamp once it's sent, so its next recast gets the full delay.
function game.sent(action)
    if action.recast then ready_since[recast_key(action)] = nil end  -- /heal, /follow: no recast
end

-- The snapshot. { loading = true } until the client has the player's job.
function game.read(now)
    init()
    local mm = AshitaCore:GetMemoryManager()
    local player, party, em = mm:GetPlayer(), mm:GetParty(), mm:GetEntity()
    local zone = party:GetMemberZone(0)
    if player:GetMainJobLevel() == 0 or zone == 0 then return { loading = true, now = now } end

    local units, allied, tracks, listed = {}, {}, {}, {}
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local sid, tidx = party:GetMemberServerId(i), party:GetMemberTargetIndex(i)
            listed[sid] = true
            local u = {
                slot = i, sid = sid, tidx = tidx, name = party:GetMemberName(i),
                kind = i == 0 and 'self' or i > 5 and 'alliance' or sid >= TRUST and 'trust' or 'party',
                tracked = tracked.find(sid) and true,
                hpp = party:GetMemberHPPercent(i), hp = party:GetMemberHP(i),
                mpp = party:GetMemberMPPercent(i), mp = party:GetMemberMP(i), tp = party:GetMemberTP(i),
                in_zone = party:GetMemberZone(i) == zone,
            }
            if u.hpp == 100 and u.hp > 0 then max_hp[sid] = u.hp end
            if i == 0 and player:GetHPMax() > 0 then max_hp[sid] = player:GetHPMax() end
            u.max_known = max_hp[sid] ~= nil
            if i <= 5 then
                u.jobs = { party:GetMemberMainJob(i), party:GetMemberMainJobLevel(i),
                           party:GetMemberSubJob(i), party:GetMemberSubJobLevel(i) }
            end
            if i == 0 then
                u.uses_mp = player:GetMPMax() > 0
            else
                local jobs = ('%d %d/%d'):format(sid, party:GetMemberMainJob(i), party:GetMemberSubJob(i))
                if u.mp > 0 then has_mp[jobs] = true end
                u.uses_mp = has_mp[jobs] == true
            end
            -- Never seen at full: estimate from HP%. Rough at low HP, good enough to score.
            u.max_hp = max_hp[sid] or (u.hpp > 0 and u.hp > 0 and math.floor(u.hp * 100 / u.hpp)) or nil
            -- Only one the client draws: out of its range a member has no entity, and
            -- would read as 0 yalms away. Then dist and pos are unknown: out of reach.
            if u.in_zone and tidx > 0 and (i == 0 or present(em, tidx)) then
                u.status, u.dist, u.pos = em:GetStatus(tidx), i == 0 and 0 or dist(em, tidx), pos(em, tidx)
            end
            u.alive = u.hpp > 0 and u.status ~= DEAD
            if u.kind == 'self' then u.buffs, u.stacks = own_buffs(player)
            elseif u.kind == 'party' then u.buffs, u.stacks = party_buffs(sid)
            else  -- a trust or the alliance: the client keeps no list
                if not u.alive then buffs.forget(sid) end  -- a death clears statuses silently
                u.buffs = buffs.of(sid, now); tracks[sid] = true
            end
            u.hot = observed.hot(sid, now, u.buffs[REGEN])
            local list = u.kind == 'alliance' and allied or units
            list[#list + 1] = u
        end
    end

    local me = units[1]
    relocate(em, now, listed)
    for _, t in ipairs(tracked.list) do
        if not listed[t.sid] then  -- one who joined your party or alliance is a member while they stay
            units[#units + 1] = tracked_unit(em, t, me, now)
            tracks[t.sid] = true
        end
    end
    for _, u in ipairs(allied) do units[#units + 1] = u end

    local bt = battle_target(em) or allied[1] and claimed_target(em, listed, now) or nil
    if bt and bt.mob then last_combat = now end
    if move.zone ~= zone then move.pos, move.zone = nil, zone end  -- a zone or teleport isn't you moving (AFK sleep)
    local is_moving = moving(em, me.tidx, now)  -- before moved_at is read
    local seen = {}
    for _, u in ipairs(units) do
        if u.kind ~= 'self' then u.moving = on_the_move(seen, u, now) end
    end
    if bt then bt.moving = on_the_move(seen, bt, now) end
    motion = seen
    local pet = entity(em, em:GetPetTargetIndex(me.tidx))
    -- A pet's statuses go silently when it dies or is dismissed, and the next may reuse its id.
    -- A luopan's auras end with it, with no message: forget them on those whose statuses come from packets.
    if pet_sid and not (pet and pet.sid == pet_sid and pet.hpp > 0) then
        buffs.forget(pet_sid)
        if player:GetMainJob() == geo.JOB then
            for sid in pairs(tracks) do
                for _, id in pairs(geo.AURAS) do buffs.lose(sid, id) end
            end
            for _, u in ipairs(units) do  -- already read this time round
                if tracks[u.sid] then u.buffs = buffs.of(u.sid, now) end
            end
        end
    end
    local alive = pet and pet.hpp > 0
    if alive and pet.sid ~= pet_sid then pet_since = now end
    if pet then pet.since = pet_since end
    pet_sid = alive and pet.sid or nil
    if pet then pet.buffs = buffs.of(pet.sid, now); tracks[pet.sid] = true end
    -- Statuses on one gone since the last read (a trust dismissed, a member who
    -- left the alliance) went silently: if they come back, they start clean.
    for sid in pairs(fed) do
        if not tracks[sid] then buffs.forget(sid) end
    end
    fed = tracks
    local event = event_ptr ~= 0 and ashita.memory.read_uint32(event_ptr + 1) or 0
    local finished, spell_finish = packets.last_finish()
    local casting, cast_at = packets.casting(now)

    return {
        finished = finished, spell_finish = spell_finish,
        now = now, zone = zone, me = me, units = units, tracks = tracks, bt = bt, target = player_target(mm, em),
        pet = pet, ammo = ammo(), items = inventory(), stratagems = stratagems(mm, player), ready = ready_charges(mm, player),
        roll = cor.last(),
        automaton = pup.automaton(),
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
        recast = game.recast, owned = game.owned,
        learned = observed.learned, day = day(), weather = weather(),
    }
end

return game
