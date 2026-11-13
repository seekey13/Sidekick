--[[
    One read of the game: you, your party and trusts, the players you track
    (core/tracked.lua), then your alliance's other two parties, as one list of
    units (behaviors go down it in that order, as v2 did); your battle target
    and pet, and the flags that stop automation
    (casting, moving, mounted, dead, incapacitated, safe zone...; `event`, a cutscene
    or an NPC you're talking to, is a safe zone too). The engine
    decides from this snapshot alone, so tests can hand it a fake one.

    unit = { slot, sid, tidx, name, kind = 'self'|'party'|'trust'|'alliance'|'tracked', hpp, hp, max_hp,
             immune (a trust that can't be hurt: Moogle, Sakura, Kupofried...; core/engine.lua hides it from behaviors),
             mpp, mp, tp, uses_mp (yours: max MP > 0; your party's: a job with MP, main or
             sub, or seen with MP on these jobs; the alliance's: seen with MP),
             max_known (max_hp is real: yours, or seen at full HP),
             jobs = { main, main_lv, sub, sub_lv } (you and your party's players),
             in_zone, dist, pos = { x, y, z },
             status (entity), alive, buffs = { [id] = true },
             stacks = { [id] = how many stand } (you and your party's players: runes
             and songs of one kind stack; nil for a player the client's list has no entry for yet),
             moving (others: moved in the last half second),
             hot = HP still to come from your Regen, nil if none,
             futile = { [remover's observed.key] = { [id] = true } }: statuses it shows that remover just had no effect on
             (core/removal.lua), left be by behaviors/remove.lua,
             pet (a party member's or a tracked player's, while the client draws both: an entity as
             `bt`'s, { sid, tidx, name, hpp, dist, pos, status }, its HP % alone; never one at 0%) }
    Slots: 0 you, 1-5 your party, 6-11 and 12-17 the alliance's other parties
    (kind 'alliance', their statuses from packets as a trust's).
    A tracked player has no slot and no MP; in_zone while the client draws them
    (in range; out of it, their HP and status as last seen, or as a session file
    says), max_hp from a session file, else estimated from their /check level (else
    yours), and main, main_lv, sub, sub_lv once a /check or a session file has
    answered; `auto` names the session whose file tracks them (core/share.lua). A member (or alliance member) you also track has tracked = true.
    The pet is { sid, tidx, name, hpp, mpp, tp, uses_mp (seen with MP), dist, pos, status (1 engaged), buffs,
    since (first seen) }; the
    battle target `bt` { sid, tidx, name, hpp, dist, pos, mob, claimed, moving }, `claimed`
    when it's a mob another party of the alliance claimed (the client has no <bt>), or
    any the alliance claimed while a trust is in another party (the client's isn't asked).
    `target` is your current target when it's another player: { tidx, sid, name }.
    `t` (not `target`) is your current target (<t>) when it's a living mob nobody outside
    the alliance claimed: an entity as `bt`'s, mob = true; looked for only when <bt> is
    (not idle, not in a safe zone).
    Plus when your cast began (cast_at, while casting);
    what healing scores with: learned potency, the day and the weather;
    the item in your ammo slot and what's in your inventory (and `owned`, the ammo
    you hold where it can be worn from, read when asked); when you last moved and
    last had a battle target; and the job modules' own fields (core/jobs.lua:
    `read`): stratagem (`stratagems`) and Ready (`ready`) charges, your Phantom
    Rolls' totals (`roll`, `roll_totals`), your automaton's name (`automaton`, nil
    until the server says it).
]]--

local ffi = require('ffi')
local buffs = require('core.buffs')
local can = require('core.can')
local job_modules = require('core.jobs')
local observed = require('core.observed')
local packets = require('core.packets')
local removal = require('core.removal')
local status = require('core.status')
local tracked = require('core.tracked')
local util = require('core.util')

local game = {}

local TRUST = 0x1000000  -- server ids from here up are NPCs; in a party slot, a trust
-- CatsEyeXI trusts that take no damage and no status (they stay at full HP), so
-- healing, buffing, cleansing or recovering them is wasted (v2's EXCLUDED_TRUSTS).
-- Matched by name and an NPC's id, so a player of the same name is never left out.
local IMMUNE = { ['Moogle'] = true, ['Sakura'] = true, ['Kupofried'] = true,
                 ['Star Sibyl'] = true, ['Brygid'] = true, ['Cornelia'] = true }
-- The jobs with MP of their own: WHM, BLM, RDM, PLD, DRK, SMN, BLU, SCH, GEO, RUN.
local MP_JOBS = { [3] = true, [4] = true, [5] = true, [7] = true, [8] = true, [15] = true, [16] = true, [20] = true,
                  [21] = true, [22] = true }
local DEAD, MOUNTED_STATUS, RESTING = 3, 5, 33  -- entity status
local MOUNTED_BUFF, AMNESIA, REGEN = 252, 16, status.REGEN
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
    typedef struct { uint8_t padding00[116]; uint32_t GuideNo; uint32_t UniqueNo; } sk_battle_actor;
    typedef sk_battle_actor* (__stdcall* sk_seek_battle_actor)(void);
]]

-- Client functions found once, on first read (none of this exists offline).
local seek_bt, event_ptr, weather_ptr, clock_ptr  -- false / 0 when the signature isn't found
local function init()
    if seek_bt ~= nil then return end
    local bt = ashita.memory.find('FFXiMain.dll', 0, '66A1????????83EC186685C053565774??0FBFC08B0C85', 0, 0)
    seek_bt = bt and bt ~= 0 and ffi.cast('sk_seek_battle_actor', bt) or false
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
local motion = {}  -- [sid] = { x, y, z, moved }: where each other unit and the battle target last were
local last_combat = -math.huge
local pet_sid  -- the live pet last seen: its statuses are forgotten once it's gone or dead
local pet_since  -- when that pet was first seen: a new one (it may reuse the id) comes after a read without one
local pet_mp_since  -- pet_since of the last pet seen with MP: a wyvern's or a jug pet's 0% isn't an empty tank
local ready_since = {}  -- [recast key] = when its timer first read 0
local rescan_at = -math.huge
local claim = { at = -math.huge, tidx = nil }  -- the last look for an alliance-claimed mob
local fed = {}  -- [sid] = true: last read's units whose statuses come from packets

local any = can.any

-- A list of status ids (0 and 255 for none) as a set, and how many of each stand
-- (runes stack: jobs/run.lua; so do songs of one kind: jobs/brd.lua).
local function counted(list)
    local set, stacks = {}, {}
    for _, id in ipairs(list) do
        if id > 0 and id ~= 255 then set[id], stacks[id] = true, (stacks[id] or 0) + 1 end
    end
    return set, stacks
end

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

local function position(em, i)
    return { em:GetLocalPositionX(i), em:GetLocalPositionY(i), em:GetLocalPositionZ(i) }
end

local function distance(em, i) return math.sqrt(em:GetDistance(i)) end

local function entity(em, tidx)
    if not tidx or tidx == 0 then return nil end
    return {
        tidx = tidx, sid = em:GetServerId(tidx), name = em:GetName(tidx), hpp = em:GetHPPercent(tidx),
        dist = distance(em, tidx), status = em:GetStatus(tidx), pos = position(em, tidx),
    }
end

-- An entity the client is drawing: spawned near you, not hidden.
local function present(em, i)
    local flags = em:GetRenderFlags0(i)
    return em:GetRawEntity(i) ~= nil and bit.band(flags, 0x200) ~= 0 and bit.band(flags, 0x4000) == 0
end

-- Another player's pet while the client draws it. Its MP and TP the client reads for
-- your pet only (core/share.lua brings another session's); one at 0% is gone, as a
-- dead or dismissed pet lingers a while.
local function their_pet(em, owner)
    local pet = entity(em, em:GetPetTargetIndex(owner))
    if pet and pet.hpp > 0 and present(em, pet.tidx) then return pet end
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

-- Your current target (not one being picked) when it's a living mob, as <t> names it,
-- and one nobody outside the alliance (`listed`, by server id) claimed: the server
-- refuses to send your pet at another party's mob, and the send would only repeat.
-- Claims are compared on their low word, as claimed_target's.
local function mob_target(mm, em, listed)
    local t = mm:GetTarget()
    local i = t:GetTargetIndex(t:GetIsSubTargetActive() == 0 and 0 or 1)
    if not i or i == 0 or bit.band(em:GetSpawnFlags(i), MOB) == 0 or em:GetHPPercent(i) == 0
        or not present(em, i) then return nil end
    local c = bit.band(em:GetClaimStatus(i), 0xFFFF)
    if c ~= 0 then
        local ours = false
        for sid in pairs(listed) do ours = ours or bit.band(sid, 0xFFFF) == c end
        if not ours then return nil end
    end
    local e = entity(em, i)
    if e then e.mob = true end
    return e
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
        u.tidx, u.dist, u.pos, u.pet = i, distance(em, i), position(em, i), their_pet(em, i)
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

-- The client's <bt>. Retail never puts a trust in another party of the alliance,
-- but trusts called past a full party land there, and the client's lookup then
-- jumps to a bad pointer, crashing Sidekick: while one is there it isn't asked,
-- and the mob comes from the alliance's claims (claimed_target).
local function battle_target(em, trust_allied)
    if not seek_bt or trust_allied then return nil end
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
                local d = distance(em, i)
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

local function moving(em, tidx, now)
    if now - move.at < MOVE_SAMPLE then return now - move.moved < MOVE_SAMPLE end
    local x, y, z = unpack(position(em, tidx))
    if move.x and (x ~= move.x or y ~= move.y or z ~= move.z) then move.moved = now end
    move.at, move.x, move.y, move.z = now, x, y, z
    return now - move.moved < MOVE_SAMPLE
end

-- Whether `e` (a unit or the battle target) moved within MOVE_GRACE: a luopan
-- stays where it lands (jobs/geo.lua). A first sighting reads as standing still.
local function on_the_move(seen, e, now)
    if not e.pos then return nil end
    local m = motion[e.sid] or { moved = -math.huge }
    local x, y, z = e.pos[1], e.pos[2], e.pos[3]
    if m.x and (x ~= m.x or y ~= m.y or z ~= m.z) then m.moved = now end
    m.x, m.y, m.z = x, y, z
    seen[e.sid] = m
    return now - m.moved < MOVE_GRACE
end

local function ability_timer(recast, id)
    for i = 0, 31 do
        if recast:GetAbilityTimerId(i) == id then return recast:GetAbilityTimer(i) end
    end
    return 0
end

-- Your jobs and levels, as the snapshot carries them.
local function jobs_of(player)
    return { main = player:GetMainJob(), main_lv = player:GetMainJobLevel(),
             sub = player:GetSubJob(), sub_lv = player:GetSubJobLevel() }
end

-- Seconds left on ability recast timer `id`.
local function recast_left(id) return ability_timer(AshitaCore:GetMemoryManager():GetRecast(), id) / 60 end

-- The job modules' charge pools (core/charges.lua; core/jobs.lua: `POOL`).
local POOLS = {}
for _, pool in job_modules.each('POOL') do POOLS[#POOLS + 1] = pool end

-- Where `action`'s ready stamp is kept: by its recast, and for a pool's by the charges it costs too.
local function ready_key(action) return action.kind .. action.recast .. (action.charges and ':' .. action.charges or '') end

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
    for _, pool in ipairs(POOLS) do
        if timer > 0 and pool:spends(action) then
            wait = pool:wait(wait, util.level(jobs_of(mm:GetPlayer()), pool.job), action.charges)
        end
    end
    local key = ready_key(action)
    if wait > 0 then
        ready_since[key] = nil
        return wait
    end
    ready_since[key] = ready_since[key] or os.clock()
    return math.max(0, READY_DELAY - (os.clock() - ready_since[key]))
end

-- Whether the client lists ability `action` now (an ability the server lists only at times: core/catalog.lua).
function game.listed(action)
    return AshitaCore:GetMemoryManager():GetPlayer():HasAbility(action.id)
end

-- Forget `action`'s ready stamp once it's sent, so its next recast gets the full delay.
function game.sent(action)
    if not action.recast then return end  -- /heal, /follow: no recast
    ready_since[ready_key(action)] = nil
end

-- Party slot `i` as a unit: 0 you, 1-5 your party and trusts, 6-17 the alliance.
local function member(party, player, em, i, zone, now)
    local sid, tidx = party:GetMemberServerId(i), party:GetMemberTargetIndex(i)
    local u = {
        slot = i, sid = sid, tidx = tidx, name = party:GetMemberName(i),
        kind = i == 0 and 'self' or i > 5 and 'alliance' or sid >= TRUST and 'trust' or 'party',
        tracked = tracked.find(sid) and true,
        hpp = party:GetMemberHPPercent(i), hp = party:GetMemberHP(i),
        mpp = party:GetMemberMPPercent(i), mp = party:GetMemberMP(i), tp = party:GetMemberTP(i),
        in_zone = party:GetMemberZone(i) == zone,
    }
    u.immune = sid >= TRUST and IMMUNE[u.name] or nil
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
        -- A job with MP, main or sub: at 0 MP (just loaded, out of zone) a mage still has some. Else once seen with it.
        local key = ('%d %d/%d'):format(sid, party:GetMemberMainJob(i), party:GetMemberSubJob(i))
        if u.mp > 0 then has_mp[key] = true end
        local j = u.jobs or {}
        u.uses_mp = has_mp[key] == true or MP_JOBS[j[1]] == true or (j[4] or 0) > 0 and MP_JOBS[j[3]] == true
    end
    -- Never seen at full: estimate from HP%. Rough at low HP, good enough to score.
    u.max_hp = max_hp[sid] or (u.hpp > 0 and u.hp > 0 and math.floor(u.hp * 100 / u.hpp)) or nil
    -- Only one the client draws: out of its range a member has no entity, and
    -- would read as 0 yalms away. Then dist and pos are unknown: out of reach.
    if u.in_zone and tidx > 0 and (i == 0 or present(em, tidx)) then
        u.status = em:GetStatus(tidx)
        u.dist, u.pos = i == 0 and 0 or distance(em, tidx), position(em, tidx)
        if u.kind == 'party' then u.pet = their_pet(em, tidx) end  -- yours is the snapshot's (read_pet)
    end
    u.alive = u.hpp > 0 and u.status ~= DEAD
    if u.kind == 'self' then u.buffs, u.stacks = own_buffs(player)
    elseif u.kind == 'party' then u.buffs, u.stacks = party_buffs(sid)
    else  -- a trust or the alliance: the client keeps no list
        if not u.alive then buffs.forget(sid) end  -- a death clears statuses silently
        u.buffs = buffs.of(sid, now)
    end
    u.hot = observed.hot(sid, now, u.buffs[REGEN])
    return u
end

-- Your pet, if any. A pet's statuses go silently when it dies or is dismissed, and
-- the next may reuse its id; a luopan's auras end with it, with no message, so
-- they're forgotten on those whose statuses come from packets (`tracks`).
local function read_pet(em, player, me, jobs, units, tracks, now)
    local pet = entity(em, em:GetPetTargetIndex(me.tidx))
    if pet_sid and not (pet and pet.sid == pet_sid and pet.hpp > 0) then
        buffs.forget(pet_sid)
        local gone = false
        for _, auras in job_modules.each('pet_auras', jobs.main) do  -- core/jobs.lua
            gone = true
            for sid in pairs(tracks) do
                for _, id in ipairs(auras) do buffs.lose(sid, id) end
            end
        end
        if gone then
            for _, u in ipairs(units) do  -- already read this time round
                if tracks[u.sid] then u.buffs = buffs.of(u.sid, now) end
            end
        end
    end
    local alive = pet and pet.hpp > 0
    if alive and pet.sid ~= pet_sid then pet_since = now end
    pet_sid = alive and pet.sid or nil
    if not pet then return nil end
    pet.since, pet.mpp, pet.tp = pet_since, player:GetPetMPPercent(), player:GetPetTP()
    if pet.mpp > 0 then pet_mp_since = pet_since end
    pet.uses_mp = pet_since ~= nil and pet_mp_since == pet_since
    pet.buffs, tracks[pet.sid] = buffs.of(pet.sid, now), true
    return pet
end

-- The snapshot. { loading = true } until the client has the player's job, and while zoning.
-- `idle` (automation stopped or asleep): no battle target is looked for, nor in a safe zone. Finding
-- <bt> calls into the client, so it's done only when something may act on it.
function game.read(now, idle)
    init()
    local mm = AshitaCore:GetMemoryManager()
    local player, party, em = mm:GetPlayer(), mm:GetParty(), mm:GetEntity()
    local zone = party:GetMemberZone(0)
    if player:GetMainJobLevel() == 0 or zone == 0 or packets.zoning(now) then return { loading = true, now = now } end
    local jobs = jobs_of(player)

    local units, allied, tracks, listed = {}, {}, {}, {}
    local trust_allied = false  -- a trust in slots 6-17, or one there whose id isn't read yet (battle_target)
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local u = member(party, player, em, i, zone, now)
            listed[u.sid] = true
            if i > 5 and (u.sid >= TRUST or u.sid == 0) then trust_allied = true end
            if u.kind == 'trust' or u.kind == 'alliance' then tracks[u.sid] = true end  -- statuses from packets
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

    local event = event_ptr ~= 0 and ashita.memory.read_uint32(event_ptr + 1) or 0
    local in_event = event ~= 0 and ashita.memory.read_uint8(event) == 1
    local safe = SAFE_ZONES[zone] == true or in_event
    local bt = not (idle or safe) and (battle_target(em, trust_allied) or allied[1] and claimed_target(em, listed, now)) or nil
    if bt and bt.mob then last_combat = now end
    if move.zone ~= zone then move.x, move.zone = nil, zone end  -- a zone or teleport isn't you moving (AFK sleep)
    local is_moving = moving(em, me.tidx, now)  -- before moved_at is read
    local seen = {}
    for _, u in ipairs(units) do
        if u.kind ~= 'self' then u.moving = on_the_move(seen, u, now) end
    end
    if bt then bt.moving = on_the_move(seen, bt, now) end
    motion = seen
    local pet = read_pet(em, player, me, jobs, units, tracks, now)
    -- Statuses on one gone since the last read (a trust dismissed, a member who
    -- left the alliance) went silently: if they come back, they start clean.
    for sid in pairs(fed) do
        if not tracks[sid] then buffs.forget(sid) end
    end
    fed = tracks
    for _, u in ipairs(units) do u.futile = removal.futile(u.sid, u.buffs, now) end
    local finished, spell_finish = packets.last_finish()
    local casting, cast_at = packets.casting(now)

    local g = {
        finished = finished, spell_finish = spell_finish,
        now = now, zone = zone, me = me, units = units, tracks = tracks, bt = bt, target = player_target(mm, em),
        t = not (idle or safe) and mob_target(mm, em, listed) or nil,
        pet = pet, ammo = ammo(), items = inventory(),
        main = jobs.main, main_lv = jobs.main_lv, sub = jobs.sub, sub_lv = jobs.sub_lv,
        casting = casting, cast_at = cast_at,
        moving = is_moving, moved_at = move.moved,
        combat = now - last_combat < COMBAT_GRACE, combat_at = last_combat,
        safe = safe, event = in_event,
        mounted = me.status == MOUNTED_STATUS or me.buffs[MOUNTED_BUFF] == true,
        dead = not me.alive,
        resting = me.status == RESTING,
        incapacitated = any(me.buffs, INCAPACITATED),
        silenced = any(me.buffs, SILENCED),
        amnesia = me.buffs[AMNESIA] == true,
        recast = game.recast, owned = game.owned, listed = game.listed,
        learned = observed.learned, day = day(), weather = weather(),
    }
    for _, f in job_modules.each('read') do f(g, recast_left) end
    return g
end

return game
