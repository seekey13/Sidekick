-- Phase 3 behaviors on fake snapshots: wake, recover, pet, follow, rest, removal by item.
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local WHM, RDM, PLD, BLM, SAM, PUP, DRG, MNK = 3, 5, 7, 4, 12, 18, 14, 2
local SLEEP, POISON, INVISIBLE, SNEAK = 2, 3, 69, 71
local OIL = 18731
local snap = fake.snap

local function decide(g, cfg, list, mem) return fake.decide(g, list, cfg, mem) end

local function cfg_with(t)
    local cfg = settings.defaults()
    for path, v in pairs(t) do
        local parent, key = path:match('^(.-)%.([^.]+)$')
        cfg[parent][key] = v
    end
    return cfg
end

-- Wake ----------------------------------------------------------------------------

local whm = fake.catalog(WHM, 75, BLM, 37)

test('wake: the cheapest heal that wakes, on a sleeper at full HP', function ()
    local cmd, intent = decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), nil, whm)
    eq({ cmd, intent.behavior, intent.why }, { '/ma "Cure" 101', 'wake', 'A asleep' })
    eq({ decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), cfg_with({ ['wake.on'] = false }), whm) },
        { nil, 'nothing to do' })
end)

test('wake: two asleep together get one area heal; spread, the focus member first', function ()
    local two = function (spread)
        return snap({ { name = 'A', buffs = { [SLEEP] = true } },
                      { name = 'B', buffs = { [SLEEP] = true }, pos = spread and { 30, 0, 0 } or nil } })
    end
    local cmd, intent = decide(two(false), nil, whm)
    eq({ cmd, intent.why }, { '/ma "Curaga" 101', '2 asleep' })
    eq(decide(two(true), nil, whm), '/ma "Cure" 101')
    eq(decide(two(true), cfg_with({ ['heal.focus'] = 'B' }), whm), '/ma "Cure" 102')
end)

test('wake: the cheapest that wakes, one healing never uses (heal.never) too', function ()
    local never = cfg_with({ ['heal.never'] = { Cure = true, Curaga = true } })
    eq(decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), never, whm), '/ma "Cure" 101')
    eq(decide(snap({ { name = 'A', buffs = { [SLEEP] = true } }, { name = 'B', buffs = { [SLEEP] = true } } }), never, whm),
        '/ma "Curaga" 101')
end)

test('wake: a heal gated to Idle or Combat (cfg.gates) still wakes, in combat or out', function ()
    local cfg = cfg_with({})
    cfg.gates.Cure, cfg.gates.Curaga = 'idle', 'idle'
    local g = snap({ { name = 'A', buffs = { [SLEEP] = true } } })
    g.combat = true
    eq(decide(g, cfg, whm), '/ma "Cure" 101')
    cfg.gates.Cure, cfg.gates.Curaga = 'combat', 'combat'
    eq(decide(snap({ { name = 'A', buffs = { [SLEEP] = true } } }), cfg, whm), '/ma "Cure" 101')
end)

-- Recover ---------------------------------------------------------------------------

test('efficient_heals: on while one heal efficient healing could use is on; off once all are; none on a job without',
        function ()
    local heal = require('behaviors.heal')
    local cfg = settings.defaults()
    eq(heal.efficient_heals(whm, cfg), 'on')
    for _, a in ipairs(whm) do
        if a.role == 'heal' and a.family ~= 'Cure' then cfg.rows[settings.key(a)] = { on = false } end
    end
    cfg.heal.never = { Cure = true, ['Cure II'] = true, ['Cure III'] = true, ['Cure IV'] = true }
    eq(heal.efficient_heals(whm, cfg), 'on')    -- Cure V still ticked
    cfg.heal.never['Cure V'] = true
    eq(heal.efficient_heals(whm, cfg), 'off')
    eq(heal.efficient_heals(fake.catalog(SAM, 75, nil, 0), cfg), 'none')
    eq(heal.efficient_heals(fake.catalog(9, 75, nil, 0, { 'Wild Carrot' }), cfg), 'none')  -- BST: Ready charges are kept
end)

test('recover: Convert under the MP line, only while it gains and you are out of danger', function ()
    local rdm = fake.catalog(RDM, 75, nil, 0, { 'Convert' })
    local cfg = cfg_with({ ['heal.on'] = false })
    local g = snap()
    g.me.mpp, g.me.mp, g.me.hp = 20, 200, 1000
    local cmd, intent = decide(g, cfg, rdm)
    eq({ cmd, intent.why }, { '/ja "Convert" <me>', 'MP 20%' })
    g.me.hpp = 40
    eq({ decide(g, cfg, rdm) }, { nil, 'nothing to do' })
    g.me.hpp, g.me.mpp = 100, 50
    eq({ decide(g, cfg, rdm) }, { nil, 'nothing to do' })
end)

