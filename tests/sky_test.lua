-- core/sky.lua: enspell and storm rows following the weather and the day (Match), through the
-- buff behavior and the UI model, over the real catalog.
local sky = require('core.sky')
local settings = require('core.settings')
local model = require('ui.model')
local fake = require('tests.fake')

local RDM, SCH, WHM = 5, 20, 3
local FIRE, ICE, WIND, EARTH, THUNDER, WATER, LIGHT, DARK = 0, 1, 2, 3, 4, 5, 6, 7
-- Weather ids: 0 Clear, 4/5 Hot Spell / Heat Wave .. 16 Auras, 18 Gloom.
local CLEAR, HOT_SPELL, HEAT_WAVE, RAIN, WINDY, SNOW, AURORAS, GLOOM = 0, 4, 5, 6, 10, 12, 16, 18
-- Days: 0 Firesday .. 5 Lightningday, 6 Lightsday, 7 Darksday.
local FIRESDAY, WATERSDAY, ICEDAY, LIGHTSDAY = 0, 2, 4, 6
local FIRESTORM, HAILSTORM, AURORASTORM, THUNDERSTORM_II = 178, 179, 184, 593

local rdm = fake.catalog(RDM, 75, WHM, 37)
local rdm50 = fake.catalog(RDM, 50, WHM, 25)
local rdm20 = fake.catalog(RDM, 20, WHM, 10)
local sch = fake.catalog(SCH, 75, WHM, 37, { 'Light Arts' })

