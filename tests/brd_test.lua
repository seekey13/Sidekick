-- Bard (jobs/brd.lua): songs by slot, on everyone near you or through Pianissimo on one member.
local engine = require('core.engine')
local settings = require('core.settings')
local brd = require('jobs.brd')
local fake = require('tests.fake')

local BRD, WHM = 10, 3
local MINUET, MARCH, BALLAD, PIANISSIMO, INVISIBLE, NIGHTINGALE, TROUBADOUR = 198, 214, 196, 409, 69, 347, 348
local cat = fake.catalog(BRD, 75, WHM, 37, { 'Pianissimo', 'Nightingale', 'Troubadour' })

local function named(list, name)
    for _, a in ipairs(list) do if a.name == name then return a end end
end

-- BRD 75 / WHM 37 with `others`; `buffs` on you, as stacks (an id twice stands twice).
local function snap(others, buffs, over, waits)
    local o = { main = BRD, main_lv = 75, sub = WHM, sub_lv = 37 }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap(others, o, waits)
    g.me.stacks = {}
    for _, id in ipairs(buffs or {}) do
        g.me.buffs[id] = true
        g.me.stacks[id] = (g.me.stacks[id] or 0) + 1
    end
    return g
end

-- A party player with these statuses, read with their stacks as yours are.
local function player(t, buffs)
    t.buffs, t.stacks = {}, {}
    for _, id in ipairs(buffs or {}) do
        t.buffs[id] = true
        t.stacks[id] = (t.stacks[id] or 0) + 1
    end
    return t
end

-- Song picks: { area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II', ... }. No song stamped yet.
local function cfg_with(picks, over)
    brd.clear()
    local cfg = settings.defaults()
    for k, v in pairs(picks or {}) do cfg.song[k] = v end
    for k, v in pairs(over or {}) do cfg.buff[k] = v end
    return cfg
end

local function decide(g, cfg, mem)
    local intent, why = engine.decide(g, cat, cfg or settings.defaults(), mem or {})
    if not intent then return nil, why end
    return engine.command(intent, cfg or settings.defaults()), intent
end

test('catalog: songs are their own role, by the kind they show; Pianissimo a modifier with no chip', function ()
    local m = named(cat, 'Valor Minuet IV')
    eq({ m.role, m.status, m.duration, m.note, m.pick_one }, { 'song', { MINUET }, 120, '+ATK', nil })
    eq({ named(cat, 'Victory March').status, named(cat, 'Advancing March').status }, { { MARCH }, { MARCH } })
    local p = named(cat, 'Pianissimo')
    eq({ p.role, p.status, p.chip, p.applies }, { 'modifier', { PIANISSIMO }, nil, nil })
    eq(named(cat, 'Nightingale').role, 'buff')  -- still a buff row
    eq({ brd.slots(snap()), brd.slots(snap(nil, nil, { main = WHM, sub = BRD })), brd.slots(snap(nil, nil, { main = WHM, sub = 4 })) },
       { 2, 1, 0 })
end)

test('nothing picked: nothing sung', function ()
    eq(select(2, decide(snap({ player({ name = 'A' }) }))), 'nothing to do')
end)

test('an area song goes when someone near you lacks it, you included', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Victory March' })
    local g = snap({ player({ name = 'A' }), player({ name = 'B', dist = 15 }) })
    local cmd, intent = decide(g, cfg)
    eq({ cmd, intent.behavior, intent.why }, { '/ma "Valor Minuet IV" <me>', 'song', 'Me +1 lack it' })
    -- You and A have both; B is out of its reach (about 10 yalms) and doesn't count.
    g = snap({ player({ name = 'A' }, { MINUET, MARCH }), player({ name = 'B', dist = 15 }) }, { MINUET, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ player({ name = 'A' }, { MINUET }) }, { MINUET, MARCH })
    cmd, intent = decide(g, cfg)
    eq({ cmd, intent.why }, { '/ma "Victory March" <me>', 'A lacks it' })
end)

test('two of one kind stand twice; with one up, the one sung less lately goes', function ()
    local cfg = cfg_with({ area_1 = 'Victory March', area_2 = 'Advancing March' })
    local mem = {}
    local g = snap({}, { MARCH, MARCH })
    eq(select(2, decide(g, cfg, mem)), 'nothing to do')
    g = snap({}, {})
    local cmd, intent = decide(g, cfg, mem)
    eq(cmd, '/ma "Victory March" <me>')
    engine.sent(intent, g, mem)
    eq(decide(snap({}, { MARCH }, { now = 1003 }), cfg, mem), '/ma "Victory March" <me>')  -- not landed yet: as if cut off
    brd.landed(intent.action, { 1 }, 1004, {}, 2)  -- its finish
    g = snap({}, { MARCH }, { now = 1030 })  -- one March up: Victory, sung last
    eq(decide(g, cfg, mem), '/ma "Advancing March" <me>')
end)

test('a song picked twice is one; a song you lack is skipped', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Valor Minuet IV' })
    local g = snap({}, { MINUET })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    eq(#brd.picked(cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Valor Minuet V' }), 'area', brd.actions(cat), 2), 1)  -- V is BRD 87
end)

test('a song on one member: Pianissimo first, then the song on them', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II' })
    local mem = {}
    local g = snap({ player({ name = 'A' }) })
    local cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Pianissimo" <me>', 'for Mage\'s Ballad II -> A: A' })
    engine.sent(intent, g, mem)
    cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.target.name }, { '/ma "Mage\'s Ballad II" 101', 'A' })
    g = snap({ player({ name = 'A' }, { BALLAD }) })
    eq(select(2, decide(g, cfg, {})), 'nothing to do')
end)

