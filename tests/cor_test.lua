-- Corsair's Phantom Rolls (jobs/cor.lua): v2's Double-Up rules, the totals off
-- the 0x028 packets, the rolls kept up and doubled through the engine (Snake
-- Eye as a modifier), and the Rolls section in ui/model.lua.
local cor = require('jobs.cor')
local engine = require('core.engine')
local packets = require('core.packets')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local COR, WHM, NIN = 17, 3, 13
local CORSAIRS, NINJA, DOUBLE_UP_CHANCE, BUST, SNAKE_EYE = 326, 322, 308, 309, 357  -- statuses
local CORSAIRS_ID, NINJA_ID = 626, 622  -- catalog ids: the server's ability id + 512
local JAS = { 'Corsair\'s Roll', 'Ninja Roll', 'Chaos Roll', 'Double-Up', 'Snake Eye', 'Fold' }
local cat = fake.catalog(COR, 75, WHM, 37, JAS)

local named = fake.named

-- COR 75 / WHM 37 with these statuses on you and this last roll; others in slots 1..n.
local function snap(buffs, roll, waits, others, over)
    local o = { main = COR, sub = WHM, roll = roll }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap(others or {}, o, waits)
    for _, id in ipairs(buffs) do g.me.buffs[id] = true end
    return g
end

local function cfg_with(first, second, risk)
    local cfg = settings.defaults()
    cfg.roll.first, cfg.roll.second, cfg.roll.risk = first or '', second or '', risk or 'medium'
    return cfg
end

local function decide(g, cfg, mem, list) return fake.decide(g, list or cat, cfg, mem) end

local function step(g, cfg, mem, list) return fake.step(g, list or cat, cfg, mem) end

test('catalog: rolls know their lucky and unlucky totals and the status named like them', function ()
    local c, n = named(cat, 'Corsair\'s Roll'), named(cat, 'Ninja Roll')
    eq({ c.role, c.id, c.lucky, c.unlucky, c.status, c.note }, { 'roll', CORSAIRS_ID, 5, 9, { CORSAIRS }, 'EXP+' })
    eq({ n.id, n.lucky, n.unlucky, n.status }, { NINJA_ID, 4, 8, { NINJA } })
    eq({ named(cat, 'Double-Up').role, named(cat, 'Fold').role, named(cat, 'Double-Up').lucky }, { 'roll', 'roll', nil })
    local se = named(cat, 'Snake Eye')
    eq({ se.role, se.status, se.applies }, { 'modifier', { SNAKE_EYE }, nil })
end)

-- v2's roll_strategy self-test: { total, lucky, unlucky, risk, snake ready, fold ready }, expected.
local DECIDE = {
    { { 11, 5, 9, 'highest', true, true }, 'stop', 'never doubles at 11' },
    { { 3, 5, 9, 'lowest', false, false }, 'double', 'no die can bust at 5 or under' },
    { { 5, 5, 9, 'medium', true, true }, 'stop', 'medium banks lucky at 5 or under' },
    { { 5, 5, 9, 'lowest', true, true }, 'stop', 'lowest banks lucky at 5 or under' },
    { { 5, 5, 9, 'highest', false, false }, 'double', 'highest gives up lucky for 11 (no bust at 5)' },
    { { 3, 3, 7, 'highest', false, false }, 'double', 'highest rolls through lucky with Fold down' },
    { { 10, 5, 9, 'lowest', true, false }, 'snake_eye', 'Snake Eye takes 10 to 11 on every risk' },
    { { 10, 5, 9, 'lowest', false, false }, 'stop', 'lowest stops at 10 without Snake Eye' },
    { { 6, 4, 8, 'lowest', false, true }, 'stop', 'lowest never gambles, Fold or not' },
    { { 7, 8, 2, 'medium', true, false }, 'snake_eye', 'medium spends Snake Eye at lucky - 1' },
    { { 7, 8, 2, 'highest', true, false }, 'double', 'highest keeps Snake Eye for 10' },
    { { 6, 10, 7, 'medium', false, false }, 'double', 'medium chases a lucky one die away' },
    { { 6, 4, 9, 'medium', false, false }, 'stop', 'medium banks once lucky is out of reach' },
    { { 8, 4, 8, 'medium', false, false }, 'double', 'medium doubles off unlucky at 8' },
    { { 9, 5, 9, 'medium', false, false }, 'stop', 'medium sits on unlucky past 8' },
    { { 7, 4, 8, 'highest', false, true }, 'double', 'highest chases 11 while Fold insures it' },
    { { 7, 4, 8, 'highest', false, false }, 'stop', 'highest plays as medium without Fold' },
}

test('cor.decide: v2\'s rules, case by case', function ()
    for _, c in ipairs(DECIDE) do eq(cor.decide(unpack(c[1], 1, 6)), c[2], c[3]) end
end)

