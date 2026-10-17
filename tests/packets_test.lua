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
