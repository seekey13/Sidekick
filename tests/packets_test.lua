-- core/packets.lua on parsed 0x028s: statuses landing on trusts and your pet.
local buffs = require('core.buffs')
local packets = require('core.packets')

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
       { { ['Valor Minuet IV'] = { at = 5, id = 198, double = true } }, { ['Valor Minuet IV'] = { at = 5, id = 198, double = true } }, nil })
    -- The trust's status, read from packets, lasts twice its 120s too.
    eq({ buffs.of(TRUST, 5 + 239)[198], buffs.of(TRUST, 5 + 241)[198] }, { true, nil })
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