local ME, OTHER = 1, 2
local ctx = { me = ME, tracks = {}, duration = function () end }
local function roll_packet(actor, id, results)
    local p = { actor = actor, category = 6, param = id - 512, targets = {} }
    for _, r in ipairs(results) do
        p.targets[#p.targets + 1] = { id = r[1], results = { { message = r[2], param = r[3], info = 0 } } }
    end
    return p
end

test('packets: your roll\'s total from your own entry, its Double-Ups, a Bust, zoning', function ()
    cor.clear()
    packets.action(roll_packet(ME, CORSAIRS_ID, { { OTHER, 421, 4 }, { ME, 420, 4 } }), ctx, 10)
    eq(cor.last(), { id = CORSAIRS_ID, total = 4, die = 0, at = 10 })
    packets.action(roll_packet(OTHER, NINJA_ID, { { ME, 421, 3 } }), ctx, 11)  -- another Corsair's roll on you
    eq(cor.last().id, CORSAIRS_ID)
    packets.action(roll_packet(ME, CORSAIRS_ID, { { ME, 424, 9 } }), ctx, 12)  -- a Double-Up names the roll
    eq(cor.last(), { id = CORSAIRS_ID, total = 9, die = 0, at = 12, doubled = true })
    packets.action(roll_packet(ME, CORSAIRS_ID, { { ME, 426, 13 } }), ctx, 13)
    eq(cor.last(), { id = CORSAIRS_ID, total = 13, die = 0, at = 13, bust = true })
    packets.action(roll_packet(ME, NINJA_ID, { { ME, 424, 12 } }), ctx, 13.5)  -- a Double-Up past 11 is a Bust too
    eq(cor.last().bust, true)
    packets.action(roll_packet(ME, NINJA_ID, { { ME, 420, 2 } }), ctx, 14)
    packets.handle({ id = 0x00A }, ctx, 15)
    eq(cor.last(), nil)
end)

test('no roll picked: nothing; a pick the job lacks: nothing', function ()
    eq(decide(snap({}), cfg_with(), {}), nil)
    eq(decide(snap({}), cfg_with('Bolter\'s Roll'), {}), nil)
end)

test('the first roll, then its total waited for before anything else of COR\'s', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll', 'Ninja Roll'), {}
    local cmd, intent = step(snap({}), cfg, mem)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Corsair\'s Roll" <me>', 'roll', 'not up' })
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, nil, { ['Corsair\'s Roll'] = 60, ['Ninja Roll'] = 60 })
    g.now = 1002
    eq(decide(g, cfg, mem), nil)  -- the status shows, but its total hasn't come
end)

test('a roll is doubled at 5 or under, then the Double-Ups 6 seconds apart; a banked lucky lets the second go', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll', 'Ninja Roll'), {}
    step(snap({}), cfg, mem)  -- Corsair's Roll at 1000
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 2, at = 1000.5 })
    g.now = 1002
    local cmd, intent = step(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Double-Up" <me>', 'Corsair\'s Roll at 2' })
    g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 4, at = 1003, doubled = true })
    g.now = 1004
    eq(decide(g, cfg, mem), nil)  -- a die can't bust yet, but the last Double-Up was 2s ago
    g.now = 1008
    eq(decide(g, cfg, mem), nil)  -- 6s from the send, but its total came at 1003 (lag)
    g.now = 1009
    eq(step(g, cfg, mem), '/ja "Double-Up" <me>')
    g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 5, at = 1010, doubled = true })
    g.now = 1011
    eq(decide(g, cfg, mem), '/ja "Ninja Roll" <me>')  -- lucky: banked
end)

test('the risk picked decides: medium chases lucky one die away, lowest stops', function ()
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 6, at = 990 },
        { ['Corsair\'s Roll'] = 50, ['Ninja Roll'] = 50 })  -- Phantom Roll's shared recast
    eq(decide(g, cfg_with('Corsair\'s Roll', 'Ninja Roll', 'medium'), {}), nil)  -- 6: lucky 5 is gone, but Ninja Roll waits on recast
    g.roll.total = 3
    eq(decide(g, cfg_with('Corsair\'s Roll', 'Ninja Roll', 'lowest'), {}), '/ja "Double-Up" <me>')
    local n = snap({ NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 7, at = 990 }, { ['Ninja Roll'] = 50 }, {}, {})
    eq(decide(n, cfg_with('Ninja Roll', '', 'medium'), {}), nil)  -- 7: lucky 4 gone, not on unlucky 8
    n.roll.total = 8
    eq(decide(n, cfg_with('Ninja Roll', '', 'medium'), {}), '/ja "Double-Up" <me>')  -- off unlucky
    eq(decide(n, cfg_with('Ninja Roll', '', 'lowest'), {}), nil)
end)