test('recover: Devotion on the member lowest on MP, never one with no MP', function ()
    local cat = fake.catalog(WHM, 75, nil, 0, { 'Devotion' })
    local g = snap({ { name = 'A', mpp = 25 }, { name = 'B', mpp = 10 }, { name = 'War', mpp = 0, uses_mp = false } })
    eq(decide(g, nil, cat), '/ja "Devotion" 102')
    g.units[3].mpp = 50
    eq(decide(g, nil, cat), '/ja "Devotion" 101')
end)

test('recover: Devotion with a target goes only on them, under the MP line, and waits for them while they are away',
    function ()
    local cat = fake.catalog(WHM, 75, nil, 0, { 'Devotion' })
    local cfg = cfg_with({ ['recover.target'] = 'A' })
    local g = snap({ { name = 'A', mpp = 25 }, { name = 'B', mpp = 10 } })
    local cmd, intent = decide(g, cfg, cat)
    eq({ cmd, intent.why }, { '/ja "Devotion" 101', 'A MP 25%' })  -- B is lower, but not the target
    g.units[2].mpp = 40  -- A
    eq({ decide(g, cfg, cat) }, { nil, 'nothing to do' })  -- over the line: B under it is still left alone
    g.units[2].mpp, g.units[2].in_zone = 25, false
    eq({ decide(g, cfg, cat) }, { nil, 'nothing to do' })  -- in another zone: still kept for A
    g.units[2].in_zone, g.units[2].alive, cfg.revive.on = true, false, false
    eq({ decide(g, cfg, cat) }, { nil, 'nothing to do' })  -- dead (and not raised here): still kept for A
    g.units[2].alive, cfg.revive.on = true, true
    cfg.recover.target = ''
    eq(decide(g, cfg, cat), '/ja "Devotion" 102')  -- whoever is lowest: B
    cfg.recover.target = 'a'
    eq(decide(g, cfg, cat), '/ja "Devotion" 101')  -- named in any case, as focus and Entrust are
end)

test('recover: Devotion with a target not in your party goes on whoever is lowest until they are', function ()
    local cat = fake.catalog(WHM, 75, nil, 0, { 'Devotion' })
    local cfg = cfg_with({ ['recover.target'] = 'Gone' })
    local g = snap({ { name = 'A', mpp = 25 }, { name = 'B', mpp = 10 }, { name = 'Zed', mpp = 5, kind = 'alliance' },
                     { name = 'Out', kind = 'tracked' } })
    eq(decide(g, cfg, cat), '/ja "Devotion" 102')  -- left the party: B, the lowest
    cfg.recover.target = 'Zed'
    eq(decide(g, cfg, cat), '/ja "Devotion" 102')  -- another party of the alliance: Devotion can't reach them
    cfg.recover.target = 'Out'
    eq(decide(g, cfg, cat), '/ja "Devotion" 102')  -- tracked
end)

test('recover: Meditate in combat under the TP line; Chivalry from its own TP line', function ()
    local sam = fake.catalog(SAM, 75, nil, 0, { 'Meditate' })
    eq(decide(snap(nil, { combat = true }), nil, sam), '/ja "Meditate" <me>')
    eq({ decide(snap(), nil, sam) }, { nil, 'nothing to do' })
    local pld = fake.catalog(PLD, 75, nil, 0, { 'Chivalry' })
    local cfg = cfg_with({ ['heal.on'] = false })
    local g = snap()
    g.me.mpp, g.me.tp = 20, 2000
    eq({ decide(g, cfg, pld) }, { nil, 'nothing to do' })
    g.me.tp = 3000
    eq(decide(g, cfg, pld), '/ja "Chivalry" <me>')
    g.me.tp, cfg.recover.min_tp = 2000, 1500
    eq(decide(g, cfg, pld), '/ja "Chivalry" <me>')
end)

test('recover: Aspir from the battle target', function ()
    local g = snap(nil, { combat = true, bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 } })
    g.me.mpp = 20
    eq(decide(g, nil, whm), '/ma "Aspir" <bt>')
end)

-- Pet ------------------------------------------------------------------------------

