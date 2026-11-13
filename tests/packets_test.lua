-- core/packets.lua on parsed 0x028s: statuses landing on trusts and your pet.
local buffs = require('core.buffs')
local packets = require('core.packets')
local observed = require('core.observed')

local ME, TRUST, PET, MOB, STRANGER = 1, 0x1000001, 0x1000002, 0x1000100, 0x1000200
local SLEEP, POISON, PROTECT = 2, 3, 40
local SPELL, MOB_SKILL = 4, 11
local ECHO = 4151  -- Echo Drops

local function ctx(durations)
    return { me = ME, pet = PET, tracks = { [TRUST] = true, [PET] = true },
             duration = function (spell) return (durations or {})[spell] end }
end

-- One action; results = { { target sid, message, param }, ... }.
local function action(actor, category, param, results)
    local p = { actor = actor, category = category, param = param, targets = {} }
    for _, r in ipairs(results) do
        p.targets[#p.targets + 1] = { id = r[1], results = { { message = r[2], param = r[3] } } }
    end
    return p
end

test('a mob\'s Sleepga: its main target and the others it lands on', function ()
    buffs.clear()
    packets.action(action(MOB, SPELL, 273, { { TRUST, 236, SLEEP }, { PET, 277, SLEEP } }), ctx(), 0)
    eq({ buffs.of(TRUST, 1), buffs.of(PET, 1) }, { { [SLEEP] = true }, { [SLEEP] = true } })
end)

test('a TP move\'s poison, on tracked units only', function ()
    buffs.clear()
    packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, POISON }, { STRANGER, 243, POISON } }), ctx(), 0)
    eq({ buffs.of(TRUST, 1), buffs.of(STRANGER, 1) }, { { [POISON] = true }, {} })
end)

test('a removal clears what it names; your remover with no effect clears all it removes but Doom', function ()
    local PETRIFY, DOOM, CURSE, SLOW = 7, 15, 9, 13
    local c = ctx()
    c.removes = function (key)
        return ({ ma18 = { PETRIFY }, ma20 = { CURSE, DOOM }, ja706 = { POISON, SLOW } })[key]
    end
    buffs.clear()
    packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, PETRIFY }, { PET, 242, PETRIFY } }), c, 0)
    packets.action(action(ME, SPELL, 18, { { TRUST, 83, PETRIFY } }), c, 1)  -- Stona: removed
    packets.action(action(ME, SPELL, 18, { { PET, 75, 0 } }), c, 1)          -- no effect: it wore off unseen
    eq({ buffs.of(TRUST, 2), buffs.of(PET, 2) }, { {}, {} })
    -- Cursna with no effect may have failed on Doom: only the curse goes.
    buffs.gain(TRUST, CURSE, 2); buffs.gain(TRUST, DOOM, 2)
    packets.action(action(ME, SPELL, 20, { { TRUST, 75, 0 } }), c, 3)
    eq(buffs.of(TRUST, 4), { [DOOM] = true })
    packets.action(action(ME, SPELL, 20, { { TRUST, 359, DOOM } }), c, 4)    -- narrowly escapes
    eq(buffs.of(TRUST, 5), {})
    -- Erase and a waltz name the one status they took: the rest stays.
    buffs.gain(TRUST, POISON, 5); buffs.gain(TRUST, SLOW, 5)
    packets.action(action(ME, 14, 194, { { TRUST, 123, SLOW } }), c, 6)
    eq(buffs.of(TRUST, 7), { [POISON] = true })
    packets.action(action(STRANGER, SPELL, 143, { { TRUST, 341, POISON } }), c, 7)
    eq(buffs.of(TRUST, 8), {})
    -- Another's spell with no effect says nothing of what's on them.
    buffs.gain(TRUST, PETRIFY, 8)
    packets.action(action(STRANGER, SPELL, 18, { { TRUST, 75, 0 } }), c, 9)
    eq(buffs.of(TRUST, 10), { [PETRIFY] = true })
end)

