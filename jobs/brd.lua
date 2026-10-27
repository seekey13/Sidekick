--[[
    Bard: songs, picked by slot under Songs (cfg.song, by name, '' for none):
    area_1, area_2 sung as they are on you and your party near you, and each party
    slot's own (me_1, p1_1...) sung on whoever is in it alone through Pianissimo, a
    modifier the engine fires first. One Bard's songs stand brd.slots(g) on each
    player and one more pushes out the oldest, so a member's own picks leave fewer
    slots for the area songs, and while an area song is owed and can't go the songs
    on one member wait: it would push them out. Two songs of one kind (Victory and
    Advancing March) are two statuses of one id, counted with `stacks` on you and
    your party's players; a trust's come from packets, one per id, so any one
    stands for them all.

    Stamps: each of your songs is stamped on everyone its cast's finish packet says
    it landed on (core/packets.lua -> brd.landed), doubled under Troubadour. A stamp
    goes when one more song pushes it out, when its member dies or, on a list we can
    read, once its kind shows no more VERIFY seconds after it landed. With Song
    Duration (cfg.song.duration, a BRD main from TIMED_LEVEL) a stamp alone says
    whether its song is due; while Nightingale and Troubadour are both up, every
    song stamped without Troubadour is. The stamps also say which of two one-kind
    songs was sung last.

    Pianissimo fast casting (cfg.song.fast): an area song goes through Pianissimo
    too, for its shorter cast, cancelled engine.CANCEL_AFTER seconds into it
    (intent.cancel) so the song still lands on everyone near you.
]]--

local buff = require('behaviors.buff')
local can = require('core.can')
local slots = require('core.slots')

local brd = {}

