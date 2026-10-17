-- core/profiles.lua: named snapshots of a job pair's settings, as v2's. Live
-- settings stay the working copy; Default brings back the one parked at a load.
local profiles = require('core.profiles')
local settings = require('core.settings')
local model = require('ui.model')

local function cfg_with(fn)
    local cfg = settings.defaults()
    if fn then fn(cfg) end
    return cfg
end

test('save keeps the settings as they are now; later changes stay out of it', function ()
    local cfg = cfg_with(function (c) c.heal.danger = 40 end)
    eq(profiles.save(cfg, 'Dynamis'), true)
    eq({ profiles.active(cfg), profiles.names(cfg) }, { 'Dynamis', { 'Dynamis' } })
    cfg.heal.danger = 70
    eq(cfg.profiles.Dynamis.heal.danger, 40)
end)

test('a profile never holds the profiles, the HUD, the language, following, the focus, who is skipped or Entrust\'s member', function ()
    local cfg = cfg_with(function (c)
        c.ui.japanese, c.follow.on, c.follow.target, c.heal.focus, c.heal.skip.Kupipi = true, true, 'A', 'B', true
        c.geo.entrust, c.geo.entrust_spell = 'Tank', 'Indi-Fury'
        c.rows.Haste = { on = true, targets = { [0] = true, [3] = true } }
    end)
    profiles.save(cfg, 'EXP')
    profiles.save_as(cfg, 'Two')
    local snap = cfg.profiles.Two
    eq({ snap.profiles, snap.profile, snap.parked, snap.ui, snap.follow, snap.heal.focus, snap.heal.skip },
        { nil, nil, nil, nil, nil, nil, nil })
    eq(snap.rows.Haste, { on = true, targets = { [0] = true, [3] = true } })
    eq({ snap.geo.entrust, snap.geo.entrust_spell }, { nil, 'Indi-Fury' })
    eq(snap.heal.danger, 50)
end)

test('loading from Default parks the working copy; Default brings it back, and loads keep what is kept', function ()
    local cfg = cfg_with(function (c) c.heal.danger = 40; c.rows.Cure = { on = false } end)
    profiles.save_as(cfg, 'Dynamis')
    profiles.load_default(cfg)
    cfg.heal.danger, cfg.rows.Cure, cfg.heal.focus, cfg.ui.hp_width = 60, nil, 'Kupipi', 300
    local same_heal, same_ui = cfg.heal, cfg.ui
    eq(profiles.load(cfg, 'Dynamis'), true)
    eq({ cfg.heal.danger, cfg.rows.Cure, cfg.heal.focus, cfg.ui.hp_width, cfg.profile }, { 40, { on = false }, 'Kupipi', 300, 'Dynamis' })
    eq(rawequal(cfg.ui, same_ui), true, 'the HUD table is kept')
    eq(rawequal(cfg.heal, same_heal), false, 'heal is the profile\'s')
    cfg.heal.danger = 45  -- a tweak goes to the working copy, never the profile
    eq(cfg.profiles.Dynamis.heal.danger, 40)
    profiles.load_default(cfg)
    eq({ cfg.heal.danger, cfg.rows.Cure, cfg.heal.focus, cfg.profile, cfg.parked }, { 60, nil, 'Kupipi', '', {} })
end)

test('going from one profile to another keeps the Default parked from before the first', function ()
    local cfg = cfg_with()
    cfg.recover.mp = 20
    profiles.save_as(cfg, 'A')
    cfg.recover.mp = 40
    profiles.save_as(cfg, 'B')
    profiles.load_default(cfg)
    cfg.recover.mp = 99
    profiles.load(cfg, 'A')
    profiles.load(cfg, 'B')
    eq(cfg.recover.mp, 40)
    profiles.load_default(cfg)
    eq(cfg.recover.mp, 99)
end)

test('a Save from Default parks nothing, so the next load parks the working copy for Default', function ()
    local cfg = cfg_with(function (c) c.heal.danger = 42 end)
    profiles.save(cfg, 'A')
    cfg.heal.danger = 41
    profiles.save_as(cfg, 'B')
    cfg.heal.danger = 43
    profiles.load(cfg, 'A')
    profiles.load(cfg, 'B')
    profiles.load_default(cfg)
    eq(cfg.heal.danger, 43)
end)

test('a profile saved before newer settings existed gets their defaults', function ()
    local cfg = cfg_with()
    cfg.profiles.Old = { heal = { danger = 35 }, rows = {} }
    profiles.load(cfg, 'Old')
    eq({ cfg.heal.danger, cfg.heal.critical, cfg.buff.hold_aoe, cfg.rest.delay }, { 35, 30, false, 5 })
end)