test('Cursna takes every curse though it names one; Esuna clears only what it names', function ()
    local PETRIFY, CURSE, CURSE2, BANE, PARALYSIS = 7, 9, 20, 30, 4
    local c = ctx()
    c.removes = function (key)
        if key == 'ma20' then return { CURSE, 15, CURSE2, BANE }, false end
        if key == 'ma95' then return { POISON, PARALYSIS, PETRIFY }, true end
    end
    buffs.clear()
    for _, id in ipairs({ CURSE, BANE }) do buffs.gain(TRUST, id, 0) end
    packets.action(action(ME, SPELL, 20, { { TRUST, 83, CURSE } }), c, 1)
    eq(buffs.of(TRUST, 2), {})
    -- Esuna: a success (message 0) names the one it took; no effect says nothing of them.
    for _, id in ipairs({ POISON, PARALYSIS, PETRIFY }) do buffs.gain(TRUST, id, 2); buffs.gain(PET, id, 2) end
    packets.action(action(ME, SPELL, 95, { { ME, 0, POISON }, { TRUST, 0, POISON }, { PET, 75, 0 } }), c, 3)
    eq({ buffs.of(TRUST, 4), buffs.of(PET, 4) },
       { { [PARALYSIS] = true, [PETRIFY] = true }, { [POISON] = true, [PARALYSIS] = true, [PETRIFY] = true } })
end)

test('another\'s Esuna clears on a trust the status it names', function ()
    buffs.clear()
    buffs.gain(TRUST, POISON, 0)
    packets.action(action(STRANGER, SPELL, 95, { { STRANGER, 0, POISON }, { TRUST, 0, POISON } }), ctx(), 1)
    eq(buffs.of(TRUST, 2), {})
end)

-- A 0x029 as the server builds it (0x029_battle_message.h): actor at 0x04, target at 0x08, param at 0x0C,
-- message at 0x18. Doom's own come from the doomed unit, to itself.
local function message_packet(target, param, message)
    local b = {}
    for i = 1, 0x1C do b[i] = 0 end
    local function put(at, v, n) for i = 0, n - 1 do b[at + i + 1] = math.floor(v / 0x100 ^ i) % 0x100 end end
    put(0x04, target, 4); put(0x08, target, 4); put(0x0C, param, 4); put(0x18, message, 2)
    return { id = 0x029, data = string.char(unpack(b)) }
end

-- Ashita's struct.unpack, little endian, for the 'i4' and 'H' core/packets.lua reads.
local function with_struct(fn)
    local was = struct
    rawset(_G, 'struct', { unpack = function (fmt, d, pos)
        local n = fmt == 'H' and 2 or 4
        local v = 0
        for i = n - 1, 0, -1 do v = v * 0x100 + d:byte(pos + i) end
        if fmt == 'i4' and v >= 0x80000000 then v = v - 0x100000000 end
        return v, pos + n
    end })
    local ok, err = pcall(fn)
    rawset(_G, 'struct', was)
    if not ok then error(err, 0) end
end

test('Doom on a trust: on while its counter runs, Cursnas that miss and all; off as it\'s taken off', function ()
    local CURSE, DOOM, PARALYSIS = 9, 15, 4
    local COUNT, ESCAPE = 112, 359
    local c = ctx()
    c.removes = function (key) if key == 'ma20' then return { CURSE, DOOM } end end
    with_struct(function ()
        buffs.clear()
        packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, DOOM } }), c, 0)
        -- The count every 3 s from 5 s, and a Cursna with no effect after each: the Doom stays, read right after
        -- the Cursna, before the next count could put it back.
        for k = 0, 9 do
            local s = 5 + 3 * k
            packets.handle(message_packet(TRUST, 20 - k, COUNT), c, s)
            packets.action(action(ME, SPELL, 20, { { TRUST, 75, 0 } }), c, s + 1)
            eq(buffs.of(TRUST, s + 1), { [DOOM] = true })
        end
        -- One that took a curse (83): the curse goes, the Doom stays.
        packets.handle(message_packet(TRUST, 10, COUNT), c, 35)
        buffs.gain(TRUST, CURSE, 35)
        packets.action(action(ME, SPELL, 20, { { TRUST, 83, CURSE } }), c, 36)
        eq(buffs.of(TRUST, 36), { [DOOM] = true })
        -- The count is a number, not a status: 4 is not Paralysis.
        packets.handle(message_packet(TRUST, PARALYSIS, COUNT), c, 38)
        eq(buffs.of(TRUST, 38), { [DOOM] = true })
        -- "Narrowly escapes impending doom" as a 0x029 (an NM's death, Mix: Holy Water on a trust): off. A
        -- player's own Holy Water tells only them.
        packets.handle(message_packet(TRUST, 0, ESCAPE), c, 43)
        eq(buffs.of(TRUST, 43), {})
        -- As Cursna's own result (0x028): off too.
        packets.handle(message_packet(TRUST, 19, COUNT), c, 50)
        packets.action(action(ME, SPELL, 20, { { TRUST, ESCAPE, DOOM } }), c, 51)
        eq(buffs.of(TRUST, 51), {})
        -- The count of a unit not tracked: nothing.
        packets.handle(message_packet(STRANGER, 19, COUNT), c, 52)
        eq(buffs.of(STRANGER, 52), {})
    end)