test('a song on you through Pianissimo is sung on <me>, with Pianissimo up', function ()
    local cfg = cfg_with({ me_1 = 'Mage\'s Ballad II' })
    eq(decide(snap({}, { PIANISSIMO }), cfg), '/ma "Mage\'s Ballad II" <me>')
end)

test('Pianissimo on recast: the songs on one member wait, and say so', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }) }, {}, nil, { Pianissimo = 20 })
    eq(select(2, decide(g, cfg)), 'holding Mage\'s Ballad II for Pianissimo')
    local below = fake.catalog(BRD, 15, WHM, 7, {})  -- no Pianissimo under BRD 20
    eq(select(2, engine.decide(snap({ player({ name = 'A' }) }, {}, { main_lv = 15, sub_lv = 7 }), below, cfg, {})), 'nothing to do')
end)

test('while an area song is owed and can\'t go, the songs on one member wait', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }, { MINUET }) }, {}, nil, { ['Valor Minuet IV'] = 10 })
    eq(select(2, decide(g, cfg)), 'holding Mage\'s Ballad II for Valor Minuet IV')
    eq(select(2, decide(g, cfg_with({ area_1 = 'Valor Minuet IV' }))), 'nothing to do', 'nothing held behind it')
    g = snap({ player({ name = 'A' }, { MINUET }) }, { MINUET })
    eq(decide(g, cfg), '/ja "Pianissimo" <me>')
end)

