-- core/util.lua's helpers and can.near: shared by several modules, so a change to
-- one shows up here rather than as a behavior failing far from it.
local can = require('core.can')
local util = require('core.util')

test('clamp holds a number to its range, a NaN at the low end', function ()
    eq({ util.clamp(-1, 0, 10), util.clamp(5, 0, 10), util.clamp(11, 0, 10), util.clamp(0 / 0, 0, 10) }, { 0, 5, 10, 0 })
end)

test('round goes to the nearest whole number, a half up', function ()
    eq({ util.round(2.4), util.round(2.5), util.round(-2.5), util.round(-2.6) }, { 2, 3, -2, -3 })
end)

test('contains finds a value in a list', function ()
    eq({ util.contains({ 'a', 'b' }, 'b'), util.contains({ 'a', 'b' }, 'c'), util.contains({}, 'a') }, { true, false, false })
end)

test('a shallow copy is a new table, its values shared', function ()
    local inner = {}
    local t = { 1, k = inner }
    local c = util.shallow_copy(t)
    eq({ c ~= t, c[1], rawequal(c.k, inner) }, { true, 1, true })
end)

test('an overlay reads its own fields, else the base\'s, and never writes the base', function ()
    local base = { a = 1, b = 2 }
    local o = util.overlay(base, { b = 3 })
    o.c = 4
    eq({ o.a, o.b, o.c, base.b }, { 1, 3, 4, 2 })
    eq(base.c, nil)
end)

test('catalog records sort by level, or by priority and then level', function ()
    local low, high, first = { name = 'low', level = 10, priority = 0 }, { name = 'high', level = 50, priority = 0 },
                             { name = 'first', level = 1, priority = 5 }
    local list = { low, first, high }
    table.sort(list, util.by_level)
    eq({ list[1].name, list[2].name, list[3].name }, { 'high', 'low', 'first' })
    table.sort(list, util.by_priority)
    eq({ list[1].name, list[2].name, list[3].name }, { 'first', 'high', 'low' })
end)

test('capitalize makes a lower-case first letter a capital', function ()
    eq({ util.capitalize('medium'), util.capitalize('Heal'), util.capitalize(''), util.capitalize('1st') },
       { 'Medium', 'Heal', '', '1st' })
end)

test('near: you always are, another within the radius is, and one with no distance (not drawn) never is', function ()
    eq({ can.near({ kind = 'self' }, 0), can.near({ kind = 'party', dist = 10 }, 10),
         can.near({ kind = 'party', dist = 10.5 }, 10), can.near({ kind = 'party' }, 1e9) },
       { true, true, false, false })
end)