end)

test('a Doom read from packets lasts DOOM_HOLD past its gain or its last count: one that ended unseen draws Cursna no longer',
    function ()
    local DOOM, COUNT = 15, 112
    with_struct(function ()
        buffs.clear()
        packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, DOOM } }), ctx(), 0)
        eq(buffs.of(TRUST, buffs.DOOM_HOLD - 0.1), { [DOOM] = true })  -- the first count comes within 6 s
        eq(buffs.of(TRUST, buffs.DOOM_HOLD), {})
        -- The counts stop (out of range, taken off where no one saw): gone DOOM_HOLD after the last.
        packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, DOOM } }), ctx(), 10)
        packets.handle(message_packet(TRUST, 19, COUNT), ctx(), 15)
        packets.handle(message_packet(TRUST, 18, COUNT), ctx(), 18)
        eq(buffs.of(TRUST, 18 + buffs.DOOM_HOLD - 0.1), { [DOOM] = true })
        eq(buffs.of(TRUST, 18 + buffs.DOOM_HOLD), {})
        -- A count with no gain seen (they came into range doomed): Doom.
        packets.handle(message_packet(PET, 7, COUNT), ctx(), 40)
        eq(buffs.of(PET, 40), { [DOOM] = true })
        -- A catalog duration doesn't stretch it.
        buffs.gain(TRUST, DOOM, 50, 600)
        eq(buffs.of(TRUST, 50 + buffs.DOOM_HOLD), {})
    end)
end)

test('your remover with no effect on you or your party: what it clears is futile there for it while shown, but Doom', function ()
    local removal = require('core.removal')
    local PARTY, PARALYSIS, SLOW, DOOM, CURSE = 0x100, 4, 13, 15, 9
    local c = ctx()
    c.removes = function (key)
        if key == 'ma143' then return { SLOW, PARALYSIS } end
        if key == 'ma20' then return { CURSE, DOOM } end
        if key == 'ma95' then return { PARALYSIS }, true end
    end
    removal.clear()
    local shown = { [SLOW] = true, [DOOM] = true, [CURSE] = true }
    removal.futile(PARTY, shown, 0)  -- the read before: what it showed
    packets.action(action(ME, SPELL, 143, { { PARTY, 75, 0 } }), c, 1)  -- Erase: no effect
    packets.action(action(ME, SPELL, 20, { { PARTY, 75, 0 } }), c, 1)   -- Cursna: no effect
    -- Each remover's marks are its own: another that clears SLOW may still try it.
    eq(removal.futile(PARTY, shown, 2), { ma143 = { [SLOW] = true }, ma20 = { [CURSE] = true } })
    -- Seen gone, a mark goes: one put back is cleared again.
    eq(removal.futile(PARTY, { [CURSE] = true }, 3), { ma20 = { [CURSE] = true } })
    eq(removal.futile(PARTY, shown, 4), { ma20 = { [CURSE] = true } })
    -- And it holds no longer than HOLD while shown.
    eq(removal.futile(PARTY, shown, 1 + removal.HOLD + 1), {})
    -- Your Esuna's no effect says you had nothing to share: nothing is marked.
    removal.futile(PARTY, { [PARALYSIS] = true }, 99)
    packets.action(action(ME, SPELL, 95, { { PARTY, 75, 0 } }), c, 100)
    eq(removal.futile(PARTY, { [PARALYSIS] = true }, 101), {})
    -- A status that lands with the no effect, not shown at the read before, is new: not marked.
    removal.clear()
    removal.futile(PARTY, {}, 200)
    packets.action(action(ME, SPELL, 143, { { PARTY, 75, 0 } }), c, 201)
    eq(removal.futile(PARTY, { [SLOW] = true }, 202), {})
    -- One never read yet: nothing is marked.
    removal.clear()
    packets.action(action(ME, SPELL, 143, { { PARTY, 75, 0 } }), c, 300)
    eq(removal.futile(PARTY, shown, 301), {})
end)