test('Pianissimo up: the area songs wait, the next song lands on one member', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }) }, { PIANISSIMO })
    eq(decide(g, cfg), '/ma "Mage\'s Ballad II" 101')
    cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('a member\'s own songs leave them fewer slots for the area ones', function ()
    -- A has Ballad of their own: one slot left, filled by either area song.
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', area_2 = 'Victory March', p1_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A' }, { BALLAD, MARCH }) }, { MINUET, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ player({ name = 'A' }, { BALLAD }) }, { MINUET, MARCH })
    eq(decide(g, cfg), '/ma "Valor Minuet IV" <me>')
    -- Two of their own: no area song counts for them.
    cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II', p1_2 = 'Mage\'s Ballad' })
    g = snap({ player({ name = 'A' }, { BALLAD, BALLAD }) }, { MINUET })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    -- Yours too: with two songs of your own, the area song is for the others alone.
    cfg = cfg_with({ area_1 = 'Valor Minuet IV', me_1 = 'Mage\'s Ballad II', me_2 = 'Victory March' })
    g = snap({ player({ name = 'A' }, { MINUET }) }, { BALLAD, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('a trust\'s statuses come one per id: any one stands for them all', function ()
    local cfg = cfg_with({ area_1 = 'Victory March', area_2 = 'Advancing March' })
    local g = snap({ { name = 'Kupipi', kind = 'trust', buffs = { [MARCH] = true } } }, { MARCH, MARCH })
    eq(select(2, decide(g, cfg)), 'nothing to do')
    g = snap({ { name = 'Kupipi', kind = 'trust' } }, { MARCH, MARCH })
    eq(select(2, decide(g, cfg)).why, 'Kupipi lacks it')
end)

test('on a BRD subjob, one slot per target', function ()
    local sub = fake.catalog(WHM, 75, BRD, 37, { 'Pianissimo' })
    local cfg = cfg_with({ area_1 = 'Valor Minuet III', area_2 = 'Army\'s Paeon III' })
    local g = snap({}, { MINUET }, { main = WHM, sub = BRD })
    eq(select(2, engine.decide(g, sub, cfg, {})), 'nothing to do')
end)

test('the songs on one member: only one there, alive and in reach; nothing while you\'re Invisible', function ()
    local cfg = cfg_with({ p1_1 = 'Mage\'s Ballad II', p2_1 = 'Mage\'s Ballad II' })
    local g = snap({ player({ name = 'A', dist = 25 }), player({ name = 'B', hpp = 0 }) }, { PIANISSIMO })
    local quiet = cfg_with({ p1_1 = 'Mage\'s Ballad II', p2_1 = 'Mage\'s Ballad II' })
    quiet.revive.on = false  -- B would be raised
    eq(select(2, decide(g, quiet)), 'nothing to do')
    g = snap({ player({ name = 'A', dist = 18 }) }, { PIANISSIMO })
    eq(decide(g, cfg), '/ma "Mage\'s Ballad II" 101')
    g = snap({ player({ name = 'A' }) }, { PIANISSIMO, INVISIBLE })
    eq(select(2, decide(g, cfg)), 'nothing to do')
end)

test('Hold area buffs: an area song waits for a player who lacks it, the songs on one member with it', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p2_1 = 'Mage\'s Ballad II' }, { hold_aoe = true })
    local mem = {}
    local g = snap({ player({ name = 'Far', dist = 25 }), player({ name = 'B' }) })
    eq(select(2, engine.decide(g, cat, cfg, mem)), 'holding Valor Minuet IV: Far 25.0y away')
    eq(engine.gather(g, cfg, mem), '/p Gather together for Valor Minuet IV')
    -- One with a song of their own isn't waited for: the area song goes.
    cfg.song.p1_1 = 'Mage\'s Ballad'
    eq(decide(g, cfg), '/ma "Valor Minuet IV" <me>')
end)

test('a member\'s own songs and the area ones of one kind are one set', function ()
    -- Area Victory March up on you; your own Advancing March wants a second March.
    local cfg = cfg_with({ area_1 = 'Victory March', me_1 = 'Advancing March' })
    eq(decide(snap({}, { MARCH, PIANISSIMO }), cfg), '/ma "Advancing March" <me>')
    -- No March up: the area one first; one up (which can't be read), the second through Pianissimo.
    eq(decide(snap({}, {}), cfg), '/ma "Victory March" <me>')
    eq(decide(snap({}, { MARCH }), cfg), '/ja "Pianissimo" <me>')
    -- An area Ballad on A, and A's own Ballad II.
    cfg = cfg_with({ area_1 = 'Mage\'s Ballad', p1_1 = 'Mage\'s Ballad II' })
    eq(decide(snap({ player({ name = 'A' }, { BALLAD }) }, { BALLAD, PIANISSIMO }), cfg), '/ma "Mage\'s Ballad II" 101')
    -- One song in both: one Ballad.
    cfg = cfg_with({ area_1 = 'Mage\'s Ballad II', p1_1 = 'Mage\'s Ballad II' })
    eq(select(2, decide(snap({ player({ name = 'A' }, { BALLAD }) }, { BALLAD }), cfg)), 'nothing to do')
end)

test('Hold area buffs with no one near lacking it: the songs on one member still go', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p2_1 = 'Mage\'s Ballad II' }, { hold_aoe = true })
    local g = snap({ player({ name = 'Far', dist = 40 }), player({ name = 'B' }, { MINUET }) }, { MINUET })
    eq(decide(g, cfg), '/ja "Pianissimo" <me>')