test('save under another name while one is loaded renames it; with Default loaded it adds one', function ()
    local cfg = cfg_with(function (c) c.heal.danger = 40 end)
    profiles.save(cfg, 'Dyna')
    cfg.heal.danger = 70
    profiles.save(cfg, 'Dynamis')
    eq({ profiles.names(cfg), cfg.profiles.Dynamis.heal.danger, cfg.profile }, { { 'Dynamis' }, 40, 'Dynamis' })
    profiles.save(cfg, 'Dynamis')
    eq(cfg.profiles.Dynamis.heal.danger, 70)
    profiles.load_default(cfg)
    profiles.save(cfg, 'EXP')
    eq(profiles.names(cfg), { 'Dynamis', 'EXP' })
end)

test('Save never lands on another profile, renaming or adding; Save as replaces it', function ()
    local cfg = cfg_with(function (c) c.heal.danger = 10 end)
    profiles.save_as(cfg, 'X')
    cfg.heal.danger = 20
    profiles.save_as(cfg, 'Y')
    profiles.load(cfg, 'X')
    eq(profiles.save(cfg, 'Y'), false)  -- X renamed onto Y
    profiles.load_default(cfg)
    eq(profiles.save(cfg, 'Y'), false)  -- a new one over Y
    eq({ cfg.profiles.X.heal.danger, cfg.profiles.Y.heal.danger }, { 10, 20 })
    cfg.heal.danger = 30
    eq(profiles.save_as(cfg, 'Y'), true)
    eq(cfg.profiles.Y.heal.danger, 30)
end)

test('no profile is blank or named Default; find takes any case, an exact match first', function ()
    local cfg = cfg_with()
    eq({ profiles.save(cfg, ''), profiles.save_as(cfg, 'default'), profiles.save(cfg, 'DEFAULT') }, { false, false, false })
    eq(next(cfg.profiles), nil)
    profiles.save_as(cfg, 'tank')
    profiles.save_as(cfg, 'Tank')
    eq({ profiles.find(cfg, 'Tank'), profiles.find(cfg, 'tank') }, { 'Tank', 'tank' })
    eq({ profiles.find(cfg, 'TANK') ~= nil, profiles.find(cfg, 'heal'), profiles.find(cfg, 'default') }, { true, nil, nil })
    eq(profiles.names(cfg)[1]:lower(), 'tank')
    profiles.save_as(cfg, 'Sky  Two')
    eq(profiles.find(cfg, 'sky two'), 'Sky  Two')  -- as /sk3 profile joins its words
end)

test('new resets the working copy to the defaults on Default; delete of the loaded one goes back to Default', function ()
    local cfg = cfg_with(function (c) c.heal.danger, c.ui.japanese = 40, true end)
    profiles.save_as(cfg, 'A')
    profiles.new(cfg)
    eq({ cfg.heal.danger, cfg.ui.japanese, cfg.profile, profiles.names(cfg) }, { 50, true, '', { 'A' } })
    cfg.heal.danger = 65
    profiles.load(cfg, 'A')
    eq(profiles.delete(cfg, 'A'), true)
    eq({ cfg.heal.danger, cfg.profile, profiles.names(cfg) }, { 65, '', {} })
    eq(profiles.delete(cfg, 'A'), false)
end)

test('the active profile is the loaded one that still exists', function ()
    local cfg = cfg_with()
    cfg.profile = 'Gone'
    eq(profiles.active(cfg), nil)
end)

test('the view lists the profiles and the loaded one; act loads, saves, renames, resets and deletes them', function ()
    local cfg = cfg_with()
    local writes = 0
    local act = model.actions(cfg, { sent = {} }, function () writes = writes + 1 end, {})
    act.save_profile('Dynamis')
    act.save_profile('', true)  -- no name: nothing saved
    eq({ cfg.profile, writes }, { 'Dynamis', 1 })
    cfg.heal.danger = 33
    act.save_profile('EXP', true)
    act.profile(nil)
    act.profile('Dynamis')
    eq({ cfg.heal.danger, cfg.profile }, { 50, 'Dynamis' })
    act.new_profile()
    act.delete_profile('EXP')
    eq({ profiles.names(cfg), cfg.profile, writes }, { { 'Dynamis' }, '', 6 })
    local view = model.build(require('tests.fake').snap({ { name = 'A' } }), {}, cfg, { sent = {} },
        { job = function () return 'WHM' end, statuses = {} })
    eq(view.profiles, { names = { 'Dynamis' } })
end)
