-- The alliance's other two parties (party slots 6-17): what reaches them, and
-- every behavior with them, on fake snapshots over a real catalog (WHM 75 / BLM 37).
-- An area effect lands on its target's party alone, so each party is scored apart.
local can = require('core.can')
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, BLM, SCH = 3, 4, 20
local SLEEP, PARALYSIS, SLOW, PROTECT, HASTE, LIGHT_ARTS, ACCESSION = 2, 4, 13, 40, 33, 358, 366
local cat = fake.catalog(WHM, 75, BLM, 37, { 'Divine Seal', 'Martyr', 'Devotion' })
local sch = fake.catalog(SCH, 75, nil, 0, { 'Accession' })
local snap = fake.snap

local function decide(g, cfg, list) return fake.decide(g, list or cat, cfg) end

-- An alliance member, 'Bob' unless named: the first is slot 6 (B0), server id 301.
local function ally(t)
    local u = { kind = 'alliance', name = 'Bob' }
    for k, v in pairs(t or {}) do u[k] = v end
    return u
end

-- Settings healing the alliance too.
local function healing_them()
    local cfg = settings.defaults()
    cfg.heal.alliance = true
    return cfg
end

local function action(name)
    for _, a in ipairs(cat) do if a.name == name then return assert(a, name) end end
end

-- What reaches them ----------------------------------------------------------------

test('parties: yours (you, members, trusts, your pet), B for slots 6-11, C for 12-17; a tracked player\'s unknown', function ()
    local g = snap({ { name = 'A' }, { name = 'T', kind = 'trust' }, ally({ name = 'B0' }), ally({ name = 'C0', slot = 12 }),
        { kind = 'tracked', name = 'Out' } })
    local parties = {}
    for i, u in ipairs(g.units) do parties[i] = can.party(u) or 0 end
    eq(parties, { 1, 1, 1, 2, 3, 0 })
    eq({ can.party({ name = 'Carbuncle' }), can.in_party(g.units[4]), can.in_party(g.units[3]) }, { 1, false, true })
    local b1 = fake.unit(ally({ name = 'B1', slot = 7 }))
    eq({ can.together(g.units[4], b1), can.together(g.units[4], g.units[5]), can.together(g.me, g.units[2]),
         can.together(g.units[6], g.units[6]) }, { true, false, true, false })
end)

test('Cure, Protect, Haste, the -na spells and raises reach them; Regen, Erase, Curaga, Esuna and Devotion do not', function ()
    local u = snap({ ally() }).units[2]
    for _, n in ipairs({ 'Cure IV', 'Protect IV', 'Haste', 'Paralyna', 'Cursna' }) do eq(can.reach(action(n), u), true, n) end
    for _, n in ipairs({ 'Regen', 'Erase', 'Curaga', 'Esuna', 'Protectra V', 'Devotion' }) do eq(can.reach(action(n), u), false, n) end
    eq(can.reach(action('Arise'), snap({ ally({ hpp = 0 }) }).units[2]), true)
end)

-- Healing --------------------------------------------------------------------------

test('heal: the alliance is healed only with heal.alliance on, by a heal aimed at them', function ()
    eq({ decide(snap({ ally({ hpp = 45 }) })) }, { nil, 'nothing to do' })  -- v2's default: their own healers
    local cmd, intent = decide(snap({ ally({ hpp = 45 }) }), healing_them())
    eq({ cmd, intent.why }, { '/ma "Cure V" Bob', 'danger: Bob 45%' })
    eq(decide(snap({ ally({ hpp = 70 }) }), healing_them()), '/ma "Cure III" Bob')  -- no Regen: party only
end)

test('heal: an alliance member who is the focus is healed with heal.alliance off', function ()
    local cfg = settings.defaults()
    cfg.heal.focus = 'bob'
    eq(decide(snap({ ally({ hpp = 55 }) }), cfg), '/ma "Cure IV" Bob')  -- under the focus member's 60 line
end)

test('heal: Curaga covers your party only, never the alliance member beside them', function ()
    local three = { { name = 'P1', hpp = 70 }, { name = 'P2', hpp = 70 }, { name = 'P3', hpp = 70 } }
    eq(decide(snap(three), healing_them()), '/ma "Curaga III" <me>')
    three[3] = ally({ hpp = 70 })
    eq(decide(snap(three), healing_them()), '/ma "Regen II" P1')   -- two in the party: one at a time, as for two
end)

-- Two hurt together 30 yalms from you, the second in `second`'s party; SCH under Light Arts.
local function pair(second, up)
    local g = snap({ ally({ name = 'B0', hpp = 45, pos = { 30, 0, 0 } }), second })
    g.me.buffs[LIGHT_ARTS] = true
    for _, id in ipairs(up or {}) do g.me.buffs[id] = true end
    return g
end

test('heal: Accession spreads a Cure over another party of the alliance, counted on its own', function ()
    local b1 = ally({ name = 'B1', slot = 7, sid = 302, hpp = 45, pos = { 30, 0, 0 } })
    local cmd, intent = decide(pair(b1), healing_them(), sch)
    eq({ cmd, intent.why }, { '/ja "Accession" <me>', 'danger: B0 45% +1, for Cure IV' })
    cmd, intent = decide(pair(b1, { ACCESSION }), healing_them(), sch)
    eq({ cmd, intent.why }, { '/ma "Cure IV" B0', 'danger: B0 45% +1' })
    eq({ decide(pair(b1), nil, sch) }, { nil, 'nothing to do' })  -- heal.alliance off
end)

