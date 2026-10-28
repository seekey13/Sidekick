--[[
    What the game tells us only through packets:
      - when your own cast or item use starts, finishes or is interrupted (the cast lock and
        the post-action throttle in core/engine.lua),
      - statuses gained and lost by units with no readable status list
        (core/buffs.lua),
      - what your own heals restored and where your Regens landed (core/observed.lua),
      - a /check's answer: a tracked player's jobs and levels (core/tracked.lua),
      - your own job abilities' results on you, for the job modules (core/jobs.lua: `ability`),
      - who your songs landed on (jobs/brd.lua),
      - your automaton's name (jobs/pup.lua),
      - your Blue Mage's set spells (jobs/blu.lua).
    Message ids and bit layouts verified against the CatsEyeXI server
    (src/map/packets/s2c/0x028_battle2.cpp, 0x0c9_equip_inspect_general.h, 0x044_extended_job_pup.h, 0x044_extended_job_blu.h,
    msg_std.h / msg_basic.h).
]]--

local blu = require('jobs.blu')
local brd = require('jobs.brd')
local buffs = require('core.buffs')
local jobs = require('core.jobs')
local observed = require('core.observed')
local players = require('core.tracked')  -- the players you track
local pup = require('jobs.pup')
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

-- 0x028 action packet: header plus each target's results (bit-packed, big endian).
local function parse_action(e)
    local data, offset, limit = e.data_raw, 40, e.size * 8
    local function bits(n)
        if offset + n > limit then limit = 0; return 0 end  -- malformed: whole packet is trash
        local v = ashita.bits.unpack_be(data, 0, offset, n)
        offset = offset + n
        return v
    end
    local p = { actor = bits(32) }
    local count = bits(6)
    offset = offset + 4
    p.category = bits(4)
    p.param = bits(16)  -- spell/ability id on a finish; a marker (or INTERRUPT) on a begin
    bits(16)
    bits(32)            -- recast
    p.targets = {}
    for _ = 1, count do
        local t = { id = bits(32), results = {} }
        local n = bits(4)
        if n == 0 then break end
        for _ = 1, n do
            bits(3 + 2 + 12)                     -- resolution, kind, animation
            local r = { info = bits(5) }         -- COR: the die
            bits(2 + 3)                          -- scale, knockback
            r.param = bits(17)
            r.message = bits(10)
            bits(31)                             -- flags
            if bits(1) == 1 then bits(10 + 17 + 10) end  -- additional effect
            if bits(1) == 1 then bits(10 + 14 + 10) end  -- spikes
            t.results[#t.results + 1] = r
        end
        p.targets[#p.targets + 1] = t
    end
    return limit ~= 0 and p or nil
end

-- A parsed 0x028 (tests hand one in directly).
-- ctx: { me = your server id, pet = your pet's or nil, tracks = { [server id] = true }
-- for units whose statuses come from packets, duration = function(spell id) -> seconds or nil,
-- song = function(spell id) -> the song's catalog record or nil, buffs = yours, slots = your songs per target,
-- removes = function(observed.key) -> the status ids your remover clears and whether it's Esuna's
-- kind (cast on you, clearing on those near only what you have too), or nil }
function packets.action(p, ctx, now)
    if p.actor == ctx.me and p.category ~= 1 then  -- 1 = auto-attack, says nothing
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
    local song = p.actor == ctx.me and p.category == SPELL_FINISH and ctx.song and ctx.song(p.param)
    local clears, shared
    if key and kind ~= 'pet' and ctx.removes then clears, shared = ctx.removes(key) end  -- your remover's
    local sung = {}  -- who your song landed on
    for _, t in ipairs(p.targets) do
        local tracked = ctx.tracks[t.id]
        for _, r in ipairs(t.results) do
            if kind == 'ja' and p.actor == ctx.me and t.id == ctx.me then
                for f in jobs.each('ability') do f(p.param + ABILITY_BASE, r.param, r.message, now, r.info) end
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
                local lasts = song and brd.lasts(song, ctx.buffs) or spell and ctx.duration(p.param) or nil
                if tracked then buffs.gain(t.id, r.param, now, lasts) end
                if key and spell then observed.landed(key, t.id, now) end
                if song then sung[#sung + 1] = t.id end
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
    if sung[1] then brd.landed(song, sung, now, ctx.buffs, ctx.slots) end
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

-- 0x044, the extended job data, one per job (main, then sub): for PUP the
-- automaton's name, 16 bytes at 0x58, NUL-padded (none when it's 16 long); for
-- BLU the set spells, a byte per slot at 0x08.
local function on_extended_job(e)
    local d, job = e.data, e.data:byte(0x04 + 1)
    if job == pup.JOB and #d >= 0x58 + 16 then
        pup.named((d:sub(0x58 + 1, 0x58 + 16):match('^[^%z]*')))
    elseif job == blu.JOB and #d >= 0x08 + blu.SLOTS then
        blu.slots({ d:byte(0x08 + 1, 0x08 + blu.SLOTS) })
    end
end

function packets.handle(e, ctx, now)
    if e.id == 0x028 then
        local p = parse_action(e)
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
        for f in jobs.each('zone') do f() end
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