test('your item in use locks like a cast, until it finishes or is cut off', function ()
    packets.action(action(ME, 9, 24931, {}), ctx(), 10)  -- 24931: an item's start
    eq({ packets.casting(10.5) }, { true, 10 })  -- and when it began
    packets.action(action(ME, 5, ECHO, {}), ctx(), 11)
    eq({ packets.casting(11), packets.last_finish() }, { false, 11, false })
    packets.action(action(ME, 9, 24931, {}), ctx(), 12)
    packets.action(action(ME, 9, 28787, {}), ctx(), 13)  -- interrupted
    eq(packets.casting(13), false)
end)

test('a paralyzed item use: a spell-style finish, then the interrupt, so the short lockout', function ()
    packets.action(action(ME, 9, 24931, {}), ctx(), 20)
    packets.action(action(ME, SPELL, 0, {}), ctx(), 21)      -- "is paralyzed", sent as a MagicFinish
    packets.action(action(ME, 9, 28787, {}), ctx(), 21)
    eq({ packets.casting(21), packets.last_finish() }, { false, 21, false })
end)

test('only a spell\'s id names a duration', function ()
    buffs.clear()
    local c = ctx({ [1234] = 10 })
    packets.action(action(MOB, MOB_SKILL, 1234, { { TRUST, 242, POISON } }), c, 0)
    packets.action(action(STRANGER, SPELL, 1234, { { TRUST, 230, PROTECT } }), c, 0)
    eq(buffs.of(TRUST, 50), { [POISON] = true })
end)

test('your song is stamped on who its finish says it landed on, doubled under Troubadour', function ()
    local brd = require('jobs.brd')
    brd.clear()
    local minuet = { name = 'Valor Minuet IV', role = 'song', status = { 198 }, duration = 120 }
    local protect = { name = 'Protect', role = 'buff', status = { 40 } }
    buffs.clear()
    local c = ctx()
    c.spell = function (id) return id == 397 and minuet or id == 43 and protect or nil end
    c.buffs, c.slots = { [348] = true }, 2
    -- On you and a trust; a stranger it had no effect on (75) isn't stamped.
    packets.action(action(ME, SPELL, 397, { { ME, 230, 198 }, { TRUST, 266, 198 }, { STRANGER, 75, 198 } }), c, 5)
    eq({ brd.stamps()[ME], brd.stamps()[TRUST], brd.stamps()[STRANGER] },
       { { ['Valor Minuet IV'] = { at = 5, id = 198, double = true, ends = 245 } },
         { ['Valor Minuet IV'] = { at = 5, id = 198, double = true, ends = 245 } }, nil })
    -- The trust's status, read from packets, lasts twice its 120s too.
    eq({ buffs.of(TRUST, 5 + 239)[198], buffs.of(TRUST, 5 + 241)[198] }, { true, nil })
    -- Two of one kind are one status: it lasts as long as the one that wears last, so
    -- a second without Troubadour (ends 450) leaves the first's 540.
    packets.action(action(ME, SPELL, 397, { { TRUST, 266, 198 } }), c, 300)
    c.buffs = {}
    packets.action(action(ME, SPELL, 397, { { TRUST, 266, 198 } }), c, 330)
    eq({ buffs.of(TRUST, 539)[198], buffs.of(TRUST, 541)[198] }, { true, nil })
    -- Another's song, or your other spells, stamp nothing.
    brd.clear()
    packets.action(action(MOB, SPELL, 397, { { ME, 230, 198 } }), c, 6)
    packets.action(action(ME, SPELL, 43, { { ME, 230, 40 } }), c, 6)
    eq(next(brd.stamps()), nil)
end)

test('zoning: from the zone-out until the zone-in settles, or a minute without it', function ()
    local function at(id, now) packets.handle({ id = id, data = '' }, ctx(), now) end
    at(0x00B, 100)
    eq({ packets.zoning(101), packets.zoning(110) }, { true, true })
    at(0x00A, 110)
    eq({ packets.zoning(112), packets.zoning(113.5) }, { true, false })
    at(0x00B, 200)
    eq({ packets.zoning(259), packets.zoning(261), packets.zoning(262) }, { true, false, false })
end)

