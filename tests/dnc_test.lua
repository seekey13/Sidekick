-- Dancer (jobs/dnc.lua): the stances' blocks, Trance's free TP, and finishing moves past five.
local can = require('core.can')
local settings = require('core.settings')
local fake = require('tests.fake')

local DNC, WHM = 19, 3
local SABER, FAN, TRANCE = 410, 411, 376
local FM4, FM5, FM6 = 384, 385, 588  -- Finishing Move (4), (5), (6+)
local cat = fake.catalog(DNC, 75, WHM, 37, { 'Curing Waltz', 'Curing Waltz II', 'Curing Waltz III',
    'Curing Waltz IV', 'Divine Waltz', 'Healing Waltz', 'Drain Samba', 'Aspir Samba', 'Haste Samba',
    'Saber Dance', 'Fan Dance', 'No Foot Rise', 'Reverse Flourish', 'Presto' })

local named = fake.named

-- DNC 75 / WHM 37 with `tp`, these statuses on you, and `others`; `over` sets snapshot fields.
local function snap(tp, buffs, others, over)
    local o = { main = DNC, main_lv = 75, sub = WHM, sub_lv = 37 }
    for k, v in pairs(over or {}) do o[k] = v end
    local g = fake.snap(others, o)
    g.me.tp = tp
    for _, id in ipairs(buffs or {}) do g.me.buffs[id] = true end
    return g
end

-- Rows on: { ['Saber Dance'] = true, samba = 'Haste Samba', ... } (a string picks the spell).
local function cfg_with(rows)
    local cfg = settings.defaults()
    for key, v in pairs(rows or {}) do cfg.rows[key] = { on = true, pick = type(v) == 'string' and v or nil } end
    return cfg
end

local function decide(g, cfg) return fake.decide(g, cat, cfg) end

test('catalog: Trance waives waltzes and Aspir Samba; stances name what they block', function ()
    eq({ named(cat, 'Curing Waltz III').trance, named(cat, 'Divine Waltz').trance,
         named(cat, 'Healing Waltz').trance, named(cat, 'Aspir Samba').trance },
       { true, true, true, true })
    eq({ named(cat, 'Drain Samba').trance, named(cat, 'Haste Samba').trance }, { nil, nil })
    eq({ named(cat, 'Curing Waltz').names, named(cat, 'Haste Samba').names },
       { { [SABER] = 'Saber Dance' }, { [FAN] = 'Fan Dance' } })
    eq({ named(cat, 'Reverse Flourish').requires, named(cat, 'No Foot Rise').status }, { { FM5, FM6 }, { FM5, FM6 } })
end)

test('Saber Dance: no waltz, and the row says why; the subjob cure heals instead', function ()
    local g = snap(1000, { SABER }, { { name = 'A', hpp = 45 } })
    eq({ can.use(named(cat, 'Curing Waltz II'), g) }, { false, 'blocked by Saber Dance' })
    eq(decide(g), '/ma "Cure III" 101')
    g.me.buffs[SABER] = nil
    eq(decide(g), '/ja "Curing Waltz IV" 101')
end)

test('Fan Dance: no samba', function ()
    local g = snap(1000, { FAN }, {}, { combat = true })
    eq({ can.use(named(cat, 'Haste Samba'), g) }, { false, 'blocked by Fan Dance' })
    eq(decide(g, cfg_with({ samba = 'Haste Samba' })), nil)
end)

test('Trance: a waltz at no TP, the biggest one, since it costs nothing', function ()
    local g = snap(0, {}, { { name = 'A', hpp = 45 } })
    eq(decide(g), '/ma "Cure III" 101')  -- no TP, no waltz
    g.me.buffs[TRANCE] = true
    eq(can.use(named(cat, 'Curing Waltz IV'), g), true)
    eq(decide(g), '/ja "Curing Waltz IV" 101')
end)

test('Trance: a free waltz beats Regen for chip damage', function ()
    local g = snap(0, {}, { { name = 'A', hpp = 70 } })
    eq(decide(g), '/ma "Regen" 101')
    g.me.buffs[TRANCE] = true
    eq(decide(g), '/ja "Curing Waltz III" 101')
end)

test('Trance: Aspir Samba at no TP; Drain and Haste Samba still want theirs', function ()
    local g = snap(0, { TRANCE }, {}, { combat = true })
    eq(decide(g, cfg_with({ samba = 'Aspir Samba' })), '/ja "Aspir Samba" <me>')
    eq({ can.use(named(cat, 'Haste Samba'), g) }, { false, 'TP' })
    eq(decide(g, cfg_with({ samba = 'Haste Samba' })), nil)
end)

test('sambas and Presto go in combat only', function ()
    local cfg = cfg_with({ samba = 'Haste Samba', Presto = true })
    eq({ can.use(named(cat, 'Haste Samba'), snap(1000)) }, { false, 'combat only' })
    eq(decide(snap(1000), cfg), nil)
    eq(decide(snap(1000, {}, {}, { combat = true }), cfg), '/ja "Haste Samba" <me>')
    eq(decide(snap(1000), cfg_with({ Presto = true })), nil)
    eq(decide(snap(1000, {}, {}, { combat = true }), cfg_with({ Presto = true })), '/ja "Presto" <me>')
end)

test('Trance: a sleeper is woken with a free waltz rather than a cure', function ()
    local g = snap(1000, {}, { { name = 'A', buffs = { [2] = true } } })
    eq(decide(g), '/ma "Cure" 101')  -- 8 MP beats 200 TP
    g.me.buffs[TRANCE] = true
    eq(decide(g), '/ja "Curing Waltz" 101')
end)

test('finishing moves: Reverse Flourish at five or more, No Foot Rise under five', function ()
    local g = snap(200, { FM4 }, {}, { combat = true })
    eq({ can.use(named(cat, 'Reverse Flourish'), g) }, { false, 'needs Finishing Move (5)' })
    local cfg = cfg_with({ ['No Foot Rise'] = true })
    eq(decide(g, cfg), '/ja "No Foot Rise" <me>')
    for _, fm in ipairs({ FM5, FM6 }) do
        g = snap(200, { fm }, {}, { combat = true })
        eq(decide(g, cfg), '/ja "Reverse Flourish" <me>')
        g.me.tp = 1500  -- over the TP line: No Foot Rise has nothing to add
        eq(decide(g, cfg), nil)
    end
end)