test('Snake Eye at 10 goes first, as a modifier, then the Double-Up while its status is expected', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll', '', 'lowest'), {}
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 10, at = 990 })
    local cmd, intent = step(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Snake Eye" <me>', 'for Double-Up: Corsair\'s Roll at 10' })
    g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 10, at = 990 }, { ['Snake Eye'] = 300 })
    g.now = 1001.2
    eq(step(g, cfg, mem), '/ja "Double-Up" <me>')
    -- Its status read from the game says the same, whatever the risk would say now.
    g = snap({ CORSAIRS, DOUBLE_UP_CHANCE, SNAKE_EYE }, { id = CORSAIRS_ID, total = 10, at = 990 }, { ['Snake Eye'] = 300 })
    eq(decide(g, cfg, {}), '/ja "Double-Up" <me>')
end)

test('a busted roll is never doubled: its total is a Bust\'s', function ()
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 3, at = 990, bust = true })
    eq(decide(g, cfg_with('Corsair\'s Roll'), {}), nil)
end)

test('highest doubles at 6-10 while Fold is ready, else plays as medium', function ()
    local g = snap({ NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 7, at = 990 })
    eq(decide(g, cfg_with('Ninja Roll', '', 'highest'), {}), '/ja "Double-Up" <me>')
    g = snap({ NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 7, at = 990 }, { Fold = 200 })
    eq(decide(g, cfg_with('Ninja Roll', '', 'highest'), {}), nil)
    g.roll.total = 8
    eq(decide(g, cfg_with('Ninja Roll', '', 'highest'), {}), '/ja "Double-Up" <me>')  -- off unlucky, as medium
end)

test('Snake Eye on you never doubles an 11', function ()
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE, SNAKE_EYE }, { id = CORSAIRS_ID, total = 11, at = 990 })
    eq(decide(g, cfg_with('Corsair\'s Roll'), {}), nil)
end)

test('a newer roll sent and its total not in: the earlier total is never doubled, though its rule now says so', function ()
    local cfg, mem = cfg_with('Ninja Roll', 'Corsair\'s Roll', 'highest'), {}
    -- Ninja Roll settled at 7 (Fold down), so Corsair's Roll went.
    local g = snap({ NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 7, at = 990 }, { Fold = 200 })
    eq(step(g, cfg, mem), '/ja "Corsair\'s Roll" <me>')
    -- Its packet is late or lost; Fold comes ready and the chance status is Corsair's now.
    for _, now in ipairs({ 1001.5, 1000 + cor.WAIT + 1 }) do
        g = snap({ NINJA, CORSAIRS, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 7, at = 990 }, { ['Corsair\'s Roll'] = 60 })
        g.now = now
        eq(decide(g, cfg, mem), nil)
    end
end)

test('resting waits while a Double-Up is due, then may start once the roll is settled', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll'), {}
    cfg.rest.on, cfg.rest.mp = true, 70
    local over = { finished = 990 }
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 2, at = 990 }, nil, {}, over)
    g.me.mpp = 60
    eq(step(g, cfg, mem), '/ja "Double-Up" <me>')  -- at 1000
    g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 4, at = 1000.5 }, nil, {}, over)
    g.me.mpp, g.now = 60, 1005.6
    eq({ decide(g, cfg, mem) }, { nil, 'nothing to do' })  -- the next Double-Up is due at 1006
    g.now = 1006
    eq(step(g, cfg, mem), '/ja "Double-Up" <me>')
    g = snap({ CORSAIRS }, { id = CORSAIRS_ID, total = 5, at = 1006.5 }, nil, {}, over)
    g.me.mpp, g.now = 60, 1012
    eq(decide(g, cfg, mem), '/heal on')
end)

test('nothing while you are Invisible: no roll, Double-Up or Fold', function ()
    local INVISIBLE = 69
    local cfg = cfg_with('Corsair\'s Roll')
    eq(decide(snap({ INVISIBLE }), cfg, {}), nil)
    eq(decide(snap({ INVISIBLE, BUST }), cfg, {}), nil)
    eq(decide(snap({ INVISIBLE, CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 2, at = 990 }), cfg, {}), nil)
    eq(decide(snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 2, at = 990 }), cfg, {}), '/ja "Double-Up" <me>')
end)

test('a Bust: Fold when it is ready; until then it takes a roll\'s place', function ()
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll')
    local cmd, intent = decide(snap({ BUST, NINJA }), cfg, {})
    eq({ cmd, intent.why }, { '/ja "Fold" <me>', 'Bust' })
    eq(decide(snap({ BUST, NINJA }, nil, { Fold = 200 }), cfg, {}), nil)  -- Bust and Ninja Roll: both places taken
    eq(decide(snap({ BUST }, nil, { Fold = 200 }), cfg, {}), '/ja "Corsair\'s Roll" <me>')
end)