test('the spell and ability lists are counted, and no other packet', function ()
    local before = packets.lists()
    for _, id in ipairs({ 0x0AC, 0x0AA, 0x0AB, 0x0AC }) do packets.handle({ id = id, data = '' }, ctx(), 0) end
    eq(packets.lists() - before, 3)
end)

-- A raw 0x028 with the server's field widths, read through a stand-in for ashita.bits (bits
-- kept one per entry, a field's high bit first). targets = { { sid, { { message, param,
-- spikes }, ... } } }; every result has an additional effect, a result with `spikes` spikes too.
local function raw_action(actor, category, param, targets)
    local d = {}
    local function put(n, v) for i = n - 1, 0, -1 do d[#d + 1] = math.floor(v / 2 ^ i) % 2 end end
    put(40, 0); put(32, actor); put(6, #targets); put(4, 0); put(4, category); put(16, param); put(16, 0); put(32, 0)
    for _, t in ipairs(targets) do
        put(32, t[1]); put(4, #t[2])
        for _, r in ipairs(t[2]) do
            put(17, 0); put(5, 0); put(5, 0); put(17, r[2]); put(10, r[1]); put(31, 0)
            put(1, 1); put(37, 12345)  -- an additional effect: skipped
            if r[3] then put(1, 1); put(34, 6789) else put(1, 0) end
        end
    end
    return { id = 0x028, data_raw = d, size = math.ceil(#d / 8) }
end

local function with_bits(fn)
    local was, reads = ashita, 0
    ashita = { bits = { unpack_be = function (d, _, at, n)
        reads = reads + 1
        local v = 0
        for i = 1, n do v = v * 2 + (d[at + i] or 0) end
        return v
    end } }
    local ok, err = pcall(fn, function () local r = reads; reads = 0; return r end)
    ashita = was
    if not ok then error(err, 0) end
end

test('a raw 0x028: tracked targets read past untracked ones, an auto-attack not read past its header', function ()
    with_bits(function (reads)
        buffs.clear()
        packets.handle(raw_action(MOB, MOB_SKILL, 1234, { { STRANGER, { { 242, POISON, true } } }, { TRUST, { { 242, POISON } } },
                                                          { PET, { { 242, SLEEP }, { 242, POISON } } } }), ctx(), 0)
        eq({ buffs.of(TRUST, 1), buffs.of(PET, 1), buffs.of(STRANGER, 1) },
           { { [POISON] = true }, { [SLEEP] = true, [POISON] = true }, {} })
        -- Nothing tracked: another's action stops at its actor and category.
        reads()
        local none = ctx(); none.tracks = {}
        packets.handle(raw_action(MOB, MOB_SKILL, 1234, { { STRANGER, { { 242, POISON } } } }), none, 0)
        eq(reads(), 3)
        packets.handle(raw_action(MOB, 1, 0, { { TRUST, { { 1, 50 } } } }), ctx(), 0)
        eq(reads(), 3)
        -- Your own: the cast lock, with nothing tracked too.
        packets.handle(raw_action(ME, 8, 0, { { MOB, { { 0, 0 } } } }), none, 10)
        eq(packets.casting(11), true)
        packets.handle(raw_action(ME, SPELL, 0, { { MOB, { { 0, 0 } } } }), none, 12)
        eq({ packets.casting(13), packets.last_finish() }, { false, 12, true })
    end)
end)

test('a raw 0x028: your own and your pet\'s heals are read on untracked targets too', function ()
    with_bits(function ()
        local none = ctx(); none.tracks = {}
        observed.clear()
        local cure, ruby = 'ma1', 'pet' .. (595 + 512)  -- Cure; a pet's move, its id + 512 (observed.key)
        observed.sent(cure, { need = { [STRANGER] = 500 }, mult = 1, at = 0 })
        observed.sent(ruby, { need = { [STRANGER] = 500 }, mult = 1, at = 0 })
        packets.handle(raw_action(ME, SPELL, 1, { { STRANGER, { { 7, 100, true } } } }), none, 1)
        packets.handle(raw_action(PET, 13, 595, { { STRANGER, { { 7, 80 } } } }), none, 1)
        eq({ observed.learned[cure], observed.learned[ruby] }, { 100, 80 })
        observed.learned[cure], observed.learned[ruby] = nil, nil
    end)
end)
