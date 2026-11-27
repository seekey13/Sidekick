-- core/buffs.lua: packet-fed statuses expire on their own.
local buffs = require('core.buffs')

test('a gained status shows until its duration runs out', function ()
    buffs.clear()
    buffs.gain(7, 40, 100, 1800)
    eq(buffs.of(7, 1899), { [40] = true })
    eq(buffs.of(7, 1900), {})
end)

test('without a known duration a status still expires', function ()
    buffs.clear()
    buffs.gain(7, 33, 0)
    eq(buffs.of(7, buffs.DEFAULT_SECONDS - 1), { [33] = true })
    eq(buffs.of(7, buffs.DEFAULT_SECONDS), {})
end)

test('lose and clear drop statuses; unknown units have none', function ()
    buffs.clear()
    buffs.gain(7, 40, 0); buffs.gain(7, 41, 0)
    buffs.lose(7, 40)
    eq(buffs.of(7, 1), { [41] = true })
    buffs.clear()
    eq(buffs.of(7, 1), {})
    eq(buffs.of(99, 1), {})
end)

test('a known duration: the seconds left till it runs out, then none; lost, forgotten or gone from the list, none', function ()
    buffs.clear()
    buffs.timed(7, 40, 100, 1800)
    eq({ buffs.left(7, 40, 100), buffs.left(7, 40, 1000), buffs.left(7, 41, 1000), buffs.left(8, 40, 1000) },
       { 1800, 900, nil, nil })
    eq({ buffs.left(7, 40, 1900), buffs.left(7, 40, 1000) }, { nil, nil })  -- run out: still on, it lasted longer
    eq(buffs.of(7, 1000), {})  -- automation's statuses are apart
    buffs.timed(7, 40, 0, 60); buffs.timed(7, 41, 0, 60); buffs.timed(8, 40, 0, 60)
    buffs.lose(7, 40)
    eq({ buffs.left(7, 40, 1), buffs.left(7, 41, 1) }, { nil, 59 })
    buffs.keep(7, { [42] = true })  -- 41 isn't on them now: it wore off
    eq(buffs.left(7, 41, 1), nil)
    buffs.forget(8)
    eq(buffs.left(8, 40, 1), nil)
    buffs.timed(7, 214, 0, 120, true); buffs.timed(7, 214, 10, 60, true)  -- songs of a kind: the later end stands
    eq(buffs.left(7, 214, 10), 110)
    -- Its end is kept in whole seconds: two ending within the same second have the same time left at every moment,
    -- so the HUD's order of them holds as the seconds tick.
    buffs.timed(7, 33, 0.6, 180); buffs.timed(7, 43, 0.3, 180)
    eq({ buffs.left(7, 33, 100.2), buffs.left(7, 43, 100.2), buffs.left(7, 33, 100.7), buffs.left(7, 43, 100.7) },
       { 79.8, 79.8, 79.3, 79.3 })
end)

test('a unit forgotten (dead, or the pet gone) has none; others keep theirs', function ()
    buffs.clear()
    buffs.gain(7, 2, 0); buffs.gain(8, 2, 0)
    buffs.forget(7)
    eq({ buffs.of(7, 1), buffs.of(8, 1) }, { {}, { [2] = true } })
end)