test('a Corsair subjob keeps one roll, and none while Busted', function ()
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll')
    local sub = fake.catalog(NIN, 75, COR, 37, JAS)
    local over = { main = NIN, sub = COR }
    eq(decide(snap({}, nil, nil, {}, over), cfg, {}, sub), '/ja "Corsair\'s Roll" <me>')
    eq(decide(snap({ CORSAIRS }, nil, nil, {}, over), cfg, {}, sub), nil)
    eq(decide(snap({ BUST }, nil, { Fold = 200 }, {}, over), cfg, {}, sub), nil)
    eq(#cor.picked(sub, cfg, NIN), 1)
end)

test('a total that never comes: after a while the roll is left as it is, never doubled blind', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll', 'Ninja Roll'), {}
    step(snap({}), cfg, mem)  -- Corsair's Roll at 1000
    local g = snap({ CORSAIRS, DOUBLE_UP_CHANCE }, { id = CORSAIRS_ID, total = 2, at = 900 })  -- an old total
    g.now = 1003
    eq(decide(g, cfg, mem), nil)
    g.now = 1000 + cor.WAIT
    eq(decide(g, cfg, mem), '/ja "Ninja Roll" <me>')
end)

test('the Double-Up Chance is the last roll\'s: an earlier roll is never doubled', function ()
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll', 'highest')
    -- Ninja Roll was the last one, banked at 9; Corsair's sits at 2 from before.
    local g = snap({ CORSAIRS, NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 9, at = 990 }, { Fold = 200 })
    eq(decide(g, cfg, {}), nil)
end)

test('held for the group with buff.hold_aoe: a member lacking it outside the roll\'s area', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll'), {}
    cfg.buff.hold_aoe = true
    local g = snap({}, nil, nil, { { name = 'A', dist = 3 }, { name = 'B', dist = 9 } })
    eq({ decide(g, cfg, mem) }, { nil, 'holding Corsair\'s Roll: B 9.0y away' })  -- the DAT's area: 8.4 yalms
    eq(engine.gather(g, cfg, mem), '/p Gather together for Corsair\'s Roll')
    g.units[3].dist = 8
    eq(decide(g, cfg, mem), '/ja "Corsair\'s Roll" <me>')
    cfg.buff.hold_aoe = false
    g.units[3].dist = 15
    eq(decide(g, cfg, {}), '/ja "Corsair\'s Roll" <me>')
end)

test('the Rolls section: only for a job with rolls; picks, risk, the second for a main COR, the last total', function ()
    local NAMES = { job = function (id) return ({ [COR] = 'COR', [WHM] = 'WHM', [NIN] = 'NIN' })[id] end,
                    statuses = fake.res.statuses }
    local st = { running = false, log = true, sent = {} }
    local function sections(view)
        local ids = {}
        for _, s in ipairs(view.sections) do ids[#ids + 1] = s.id end
        return table.concat(ids, ' ')
    end
    local cfg = cfg_with('Ninja Roll', '', 'highest')
    local view = model.build(snap({ NINJA }, { id = NINJA_ID, total = 4, at = 990 }), cat, cfg, st, NAMES)
    eq(sections(view):find('buff roll') ~= nil, true)
    local r = view.roll
    eq({ r.first, r.second, r.risk, r.risks, r.two }, { 'Ninja Roll', '', 'highest', { 'lowest', 'medium', 'highest' }, true })
    eq(r.choices, {
        { name = 'Chaos Roll', label = 'Chaos Roll (ATK+)', lucky = 4, unlucky = 8 },
        { name = 'Corsair\'s Roll', label = 'Corsair\'s Roll (EXP+)', lucky = 5, unlucky = 9 },
        { name = 'Ninja Roll', label = 'Ninja Roll (EVA+)', lucky = 4, unlucky = 8 },
    })
    eq(r.last, { name = 'Ninja Roll', total = 4, lucky = 4, unlucky = 8, bust = false })
    eq(model.build(snap({}, { id = NINJA_ID, total = 4, at = 990 }), cat, cfg, st, NAMES).roll.last, nil)  -- worn off
    eq(model.build(snap({}, { id = NINJA_ID, total = 12, at = 990, bust = true }), cat, cfg, st, NAMES).roll.last.bust, true)
    eq(model.build(snap({}, nil, nil, {}, { main = NIN, sub = COR }), fake.catalog(NIN, 75, COR, 37, JAS), cfg, st, NAMES).roll.two, false)
    eq(sections(model.build(fake.snap({}), fake.catalog(WHM, 75, NIN, 37), cfg, st, NAMES)):find('roll'), nil)
    local act = model.actions(cfg, st, function () end)
    act.set('roll.second', 'Chaos Roll')
    act.set('roll.risk', 'lowest')
    act.section('roll', false)
    eq(cfg.roll, { on = false, first = 'Ninja Roll', second = 'Chaos Roll', risk = 'lowest', max_at_11 = false })
end)

test('max_at_11: while one roll stands at 11, the other is doubled until it is 11 too; then the risk picked', function ()
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll', 'lowest')
    local function g_at(total, totals, buffs, waits)
        local g = snap(buffs or { CORSAIRS, NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = total, at = 990 }, waits or { Fold = 200 })
        g.roll_totals = totals
        return g
    end
    local eleven = { [CORSAIRS_ID] = 11, [NINJA_ID] = 9 }
    eq(decide(g_at(9, eleven), cfg, {}), nil)  -- off: lowest stops at 9
    cfg.roll.max_at_11 = true
    eq(decide(g_at(9, eleven), cfg, {}), '/ja "Double-Up" <me>')  -- no Bust with an 11 up, Fold down or not
    eq(decide(g_at(4, eleven), cfg, {}), '/ja "Double-Up" <me>')  -- past lucky 4 too
    eq(decide(g_at(10, eleven), cfg, {}), '/ja "Snake Eye" <me>')
    eq(decide(g_at(11, { [CORSAIRS_ID] = 11, [NINJA_ID] = 11 }), cfg, {}), nil)  -- both at 11
    eq(decide(g_at(9, { [CORSAIRS_ID] = 7, [NINJA_ID] = 9 }), cfg, {}), nil)  -- no 11: lowest again
    eq(decide(g_at(9, eleven, { NINJA, DOUBLE_UP_CHANCE }, { Fold = 200, ['Corsair\'s Roll'] = 50 }), cfg, {}), nil)  -- the 11 wore
    eq(cor.decide(6, 5, 9, 'max', false, false), 'double')
    eq(cor.decide(10, 5, 9, 'max', false, false), 'double')  -- no Snake Eye: Double-Up all the same
    -- An 11 on a roll that isn't picked counts for nothing.
    eq(decide(g_at(9, { [NINJA_ID] = 9, [626 + 1] = 11 }), cfg, {}), nil)
end)

test('max_at_11 on a Corsair subjob: one roll, so the risk picked', function ()
    local cfg = cfg_with('Ninja Roll', 'Corsair\'s Roll', 'lowest')
    cfg.roll.max_at_11 = true
    local sub = fake.catalog(NIN, 75, COR, 37, JAS)
    local g = snap({ CORSAIRS, NINJA, DOUBLE_UP_CHANCE }, { id = NINJA_ID, total = 9, at = 990 }, { Fold = 200 }, {},
        { main = NIN, sub = COR, roll_totals = { [CORSAIRS_ID] = 11, [NINJA_ID] = 9 } })
    eq(decide(g, cfg, {}, sub), nil)
end)

test('a roll seen down forgets its total, but not one newer than WAIT: a lost re-roll is no 11', function ()
    cor.clear()
    packets.action(roll_packet(ME, CORSAIRS_ID, { { ME, 420, 11 } }), ctx, 998)
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll')
    local g = snap({}, nil, nil, {}, { roll_totals = cor.totals() })
    g.now = 1000  -- 2s on: its status may not show yet
    decide(g, cfg, {})
    eq(cor.totals(), { [CORSAIRS_ID] = 11 })
    g.now = 998 + cor.WAIT
    decide(g, cfg, {})
    eq(cor.totals(), {})
end)

test('packets: each roll\'s last total, none once it busts, cleared on zoning', function ()
    cor.clear()
    packets.action(roll_packet(ME, CORSAIRS_ID, { { ME, 420, 11 } }), ctx, 10)
    packets.action(roll_packet(ME, NINJA_ID, { { ME, 420, 6 } }), ctx, 20)
    packets.action(roll_packet(ME, NINJA_ID, { { ME, 424, 9 } }), ctx, 26)
    eq(cor.totals(), { [CORSAIRS_ID] = 11, [NINJA_ID] = 9 })
    packets.action(roll_packet(ME, NINJA_ID, { { ME, 424, 14 } }), ctx, 32)
    eq(cor.totals(), { [CORSAIRS_ID] = 11 })
    packets.handle({ id = 0x00A }, ctx, 40)
    eq(cor.totals(), {})
end)

test('the Rolls section says when the risk is at max', function ()
    local NAMES = { job = function (id) return ({ [COR] = 'COR', [WHM] = 'WHM' })[id] end, statuses = fake.res.statuses }
    local st = { running = false, log = true, sent = {} }
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll')
    local g = snap({ CORSAIRS }, { id = CORSAIRS_ID, total = 11, at = 990 }, nil, {}, { roll_totals = { [CORSAIRS_ID] = 11 } })
    eq({ model.build(g, cat, cfg, st, NAMES).roll.max_at_11, model.build(g, cat, cfg, st, NAMES).roll.eleven }, { false, nil })
    local act = model.actions(cfg, st, function () end)
    act.set('roll.max_at_11', true)
    eq(model.build(g, cat, cfg, st, NAMES).roll.eleven, 'Corsair\'s Roll')
    g.roll_totals[NINJA_ID] = 11  -- both at 11: nothing left to double
    eq(model.build(g, cat, cfg, st, NAMES).roll.eleven, nil)
    g.roll_totals[NINJA_ID] = nil
    for _, second in ipairs({ '', 'Corsair\'s Roll' }) do  -- no other roll
        cfg.roll.second = second
        eq(model.build(g, cat, cfg, st, NAMES).roll.eleven, nil)
    end
end)

test('max_at_11: the other roll, rolled before the 11, is rolled again to chase 11', function ()
    local cfg = cfg_with('Corsair\'s Roll', 'Ninja Roll', 'medium')
    cfg.roll.max_at_11 = true
    -- Ninja Roll banked at 5, then Corsair's Roll hit 11: its Double-Up Chance is no use to Ninja Roll.
    local function g_with(totals, waits)
        local g = snap({ CORSAIRS, NINJA }, { id = CORSAIRS_ID, total = 11, at = 990 }, waits)
        g.roll_totals = totals
        return g
    end
    local cmd, intent = decide(g_with({ [CORSAIRS_ID] = 11, [NINJA_ID] = 5 }), cfg, {})
    eq({ cmd, intent.why }, { '/ja "Ninja Roll" <me>', 'at 5, for 11' })
    eq(decide(g_with({ [CORSAIRS_ID] = 11, [NINJA_ID] = 5 }, { ['Ninja Roll'] = 50 }), cfg, {}), nil)  -- Phantom Roll's recast
    eq(decide(g_with({ [CORSAIRS_ID] = 11 }), cfg, {}), nil)  -- its total unknown: left be
    eq(decide(g_with({ [CORSAIRS_ID] = 11, [NINJA_ID] = 11 }), cfg, {}), nil)
    cfg.roll.max_at_11 = false
    eq(decide(g_with({ [CORSAIRS_ID] = 11, [NINJA_ID] = 5 }), cfg, {}), nil)
end)

-- /sk "Bolter's Roll": that roll now, then Double-Up at lowest (jobs/cor.lua). Its own
-- catalog, so the Rolls section's choices above stay the three rolls they name.
local BOLTER, BOLTER_ID = 330, 630
local shot_cat = fake.catalog(COR, 75, WHM, 37, { 'Bolter\'s Roll', 'Corsair\'s Roll', 'Ninja Roll', 'Chaos Roll',
    'Double-Up', 'Snake Eye', 'Fold' })

local function order(mem, name) cor.order(mem, named(shot_cat, name or 'Bolter\'s Roll')) end

-- Rolls switched off, so only the commanded roll can go.
local function quiet()
    local cfg = cfg_with('', '', 'highest')
    cfg.roll.on = false
    return cfg
end

test('a roll\'s name: the apostrophe and case aside, or its Japanese name; nothing else', function ()
    local b = named(shot_cat, 'Bolter\'s Roll')
    eq(cor.roll_named(shot_cat, 'Bolter\'s Roll'), b)
    eq(cor.roll_named(shot_cat, '"bolter\'s roll"'), b)
    eq(cor.roll_named(shot_cat, 'bolters roll'), b)
    eq(cor.roll_named(shot_cat, b.jp), b)
    eq(cor.roll_named(shot_cat, 'Chaos Roll').name, 'Chaos Roll')
    eq(cor.roll_named(shot_cat, 'Bolter Roll'), nil)  -- the s is part of the name
    eq(cor.roll_named(shot_cat, 'Double-Up'), nil)
    eq(cor.roll_named(shot_cat, 'Cure'), nil)
end)

test('/sk "Bolter\'s Roll": the roll now, then Double-Up at lowest until lucky, with Rolls off', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    local cmd, intent = step(snap({}), cfg, mem, shot_cat)
    eq({ cmd, intent.behavior, intent.why, intent.once }, { '/ja "Bolter\'s Roll" <me>', 'roll', 'asked', true })
    local g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 2, at = 1000.5 })
    g.now = 1002
    cmd, intent = step(g, cfg, mem, shot_cat)
    eq({ cmd, intent.why, intent.once }, { '/ja "Double-Up" <me>', 'Bolter\'s Roll at 2', true })
    g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 3, at = 1003, doubled = true })
    g.now = 1004  -- inside the Double-Up gap: lucky stops anyway
    eq(decide(g, cfg, mem, shot_cat), nil)
    eq({ cor.pending(mem), mem.cor.safe }, { false, { id = BOLTER_ID, at = 1003 } })
    cfg.roll.on, cfg.roll.first, cfg.roll.risk = true, 'Bolter\'s Roll', 'highest'
    eq(decide(g, cfg, mem, shot_cat), nil)  -- that same total: highest would roll through lucky
    g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 3, at = 1020 })
    g.now = 1021
    eq(decide(g, cfg, mem, shot_cat), '/ja "Double-Up" <me>')  -- a later roll of it is the risk's again