end)

test('without Pianissimo a slot\'s own picks take no slot: the area songs are still yours', function ()
    local below = fake.catalog(BRD, 15, WHM, 7, {})
    local cfg = cfg_with({ area_1 = 'Valor Minuet', me_1 = 'Army\'s Paeon', me_2 = 'Knight\'s Minne' })
    local cmd = engine.command(engine.decide(snap({}, {}, { main_lv = 15, sub_lv = 7 }), below, cfg, {}), cfg)
    eq(cmd, '/ma "Valor Minuet" <me>')
end)

-- Song timers ------------------------------------------------------------------

local function song(name) return named(cat, name) end

test('stamps: one per song on each it landed on; one more than the slots pushes out the oldest', function ()
    brd.clear()
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 10, {}, 2)
    brd.landed(song('Victory March'), { 1 }, 20, { [TROUBADOUR] = true }, 2)
    brd.landed(song('Valor Minuet IV'), { 1 }, 30, {}, 2)  -- sung again: its own refreshed, nothing pushed
    eq(brd.stamps()[1], { ['Valor Minuet IV'] = { at = 30, id = MINUET }, ['Victory March'] = { at = 20, id = MARCH, double = true } })
    -- The one that would wear first goes, as the server's: Minuet (ends 150), not
    -- the doubled March that landed before it (ends 260).
    brd.landed(song('Mage\'s Ballad II'), { 1, 101 }, 40, {}, 2)
    eq({ brd.stamps()[1]['Valor Minuet IV'], brd.stamps()[1]['Victory March'].at, brd.stamps()[101]['Valor Minuet IV'].at },
       { nil, 20, 10 })
    brd.landed(song('Victory March'), { 101 }, 50, {}, 1)  -- a subjob's one slot
    eq(brd.stamps()[101], { ['Victory March'] = { at = 50, id = MARCH } })
end)

test('Song Duration: a song is sung again that long after it landed, while it\'s still up', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    cfg.song.duration = 100
    local A = player({ name = 'A' }, { MINUET })
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    eq(select(2, decide(snap({ A }, { MINUET }, { now = 1099 }), cfg)), 'nothing to do')
    local cmd, intent = decide(snap({ A }, { MINUET }, { now = 1100 }), cfg)
    eq({ cmd, intent.why }, { '/ma "Valor Minuet IV" <me>', 'Me +1 are due' })
    -- Off (0), or not a BRD 75 main job: only once it's gone.
    cfg.song.duration = 0
    eq(select(2, decide(snap({ A }, { MINUET }, { now = 1100 }), cfg)), 'nothing to do')
    cfg.song.duration = 100
    eq(select(2, decide(snap({ A }, { MINUET }, { now = 1100, main_lv = 74 }), cfg)), 'nothing to do')
    -- Sung under Troubadour: twice as long.
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, { [TROUBADOUR] = true }, 2)
    eq(select(2, decide(snap({ A }, { MINUET }, { now = 1199 }), cfg)), 'nothing to do')
    eq(decide(snap({ A }, { MINUET }, { now = 1200 }), cfg), '/ma "Valor Minuet IV" <me>')
end)

