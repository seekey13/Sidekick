-- Beastmaster (jobs/bst.lua): the Ready charge pool, a Ready move's charges
-- from the DAT, and Wild Carrot healing through the engine on them.
local bst = require('jobs.bst')
local engine = require('core.engine')
local settings = require('core.settings')
local fake = require('tests.fake')

local BST, WAR, WHM = 9, 1, 3
local JAS = { 'Wild Carrot', 'Sudden Lunge', 'Reward' }

local function named(list, name)
    for _, a in ipairs(list) do if a.name == name then return a end end
end

local function rabbit(t)
    local p = { name = 'KeenearedSteffi', hpp = 100, dist = 3, pos = { 0, 0, 0 }, status = 0, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

-- BST 75 / `sub` 37 with the rabbit out and `ready` charges banked; members at `hpp`.
-- A Ready move waits as the pool would (bst.charge_wait), as core/game.lua reads it.
local function snap(hpp, sub, ready, over)
    local o = { main = BST, main_lv = 75, sub = sub or WAR, sub_lv = 37, pet = rabbit(), ready = ready }
    for k, v in pairs(over or {}) do o[k] = v end
    local others = {}
    for i = 1, 3 do others[i] = { name = 'P' .. i, hpp = hpp } end
    local g = fake.snap(others, o)
    g.me.mp = sub == WHM and 400 or 0
    local seconds = (3 - (ready or 3)) * 30
    g.recast = function (a) return a.recast == bst.READY and bst.charge_wait(seconds, a.charges) or 0 end
    return g
end

local function decide(g, list, cfg)
    local intent = engine.decide(g, list, cfg or settings.defaults(), {})
    return intent and engine.command(intent, cfg or settings.defaults()), intent
end

test('charges: counted from the pool timer, 30s each of 3; the wait is for the charges a move costs', function ()
    eq({ bst.charges(0), bst.charges(1), bst.charges(30), bst.charges(31), bst.charges(90) }, { 3, 2, 2, 1, 0 })
    eq({ bst.charge_wait(45, 1), bst.charge_wait(45, 2), bst.charge_wait(45), bst.charge_wait(0, 3) }, { 0, 15, 0, 0 })
    eq(bst.charge_wait(90, 3), 90)
end)

test('catalog: a Ready move costs the charges the DAT gives as its MP, and no MP', function ()
    local cat = fake.catalog(BST, 75, WAR, 37, JAS)
    local carrot = named(cat, 'Wild Carrot')
    eq({ carrot.kind, carrot.mp, carrot.charges, carrot.recast }, { 'pet', 0, 2, bst.READY })
    eq({ named(cat, 'Sudden Lunge').mp, named(cat, 'Sudden Lunge').charges }, { 0, 1 })
    eq(named(cat, 'Reward').charges, nil)
    -- BLU's Wild Carrot is a spell: its MP is MP.
    local blu = named(fake.catalog(16, 75, nil, 0), 'Wild Carrot')
    eq({ blu.mp > 0, blu.charges }, { true, nil })
end)

test('Wild Carrot heals the party in danger on a BST with no MP, once two charges are banked', function ()
    local cat = fake.catalog(BST, 75, WAR, 37, JAS)
    local cmd, intent = decide(snap(40, WAR, 2), cat)
    eq({ cmd, intent.behavior }, { '/pet "Wild Carrot" <me>', 'heal' })
    eq(decide(snap(40, WAR, 1), cat), nil)  -- one charge: not enough
    eq(decide(snap(40, WAR, 3, { pet = rabbit({ name = 'FunguarFamiliar' }) }), cat), nil)  -- not a rabbit
end)

test('Wild Carrot only in danger: its charges are kept for the pet\'s attacks on chip damage', function ()
    local cat = fake.catalog(BST, 75, WHM, 37, JAS)
    eq(decide(snap(70, WHM, 3), cat), '/ma "Regen" 101')  -- chip damage, under the heal line: MP, not charges
    eq(decide(snap(40, WHM, 3), cat), '/pet "Wild Carrot" <me>')
    local war = fake.catalog(BST, 75, WAR, 37, JAS)
    local danger = settings.defaults().heal.danger
    eq(decide(snap(danger + 10, WAR, 3), war), nil)  -- no MP heal, and still no carrot over the danger line
    eq(decide(snap(danger - 1, WAR, 3), war), '/pet "Wild Carrot" <me>')
end)