end)

test('a commanded roll keeps doubling a missed lucky while no die can bust', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    step(snap({}), cfg, mem, shot_cat)
    local g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 4, at = 1000.5 })
    g.now = 1002
    eq(step(g, cfg, mem, shot_cat), '/ja "Double-Up" <me>')
    eq(cor.pending(mem), true)
end)

test('a commanded roll stops where a die could bust, and that total is not gambled on', function ()
    local cfg, mem = quiet(), {}
    cfg.roll.max_at_11 = true
    order(mem)
    step(snap({}), cfg, mem, shot_cat)
    local g = snap({ BOLTER, CORSAIRS, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 6, at = 1001 }, nil, {},
        { roll_totals = { [CORSAIRS_ID] = 11, [BOLTER_ID] = 6 } })
    g.now = 1002
    eq(decide(g, cfg, mem, shot_cat), nil)  -- an 11 up would be max risk; this command still stops
    eq(cor.pending(mem), false)
    cfg = cfg_with('Bolter\'s Roll', '', 'highest')
    eq(decide(g, cfg, mem, shot_cat), nil)  -- highest, Fold ready: it would Double-Up a 6
end)

test('a commanded 10 spends Snake Eye, then Double-Ups once that die is coming', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    step(snap({}), cfg, mem, shot_cat)
    local g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 10, at = 1000.5 })
    g.now = 1002
    local cmd, intent = step(g, cfg, mem, shot_cat)
    eq({ cmd, intent.once, intent.behavior, intent.why },
       { '/ja "Snake Eye" <me>', true, 'roll', 'for Double-Up: Bolter\'s Roll at 10' })
    g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 10, at = 1000.5 }, { ['Snake Eye'] = 60 })
    g.now = 1002.5
    cmd, intent = step(g, cfg, mem, shot_cat)
    eq({ cmd, intent.once, intent.why }, { '/ja "Double-Up" <me>', true, 'Bolter\'s Roll at 10' })
