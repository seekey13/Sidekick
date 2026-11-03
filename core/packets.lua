--[[
    What the game tells us only through packets:
      - when your own cast or item use starts, finishes or is interrupted (the cast lock and
        the post-action throttle in core/engine.lua),
      - statuses gained and lost by units with no readable status list
        (core/buffs.lua),
      - what your own heals restored and where your Regens landed (core/observed.lua),
      - a /check's answer: a tracked player's jobs and levels (core/tracked.lua),
      - for the job modules (core/jobs.lua): your own job abilities' results on you
        (`ability`: Phantom Rolls), who your spells landed on and for how long
        (`spell`, `lasts`: songs), and your jobs' extended data (`extended`: your
        automaton's name, your Blue Mage's set spells).
    Message ids and bit layouts verified against the CatsEyeXI server
    (src/map/packets/s2c/0x028_battle2.cpp, 0x0c9_equip_inspect_general.h, 0x044_extended_job_pup.h, 0x044_extended_job_blu.h,
    msg_std.h / msg_basic.h).
]]--

local buffs = require('core.buffs')
local jobs = require('core.jobs')
local observed = require('core.observed')
local players = require('core.tracked')  -- the players you track
local status = require('core.status')

local packets = {}

-- Param carried by a cancelled action instead of a finish (no spell id is 28787).
local INTERRUPT = 28787
-- 0x028 categories: 2 ranged, 3 ws, 4 spell, 5 item, 6/14/15 job ability.
local FINISH = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [14] = true, [15] = true }
local CAST_BEGIN, ITEM_BEGIN, SPELL_FINISH = 8, 9, 4
-- A cast whose finish packet never arrived (zoning, lost packet) unlocks after this.
local CAST_TIMEOUT = 16
-- Zoning: from the zone-out 0x00B until ZONE_SETTLE seconds after the zone-in 0x00A
-- (the client is still building the zone), ZONE_TIMEOUT at most if 0x00A goes missing.
local ZONE_SETTLE, ZONE_TIMEOUT = 3, 60

-- 0x028 per-target messages. Gains (param = the status): buffs and enfeebles from
-- spells, abilities and TP moves, and the variants an area one shows its other targets.
local GAINS_028 = { [186] = true, [230] = true, [236] = true, [237] = true, [242] = true, [243] = true,
                    [266] = true, [277] = true, [278] = true }
-- Effect removed, param = the status: a -na spell (83), an ability's removal (123: a waltz,
-- a pet's Remove), a TP move's erase (159), Erase, Dispel or Finale (341), Cursna's Doom (359).
local LOSES_028 = { [83] = true, [123] = true, [159] = true, [341] = true, [359] = true }
-- Cursna's 83 names one curse, but it takes every one there.
local CURSES = { [9] = true, [20] = true, [30] = true }  -- Curse, Curse II, Bane
-- Recovers HP, param = HP: cures, waltzes, Chakra, blood pacts and their area variants.
local HEALS_028 = { [7] = true, [24] = true, [102] = true, [238] = true, [263] = true, [318] = true, [367] = true }
-- Categories whose heals are yours: 4 spell, 6/14/15 job ability; 11/13 your pet's moves.
local KIND = { [4] = 'ma', [6] = 'ja', [14] = 'ja', [15] = 'ja', [11] = 'pet', [13] = 'pet' }
local ABILITY_BASE = 512  -- catalog ability id = packet param (ability or pet skill id) + 512; see observed.key

-- 0x029 messages whose param IS a status id; every other 0x029 (damage, misses,
-- synth results...) carries an unrelated param and must not be read as a status.
local GAINS_029 = {
    [186] = true, [203] = true, [205] = true, [230] = true, [236] = true, [237] = true,
    [242] = true, [243] = true, [266] = true, [277] = true, [278] = true,
    [280] = true,  -- CatsEyeXI "is afflicted with" variant
}
local LOSES_029 = { [204] = true, [206] = true, [343] = true }  -- wears off / disappears

local cast = { active = false, since = 0, finished = -math.huge, spell = false }
local zone = { out = nil, settle = -math.huge }  -- when you zoned out (nil once back); when that settles

-- The 0x028 being read: its bytes, the next bit, and where it ends (0 once a read ran
-- past it: the packet is malformed).
local raw, at, limit = nil, 0, 0
local function bits(n)
    if at + n > limit then limit = 0; return 0 end
    local v = ashita.bits.unpack_be(raw, 0, at, n)
    at = at + n
    return v
end
local function skip(n)
    if at + n > limit then limit = 0 else at = at + n end
