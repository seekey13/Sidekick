-- core/settings.lua's files, against a fake of Ashita's settings library: `ui`
-- has its own, shared by every job pair, and a relog's fresh tables are noticed.

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- As Ashita's library does: the file's values, the defaults for the rest.
local function merge(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = copy(v)
        elseif type(v) == 'table' and type(t[k]) == 'table' then merge(t[k], v) end
    end
    return t
end

-- files = { [alias] = what is on disk }.
local function fake_lib(files)
    local lib = { cache = {}, files = files or {} }
    function lib.load(defaults, alias)
        lib.cache[alias] = merge(copy(lib.files[alias] or {}), defaults)
        return lib.cache[alias]
    end
    function lib.save(alias) lib.files[alias] = copy(lib.cache[alias]) end
    function lib.get(alias) return lib.cache[alias] end
    -- A logout and login: every cached table saved, then loaded again into a new one.
    function lib.relog()
        for alias, t in pairs(lib.cache) do
            lib.files[alias] = copy(t)
            lib.cache[alias] = copy(t)
        end
    end
    return lib
end

-- fn(settings, lib) with a fresh core/settings.lua on a fake library.
local function with_lib(files, fn)
    local lib, old_T = fake_lib(files), rawget(_G, 'T')
    rawset(_G, 'T', function (t) return t end)
    package.loaded['settings'] = lib
    local ok, err = pcall(fn, dofile('core/settings.lua'), lib)
    package.loaded['settings'] = nil
    rawset(_G, 'T', old_T)
    if not ok then error(err, 0) end
end

test('ui loads from and saves to its own file, never the job pair\'s; an old pair file\'s ui is dropped', function ()
    with_lib({ WHM_BLM = { heal = { danger = 40 }, ui = { open = true, display = 'tabs' } } }, function (settings, lib)
        local cfg = settings.load('WHM_BLM')
        eq({ cfg.heal.danger, cfg.ui.hp_width, cfg.ui.open, cfg.ui.display }, { 40, 220, false, nil })
        local ui = cfg.ui
        cfg.ui.hp_width, cfg.heal.critical = 300, 20
        settings.save()
        eq({ lib.files.WHM_BLM.ui, lib.files.WHM_BLM.heal.critical, lib.files.ui.hp_width }, { nil, 20, 300 })
        eq(rawequal(cfg.ui, ui), true, 'cfg.ui is kept')
    end)
end)

test('every job pair shares ui; the rest is the pair\'s own', function ()
    with_lib({}, function (settings)
        local cfg = settings.load('WHM_BLM')
        cfg.ui.hp_width, cfg.heal.critical = 300, 20
        settings.save()
        cfg = settings.load('WHM_SCH')
        eq({ cfg.ui.hp_width, cfg.heal.critical }, { 300, 30 })
    end)
end)

test('after a relog the library saves new tables: switched() says to load them again', function ()
    with_lib({}, function (settings, lib)
        eq(settings.switched(), false)  -- nothing loaded yet
        settings.load('WHM_BLM')
        eq(settings.switched(), false)
        lib.relog()
        eq(settings.switched(), true)
        local cfg = settings.load('WHM_BLM')
        eq(settings.switched(), false)
        cfg.ui.hp_width = 444
        settings.save()
        eq(lib.files.ui.hp_width, 444)
    end)
end)