end)

test('the rolls kept up wait for a commanded roll\'s total, then go on without it', function ()
    local cfg, mem = cfg_with('Corsair\'s Roll'), {}
    order(mem)
    eq(step(snap({}), cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')
    local g = snap({}, nil, { ['Bolter\'s Roll'] = 60 })
    g.now = 1003
    eq(decide(g, cfg, mem, shot_cat), nil)
    eq(cor.pending(mem), true)
    g.now = 1000 + cor.WAIT
    eq(decide(g, cfg, mem, shot_cat), '/ja "Corsair\'s Roll" <me>')
    eq(cor.pending(mem), false)
end)

test('a commanded roll goes in town and while AFK sleep has paused automation; the pause holds the rest', function ()
    local hurt = { { name = 'A', hpp = 40 } }
    for _, pause in ipairs({ 'safe', 'afk' }) do
        local cfg, mem = cfg_with('Corsair\'s Roll'), {}
        local g = snap({}, nil, nil, hurt, { [pause] = true })
        eq({ decide(g, cfg, {}, shot_cat) }, { nil, pause }, pause)  -- the roll kept up, and the cure, stay paused
        order(mem)
        local cmd, intent = step(g, cfg, mem, shot_cat)
        eq({ cmd, intent.once }, { '/ja "Bolter\'s Roll" <me>', true }, pause)
        g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 2, at = 1000.5 }, nil, hurt, { [pause] = true })
        g.now = 1002
        eq(step(g, cfg, mem, shot_cat), '/ja "Double-Up" <me>', pause)
        g.now = 1004
        eq({ decide(g, cfg, mem, shot_cat) }, { nil, pause }, pause)  -- between Double-Ups the pause holds the cure
        eq(cor.pending(mem), true, pause)
        g.now, g.casting = 1008, true  -- the next Double-Up is due, but not mid-cast; the pause stays the reason
        eq({ decide(g, cfg, mem, shot_cat) }, { nil, pause }, pause)
        g.casting = nil
        eq(decide(g, cfg, mem, shot_cat), '/ja "Double-Up" <me>', pause)
    end
end)

