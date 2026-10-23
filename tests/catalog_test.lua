-- core/catalog.lua against the dumped client DATs (tests/data). Job-wide parity
-- with v2 lives in tools/parity.lua; this covers what parity can't: subjobs,
-- SCH's Addendum gate, level and learned gating, and name parsing.
local catalog = require('core.catalog')
local K = require('core.knowledge')
local res = {
    spells = dofile('tests/data/spells.lua'),
    abilities = dofile('tests/data/abilities.lua'),
    statuses = dofile('tests/data/statuses.lua'),
}

local WHM, BLM, RDM, BLU, SCH, BST, MNK = 3, 4, 5, 16, 20, 9, 2

-- Catalog for main/sub at the given levels; every spell learned unless `unlearned`
-- names it; abilities only those named in `jas`.
local function build(main, main_lv, sub, sub_lv, jas, unlearned)
    local has = {}
    for _, n in ipairs(jas or {}) do has[n] = true end
    return catalog.build(res, {
        main = main, main_lv = main_lv, sub = sub, sub_lv = sub_lv or 0,
        has_spell = function (id) return not (unlearned and unlearned[res.spells[id].en]) end,
        has_ability = function (id) return has[res.abilities[id].en] == true end,
    }, K)
end

local find = require('tests.fake').named

test('split parses roman and ninjutsu tiers, leaves other names alone', function ()
    eq({ catalog.split('Cure IV') }, { 'Cure', 4 })
    eq({ catalog.split('Utsusemi: Ni') }, { 'Utsusemi', 2 })
    eq({ catalog.split('Haste') }, { 'Haste', 1 })
    eq({ catalog.split('Addendum: White') }, { 'Addendum: White', 1 })
    eq({ catalog.split('Geo-INT') }, { 'Geo-INT', 1 })
end)

test('WHM 75 Cure IV: heal from main, DAT level/cost, tier potency', function ()
    local a = find(build(WHM, 75), 'Cure IV')
    eq({ a.role, a.from, a.level, a.mp, a.potency, a.wakes }, { 'heal', 'main', 41, 88, 400, true })
end)

test('level gates spells: WHM 40 has no Cure IV', function ()
    eq(find(build(WHM, 40), 'Cure IV'), nil)
end)

test('unlearned spells are left out', function ()
    eq(find(build(WHM, 75, nil, 0, nil, { ['Cure IV'] = true }), 'Cure IV'), nil)
end)

test('subjob spells come from the sub at its level', function ()
    local cat = build(BLM, 75, WHM, 37)
    eq(find(cat, 'Cure III').from, 'sub')
    eq(find(cat, 'Cure IV'), nil)  -- WHM 41
end)

test('buff status: family name, explicit name, and the full name for tier II', function ()
    local cat = build(RDM, 75, WHM, 37)
    eq(find(cat, 'Protect IV').status, { 40 })
    eq(find(cat, 'Enfire II').status, { 277 })  -- "Enfire II", not Enfire's 94
    eq(find(build(WHM, 75), 'Protectra V').status, { 40 })
end)

test('SCH Addendum spells need Addendum or Enlightenment when only SCH can cast them', function ()
    eq(find(build(SCH, 75), 'Poisona').requires, { 401, 416 })
    eq(find(build(SCH, 75), 'Sleep').requires, { 402, 416 })  -- Addendum: Black
    eq(find(build(SCH, 75), 'Raise').requires, nil)           -- plain Raise needs nothing
end)

test('a knowledge row that would require more of an Addendum spell is refused, not dropped', function ()
    local k = setmetatable({ Poisona = { role = 'remove', removes = 'Poison', requires = 'Composure' } }, { __index = K })
    local ok, err = pcall(catalog.build, res, { main = SCH, main_lv = 75, sub_lv = 0,
        has_spell = function () return true end, has_ability = function () return false end }, k)
    eq({ ok, (tostring(err):match('Poisona: .*')) }, { false, 'Poisona: an Addendum spell can\'t require more' })
end)

test('a non-SCH source drops the Addendum gate (SCH/WHM, WHM/SCH)', function ()
    eq(find(build(SCH, 75, WHM, 37), 'Poisona').requires, nil)  -- WHM sub casts it at 6
    eq(find(build(WHM, 75, SCH, 37), 'Poisona').requires, nil)
    eq(find(build(SCH, 75, WHM, 37), 'Raise II').requires, { 401, 416 })  -- WHM 56, sub too low
end)