test('Song Duration: a stamp not yet due holds the song, a member with none goes by their statuses', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    cfg.song.duration = 100
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    -- Just landed: its status not shown yet, the stamp holds it.
    eq(select(2, decide(snap({ player({ name = 'A' }) }, {}, { now = 1002 }), cfg)), 'nothing to do')
    -- B joined after it: no stamp, lacks it.
    local g = snap({ player({ name = 'A' }, { MINUET }), player({ name = 'B' }) }, { MINUET }, { now = 1010 })
    eq(select(2, decide(g, cfg)).why, 'B lacks it')
end)

test('a stamp goes once a list we can read stops showing its song, or its member dies', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    cfg.song.duration = 100
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    -- Dispelled from A past VERIFY: A lacks it again.
    eq(select(2, decide(snap({ player({ name = 'A' }) }, { MINUET }, { now = 1000 + brd.VERIFY }), cfg)).why, 'A lacks it')
    eq(brd.stamps()[101]['Valor Minuet IV'], nil)
    brd.landed(song('Valor Minuet IV'), { 101 }, 1010, {}, 2)
    local quiet = cfg_with({ area_1 = 'Valor Minuet IV' })
    quiet.revive.on = false
    brd.landed(song('Valor Minuet IV'), { 101 }, 1010, {}, 2)
    decide(snap({ player({ name = 'A', hpp = 0 }) }, { MINUET }, { now = 1011 }), quiet)
    eq(brd.stamps()[101], nil)
    -- A trust's statuses can't say: its stamp stands.
    brd.landed(song('Valor Minuet IV'), { 101 }, 1010, {}, 2)
    quiet.song.duration = 100
    eq(select(2, decide(snap({ { name = 'Kupipi', kind = 'trust' } }, { MINUET }, { now = 1050 }), quiet)), 'nothing to do')
    -- Released (no longer in the snapshot): its stamps are forgotten.
    decide(snap({}, { MINUET }, { now = 1051 }), quiet)
    eq(brd.stamps()[101], nil)
end)

test('Song Duration: of two one-kind songs, the one due goes', function ()
    local cfg = cfg_with({ area_1 = 'Victory March', area_2 = 'Advancing March' })
    cfg.song.duration = 100
    brd.landed(song('Victory March'), { 1 }, 1000, { [TROUBADOUR] = true }, 2)  -- landed first, lasts twice as long
    brd.landed(song('Advancing March'), { 1 }, 1010, {}, 2)
    eq(decide(snap({}, { MARCH, MARCH }, { now = 1110 }), cfg), '/ma "Advancing March" <me>')
end)

test('Nightingale and Troubadour up: every song stamped without Troubadour is sung again, once', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    brd.landed(song('Mage\'s Ballad II'), { 101 }, 1005, {}, 2)
    local up = { MINUET, NIGHTINGALE, TROUBADOUR }
    local A = player({ name = 'A' }, { MINUET, BALLAD })
    eq(decide(snap({ A }, up, { now = 1020 }), cfg), '/ma "Valor Minuet IV" <me>')
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1025, { [NIGHTINGALE] = true, [TROUBADOUR] = true }, 2)
    eq(decide(snap({ A }, up, { now = 1030 }), cfg), '/ja "Pianissimo" <me>')
    brd.landed(song('Mage\'s Ballad II'), { 101 }, 1035, { [TROUBADOUR] = true }, 2)
    eq(select(2, decide(snap({ A }, up, { now = 1040 }), cfg)), 'nothing to do')
    -- Troubadour alone: nothing forced.
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1050, {}, 2)
    eq(select(2, decide(snap({ A }, { MINUET, TROUBADOUR }, { now = 1060 }), cfg)), 'nothing to do')
end)

test('Hold area buffs: a far player whose stamp is due but who still has it holds nothing', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV' }, { hold_aoe = true })
    cfg.song.duration = 100
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    local g = snap({ player({ name = 'Far', dist = 25 }, { MINUET }) }, { MINUET }, { now = 1100 })
    eq(decide(g, cfg), '/ma "Valor Minuet IV" <me>')
    -- One who lacks it is still waited for.
    g = snap({ player({ name = 'Far', dist = 25 }) }, { MINUET }, { now = 1100 })
    eq(select(2, decide(g, cfg)), 'holding Valor Minuet IV: Far 25.0y away')
end)