local pup = fake.catalog(PUP, 75, nil, 0, { 'Repair', 'Maintenance', 'Deploy' })
local function automaton(t)
    local p = { name = 'Automaton', hpp = 100, dist = 3, status = 0, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

test('pet: Repair under the pet HP line, only with an oil worn', function ()
    eq({ decide(snap(nil, { pet = automaton({ hpp = 40 }) }), nil, pup) }, { nil, 'nothing to do' })
    local cmd, intent = decide(snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL }), nil, pup)
    eq({ cmd, intent.behavior, intent.why }, { '/ja "Repair" <me>', 'pet', 'Automaton 40%' })
    eq(decide(snap(nil, { pet = automaton({ hpp = 40 }), ammo = 19185 }), nil, pup), '/ja "Repair" <me>')  -- +3
    eq({ decide(snap(nil, { pet = automaton({ hpp = 60 }), ammo = OIL }), nil, pup) }, { nil, 'nothing to do' })
    local g = snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL })
    g.me.buffs[INVISIBLE] = true
    eq({ decide(g, nil, pup) }, { nil, 'invisible' })
end)

test('pet: Repair only within 20 yalms of the automaton, as the server allows', function ()
    eq({ decide(snap(nil, { pet = automaton({ hpp = 40, dist = 25 }), ammo = OIL }), nil, pup) }, { nil, 'nothing to do' })
end)

test('pet: cared for and sent in while healing waits for a cure', function ()
    local cat = fake.catalog(PUP, 75, WHM, 37, { 'Repair', 'Deploy' })
    local waits = {}
    for _, a in ipairs(cat) do if a.role == 'heal' then waits[a.name] = 5 end end
    local hurt = { { name = 'A', hpp = 45 } }
    eq(decide(snap(hurt, { pet = automaton({ hpp = 40 }), ammo = OIL }, waits), nil, cat), '/ja "Repair" <me>')
    local cfg = settings.defaults()
    cfg.rows.Deploy = { on = true }
    local g = snap(hurt, { pet = automaton(), bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 }, combat = true }, waits)
    eq(decide(g, cfg, cat), '/pet "Deploy" <bt>')
    g.pet = nil
    eq({ decide(g, cfg, cat) }, { nil, 'waiting for a cure' })
end)

test('pet: Maintenance clears what ails it', function ()
    eq(decide(snap(nil, { pet = automaton({ buffs = { [POISON] = true } }), ammo = OIL }), nil, pup),
        '/ja "Maintenance" <me>')
end)