test('one action, several uses: Chakra heals and cures', function ()
    local cat = build(MNK, 75, nil, 0, { 'Chakra' })
    eq(find(cat, 'Chakra', 'heal') ~= nil, true)
    eq(find(cat, 'Chakra', 'remove').removes, { 3, 5 })
end)

test('kind-specific uses: BLU Wild Carrot heals, BST Wild Carrot is a pet move', function ()
    local blu = find(build(BLU, 75), 'Wild Carrot')
    eq({ blu.kind, blu.role, blu.potency }, { 'ma', 'heal', 120 })
    local bst = find(build(BST, 75, nil, 0, { 'Wild Carrot' }), 'Wild Carrot')
    eq({ bst.kind, bst.role, bst.area }, { 'pet', 'heal', 8 })
end)

test('heal fields: cast seconds, Regen ticks, boosts with their status', function ()
    local cat = build(WHM, 75, nil, 0, { 'Divine Seal' })
    eq({ find(cat, 'Cure V').cast, find(cat, 'Curaga').area, find(cat, 'Cure').skill }, { 2.5, 8, 33 })
    eq({ find(cat, 'Regen III', 'heal').tick, find(cat, 'Regen III', 'heal').status }, { 20, { 42 } })
    eq(find(cat, 'Regen III', 'buff').label, 'Regen (keep up)')
    local ds = find(cat, 'Divine Seal')
    eq({ ds.boost, ds.status }, { { kind = 'cure', factor = 2, mp = 1 }, { 78 } })
    eq(find(build(SCH, 75, nil, 0, { 'Accession' }), 'Accession').boost,
        { kind = 'healing', factor = 1, area = 10, mp = 2, tiers = 4 })
end)

test('items: last, used on you, specific first, spelled as the client does', function ()
    local named = { spells = res.spells, abilities = res.abilities, statuses = res.statuses,
                    items = { [5356] = { en = 'Rmdy. Ointment', jp = '' } } }
    local cat = catalog.build(named, { main = BLM, main_lv = 75, sub_lv = 0,
        has_spell = function () return true end, has_ability = function () return false end }, K)
    local tail = {}
    for i = #cat - 8, #cat do tail[#tail + 1] = cat[i].name end
    eq(tail, { 'Antidote', 'Eye Drops', 'Echo Drops', 'Holy Water', 'Tincture', 'Hallowed Water',
               'Rmdy. Ointment', 'Remedy', 'Panacea' })
    eq(cat[#cat - 9].kind ~= 'item', true)
    local echo = find(cat, 'Echo Drops')
    eq({ echo.kind, echo.role, echo.id, echo.removes, echo.targets }, { 'item', 'remove', 4151, { 6 }, 1 })
    eq(find(cat, 'Rmdy. Ointment').family, 'Remedy Ointment')
end)

test('families without knowledge are listed with no role', function ()
    local a = find(build(BLM, 75), 'Fire IV')
    eq({ a ~= nil, a and a.role }, { true, nil })
end)

test('trust spells are not catalogued', function ()
    eq(find(build(WHM, 75), 'Shantotto'), nil)
end)

-- Pet commands leave HasAbility while no pet is out. A PUP still has every
-- maneuver, once; Deploy and the rest of the pet commands do not.
test('a PUP has every maneuver even when the client lists none', function ()
    local PUP, WAR = 18, 1
    local names = {}
    for _, a in ipairs(build(PUP, 75, nil, 0, {})) do
        if a.role == 'maneuver' then names[#names + 1] = a.name end
    end
    eq(names, { 'Fire Maneuver', 'Ice Maneuver', 'Wind Maneuver', 'Earth Maneuver',
                'Thunder Maneuver', 'Water Maneuver', 'Light Maneuver', 'Dark Maneuver' })
    local n = 0
    for _, a in ipairs(build(PUP, 75, nil, 0, { 'Fire Maneuver' })) do
        if a.name == 'Fire Maneuver' then n = n + 1 end
    end
    eq(n, 1)
    eq(find(build(PUP, 75, nil, 0, {}), 'Deploy'), nil)
    eq(find(build(WAR, 75, PUP, 37, {}), 'Ice Maneuver').role, 'maneuver')
    eq(find(build(WHM, 75, nil, 0, {}), 'Fire Maneuver'), nil)
end)

test('MP cost is the client\'s, even where the CatsEyeXI server lists another', function ()
    eq(find(build(WHM, 75), 'Arise').mp, 150)  -- server spell_list says 300
end)