brd.JOB = 10
brd.SLOTS = 2  -- songs per target on a BRD main job; one on a subjob
-- The targets songs are picked for: Area, then each party slot.
brd.SETS = { { key = 'area', label = 'Area' }, { key = 'me', slot = 0, label = 'ME' } }
for i = 1, 5 do brd.SETS[#brd.SETS + 1] = { key = 'p' .. i, slot = i, label = 'P' .. i } end

local PIANISSIMO, NIGHTINGALE, TROUBADOUR = 409, 347, 348
brd.TIMED_LEVEL = 75  -- Song Duration only for a BRD main job from here, as v2 (where song duration gear is)
brd.VERIFY = 5        -- seconds after a song lands before its status must show on a list we can read

-- How many songs stand on each target for your BRD level: 0 off Bard.
function brd.slots(g)
    if g.main == brd.JOB then return brd.SLOTS end
    return g.sub == brd.JOB and 1 or 0
end

-- Whether Song Duration can be set: a BRD main job from TIMED_LEVEL.
function brd.timer_job(g) return g.main == brd.JOB and g.main_lv >= brd.TIMED_LEVEL end

-- Song Duration in seconds when the timers decide, else nil.
function brd.timed(g, cfg)
    local s = cfg.song.duration or 0
    return brd.timer_job(g) and s > 0 and s or nil
end

-- How long song `a` lasts as it lands now, by its base duration: twice that under Troubadour.
function brd.lasts(a, buffs)
    return a.duration * ((buffs or {})[TROUBADOUR] and 2 or 1)
end

-- Your songs' stamps: stamps[server id][song name] = { at, id = its status, double }.
local stamps = {}

-- Song `a` (a catalog record) landed on these server ids at `now`, from your own
-- spell finish; `buffs` are yours (Troubadour doubles it), `stand` how many songs
-- stand on each: one more pushes out the one that would wear first (LSB's
-- ApplyBardEffect), by when it landed and whether it was doubled.
function brd.landed(a, sids, now, buffs, stand)
    for _, sid in ipairs(sids) do
        local rows = stamps[sid] or {}
        stamps[sid] = rows
        if not rows[a.name] then  -- sung again, a song refreshes its own
            local n = 0
            for _ in pairs(rows) do n = n + 1 end
            while n >= math.max(stand or brd.SLOTS, 1) do
                local first, ends = nil, math.huge
                for name, r in pairs(rows) do
                    local e = r.at + a.duration * (r.double and 2 or 1)
                    if e < ends then first, ends = name, e end
                end
                rows[first], n = nil, n - 1
            end
        end
        rows[a.name] = { at = now, id = a.status[1], double = (buffs or {})[TROUBADOUR] == true or nil }
    end
end

function brd.stamps() return stamps end
function brd.clear() stamps = {} end  -- a job change: your songs go with it

-- Drop the stamps a death or a list we can read says are gone, and those of
-- any no longer in the snapshot (a trust released or gone, one who left).
local function prune(g)
    local listed = {}
    for _, u in ipairs(g.units) do listed[u.sid or false] = true end
    for sid in pairs(stamps) do
        if not listed[sid] then stamps[sid] = nil end
    end
    for _, u in ipairs(g.units) do
        local rows = u.sid and stamps[u.sid]
        if rows and u.in_zone and not u.alive then
            stamps[u.sid] = nil
        elseif rows and u.in_zone and u.stacks then
            for name, r in pairs(rows) do
                if g.now - r.at >= brd.VERIFY and (u.stacks[r.id] or 0) == 0 then rows[name] = nil end
            end
        end
    end
end

-- Your songs by name, and Pianissimo.
function brd.actions(cat)
    return slots.by_name(cat, 'song'), slots.by_name(cat, 'modifier').Pianissimo
end

-- A set's songs, as catalog records in slot order, for the first `n` slots: a
-- slot with none (or one you lack) is skipped, and a song picked twice is one.
function brd.picked(cfg, key, songs, n) return slots.picked(cfg.song, key, songs, n, true) end

-- How many of status `id` stand on `u`; a trust's (no stacks) stand for all.
local function count(u, id)
    if u.stacks then return u.stacks[id] or 0 end
    return u.buffs[id] and math.huge or 0
end

-- Whether `u` lacks `a` among the songs `sets` pick for them together (their
-- own, and the area ones while they count for those): songs of one kind want
-- one status each, a song picked in two of them one.
local function lacks(u, a, sets)
    local id, want, seen = a.status[1], 0, {}
    for _, set in ipairs(sets) do
        for _, s in ipairs(set) do
            if s.status[1] == id and not seen[s] then seen[s], want = true, want + 1 end
        end
    end
    return count(u, id) < want
end

-- How many of the area songs `u` holds (each kind no more times than it's picked).
local function held(u, area)
    local want, out = {}, 0
    for _, a in ipairs(area) do want[a.status[1]] = (want[a.status[1]] or 0) + 1 end
    for id, n in pairs(want) do out = out + math.min(count(u, id), n) end
    return out
end

-- Whether `u` can be sung to: there, alive, in your party.
local function here(u) return u.in_zone and u.alive and can.in_party(u) end

-- Area song `a`: who near you it's for is owed it (the first, and how many),
-- and, holding for the group, the first player in your party lacking it out of
-- its reach with no song of their own (a stamp due on one who still has it holds
-- nothing). `free(u)`: the slots `u` has for area songs; `owes(u, a, lacking)`:
-- whether `u` is owed it (`lacking`: by their statuses alone).
local function voters(a, g, free, owes, hold)
    local radius = can.yalms(a.area)
    local near, n, away = nil, 0, nil
    for _, u in ipairs(g.units) do
        local room = free(u)
        if here(u) and room > 0 then
            if can.near(u, radius) then
                if owes(u, a) then near, n = near or u, n + 1 end
            elseif hold and u.kind == 'party' and room == brd.slots(g) and not away and owes(u, a, true) then
                away = u
            end
        end
    end
    return near, n, away
end

-- Of `set`'s songs of `a`'s kind, the one landed least lately on `u` that can go
-- now and isn't up by its timer (`due` false), else nil: which of two one-kind
-- songs is up can't be read, and the one sung last is likeliest.
local function oldest(a, set, u, g, due)
    local rows, best, at = stamps[u.sid] or {}, nil, math.huge
    for _, s in ipairs(set) do
        local t = rows[s.name] and rows[s.name].at or -math.huge
        if s.status[1] == a.status[1] and t < at and due(u, s) ~= false and can.use(s, g) then best, at = s, t end
    end
    return best
end

function brd.want(g, cat, cfg, mem)
    local n = brd.slots(g)
    if n == 0 then return nil end
    prune(g)
    local timed = brd.timed(g, cfg)
    local window = g.me.buffs[NIGHTINGALE] and g.me.buffs[TROUBADOUR]
    -- What your stamp of `a` on `u` says: true due, false still up, nil that it can't say.
    local function due(u, a)
        local r = stamps[u.sid] and stamps[u.sid][a.name]
        if not r then return nil end
        if window and not r.double then return true end
        if not timed then return nil end
        return g.now >= r.at + timed * (r.double and 2 or 1)
    end
    -- The song to sing for `a` on `u`: `a` itself when its stamp says it's due, else
    -- of its kind the one sung least lately.
    local function choose(a, set, u)
        if due(u, a) then return can.use(a, g) and a or nil end
        return oldest(a, set, u, g, due)
    end
    local songs, pianissimo = brd.actions(cat)
    local area, own, by_slot = brd.picked(cfg, 'area', songs, n), {}, {}
    for _, set in ipairs(brd.SETS) do
        if set.slot then own[set.slot] = brd.picked(cfg, set.key, songs, n) end
    end
    for _, u in ipairs(g.units) do
        if u.slot and u.slot <= 5 then by_slot[u.slot] = u end
    end
    -- A slot's own songs, which leave fewer slots for the area ones: none
    -- without Pianissimo (under BRD 20), since they can't go.
    local function mine(u) return pianissimo and u.slot and own[u.slot] or {} end
    local function free(u) return u.slot and u.slot <= 5 and n - #mine(u) or 0 end
    -- Whether `u` is owed area song `a`: its stamp says so (unless `lacking`), else
    -- they lack it and hold fewer of the area songs than the slots they have for them.
    local function owes(u, a, lacking)
        local d = not lacking and due(u, a)
        if not lacking and d ~= nil then return d end
        return lacks(u, a, { area, mine(u) }) and held(u, area) < free(u)
    end

    -- Area songs, unless the next song would land on one member (with fast
    -- casting, an area song takes Pianissimo and cancels it mid-cast; under
    -- Nightingale only one already up, none is raised for it).
    local up = g.me.buffs[PIANISSIMO]
    local fast = cfg.song.fast and pianissimo and (up or not g.me.buffs[NIGHTINGALE])
    local owed = false
    for _, a in ipairs(up and not fast and {} or area) do
        local near, count_, away = voters(a, g, free, owes, cfg.buff.hold_aoe)
        if away then
            -- The songs on one member wait only when it's for someone near too:
            -- otherwise it refreshes what they have and pushes nothing out.
            buff.wait_for(mem, a, near, away)
            owed = owed or near ~= nil and a
        elseif near then
            local pick = choose(a, area, near)
            if pick then
                local verb = due(near, a) and { 'is due', 'are due' } or { 'lacks it', 'lack it' }
                local why = count_ > 1 and ('%s +%d %s'):format(near.name, count_ - 1, verb[2]) or ('%s %s'):format(near.name, verb[1])
                if fast then return { action = pick, why = why, mods = { pianissimo }, cancel = PIANISSIMO } end
                return { action = pick, why = why }
            end
            owed = owed or a
        end
    end

    -- Each slot's songs on whoever is there, through Pianissimo; while an area
    -- song is owed they wait (it would push them out), and say for which, unless
    -- Pianissimo is up: an area song that can't go now leaves it to them, rather
    -- than letting it wear.
    for slot = 0, 5 do
        local u = by_slot[slot]
        for _, a in ipairs(u and here(u) and own[slot] or {}) do
            local d = due(u, a)
            local short = d or d == nil and lacks(u, a, { own[slot], free(u) > 0 and area or {} })
            local pick = can.near(u, can.yalms(a.range)) and short
                and choose(a, own[slot], u)
            if pick and owed and not up then
                mem.waiting = mem.waiting or { action = pick, mod = owed }
                return nil
            elseif pick then
                if not (pianissimo and (up or can.use(pianissimo, g))) then
                    if pianissimo then mem.waiting = mem.waiting or { action = pick, mod = pianissimo } end
                    return nil
                end
                return { action = pick, target = u.kind ~= 'self' and u or nil, mods = { pianissimo }, why = u.name }
            end
        end
    end
end

return brd