test('heal: a Cure spread around one party never counts another\'s, yours included', function ()
    local c0 = ally({ name = 'C0', slot = 12, sid = 303, hpp = 45, pos = { 30, 0, 0 } })
    local cmd, intent = decide(pair(c0), healing_them(), sch)
    eq({ cmd, intent.why }, { '/ma "Cure IV" B0', 'danger: B0 45%' })   -- B0 and C0: one at a time, no Accession
    local mine = { name = 'A', slot = 1, sid = 101, hpp = 45, pos = { 30, 0, 0 } }
    cmd, intent = decide(pair(mine, { ACCESSION }), healing_them(), sch)
    eq({ cmd, intent.why }, { '/ma "Cure IV" B0', 'danger: B0 45%' })   -- spread, but A beside B0 isn't counted
end)

test('heal: what lands on the alliance teaches potency, as their HP is read like a member\'s', function ()
    local observed = require('core.observed')
    local _, intent = decide(snap({ ally({ hpp = 70 }) }), healing_them())
    observed.learned.ma3 = nil
    intent.sent(0)
    observed.healed('ma3', 301, 200, 1)
    eq(observed.learned.ma3 ~= nil, true)
    observed.learned.ma3 = nil
end)

-- The other behaviors, with heal.alliance off ------------------------------------------

test('removal: a -na spell on an alliance member; Erase and Esuna do not reach them', function ()
    eq(decide(snap({ ally({ buffs = { [PARALYSIS] = true } }) })), '/ma "Paralyna" Bob')
    eq({ decide(snap({ ally({ buffs = { [SLOW] = true } }) })) }, { nil, 'nothing to do' })
end)

test('wake: an alliance sleeper gets a heal aimed at them; Curaga wakes your party only', function ()
    local cmd, intent = decide(snap({ ally({ buffs = { [SLEEP] = true } }) }))
    eq({ cmd, intent.why }, { '/ma "Cure" Bob', 'Bob asleep' })
    cmd, intent = decide(snap({ { name = 'A', buffs = { [SLEEP] = true } }, ally({ buffs = { [SLEEP] = true } }) }))
    eq({ cmd, intent.why }, { '/ma "Cure" A', 'A asleep' })    -- one in the party: no Curaga
end)

test('buff: a row\'s targets take alliance slots, when the spell can go outside the party', function ()
    local cfg = settings.defaults()
    cfg.rows.Haste = { on = true, targets = { [6] = true } }
    eq(decide(snap({ ally() }), cfg), '/ma "Haste" Bob')
    eq({ decide(snap({ ally({ buffs = { [HASTE] = true } }) }), cfg) }, { nil, 'nothing to do' })
    cfg.rows.Haste = nil
    cfg.rows['Regen (keep up)'] = { on = true, targets = { [6] = true } }
    eq({ decide(snap({ ally() }), cfg) }, { nil, 'nothing to do' })  -- Regen is party only
end)

test('buff: an area self-cast is recast for your party near you, not the alliance', function ()
    local cfg = settings.defaults()
    cfg.rows.Protectra = { on = true }
    local g = snap({ { name = 'A', buffs = { [PROTECT] = true } }, ally() })
    g.me.buffs[PROTECT] = true
    eq({ decide(g, cfg) }, { nil, 'nothing to do' })
end)

test('revive: a fallen alliance member is raised', function ()
    eq(decide(snap({ ally({ hpp = 0 }) })), '/ma "Arise" Bob')
end)

test('recover: Devotion is for your party only', function ()
    local g = snap({ ally({ mpp = 10 }) })
    g.me.mpp = 80
    eq({ decide(g) }, { nil, 'nothing to do' })
    g = snap({ { name = 'A', mpp = 10 } })
    g.me.mpp = 80
    eq(decide(g), '/ja "Devotion" A')
end)

test('an enemy action on a mob another party claimed names it by server id, as the client has no <bt> for it', function ()
    local g = snap({ ally() }, { bt = { sid = 9000, name = 'Crab', hpp = 80, dist = 5, mob = true, claimed = true } })
    g.me.mpp = 20
    local cfg = settings.defaults()
    local intent = engine.decide(g, cat, cfg, {})
    eq(engine.command(intent, cfg, g), '/ma "Aspir" 9000')
    g.bt.claimed = nil  -- your party's: the client's <bt>
    eq(engine.command(intent, cfg, g), '/ma "Aspir" <bt>')
end)

test('follow: an alliance leader by name, as only your party has <p1>-<p5>', function ()
    local cfg = settings.defaults()
    cfg.follow = { on = true, target = 'Bob', distance = 5 }
    eq(decide(snap({ ally({ dist = 12 }) }), cfg), '/follow Bob')
    cfg.follow.target = 'A'
    eq(decide(snap({ { name = 'A', dist = 12 } }), cfg), '/follow <p1>')
end)