test('pet: sent at the battle target when idle, opt-in', function ()
    local bt = { name = 'Crab', mob = true, dist = 5, hpp = 100 }
    local cfg = settings.defaults()
    eq({ decide(snap(nil, { pet = automaton(), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
    cfg.rows.Deploy = { on = true }
    local cmd, intent = decide(snap(nil, { pet = automaton(), bt = bt, combat = true }), cfg, pup)
    eq({ cmd, intent.behavior }, { '/pet "Deploy" <bt>', 'pet_send' })
    eq({ decide(snap(nil, { pet = automaton({ status = 1 }), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
    eq({ decide(snap(nil, { pet = automaton({ hpp = 0 }), bt = bt, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
end)

test('pet: sent at your own target (<t>) only while you are engaged, with pet.at_t', function ()
    local crab = { name = 'Crab', mob = true, dist = 5, hpp = 100 }
    local cfg = settings.defaults()
    cfg.rows.Deploy, cfg.pet.at_t = { on = true }, true
    -- No battle target needed (a mob not yet claimed), nor combat: being engaged is.
    local g = snap(nil, { pet = automaton(), t = crab })
    eq({ decide(g, cfg, pup) }, { nil, 'nothing to do' })  -- not engaged: a passing cursor sends nothing
    g.me.status = 1
    local cmd, intent = decide(g, cfg, pup)
    eq({ cmd, intent.behavior, intent.why }, { '/pet "Deploy" <t>', 'pet_send', 'Automaton at Crab' })
    -- The battle target alone doesn't do: it's <t> or nothing.
    eq({ decide(snap(nil, { pet = automaton(), bt = crab, combat = true }), cfg, pup) }, { nil, 'nothing to do' })
    -- Your target a player, dead, out of range, or the pet already fighting: not sent.
    for _, t in ipairs({ { name = 'A', hpp = 100, dist = 5 }, { name = 'Crab', mob = true, hpp = 0, dist = 5 },
                        { name = 'Crab', mob = true, hpp = 100, dist = 99 } }) do
        g = snap(nil, { pet = automaton(), t = t }); g.me.status = 1
        eq({ decide(g, cfg, pup) }, { nil, 'nothing to do' })
    end
    g = snap(nil, { pet = automaton({ status = 1 }), t = crab }); g.me.status = 1
    eq({ decide(g, cfg, pup) }, { nil, 'nothing to do' })
    -- Range is from your target, not the battle target, and a claimed <bt> still goes as <t>.
    g = snap(nil, { pet = automaton(), t = crab, combat = true,
                    bt = { name = 'Far', mob = true, dist = 99, hpp = 100, claimed = true, sid = 9 } })
    g.me.status = 1
    eq(decide(g, cfg, pup), '/pet "Deploy" <t>')
    -- Your own pet as your target: never sent at itself.
    g = snap(nil, { pet = automaton({ tidx = 0x700 }), t = { name = 'Automaton', mob = true, dist = 2, hpp = 100, tidx = 0x700 } })
    g.me.status = 1
    eq({ decide(g, cfg, pup) }, { nil, 'nothing to do' })
    -- Off again: back to the battle target.
    cfg.pet.at_t = false
    eq(decide(snap(nil, { pet = automaton(), bt = crab, t = crab, combat = true }), cfg, pup), '/pet "Deploy" <bt>')
end)

test('pet: Spirit Link waits while you are in danger yourself', function ()
    local drg = fake.catalog(DRG, 75, nil, 0, { 'Spirit Link' })
    local g = snap(nil, { pet = automaton({ name = 'Wyvern', hpp = 30 }) })
    eq(decide(g, nil, drg), '/ja "Spirit Link" <me>')
    g.me.hpp = 40
    eq({ decide(g, cfg_with({ ['heal.on'] = false }), drg) }, { nil, 'nothing to do' })
end)

-- Follow and rest -------------------------------------------------------------------------

local function follower()
    return cfg_with({ ['follow.on'] = true, ['follow.target'] = 'a' })
end

test('follow: past the distance, by party slot; not while moving', function ()
    local cmd, intent = decide(snap({ { name = 'B' }, { name = 'A', dist = 8 } }), follower(), whm)
    eq({ cmd, intent.why }, { '/follow <p2>', 'A 8.0y away' })
    eq({ decide(snap({ { name = 'A', dist = 4 } }), follower(), whm) }, { nil, 'nothing to do' })
    eq({ decide(snap({ { name = 'A', dist = 8 } }, { moving = true }), follower(), whm) }, { nil, 'moving' })
    -- A trust left out of support (core/engine.lua: immune) can still be followed.
    eq(decide(snap({ { name = 'A', kind = 'trust', immune = true, dist = 8 } }), follower(), whm), '/follow <p1>')
end)

test('follow: mounted, in a safe zone and in AFK sleep too, where the rest waits; never in an event', function ()
    local hurt = { { name = 'B', hpp = 40 }, { name = 'A', dist = 8 } }
    for _, over in ipairs({ { mounted = true }, { safe = true }, { afk = true }, { mounted = true, afk = true } }) do
        eq(decide(snap(hurt, over), follower(), whm), '/follow <p2>')
        eq({ decide(snap(hurt, over), nil, whm) }, { nil, over.mounted and 'mounted' or over.safe and 'safe' or 'afk' })
    end
    eq({ decide(snap({ { name = 'A', dist = 4 } }, { mounted = true }), follower(), whm) }, { nil, 'mounted' })
    eq({ decide(snap(hurt, { safe = true, event = true }), follower(), whm) }, { nil, 'safe' })
    eq({ decide(snap(hurt, { mounted = true, moving = true }), follower(), whm) }, { nil, 'mounted' })
    for _, gate in ipairs({ 'dead', 'incapacitated', 'casting' }) do
        eq({ decide(snap(hurt, { [gate] = true }), follower(), whm) }, { nil, gate })
    end
    eq({ decide(snap(hurt, { resting = true }), follower(), whm) }, { nil, 'resting' })  -- resting stands up for it
end)

test('follow while automation is stopped: engine.free decides it alone, through the same gates', function ()
    local g = snap({ { name = 'B', hpp = 40 }, { name = 'A', dist = 8 } })
    eq(decide(g, follower(), whm):match('^/ma "Cur'), '/ma "Cur')  -- running, the heal goes first
    local intent = engine.free(g, whm, follower(), {})
    eq({ engine.command(intent, follower()), intent.behavior }, { '/follow <p2>', 'follow' })
    g.mounted = true
    eq(engine.command(engine.free(g, whm, follower(), {}), follower()), '/follow <p2>')
    g.mounted, g.moving = nil, true
    eq({ engine.free(g, whm, follower(), {}) }, { nil, 'moving' })
    g.moving = nil
    eq({ engine.free(g, whm, settings.defaults(), {}) }, { nil, 'nothing to do' })  -- off
end)

test('rest: under the MP line, out of combat, 3s after your last move and send', function ()
    local cfg = cfg_with({ ['rest.on'] = true, ['rest.mp'] = 40 })
    local g = snap(nil, { moved_at = 997, combat_at = 994, finished = 999.5 })
    g.me.mpp = 40
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' }, 'at the line, not under it')
    g.me.mpp = 39
    local cmd, intent = decide(g, cfg, whm, { sent_at = 997 })
    eq({ cmd, intent.why }, { '/heal on', 'MP 39%' })
    eq({ decide(g, cfg, whm, { sent_at = 997.5 }) }, { nil, 'nothing to do' }, 'a send just before')
    g.moved_at = 997.5
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' }, 'a move just before')
    g.moved_at, g.combat = 997, true
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.combat, g.me.uses_mp = false, false
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
end)

test('rest: a /heal on that did not sit you down goes again only after a while', function ()
    local cfg = cfg_with({ ['rest.on'] = true })
    local g, mem = snap(), {}
    g.me.mpp = 20
    eq(fake.step(g, whm, cfg, mem), '/heal on')
    g.now = g.now + 4
    eq({ fake.step(g, whm, cfg, mem) }, { nil, 'nothing to do' })
    g.now = g.now + 1
    eq(fake.step(g, whm, cfg, mem), '/heal on')
end)

test('rest: not in a follower\'s short stop, the leader close', function ()
    local cfg = cfg_with({ ['rest.on'] = true, ['follow.on'] = true, ['follow.target'] = 'A' })
    local g = snap({ { name = 'A', dist = 3 } }, { moved_at = 999.5 })
    g.me.mpp = 20
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.now = 1002.5
    eq(decide(g, cfg, whm), '/heal on')
end)

test('rest: not with a pet out as a SMN, main or sub (the server takes no /heal under an avatar)', function ()
    local cfg = cfg_with({ ['rest.on'] = true })
    local g = snap(nil, { pet = automaton({ name = 'Carbuncle' }), sub = 15 })
    g.me.mpp = 20
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.sub, g.main = 4, 15
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.main = WHM
    eq(decide(g, cfg, whm), '/heal on', 'another job\'s pet')
    g.sub, g.pet = 15, nil
    eq(decide(g, cfg, whm), '/heal on', 'no pet out')
end)

test('rest: not while the leader is past Stand past; at once when they come back', function ()
    local cfg = cfg_with({ ['rest.on'] = true, ['follow.target'] = 'A' })
    local g = snap({ { name = 'A', dist = 9 } })
    g.me.mpp = 20
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    g.units[2].dist = 6
    eq(decide(g, cfg, whm), '/heal on')
end)

test('resting: nothing else runs; stand at full MP or when the leader leaves', function ()
    local cfg = cfg_with({ ['rest.on'] = true, ['follow.target'] = 'A' })
    local g = snap({ { name = 'A', hpp = 40 } }, { resting = true })
    g.me.mpp = 50
    eq({ decide(g, cfg, whm) }, { nil, 'resting' })
    g.me.mpp = 100
    eq(decide(g, cfg, whm), '/heal off')
    g.me.mpp, g.units[2].dist = 50, 9
    local cmd, intent = decide(g, cfg, whm)
    eq({ cmd, intent.why }, { '/heal off', 'A left' })
end)

-- Removal by item, and the other removers only ever on you --------------------------------

local SILENCE, PARALYSIS, BLINDNESS, BIND, WEIGHT, DOOM = 6, 4, 5, 11, 12, 15
local ANTIDOTE, PANACEA, ECHO_DROPS, REMEDY = 4148, 4149, 4151, 4155

test('items: Echo Drops when silenced, opt-in, only with one in your bag, amnesia or not', function ()
    local g = snap(nil, { silenced = true, amnesia = true, items = { [ECHO_DROPS] = 3 } })
    g.me.buffs[SILENCE] = true
    local cfg = settings.defaults()
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    cfg.rows['Echo Drops'] = { on = true }
    local cmd, intent = decide(g, cfg, whm)
    eq({ cmd, intent.behavior, intent.why }, { '/item "Echo Drops" <me>', 'remove', 'Me' })
    g.items = {}
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
end)

test('items: a spell that can go first; then the most specific item you carry, for you only', function ()
    local cfg = settings.defaults()
    for _, k in ipairs({ 'Antidote', 'Remedy', 'Panacea' }) do cfg.rows[k] = { on = true } end
    local carried = { [ANTIDOTE] = 1, [REMEDY] = 1, [PANACEA] = 1 }
    local g = snap(nil, { items = carried })
    g.me.buffs[POISON] = true
    eq(decide(g, cfg, whm), '/ma "Poisona" 1')
    local blm = fake.catalog(BLM, 75, nil, 0)
    g = snap({ { name = 'A', buffs = { [POISON] = true } } }, { items = carried })
    eq({ decide(g, cfg, blm) }, { nil, 'nothing to do' })
    g.me.buffs[POISON] = true
    eq(decide(g, cfg, blm), '/item "Antidote" <me>')
    g.me.buffs[POISON], g.me.buffs[PARALYSIS] = nil, true
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')
    carried[REMEDY] = nil
    eq(decide(g, cfg, blm), '/item "Panacea" <me>')
end)

test('items: Doom first, then Silence if you cast, then the one clearing the most of yours', function ()
    local blm = fake.catalog(BLM, 75, nil, 0)
    local cfg, carried = settings.defaults(), {}
    for _, a in ipairs(blm) do if a.kind == 'item' then cfg.rows[a.family] = { on = true }; carried[a.id] = 1 end end
    local g = snap(nil, { items = carried })
    for _, id in ipairs({ DOOM, SILENCE, POISON }) do g.me.buffs[id] = true end
    eq(decide(g, cfg, blm), '/item "Holy Water" <me>')
    g.me.buffs[DOOM] = nil
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')      -- Silence and Poison in one
    carried[REMEDY] = nil
    eq(decide(g, cfg, blm), '/item "Echo Drops" <me>')  -- you cast: Silence before Poison
    g.me.uses_mp = false
    eq(decide(g, cfg, blm), '/item "Antidote" <me>')    -- you don't
    carried[REMEDY] = 1                                 -- Bad Breath: Remedy, then Panacea; never the Ointment
    for _, id in ipairs({ PARALYSIS, BLINDNESS, BIND, WEIGHT }) do g.me.buffs[id] = true end
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')
    for _, id in ipairs({ POISON, PARALYSIS, BLINDNESS, SILENCE }) do g.me.buffs[id] = nil end
    eq(decide(g, cfg, blm), '/item "Panacea" <me>')
end)

test('removal: a player switched off is skipped, and their own debuffs replace everyone\'s, both by name', function ()
    local cfg = settings.defaults()
    cfg.remove.skip = { paralysis = true }
    local g = snap({ { name = 'A', buffs = { [PARALYSIS] = true } }, { name = 'B', buffs = { [PARALYSIS] = true } } })
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    cfg.remove.off = { A = true }
    cfg.remove.skip = {}
    eq(decide(g, cfg, whm), '/ma "Paralyna" 102')
    -- It stays with A: whoever takes their slot is looked after.
    eq(decide(snap({ { name = 'C', buffs = { [PARALYSIS] = true } } }), cfg, whm), '/ma "Paralyna" 101')
    cfg.remove.off = {}
    cfg.remove.own = { A = { set = true, skip = { paralysis = true } } }
    eq(decide(g, cfg, whm), '/ma "Paralyna" 102')
    cfg.remove.skip = { paralysis = true }
    cfg.remove.own = { A = { set = true, skip = {} } }
    eq(decide(g, cfg, whm), '/ma "Paralyna" 101')
    eq({ decide(snap({ { name = 'C', buffs = { [PARALYSIS] = true } } }), cfg, whm) }, { nil, 'nothing to do' })
end)

test('removal: a remover leaves be a status it just had no effect on while the client shows it; another may try', function ()
    local cfg = settings.defaults()
    local PARALYNA, ERASE = 'ma15', 'ma143'  -- observed.key
    local g = snap({ { name = 'A', buffs = { [PARALYSIS] = true }, futile = { [PARALYNA] = { [PARALYSIS] = true } } },
                     { name = 'B', buffs = { [PARALYSIS] = true } } })
    eq(decide(g, cfg, whm), '/ma "Paralyna" 102')
    g.units[3].futile = { [PARALYNA] = { [PARALYSIS] = true } }
    eq({ decide(g, cfg, whm) }, { nil, 'nothing to do' })
    -- Another remover's no effect leaves Paralyna free to try it.
    g.units[2].futile = { [ERASE] = { [PARALYSIS] = true } }
    eq(decide(g, cfg, whm), '/ma "Paralyna" 101')
end)

test('items: a status left on still makes the Ointment a gamble', function ()
    local blm, cfg = fake.catalog(BLM, 75, nil, 0), settings.defaults()
    for _, k in ipairs({ 'Remedy Ointment', 'Remedy' }) do cfg.rows[k] = { on = true } end
    cfg.remove.skip = { poison = true }
    local g = snap(nil, { items = { [5356] = 1, [REMEDY] = 1 } })
    g.me.buffs[POISON], g.me.buffs[BLINDNESS] = true, true
    eq(decide(g, cfg, blm), '/item "Remedy" <me>')  -- the Ointment could take the Poison left on
end)

test('items: an /item the server never answered holds the next one 4s', function ()
    local blm, cfg, mem = fake.catalog(BLM, 75, nil, 0), settings.defaults(), {}
    cfg.rows['Echo Drops'] = { on = true }
    local g = snap(nil, { items = { [ECHO_DROPS] = 3 } })
    g.me.buffs[SILENCE] = true
    local _, intent = decide(g, cfg, blm, mem)
    engine.sent(intent, g, mem)
    g.now = 1002
    eq({ decide(g, cfg, blm, mem) }, { nil, 'nothing to do' })
    g.finished = 1001  -- it went off
    eq(decide(g, cfg, blm, mem), '/item "Echo Drops" <me>')
    g.finished, g.now = nil, 1004
    eq(decide(g, cfg, blm, mem), '/item "Echo Drops" <me>')
end)

test('Chakra clears only your own poison, not a member\'s near you', function ()
    local mnk = fake.catalog(MNK, 75, nil, 0, { 'Chakra' })
    local g = snap({ { name = 'A', buffs = { [POISON] = true } } })
    eq({ decide(g, nil, mnk) }, { nil, 'nothing to do' })
    g.me.buffs[POISON] = true
    eq(decide(g, nil, mnk), '/ja "Chakra" <me>')
end)

-- Invisible and Sneak -------------------------------------------------------------

-- `g` with `id` on you.
local function under(g, id) g.me.buffs[id] = true; return g end

test('Invisible: danger healing goes, efficient healing waits; Sneak stops neither', function ()
    eq({ decide(under(snap({ { name = 'A', hpp = 60 } }), INVISIBLE), nil, whm) }, { nil, 'invisible' })
    local cmd, intent = decide(under(snap({ { name = 'A', hpp = 40 } }), INVISIBLE), nil, whm)
    eq({ cmd ~= nil, intent.behavior, intent.why }, { true, 'heal', 'danger: A 40%' })
    eq(decide(under(snap({ { name = 'A', hpp = 20 } }), INVISIBLE), nil, whm) ~= nil, true, 'critical too')
    eq(select(2, decide(under(snap({ { name = 'A', hpp = 60 } }), SNEAK), nil, whm)).why, 'efficient: A 60%')
end)

-- Sneak, Invisible and Protect kept up on you and P1.
local function travel_cfg()
    local cfg = settings.defaults()
    for _, key in ipairs({ 'Protect', 'Sneak', 'Invisible' }) do
        cfg.rows[key] = { on = true, targets = { [0] = true, [1] = true } }
    end
    return cfg
end

test('Invisible: no removal, wake, pet care or other buff, only travel buffs; Sneak stops none', function ()
    local cfg = travel_cfg()
    local others = { { name = 'A', buffs = { [POISON] = true, [SNEAK] = true, [INVISIBLE] = true } },
                     { name = 'B', buffs = { [SLEEP] = true } } }
    eq(decide(under(snap(others), SNEAK), cfg, whm), '/ma "Poisona" 101')
    eq(decide(under(snap(others), INVISIBLE), cfg, whm), '/ma "Sneak" 1')
    eq({ decide(under(under(snap(others), SNEAK), INVISIBLE), cfg, whm) }, { nil, 'invisible' })
    local g = snap(nil, { pet = automaton({ hpp = 40 }), ammo = OIL })
    eq(decide(under(g, SNEAK), nil, pup), '/ja "Repair" <me>')
    eq({ decide(under(g, INVISIBLE), nil, pup) }, { nil, 'invisible' })
    eq(decide(under(snap({ { name = 'A', dist = 12 } }), INVISIBLE), follower(), whm), '/follow <p1>')
end)

test('your own Invisible goes last: members first, your Sneak and other buffs before it', function ()
    local cfg = travel_cfg()
    local function with(mine, theirs)
        local g = snap({ { name = 'A', buffs = theirs } })
        for _, id in ipairs(mine) do g.me.buffs[id] = true end
        return g
    end
    local PROTECT = 40
    eq(decide(with({}, {}), cfg, whm), '/ma "Protect IV" 1')
    eq(decide(with({ PROTECT }, { [PROTECT] = true }), cfg, whm), '/ma "Sneak" 1')
    eq(decide(with({ PROTECT, SNEAK }, { [PROTECT] = true }), cfg, whm), '/ma "Sneak" 101')
    eq(decide(with({ PROTECT, SNEAK }, { [PROTECT] = true, [SNEAK] = true }), cfg, whm), '/ma "Invisible" 101')
    local all = { [PROTECT] = true, [SNEAK] = true, [INVISIBLE] = true }
    local cmd, intent = decide(with({ PROTECT, SNEAK }, all), cfg, whm)
    eq({ cmd, intent.behavior }, { '/ma "Invisible" 1', 'buff' })
    -- A member loses theirs while you're Invisible: theirs again, then yours.
    eq(decide(with({ PROTECT, SNEAK, INVISIBLE }, { [PROTECT] = true, [SNEAK] = true }), cfg, whm),
        '/ma "Invisible" 101')
    eq({ decide(with({ PROTECT, SNEAK, INVISIBLE }, all), cfg, whm) }, { nil, 'invisible' })
end)

test('Spectral Jig is used again only once both its Sneak and its Invisible are off', function ()
    local dnc = fake.catalog(19, 75, WHM, 37, { 'Spectral Jig' })
    local cfg = settings.defaults()
    cfg.rows['Spectral Jig'] = { on = true }
    cfg.rows.Sneak = { on = true, targets = { [0] = true } }
    local g = snap(nil, { main = 19, sub = WHM })
    eq(decide(g, cfg, dnc), '/ja "Spectral Jig" <me>', 'not Sneak first: the Jig gives it')
    eq({ decide(under(g, SNEAK), cfg, dnc) }, { nil, 'nothing to do' }, 'Invisible broken: Sneak is still up')
    g = under(snap(nil, { main = 19, sub = WHM }), INVISIBLE)
    eq(decide(g, cfg, dnc), '/ma "Sneak" 1', 'Sneak lost, Invisible up: the Jig would do nothing')
end)

test('your own Invisible waits for a member\'s Sneak briefly on recast, not a long one', function ()
    local cfg = travel_cfg()
    local PROTECT = 40
    local function g(wait)
        local s = snap({ { name = 'A', buffs = { [PROTECT] = true } } }, nil, { Sneak = wait })
        s.me.buffs[PROTECT], s.me.buffs[SNEAK] = true, true
        return s
    end
    eq(decide(g(3), cfg, whm), '/ma "Invisible" 101')
    local short = g(3)
    short.units[2].buffs[INVISIBLE] = true
    eq({ decide(short, cfg, whm) }, { nil, 'nothing to do' }, 'A lacks only Sneak, 3s off')
    local long = g(30)
    long.units[2].buffs[INVISIBLE] = true
    eq(decide(long, cfg, whm), '/ma "Invisible" 1')
end)

test('your own Invisible waits at most OTHERS_FIRST seconds for a buff briefly on recast', function ()
    local cfg = travel_cfg()
    local mem = {}
    local g = snap({ { name = 'A', buffs = { [SNEAK] = true, [INVISIBLE] = true } } })
    g.recast = function (a) return a.name:find('Protect') and 5 or 0 end
    g.me.buffs[SNEAK] = true
    eq({ decide(g, cfg, whm, mem) }, { nil, 'nothing to do' }, 'Protect 5s off, A lacks it')
    g.now = g.now + 14
    eq({ decide(g, cfg, whm, mem) }, { nil, 'nothing to do' })
    g.now = g.now + 1
    eq(decide(g, cfg, whm, mem), '/ma "Invisible" 1', 'waited long enough')
    g.recast = function () return 0 end
    eq(decide(g, cfg, whm, {}), '/ma "Protect IV" 1')
    g.recast = function (a) return a.name:find('Protect') and 60 or 0 end
    eq(decide(g, cfg, whm, {}), '/ma "Invisible" 1', 'a long recast is not waited for')
end)

test('resting starts and stops while you are Invisible', function ()
    local cfg = cfg_with({ ['rest.on'] = true })
    local g = under(snap(nil, { moved_at = 0 }), INVISIBLE)
    g.me.mpp = 10
    eq(decide(g, cfg, whm), '/heal on')
end)
