-- Tracked players (core/tracked.lua): the list, a /check's answer, and every
-- behavior with one, on fake snapshots over a real catalog (WHM 75 / BLM 37).
local buffs = require('core.buffs')
local can = require('core.can')
local observed = require('core.observed')
local packets = require('core.packets')
local settings = require('core.settings')
local tracked = require('core.tracked')
local fake = require('tests.fake')

local WHM, BLM, PLD, SCH, WAR, BLU = 3, 4, 7, 20, 1, 16
local SLEEP, PARALYSIS, SLOW, PROTECT, HASTE, LIGHT_ARTS, ACCESSION, MAJESTY = 2, 4, 13, 40, 33, 358, 366, 621
local cat = fake.catalog(WHM, 75, BLM, 37, { 'Divine Seal', 'Martyr' })
local snap = fake.snap

local function decide(g, cfg, list, mem) return fake.decide(g, list or cat, cfg, mem) end

-- A tracked player, 'Out' (server id 201 when first in the list).
local function out(t)
    local u = { kind = 'tracked', name = 'Out' }
    for k, v in pairs(t or {}) do u[k] = v end
    return u
end

local function action(name)
    for _, a in ipairs(cat) do if a.name == name then return a end end
end

-- The list and /check ----------------------------------------------------------------

test('tracking: once per player, removed by name in any case, statuses forgotten', function ()
    tracked.list = {}
    eq({ tracked.add(500, 'Bob', 1100), tracked.add(500, 'Bob', 1100), tracked.add(501, 'Ann', 1101) }, { true, false, true })
    buffs.gain(500, PROTECT, 0)
    eq(tracked.remove('bob').sid, 500)
    eq({ #tracked.list, tracked.list[1].name, buffs.of(500, 1), tracked.remove('Bob') }, { 1, 'Ann', {}, nil })
    tracked.list = {}
end)

test('max HP by level: v2\'s average-HP table as a line', function ()
    eq({ tracked.max_hp(1), tracked.max_hp(10), tracked.max_hp(40), tracked.max_hp(75) }, { 69, 211, 682, 1231 })
end)

-- A 0x0C9 as the server builds it: header, server id at 0x04, flag at 0x0A, jobs and levels at 0x22.
local function check_packet(sid, flag, main, sub, main_lv, sub_lv)
    local b = {}
    for i = 1, 0x60 do b[i] = 0 end
    for i = 0, 3 do b[0x04 + i + 1] = math.floor(sid / 0x100 ^ i) % 0x100 end
    b[0x0A + 1], b[0x22 + 1], b[0x23 + 1], b[0x24 + 1], b[0x25 + 1] = flag, main, sub, main_lv, sub_lv
    return { id = 0x0C9, data = string.char(unpack(b)) }
end

test('a /check\'s general part gives a tracked player\'s jobs and levels; /anon gives nothing', function ()
    tracked.list = {}
    tracked.add(0x01020304, 'Bob', 1100)
    packets.handle(check_packet(0x01020304, 3, WHM, BLM, 75, 37), {}, 0)  -- equipment part: ignored
    eq(tracked.list[1].main_lv, nil)
    packets.handle(check_packet(0x01020304, 1, WHM, BLM, 75, 37), {}, 0)
    packets.handle(check_packet(0x0999, 1, WAR, 0, 10, 0), {}, 0)       -- someone untracked
    local t = tracked.list[1]
    eq({ t.main, t.main_lv, t.sub, t.sub_lv }, { WHM, 75, BLM, 37 })
    packets.handle(check_packet(0x01020304, 1, 0, 0, 0, 0), {}, 0)     -- /anon now: keep what was known
    eq(t.main_lv, 75)
    tracked.list = {}
end)

-- What reaches outside the party --------------------------------------------------

test('Cure, Protect, Haste, the -na spells and raises reach a tracked player; Regen, Erase, Curaga do not', function ()
    local u = fake.unit(out({ sid = 201 }))
    for _, n in ipairs({ 'Cure IV', 'Protect IV', 'Haste', 'Paralyna', 'Cursna' }) do eq(can.reach(action(n), u), true, n) end
    for _, n in ipairs({ 'Regen', 'Erase', 'Curaga', 'Esuna', 'Protectra V' }) do eq(can.reach(assert(action(n), n), u), false, n) end
    eq(can.reach(action('Arise'), fake.unit(out({ sid = 201, hpp = 0 }))), true)
    u.dist = 30
    eq(can.reach(action('Cure IV'), u), false)  -- out of range
end)

-- Behaviors -------------------------------------------------------------------------

test('heal: a tracked player gets a heal aimed at them, by server id; Regen cannot go on them', function ()
    local cmd, intent = decide(snap({ out({ hpp = 70 }) }))
    eq({ cmd, intent.why }, { '/ma "Cure III" Out', 'efficient: Out 70%' })
    eq(decide(snap({ out({ hpp = 45 }) })), '/ma "Cure V" Out')
end)

test('heal: what lands on a tracked player teaches no potency, as their max HP is a guess', function ()
    local _, intent = decide(snap({ out({ hpp = 70 }) }))
    local before = observed.learned.ma3
    intent.sent(0)
    observed.healed('ma3', 201, 100, 1)  -- 100 of the 300 guessed missing: capped by their real max HP
    eq(observed.learned.ma3, before)
end)

test('heal: an area heal counts only your party, never a tracked player beside them', function ()
    local three = { { name = 'P1', hpp = 70 }, { name = 'P2', hpp = 70 }, { name = 'P3', hpp = 70 } }
    eq(decide(snap(three)), '/ma "Curaga III" <me>')
    three[3] = out({ hpp = 70 })
    eq(decide(snap(three)), '/ma "Regen II" P1')   -- two in the party: one at a time, as for two
end)

test('heal: Accession never spreads a Cure around a tracked player, nor counts one', function ()
    local sch = fake.catalog(SCH, 75, nil, 0, { 'Accession' })
    local g = snap({ { name = 'A', hpp = 45, pos = { 30, 0, 0 } }, out({ hpp = 45, pos = { 30, 0, 0 } }) })
    g.me.buffs[LIGHT_ARTS] = true
    local cmd = decide(g, nil, sch)
    eq(cmd:match('^/ma "Cure[ IV]*" A$') or cmd:match('^/ma "Cure[ IV]*" Out$'), cmd, cmd)  -- one at a time
    g.units[3] = fake.unit({ name = 'B', slot = 2, sid = 102, hpp = 45, pos = { 30, 0, 0 } })
    eq(decide(g, nil, sch), '/ja "Accession" <me>')  -- two in the party together: spread it
end)

test('heal: with Majesty or Accession up, a Cure aimed at a tracked player still goes, counting them alone', function ()
    local pld = fake.catalog(PLD, 75, WHM, 37, { 'Majesty' })
    local g = snap({ out({ hpp = 40 }) })
    local plain = decide(g, nil, pld)
    eq(plain:match('^/ma "Cure[ IV]*" Out$') ~= nil, true, plain)
    g.me.buffs[MAJESTY] = true
    eq(decide(g, nil, pld), plain)
    local sch = fake.catalog(SCH, 75, nil, 0, { 'Accession' })
    g = snap({ out({ hpp = 45 }) })
    g.me.buffs[LIGHT_ARTS], g.me.buffs[ACCESSION] = true, true
    local cmd = decide(g, nil, sch)
    eq(cmd and cmd:match('^/ma "Cure[ IV]*" Out$') ~= nil, true, cmd)
end)

test('heal: a tracked player can be the focus, and skipped', function ()
    local cfg = settings.defaults()
    cfg.heal.focus = 'out'
    eq(decide(snap({ { name = 'A', hpp = 55 }, out({ hpp = 55 }) }), cfg), '/ma "Cure IV" Out')  -- under their 60 line
    cfg.heal.focus, cfg.heal.skip = '', { Out = true }
    eq({ decide(snap({ out({ hpp = 40 }) }), cfg) }, { nil, 'nothing to do' })
end)

test('removal: a -na spell on a tracked player; Erase and Esuna do not reach them', function ()
    eq(decide(snap({ out({ buffs = { [PARALYSIS] = true } }) })), '/ma "Paralyna" Out')
    eq({ decide(snap({ out({ buffs = { [SLOW] = true } }) })) }, { nil, 'nothing to do' })
end)

test('wake: a tracked sleeper gets a heal aimed at them; an area heal counts only the party', function ()
    eq(decide(snap({ out({ buffs = { [SLEEP] = true } }) })), '/ma "Cure" Out')
    local cmd, intent = decide(snap({ { name = 'A', buffs = { [SLEEP] = true } }, out({ buffs = { [SLEEP] = true } }) }))
    eq({ cmd, intent.why }, { '/ma "Cure" A', 'A asleep' })    -- one in the party: no Curaga
    local blu = fake.catalog(BLU, 75, nil, 0)  -- Healing Breeze goes off around you, Magic Fruit is party only
    eq({ decide(snap({ out({ buffs = { [SLEEP] = true } }) }), nil, blu) }, { nil, 'nothing to do' })
end)

test('buff: a row\'s targets include tracked players by name, when the spell can go outside the party', function ()
    local cfg = settings.defaults()
    cfg.rows.Haste = { on = true, targets = { Out = true } }
    eq(decide(snap({ out() }), cfg), '/ma "Haste" Out')
    eq({ decide(snap({ out({ buffs = { [HASTE] = true } }) }), cfg) }, { nil, 'nothing to do' })
    cfg.rows.Haste = nil
    cfg.rows['Regen (keep up)'] = { on = true, targets = { Out = true } }
    eq({ decide(snap({ out() }), cfg) }, { nil, 'nothing to do' })  -- Regen is party only
end)

test('buff: an area self-cast is recast for the party near you, not for a tracked player', function ()
    local cfg = settings.defaults()
    cfg.rows.Protectra = { on = true }
    local g = snap({ { name = 'A', buffs = { [PROTECT] = true } }, out() })
    g.me.buffs[PROTECT] = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
    g.units[2].buffs[PROTECT] = nil
    eq(decide(g, cfg), '/ma "Protectra V" <me>')
end)

test('revive: a fallen tracked player is raised', function ()
    eq(decide(snap({ out({ hpp = 0 }) })), '/ma "Arise" Out')
end)

test('follow: a tracked leader by name, as they have no party slot', function ()
    local cfg = settings.defaults()
    cfg.follow = { on = true, target = 'Out', distance = 5 }
    local cmd, intent = decide(snap({ out({ dist = 12 }) }), cfg)
    eq({ cmd, intent.why }, { '/follow Out', 'Out 12.0y away' })
    eq({ decide(snap({ out({ dist = 12, in_zone = false }) }), cfg) }, { nil, 'nothing to do' })  -- out of range
end)
