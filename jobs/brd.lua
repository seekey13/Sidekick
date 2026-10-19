--[[
    Bard: songs (v2's song passes in lib/actions/buff.lua). One Bard's songs
    stand two at once on each player (one from a BRD subjob), and a new one
    pushes that Bard's oldest out; a song sung again refreshes its own. So
    under Songs (cfg.song) each target has those slots, by name ('' for none):
      Area (song.area_1, area_2)  sung as they are, on you and everyone in
                                  your party near you (the DAT's area, about 10 yalms);
      ME, P1-P5 (song.me_1, p1_1...)  sung on that party slot alone, through
                                  Pianissimo, which the engine fires first (core/engine.lua);
                                  without it (under BRD 20) they take no slot.
    Two songs of one kind (Victory and Advancing March, Valor Minuet IV and III)
    are two statuses of one id: each pick wants its own, counted on you and your
    party's players (`stacks`); a trust's statuses come from packets, one per
    id, so there any one stands for them all.

    Area songs go first: one goes when someone near you it counts for lacks it,
    you included (a member counts only while their own picks leave them a
    slot, and is short only while they hold fewer of the area songs than that).
    While one is owed and can't go (its recast, your MP, held for the group
    while someone near lacks it too), the songs on one member wait too: the
    area song would push them out once it goes (v2's rule). A member's own
    songs and the area ones they count for are one set: an area Victory March
    and their own Advancing March want two Marches. Then each slot's picks, on whoever is there, alive and in
    reach, whenever they lack one. While Pianissimo is up the area songs wait:
    the next song lands on one member (one left with no one to sing to wears
    off on its own, as v2). Of two songs of one kind with one up,
    the one sung less lately goes (new: v2 sang the first picked, which may be
    the one up).
    Nothing goes while you're Invisible, as buffs. With buff.hold_aoe on, an
    area song is held while a player in your party who lacks it, with no song
    picked for them alone, is out of its reach (or not drawn); trusts follow.
]]--

local buff = require('behaviors.buff')
local can = require('core.can')

local brd = {}

brd.JOB = 10
brd.SLOTS = 2  -- songs per target on a BRD main job; one on a subjob
-- The targets songs are picked for: Area, then each party slot.
brd.SETS = { { key = 'area', label = 'Area' }, { key = 'me', slot = 0, label = 'ME' } }
for i = 1, 5 do brd.SETS[#brd.SETS + 1] = { key = 'p' .. i, slot = i, label = 'P' .. i } end

local INVISIBLE, PIANISSIMO = 69, 409

-- How many songs stand on each target for your BRD level: 0 off Bard.
function brd.slots(g)
    if g.main == brd.JOB then return brd.SLOTS end
    return g.sub == brd.JOB and 1 or 0
end

-- The settings path of a set's slot `i`: 'song.area_1', 'song.p3_2'.
function brd.path(key, i) return ('song.%s_%d'):format(key, i) end

-- Your songs by name, and Pianissimo.
function brd.actions(cat)
    local songs, pianissimo = {}, nil
    for _, a in ipairs(cat) do
        if a.role == 'song' then songs[a.name] = a end
        if a.name == 'Pianissimo' and a.role == 'modifier' then pianissimo = a end
    end
    return songs, pianissimo
end

-- A set's songs, as catalog records in slot order, for the first `n` slots: a
-- slot with none (or one you lack) is skipped, and a song picked twice is one.
function brd.picked(cfg, key, songs, n)
    local out, seen = {}, {}
    for i = 1, n do
        local a = songs[cfg.song[key .. '_' .. i]]
        if a and not seen[a] then seen[a] = true; out[#out + 1] = a end
    end
    return out
end

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

-- Area song `a`: who near you it's for lacks it (the first, and how many),
-- and, holding for the group, the first player in your party lacking it out of
-- its reach with no song of their own. `free(u)`: the slots `u` has for area songs.
local function voters(a, area, g, free, mine, hold)
    local radius = can.yalms(a.area)
    local near, n, away = nil, 0, nil
    for _, u in ipairs(g.units) do
        local slots = free(u)
        if here(u) and slots > 0 and lacks(u, a, { area, mine(u) }) and held(u, area) < slots then
            if u.kind == 'self' or (u.dist or math.huge) <= radius then
                near, n = near or u, n + 1
            elseif hold and u.kind == 'party' and slots == brd.slots(g) and not away then
                away = u
            end
        end
    end
    return near, n, away
end

-- Of `set`'s songs of `a`'s kind, the one sung least lately on `on` ('area' or a
-- server id) that can go now, else nil: which of two one-kind songs is up can't
-- be read, and the one sung last is likeliest.
local function oldest(a, set, on, sung, g)
    local best, at = nil, math.huge
    for _, s in ipairs(set) do
        local t = sung[s.name .. '>' .. on] or -math.huge
        if s.status[1] == a.status[1] and t < at and can.use(s, g) then best, at = s, t end
    end
    return best
end

function brd.want(g, cat, cfg, mem)
    local n = brd.slots(g)
    if n == 0 or g.me.buffs[INVISIBLE] then return nil end
    mem.brd = mem.brd or { sung = {} }  -- sung['<name>><area|sid>']: when it was last sent
    local sung = mem.brd.sung
    local function sent(a, on) return function (now) sung[a.name .. '>' .. on] = now end end
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

    -- Area songs, unless the next song would land on one member.
    local up = g.me.buffs[PIANISSIMO]
    local owed = false
    for _, a in ipairs(up and {} or area) do
        local near, count_, away = voters(a, area, g, free, mine, cfg.buff.hold_aoe)
        if away then
            -- The songs on one member wait only when it's for someone near too:
            -- otherwise it refreshes what they have and pushes nothing out.
            buff.wait_for(mem, a, near, away)
            owed = owed or near ~= nil
        elseif near then
            local pick = oldest(a, area, 'area', sung, g)
            if pick then
                local why = count_ > 1 and ('%s +%d lack it'):format(near.name, count_ - 1) or ('%s lacks it'):format(near.name)
                return { action = pick, why = why, sent = sent(pick, 'area') }
            end
            owed = true
        end
    end
    if owed then return nil end

    -- Each slot's songs on whoever is there, through Pianissimo.
    for slot = 0, 5 do
        local u = by_slot[slot]
        for _, a in ipairs(u and here(u) and own[slot] or {}) do
            local pick = (u.kind == 'self' or (u.dist or math.huge) <= can.yalms(a.range)) and lacks(u, a, { own[slot], free(u) > 0 and area or {} })
                and oldest(a, own[slot], u.sid, sung, g)
            if pick then
                if not (pianissimo and (up or can.use(pianissimo, g))) then
                    if pianissimo then mem.waiting = mem.waiting or { action = pick, mod = pianissimo } end
                    return nil
                end
                return { action = pick, target = u.kind ~= 'self' and u or nil, mods = { pianissimo }, why = u.name,
                         sent = sent(pick, u.sid) }
            end
        end
    end
end

return brd