-- The catalog's actions on row `key`.
local function acts(cat, key)
    local out = {}
    for _, a in ipairs(cat) do if settings.key(a) == key then out[#out + 1] = a end end
    return out
end

local function snap(over, buffs, job)
    local g = fake.snap({}, over)
    g.main, g.main_lv, g.sub, g.sub_lv = job or RDM, 75, WHM, 37
    for _, id in ipairs(buffs or {}) do g.me.buffs[id] = true end
    return g
end

local ON = { match = true }

test('the sky\'s elements: weather two ids each, the day, a storm I or II on you', function ()
    eq({ sky.weather(CLEAR), sky.weather(3), sky.weather(HOT_SPELL), sky.weather(HEAT_WAVE), sky.weather(RAIN),
         sky.weather(SNOW), sky.weather(AURORAS), sky.weather(GLOOM + 1), sky.weather(nil) },
       { nil, nil, FIRE, FIRE, WATER, ICE, LIGHT, DARK, nil })
    eq({ sky.day(FIRESDAY), sky.day(1), sky.day(WATERSDAY), sky.day(3), sky.day(ICEDAY), sky.day(5), sky.day(LIGHTSDAY),
         sky.day(7), sky.day(nil) },
       { FIRE, EARTH, WATER, WIND, ICE, THUNDER, LIGHT, DARK, nil })
    eq({ sky.storm({}), sky.storm({ [FIRESTORM] = true }), sky.storm({ [HAILSTORM] = true }),
         sky.storm({ [AURORASTORM] = true }), sky.storm({ [THUNDERSTORM_II] = true }) },
       { nil, FIRE, ICE, LIGHT, THUNDER })
end)

test('only enspells and storms can match, each by the element the client gives the spell', function ()
    eq({ sky.can(acts(rdm, 'enspell')), sky.can(acts(sch, 'storm')), sky.can(acts(rdm, 'barelement')),
         sky.can(acts(rdm, 'spikes')) }, { true, true, false, false })
    eq({ fake.named(sch, 'Firestorm').match, fake.named(rdm, 'Enfire II').match }, { 'weather', 'element' })
end)

test('storms: the zone\'s weather alone, never a storm on you or the day; Match off, nothing', function ()
    local storms = acts(sch, 'storm')
    eq({ sky.pick({}, storms, snap({ weather = HOT_SPELL }, nil, SCH)) }, {})
    eq({ sky.pick(ON, storms, snap({ weather = HOT_SPELL }, nil, SCH)) }, { 'Firestorm', 'weather' })
    eq({ sky.pick(ON, storms, snap({ weather = HEAT_WAVE }, nil, SCH)) }, { 'Firestorm', 'weather' })
    eq({ sky.pick(ON, storms, snap({ weather = AURORAS }, nil, SCH)) }, { 'Aurorastorm', 'weather' })
    -- Its own Hailstorm up doesn't hold it: the weather turned, so does the storm.
    eq({ sky.pick(ON, storms, snap({ weather = RAIN, day = ICEDAY }, { HAILSTORM }, SCH)) }, { 'Rainstorm', 'weather' })
    eq({ sky.pick(ON, storms, snap({ weather = CLEAR, day = FIRESDAY }, { FIRESTORM }, SCH)) }, {})
end)

test('your weather under a storm, as LandSandBoat\'s GetWeather: stacks, outlasted, or replaced', function ()
    eq({ sky.yours(HOT_SPELL, nil), sky.yours(HOT_SPELL, FIRE), sky.yours(HEAT_WAVE, FIRE), sky.yours(HEAT_WAVE, ICE),
         sky.yours(CLEAR, WATER), sky.yours(nil, FIRE) },
       { HOT_SPELL, HEAT_WAVE, HEAT_WAVE, SNOW, RAIN, HOT_SPELL })
end)

test('the enspell bonus: weather +10 / +25 double, the day +10, less for the element that beats it', function ()
    eq({ sky.bonus(FIRE, HOT_SPELL, FIRESDAY), sky.bonus(FIRE, HEAT_WAVE, nil), sky.bonus(FIRE, HOT_SPELL, WATERSDAY),
         sky.bonus(FIRE, HEAT_WAVE, WATERSDAY), sky.bonus(FIRE, RAIN + 1, nil), sky.bonus(ICE, HOT_SPELL, FIRESDAY),
         sky.bonus(LIGHT, AURORAS, LIGHTSDAY), sky.bonus(WATER, CLEAR, nil) },
       { 20, 25, 0, 15, -25, -20, 20, 0 })
end)

test('enspells: what your weather (a storm on you) and the day favor most; a tie, the weather', function ()
    local en = acts(rdm, 'enspell')
    eq({ sky.pick(ON, en, snap({ weather = HOT_SPELL })) }, { 'Enfire II', 'weather' })
    -- Watersday cancels Hot Spell's +10 on fire: Enwater's +10 is ahead. Heat Wave's +25 isn't cancelled.
    eq({ sky.pick(ON, en, snap({ weather = HOT_SPELL, day = WATERSDAY })) }, { 'Enwater II', 'day' })
    eq({ sky.pick(ON, en, snap({ weather = HEAT_WAVE, day = WATERSDAY })) }, { 'Enfire II', 'weather' })
    eq({ sky.pick(ON, en, snap({ weather = SNOW, day = FIRESDAY })) }, { 'Enfire II', 'day' })
    -- A Firestorm on you doubles Hot Spell: +25 over the day's -10.
    eq({ sky.pick(ON, en, snap({ weather = HOT_SPELL, day = WATERSDAY }, { FIRESTORM })) }, { 'Enfire II', 'storm' })
    -- Wind on Firesday: +10 each, so the weather.
    eq({ sky.pick(ON, en, snap({ weather = WINDY, day = FIRESDAY })) }, { 'Enaero II', 'weather' })
    -- A Hailstorm replaces Hot Spell with Snow: +10 ice, tied with Watersday's water.
    eq({ sky.pick(ON, en, snap({ weather = HOT_SPELL, day = WATERSDAY }, { HAILSTORM })) }, { 'Enblizzard II', 'storm' })
    eq({ sky.pick(ON, en, snap({ weather = CLEAR, day = WATERSDAY })) }, { 'Enwater II', 'day' })
    eq({ sky.pick(ON, en, snap({ weather = AURORAS, day = ICEDAY })) }, { 'Enblizzard II', 'day' })
    -- A light storm is your weather, over the zone's fire: light has no enspell, so the day.
    eq({ sky.pick(ON, en, snap({ weather = HOT_SPELL, day = ICEDAY }, { AURORASTORM })) }, { 'Enblizzard II', 'day' })
    eq({ sky.pick(ON, en, snap({ weather = AURORAS, day = LIGHTSDAY })) }, {})
    eq({ sky.pick(ON, en, snap({})) }, {})  -- weather and day unknown
end)

test('enspells: only a tier your level has (RDM 50: Enfire; RDM 20 has no Enfire, so the day)', function ()
    eq({ sky.pick(ON, acts(rdm50, 'enspell'), snap({ weather = HOT_SPELL })) }, { 'Enfire', 'weather' })
    eq({ sky.pick(ON, acts(rdm20, 'enspell'), snap({ weather = HOT_SPELL, day = 3 })) }, { 'Enaero', 'day' })
end)

-- The buff behavior: the enspell row on, on you, with Enblizzard picked.
local function enspell_cfg(match)
    local cfg = settings.defaults()
    cfg.rows.enspell = { on = true, pick = 'Enblizzard', match = match or nil }
    return cfg
end

test('buffs: Match casts the tier the sky picks, the pick when none does; off, the pick', function ()
    local function cast(g, cfg) return (fake.decide(g, rdm, cfg)) end
    eq(cast(snap({ weather = HOT_SPELL }), enspell_cfg(false)), '/ma "Enblizzard" <me>')
    eq(cast(snap({ weather = HOT_SPELL }), enspell_cfg(true)), '/ma "Enfire II" <me>')
    eq(cast(snap({ weather = AURORAS, day = LIGHTSDAY }), enspell_cfg(true)), '/ma "Enblizzard" <me>')
    -- Up already: nothing to do. The sky turns: the new one.
    eq({ fake.decide(snap({ weather = HOT_SPELL }, { 277 }), rdm, enspell_cfg(true)) }, { nil, 'nothing to do' })
    eq(cast(snap({ weather = RAIN }, { 277 }), enspell_cfg(true)), '/ma "Enwater II" <me>')
end)

test('buffs: a pick-one row with Match on and nothing picked goes only while the sky matches', function ()
    local cfg = settings.defaults()
    cfg.rows.enspell = { on = true, match = true }
    eq((fake.decide(snap({ weather = SNOW }), rdm, cfg)), '/ma "Enblizzard II" <me>')
    eq({ fake.decide(snap({ weather = AURORAS, day = LIGHTSDAY }), rdm, cfg) }, { nil, 'nothing to do' })
end)

-- The UI model's view.
local function row_of(cat, cfg, g, key)
    local view = model.build(g, cat, cfg, { running = false, log = true, sent = {} },
        { job = function () return 'RDM' end, statuses = fake.res.statuses })
    for _, s in ipairs(view.sections) do
        for _, r in ipairs(s.rows or {}) do if r.key == (key or 'enspell') then return r end end
    end
end

test('ui: an enspell row has Auto first in its list and says what it matched; a bar-element row has none', function ()
    local r = row_of(rdm, enspell_cfg(false), snap({ weather = HOT_SPELL }))
    eq({ r.match, r.match_rule, r.matched, r.choice, r.action }, { false, 'element', nil, 'Enblizzard', 'Enblizzard' })
    eq({ r.choices[1], r.choices[2].name }, { { label = 'Auto (weather/day)', match = true }, 'Enfire' })
    r = row_of(rdm, enspell_cfg(true), snap({ weather = HOT_SPELL }))
    eq({ r.match, r.matched, r.pick, r.choice, r.ready, r.action },
       { true, 'Enfire II', 'Enblizzard', 'Auto: Enfire II (weather)', true, 'Enfire II' })
    r = row_of(rdm, enspell_cfg(true), snap({ weather = AURORAS, day = LIGHTSDAY }))
    eq({ r.matched, r.choice, r.action }, { nil, 'Auto: Enblizzard', 'Enblizzard' })
    -- Nothing picked: off, pick one; Auto with nothing matching, nothing goes.
    local cfg = settings.defaults()
    cfg.rows.enspell = { on = true }
    eq(row_of(rdm, cfg, snap({ weather = HOT_SPELL })).choice, 'Pick one')
    cfg.rows.enspell.match = true
    r = row_of(rdm, cfg, snap({ weather = AURORAS, day = LIGHTSDAY }))
    eq({ r.choice, r.ready, r.avail }, { 'Auto (weather/day)', false, 'no match' })
    eq(row_of(sch, settings.defaults(), snap({}, nil, SCH), 'storm').choices[1], { label = 'Auto (weather)', match = true })
    local view = model.build(snap({}), rdm, settings.defaults(), { running = false, log = true, sent = {} },
        { job = function () return 'RDM' end, statuses = fake.res.statuses })
    for _, s in ipairs(view.sections) do
        for _, x in ipairs(s.rows or {}) do
            if x.key == 'barelement' then eq(x.match, nil) end
        end
    end
end)

test('ui: act.match sets and clears it, here and from another session (only on a row that can match)', function ()
    local cfg = settings.defaults()
    local act = model.actions(cfg, { running = false, log = true, sent = {} }, function () end)
    act.match('enspell', true)
    eq(cfg.rows.enspell.match, true)
    act.match('enspell', false)
    eq(cfg.rows.enspell.match, nil)
    eq(model.apply(act, cfg, { 'match', 'enspell', true, n = 2 }, rdm), true)
    eq(cfg.rows.enspell.match, true)
    -- A tier picked leaves Auto, here or from another session.
    act.pick('enspell', 'Enfire')
    eq(cfg.rows.enspell.match, nil)
    act.match('enspell', true)
    eq(model.apply(act, cfg, { 'pick', 'enspell', 'Enaero', n = 2 }, rdm), true)
    eq({ cfg.rows.enspell.pick, cfg.rows.enspell.match }, { 'Enaero', nil })
    eq(model.apply(act, cfg, { 'match', 'Cure', true, n = 2 }, rdm), false)
    -- Buff rows that can't follow the sky are refused too.
    eq({ model.apply(act, cfg, { 'match', 'Protect', true, n = 2 }, rdm),
         model.apply(act, cfg, { 'match', 'barelement', true, n = 2 }, rdm) }, { false, false })
    eq({ cfg.rows.Protect, cfg.rows.barelement }, { nil, nil })
end)
