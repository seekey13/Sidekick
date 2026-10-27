-- Beastmaster (jobs/bst.lua): the Ready charge pool, a Ready move's charges
-- from the DAT, and Wild Carrot healing through the engine on them.
local bst = require('jobs.bst')
local settings = require('core.settings')
local fake = require('tests.fake')

local BST, WAR, WHM = 9, 1, 3
local JAS = { 'Wild Carrot', 'Sudden Lunge', 'Reward' }

local named = fake.named

local function rabbit(t)
    local p = { name = 'KeenearedSteffi', hpp = 100, dist = 3, pos = { 0, 0, 0 }, status = 0, buffs = {} }
    for k, v in pairs(t or {}) do p[k] = v end
    return p
end

-- BST 75 / `sub` 37 with the rabbit out and `ready` charges banked; members at `hpp`.
-- A Ready move waits as the pool would (bst.POOL:wait), as core/game.lua reads it.
local function snap(hpp, sub, ready, over)
    local o = { main = BST, main_lv = 75, sub = sub or WAR, sub_lv = 37, pet = rabbit(), ready = ready }
    for k, v in pairs(over or {}) do o[k] = v end
    local others = {}
    for i = 1, 3 do others[i] = { name = 'P' .. i, hpp = hpp } end
    local g = fake.snap(others, o)
    g.me.mp = sub == WHM and 400 or 0
    local seconds = (3 - (ready or 3)) * 30
    g.recast = function (a) return bst.POOL:spends(a) and bst.POOL:wait(seconds, 75, a.charges) or 0 end
    return g
end

local function decide(g, list, cfg) return fake.decide(g, list, cfg) end

test('charges: counted from the pool timer, 30s each of 3; the wait is for the charges a move costs', function ()
    local p = bst.POOL
    eq({ p:banked(0, 75), p:banked(1, 75), p:banked(30, 75), p:banked(31, 75), p:banked(90, 75), p:banked(0, 1) },
       { 3, 2, 2, 1, 0, 3 })
    eq({ p:wait(45, 75, 1), p:wait(45, 75, 2), p:wait(45, 75), p:wait(0, 75, 3) }, { 0, 15, 0, 0 })
    eq({ p:wait(90, 75, 3), p:banked(0, 0), p:wait(45, 0) }, { 90, 0, 45 })  -- off BST: no pool
end)

test('catalog: a Ready move costs the charges the DAT gives as its MP, and no MP', function ()
    local cat = fake.catalog(BST, 75, WAR, 37, JAS)
    local carrot = named(cat, 'Wild Carrot')
    eq({ carrot.kind, carrot.mp, carrot.charges, carrot.recast }, { 'pet', 0, 2, bst.POOL.recast })
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

-- The client lists a Ready move only for the jug that has it (core/catalog.lua's `learn`).
test('Wild Carrot the client doesn\'t list is never sent, and healing goes on without it', function ()
    local cat = fake.catalog(BST, 75, WHM, 37, {})  -- no Ready move listed when the catalog was built
    eq(named(cat, 'Wild Carrot', 'heal') ~= nil, true)
    eq(decide(snap(40, WHM, 3), cat), '/pet "Wild Carrot" <me>')
    local g = snap(40, WHM, 3)
    g.listed = function (a) return a.name ~= 'Wild Carrot' end
    eq(decide(g, cat):match('^/ma '), '/ma ')
end)

test('sending the pet in: one the client doesn\'t list (Deploy for a jug) gives way to the next', function ()
    local PUP = 18
    local cat = fake.catalog(BST, 75, PUP, 37, {})
    local cfg = settings.defaults()
    cfg.rows.Deploy, cfg.rows.Fight = { on = true }, { on = true }
    local g = snap(100, PUP, 3, { bt = { mob = true, hpp = 100, dist = 3, name = 'Crab', sid = 9 }, combat = true })
    g.listed = function (a) return a.name == 'Fight' end
    eq(decide(g, cat, cfg), '/pet "Fight" <bt>')
    g.listed = function () return false end
    eq(decide(g, cat, cfg), nil)
end)