test('a party player with no status list yet (no stacks) keeps their stamps', function ()
    local cfg = cfg_with({ area_1 = 'Valor Minuet IV' })
    cfg.song.duration = 100
    brd.landed(song('Valor Minuet IV'), { 1, 101 }, 1000, {}, 2)
    local A = player({ name = 'A' })
    A.stacks = nil
    decide(snap({ A }, { MINUET }, { now = 1050 }), cfg)
    eq(brd.stamps()[101]['Valor Minuet IV'].at, 1000)
end)

-- Pianissimo fast casting ---------------------------------------------------------

-- Song picks with fast casting on.
local function fast_cfg(picks)
    local cfg = cfg_with(picks)
    cfg.song.fast = true
    return cfg
end

test('fast casting: Pianissimo, then the area song on <me>, Pianissimo cancelled a second into the cast', function ()
    local cfg, mem = fast_cfg({ area_1 = 'Valor Minuet IV' }), {}
    local g = snap({ player({ name = 'A' }) })
    local cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.why }, { '/ja "Pianissimo" <me>', 'for Valor Minuet IV: Me +1 lack it' })
    engine.sent(intent, g, mem)
    cmd, intent = decide(g, cfg, mem)
    eq({ cmd, intent.cancel }, { '/ma "Valor Minuet IV" <me>', PIANISSIMO })
    engine.sent(intent, g, mem)
    g = snap({ player({ name = 'A' }) }, { PIANISSIMO }, { now = g.now + 1, casting = true })
    eq(engine.cancel(g, mem), PIANISSIMO)
    eq(engine.cancel(g, mem), nil, 'once')
end)

test('fast casting: Pianissimo up takes the area song first, then the songs on one member', function ()
    local cfg = fast_cfg({ area_1 = 'Valor Minuet IV', p1_1 = 'Mage\'s Ballad II' })
    eq(decide(snap({ player({ name = 'A' }) }, { PIANISSIMO }), cfg), '/ma "Valor Minuet IV" <me>')
    eq(decide(snap({ player({ name = 'A' }, { MINUET }) }, { MINUET, PIANISSIMO }), cfg), '/ma "Mage\'s Ballad II" 101')
end)

test('fast casting: with Pianissimo on recast the area song goes without it, cancelling nothing', function ()
    local cfg, mem = fast_cfg({ area_1 = 'Valor Minuet IV' }), {}
    local g = snap({}, {}, nil, { Pianissimo = 20 })
    local cmd, intent = decide(g, cfg, mem)
    eq(cmd, '/ma "Valor Minuet IV" <me>')
    engine.sent(intent, g, mem)
    g = snap({}, {}, { now = g.now + 1, casting = true })
    eq(engine.cancel(g, mem), nil)
end)

test('fast casting: not while Nightingale is up; off, Pianissimo up still holds the area songs', function ()
    local cfg = fast_cfg({ area_1 = 'Valor Minuet IV' })
    local cmd, intent = decide(snap({}, { NIGHTINGALE }), cfg)
    eq({ cmd, intent.cancel }, { '/ma "Valor Minuet IV" <me>', nil })
    eq(select(2, decide(snap({}, { NIGHTINGALE, PIANISSIMO }), cfg)), 'nothing to do')
    cfg.song.fast = false
    eq(select(2, decide(snap({}, { PIANISSIMO }), cfg)), 'nothing to do')
end)

test('fast casting: no Pianissimo (under BRD 20), the area songs go as they are', function ()
    local below = fake.catalog(BRD, 15, WHM, 7, {})
    local cfg = fast_cfg({ area_1 = 'Valor Minuet' })
    local intent = engine.decide(snap({}, {}, { main_lv = 15, sub_lv = 7 }), below, cfg, {})
    eq({ intent and intent.action.name, intent and intent.cancel }, { 'Valor Minuet', nil })
end)