test('an event, a safe zone too, holds a commanded roll until it ends', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    eq({ decide(snap({}, nil, nil, {}, { safe = true, event = true }), cfg, mem, shot_cat) }, { nil, 'safe' })
    eq(cor.pending(mem), true)
    eq(step(snap({}, nil, nil, {}, { safe = true }), cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')
end)

test('a mount holds a commanded roll until you get off, in town too', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    eq({ decide(snap({}, nil, nil, {}, { mounted = true }), cfg, mem, shot_cat) }, { nil, 'mounted' })
    eq({ decide(snap({}, nil, nil, {}, { mounted = true, safe = true }), cfg, mem, shot_cat) }, { nil, 'mounted' })
    eq(cor.pending(mem), true)
    eq(step(snap({}, nil, nil, {}, {}), cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')
end)

test('a commanded roll stays armed through its recast and through Invisible, and goes while you rest', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    eq(decide(snap({}, nil, { ['Bolter\'s Roll'] = 12 }), cfg, mem, shot_cat), nil)
    eq(cor.pending(mem), true)
    eq(decide(snap({ 69 }), cfg, mem, shot_cat), nil)
    eq(cor.pending(mem), true)
    eq(step(snap({}, nil, nil, {}, { resting = true }), cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')
end)

test('a commanded roll is not held for the group', function ()
    local cfg, mem = quiet(), {}
    cfg.buff.hold_aoe = true
    order(mem)
    local g = snap({}, nil, nil, { { name = 'B', dist = 30 } })
    eq(step(g, cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')
end)

test('a Bust already up is Folded before the commanded roll; a Bust of that roll ends it', function ()
    local cfg, mem = quiet(), {}
    order(mem)
    local cmd, intent = step(snap({ BUST }), cfg, mem, shot_cat)
    eq({ cmd, intent.why, intent.once }, { '/ja "Fold" <me>', 'Bust', true })
    eq(cor.pending(mem), true)
    eq(step(snap({}), cfg, mem, shot_cat), '/ja "Bolter\'s Roll" <me>')

    mem = {}
    order(mem)
    eq(decide(snap({ BUST }, nil, { Fold = 40 }), cfg, mem, shot_cat), nil)  -- Fold's recast: stay armed
    eq(cor.pending(mem), true)

    mem = {}
    order(mem)
    step(snap({}), cfg, mem, shot_cat)
    local g = snap({ BUST }, { id = BOLTER_ID, total = 13, at = 1001, bust = true })
    g.now = 1002
    cmd, intent = step(g, cfg, mem, shot_cat)
    eq({ cmd, intent.why, intent.once }, { '/ja "Fold" <me>', 'Bust', true })
    eq(cor.pending(mem), false)

    mem = {}
    order(mem)
    step(snap({}), cfg, mem, shot_cat)
    g = snap({ BUST }, { id = BOLTER_ID, total = 13, at = 1001, bust = true }, { Fold = 40 })
    g.now = 1002
    eq(decide(g, cfg, mem, shot_cat), nil)  -- Fold not ready: leave the Bust to the rolls kept up
    eq(cor.pending(mem), false)
end)

test('a Bust with no Fold to clear it is waited out, and the reply says so', function ()
    local bare = fake.catalog(COR, 75, WHM, 37, { 'Bolter\'s Roll', 'Double-Up', 'Snake Eye' })
    local mem = {}
    cor.order(mem, named(bare, 'Bolter\'s Roll'))
    eq({ cor.bust_waits(snap({ BUST }), bare), cor.bust_waits(snap({}), bare) }, { true, false })
    eq(decide(snap({ BUST }), quiet(), mem, bare), nil)
    eq(cor.pending(mem), true)
    eq(step(snap({}), quiet(), mem, bare), '/ja "Bolter\'s Roll" <me>')
    -- With Fold: it waits only while Fold is on recast.
    eq({ cor.bust_waits(snap({ BUST }), shot_cat), cor.bust_waits(snap({ BUST }, nil, { Fold = 40 }), shot_cat) },
       { false, true })
end)

test('a commanded roll goes ahead of a cure; between Double-Ups the cure goes', function ()
    local cfg, mem = quiet(), {}
    local hurt = { { name = 'A', hpp = 40 } }
    order(mem)
    local cmd, intent = step(snap({}, nil, nil, hurt), cfg, mem, shot_cat)
    eq({ cmd, intent.behavior }, { '/ja "Bolter\'s Roll" <me>', 'roll' })
    local g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 2, at = 1000.5 }, nil, hurt)
    g.now = 1002
    eq(step(g, cfg, mem, shot_cat), '/ja "Double-Up" <me>')
    g = snap({ BOLTER, DOUBLE_UP_CHANCE }, { id = BOLTER_ID, total = 2, at = 1000.5 }, nil, hurt)
    g.now = 1004
    intent = select(2, decide(g, cfg, mem, shot_cat))
    eq({ intent.behavior, cor.pending(mem) }, { 'heal', true })
end)

test('naming another roll replaces the one armed, and a total already held', function ()
    local mem = {}
    order(mem)
    mem.cor.safe = { id = BOLTER_ID, at = 1 }
    order(mem, 'Chaos Roll')
    eq({ mem.cor.safe, mem.cor.shot.id }, { nil, named(shot_cat, 'Chaos Roll').id })
    eq(step(snap({}), quiet(), mem, shot_cat), '/ja "Chaos Roll" <me>')
end)