end

-- A result's fields up to its two optional parts: resolution, kind, animation, info,
-- scale, knockback, param, message, flags.
local RESULT_BITS = 3 + 2 + 12 + 5 + 2 + 3 + 17 + 10 + 31
-- Auto-attack. The server builds it only in its attack round (entities/battleentity.cpp), with
-- main messages 0, 1, 15, 30-32, 67, 70, 352, 353 and 373: none packets.action reads. Enspells,
-- spikes and status procs come in the additional effect and spikes parts, never read.
local MELEE = 1

-- 0x028 action packet: header plus each target's results (bit-packed, big endian), or nil
-- when it's malformed or can't matter to packets.action: an auto-attack, or another's
-- action on no unit in ctx.tracks. Of another's action, only the tracked targets are read:
-- the rest are skipped, not parsed, since packets.action does nothing with them.
local function parse_action(e, ctx)
    raw, at, limit = e.data_raw, 40, e.size * 8
    local actor = bits(32)
    local count = bits(6)
    skip(4)
    local category = bits(4)
    if category == MELEE then return nil end
    local tracks = ctx.tracks
    local all = actor == ctx.me or actor == ctx.pet  -- your own and your pet's: every target
    if not all and next(tracks) == nil then return nil end
    local p = { actor = actor, category = category, param = bits(16), targets = {} }
    skip(16 + 32)  -- recast
    for _ = 1, count do
        local id = bits(32)
        local n = bits(4)
        if n == 0 then break end
        local t = (all or tracks[id]) and { id = id, results = {} }
        for _ = 1, n do
            if t then
                skip(3 + 2 + 12)                     -- resolution, kind, animation
                local r = { info = bits(5) }         -- COR: the die
                skip(2 + 3)                          -- scale, knockback
                r.param = bits(17)
                r.message = bits(10)
                skip(31)                             -- flags
                t.results[#t.results + 1] = r
            else
                skip(RESULT_BITS)
            end
            if bits(1) == 1 then skip(10 + 17 + 10) end  -- additional effect
            if bits(1) == 1 then skip(10 + 14 + 10) end  -- spikes
        end
        if t then p.targets[#p.targets + 1] = t end
    end
    if not (all or p.targets[1]) then return nil end  -- another's, on no one tracked
    return limit ~= 0 and p or nil
end

-- How long your spell `a` lasts as it lands, when a job module knows (core/jobs.lua: `lasts`).
local function lasting(a, ctx)
    for _, f in jobs.each('lasts') do
        local s = f(a, ctx)
        if s then return s end
    end
end

-- A parsed 0x028 (tests hand one in directly).
-- ctx: { me = your server id, pet = your pet's or nil, tracks = { [server id] = true }
-- for units whose statuses come from packets, duration = function(spell id) -> seconds or nil,
-- spell = function(spell id) -> your spell's catalog record or nil, buffs = yours, slots = your songs per target
-- (jobs/brd.lua), removes = function(observed.key) -> the status ids your remover clears and whether it's Esuna's
-- kind (cast on you, clearing on those near only what you have too), or nil }
function packets.action(p, ctx, now)
    if p.actor == ctx.me and p.category ~= MELEE then
        if (p.category == CAST_BEGIN or p.category == ITEM_BEGIN) and p.param ~= INTERRUPT then
            cast.active, cast.since = true, now
        else
            cast.active = false
        end
        if FINISH[p.category] or p.param == INTERRUPT then
            cast.finished, cast.spell = now, p.category == SPELL_FINISH
        end
    end
    if p.param == INTERRUPT then return end
    local kind = KIND[p.category]
    local key = kind and p.actor == (kind == 'pet' and ctx.pet or ctx.me)
        and kind .. (kind == 'ma' and p.param or p.param + ABILITY_BASE)
    local mine = p.actor == ctx.me and p.category == SPELL_FINISH and ctx.spell and ctx.spell(p.param)
    local clears, shared
    if key and kind ~= 'pet' and ctx.removes then clears, shared = ctx.removes(key) end  -- your remover's
    local landed = {}  -- who your spell landed on
    for _, t in ipairs(p.targets) do
        local tracked = ctx.tracks[t.id]
        for _, r in ipairs(t.results) do
            if kind == 'ja' and p.actor == ctx.me and t.id == ctx.me then
                for _, f in jobs.each('ability') do f(p.param + ABILITY_BASE, r.param, r.message, now, r.info) end
            end
            if HEALS_028[r.message] then
                if key then
                    observed.healed(key, t.id, r.param, now)
                    if tracked then for _, s in ipairs(status.SLEEP) do buffs.lose(t.id, s) end end
                end
            elseif GAINS_028[r.message] then
                -- Only a spell's id names a catalog duration; an ability's or TP move's doesn't.
                local spell = p.category == SPELL_FINISH
                -- Your song lasts twice as long under Troubadour (jobs/brd.lua).
                local lasts = mine and lasting(mine, ctx) or spell and ctx.duration(p.param) or nil
                if tracked then buffs.gain(t.id, r.param, now, lasts, mine and mine.role == 'song') end
                if key and spell then observed.landed(key, t.id, now) end
                if mine then landed[#landed + 1] = t.id end
            elseif LOSES_028[r.message] and tracked then
                buffs.lose(t.id, r.param)
                if r.message == 83 and CURSES[r.param] then
                    for id in pairs(CURSES) do buffs.lose(t.id, id) end
                end
            elseif shared and tracked then
                -- Esuna's success has no message, param = the status; its no effect says
                -- you had nothing to share, not what's on them.
                if r.message == 0 and r.param > 0 then buffs.lose(t.id, r.param) end
            elseif clears and tracked then
                -- Your remover landed without naming a status (no effect: it was gone already,
                -- its wear-off unseen), so what it removes is gone. Not Doom: Cursna can fail on it.
                for _, id in ipairs(clears) do
                    if id ~= status.DOOM then buffs.lose(t.id, id) end
                end
            end
        end
    end
    if key then observed.done(key) end
    if landed[1] then
        for _, f in jobs.each('spell') do f(mine, landed, now, ctx) end
    end
end

local function on_message(e, ctx, now)
    if #e.data < 0x1A then return end
    local target = struct.unpack('i4', e.data, 0x08 + 1)
    local id = struct.unpack('i4', e.data, 0x0C + 1)
    local message = struct.unpack('H', e.data, 0x18 + 1) % 0x8000
    if not ctx.tracks[target] or id <= 0 or id == 255 then return end
    if GAINS_029[message] then buffs.gain(target, id, now)
    elseif LOSES_029[message] then buffs.lose(target, id) end
end

-- 0x0C9 comes twice per /check: equipment (flag 3), then the general part
-- (flag 1) with the checked player's server id and their jobs and levels.
local CHECK_GENERAL = 1
local function on_check(e)
    local d = e.data
    if #d < 0x26 or d:byte(0x0A + 1) ~= CHECK_GENERAL then return end
    local b1, b2, b3, b4 = d:byte(0x04 + 1, 0x04 + 4)
    players.checked(b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000,
        d:byte(0x22 + 1), d:byte(0x24 + 1), d:byte(0x23 + 1), d:byte(0x25 + 1))
end

-- 0x044, the extended job data, one per job (main, then sub), the job at 0x04:
-- its module reads the rest (core/jobs.lua: `extended`).
local function on_extended_job(e)
    local d = e.data
    if #d < 0x04 + 1 then return end
    for _, f in jobs.each('extended', d:byte(0x04 + 1)) do f(d) end
end

function packets.handle(e, ctx, now)
    if e.id == 0x028 then
        local p = parse_action(e, ctx)
        if p then packets.action(p, ctx, now) end
    elseif e.id == 0x029 then
        on_message(e, ctx, now)
    elseif e.id == 0x0C9 then
        on_check(e)
    elseif e.id == 0x044 then
        on_extended_job(e)
    elseif e.id == 0x00B then  -- zoning out: the client tears the zone down
        zone.out = now
    elseif e.id == 0x00A then  -- zoning: a cast in flight is cancelled with no packet
        zone.out, zone.settle = nil, now + ZONE_SETTLE
        cast.active = false
        buffs.clear()
        observed.clear()
        for _, f in jobs.each('zone') do f() end
    end
end

-- True while your own spell is casting or your item is in use, and when it began.
function packets.casting(now)
    if cast.active and now - cast.since > CAST_TIMEOUT then cast.active = false end
    return cast.active, cast.active and cast.since or nil
end

-- True while you zone: the client's actors are being torn down or rebuilt, and
-- calling into it then crashes the game (core/game.lua's battle target).
function packets.zoning(now)
    if zone.out and now - zone.out > ZONE_TIMEOUT then zone.out = nil end
    return zone.out ~= nil or now < zone.settle
end

-- When your last action resolved, and whether it was a spell (longer lockout).
function packets.last_finish()
    return cast.finished, cast.spell
end

return packets
