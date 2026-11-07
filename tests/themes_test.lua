-- core/themes.lua: which files in ui/ are themes, how each loads and is named, the order they're listed in, and
-- theme.txt. Theme files are written to the system's temp folder, and removed after.
local share = require('core.share')
local themes = require('core.themes')

local real = { folder = themes.folder, files = themes.files, dir = share.dir, list = themes.list }
local windows = package.config:sub(1, 1) == '\\'
local tmp = (windows and (os.getenv('TEMP') or os.getenv('TMP') or '.') or '/tmp') .. (windows and '\\' or '/')
local PREFIX = 'sk_theme_test_'

local in_ui, made = {}, {}
-- `text` as the file `name` in ui/ (the temp folder), listed with the rest.
local function put(name, text)
    local f = assert(io.open(tmp .. name, 'w'))
    f:write(text)
    f:close()
    made[name] = true
    for _, n in ipairs(in_ui) do if n == name then return end end
    in_ui[#in_ui + 1] = name
end
local function drop(name)
    os.remove(tmp .. name)
    for i, n in ipairs(in_ui) do if n == name then table.remove(in_ui, i); return end end
end

themes.folder = function () return tmp end
themes.files = function () return in_ui end

-- A theme returning `name`, counting its loads in _G[PREFIX .. 'runs'][key].
local function theme(key, name)
    return ('local runs = rawget(_G, %q) or {}; rawset(_G, %q, runs); runs[%q] = (runs[%q] or 0) + 1\n'
        .. 'return { name = %s, render = function () end }'):format(PREFIX .. 'runs', PREFIX .. 'runs', key, key,
        name and ('%q'):format(name) or 'nil')
end
local function runs(key) return (rawget(_G, PREFIX .. 'runs') or {})[key] or 0 end

-- The themes listed now, 'key name' each ('!' after one that failed to load).
local function listed()
    local out = {}
    for _, t in ipairs(themes.list) do out[#out + 1] = t.key .. ' ' .. t.name .. (t.error and '!' or '') end
    return out
end

local WINDOW = { render = function () end }

local ok, err = pcall(function ()
    test('themes.open: a theme\'s table; a syntax error, an error running it, or no render says why', function ()
        put(PREFIX .. 'good.lua', theme('good', 'Good'))
        put(PREFIX .. 'syntax.lua', 'return {')
        put(PREFIX .. 'raises.lua', 'error("no kit here", 0)')
        put(PREFIX .. 'bare.lua', 'return { name = "Bare" }')
        local good = themes.open(tmp .. PREFIX .. 'good.lua')
        eq({ type(good), good.name }, { 'table', 'Good' })
        local none, why = themes.open(tmp .. PREFIX .. 'syntax.lua')
        eq({ none, why:find(PREFIX .. 'syntax.lua', 1, true) ~= nil }, { nil, true })
        eq({ themes.open(tmp .. PREFIX .. 'raises.lua') }, { nil, 'no kit here' })
        eq({ themes.open(tmp .. PREFIX .. 'bare.lua') }, { nil, 'it returns no table with a render function' })
        eq(select(2, themes.open(tmp .. PREFIX .. 'nowhere.lua')) ~= nil, true)
        for _, n in ipairs({ 'good', 'syntax', 'raises', 'bare' }) do drop(PREFIX .. n .. '.lua') end
    end)

    test('Standard first, then each .lua in ui/ by name (its own, else its file\'s), but kit.lua and model.lua', function ()
        in_ui = {}
        put('kit.lua', 'return {}')
        put('model.lua', 'return {}')
        put('window.lua', 'return {}')
        put(PREFIX .. 'zeta.lua', theme('zeta', '  Alpha  '))  -- its name trimmed: listed by it, first
        put(PREFIX .. 'beta.LUA', theme('beta'))  -- no name: its file's
        put(PREFIX .. 'blank.lua', theme('blank', ' '))
        put(PREFIX .. 'notes.txt', 'not a theme')
        themes.init(WINDOW)
        eq(listed(), { 'window Standard', PREFIX .. 'zeta Alpha', PREFIX .. 'beta ' .. PREFIX .. 'beta',
                       PREFIX .. 'blank ' .. PREFIX .. 'blank' })
        eq({ themes.list[1].ui, themes.list[1].file, themes.list[2].file }, { WINDOW, 'ui/window.lua', 'ui/' .. PREFIX .. 'zeta.lua' })
    end)

    test('themes.find: by name, else by file, any case; Standard is standard; themes.get by file alone', function ()
        local zeta, beta = themes.list[2], themes.list[3]
        eq({ themes.find(' alpha '), themes.find(PREFIX .. 'ZETA'), themes.find(PREFIX .. 'beta'), themes.find('STANDARD') },
           { zeta, zeta, beta, themes.list[1] })
        eq({ themes.find('nope'), themes.find(''), themes.find(nil), themes.get('Alpha'), themes.get('WINDOW') },
           { nil, nil, nil, nil, themes.list[1] })
    end)

    test('a scan loads a file new since the last, and one that failed (fixed since); the rest stay as they were',
        function ()
        put(PREFIX .. 'late.lua', 'return {')  -- broken
        themes.scan()
        eq({ themes.get(PREFIX .. 'late').error ~= nil, runs('zeta') }, { true, 1 })
        put(PREFIX .. 'late.lua', theme('late', 'Late'))
        put(PREFIX .. 'zeta.lua', theme('zeta', 'Edited'))  -- an edit waits for a reload
        themes.scan()
        eq({ themes.get(PREFIX .. 'late').name, themes.get(PREFIX .. 'late').error, themes.get(PREFIX .. 'zeta').name,
             runs('zeta') }, { 'Late', nil, 'Alpha', 1 })
    end)

    test('a theme whose file goes is dropped at the next scan, but the one drawing', function ()
        local zeta = themes.get(PREFIX .. 'zeta')
        drop(PREFIX .. 'zeta.lua')
        drop(PREFIX .. 'blank.lua')
        themes.scan(zeta)
        eq(listed(), { 'window Standard', PREFIX .. 'zeta Alpha', PREFIX .. 'late Late', PREFIX .. 'beta ' .. PREFIX .. 'beta' })
        themes.scan(themes.list[1])
        eq(listed(), { 'window Standard', PREFIX .. 'late Late', PREFIX .. 'beta ' .. PREFIX .. 'beta' })
    end)

    test('load_all: each theme\'s load once, Standard\'s too; one that raises is returned with why', function ()
        local calls = {}
        themes.list[1].ui = { render = WINDOW.render, load = function () calls[#calls + 1] = 'window' end }
        themes.list[2].ui.load = function () error('no font', 0) end
        themes.list[3].ui.load = function () calls[#calls + 1] = 'beta' end
        local failed = themes.load_all()
        eq({ calls, #failed, failed[1][1], failed[1][2] }, { { 'window', 'beta' }, 1, themes.list[2], 'no font' })
        eq({ #themes.load_all(), calls }, { 0, { 'window', 'beta' } })  -- once
        eq({ themes.list[1].loaded, themes.list[3].loaded }, { true, true })
    end)

    test('themes.shown: the one drawing and each theme for the view, Standard marked', function ()
        local th = themes.shown(themes.list[2])
        eq(th.current, PREFIX .. 'late')
        eq(th.list[1], { key = 'window', name = 'Standard', file = 'ui/window.lua', standard = true })
        eq(th.list[2], { key = PREFIX .. 'late', name = 'Late', file = 'ui/' .. PREFIX .. 'late.lua' })
        eq(themes.shown(nil).current, nil)
    end)

    test('theme.txt: the PC\'s pick, written and read back; none, blank or unreadable reads nil', function ()
        share.dir = function () return tmp .. PREFIX end  -- the file is <tmp>sk_theme_test_theme.txt
        made['theme.txt'] = true
        os.remove(tmp .. PREFIX .. 'theme.txt')
        eq(themes.read(), nil)
        eq({ themes.write('Classic'), themes.read() }, { true, 'Classic' })
        eq({ themes.write('classic'), themes.read() }, { true, 'classic' })
        local f = assert(io.open(tmp .. PREFIX .. 'theme.txt', 'w'))
        f:write('  \n')
        f:close()
        eq(themes.read(), nil)
        os.remove(tmp .. PREFIX .. 'theme.txt')
    end)
end)

for name in pairs(made) do os.remove(tmp .. (name == 'theme.txt' and PREFIX .. name or name)) end
rawset(_G, PREFIX .. 'runs', nil)
themes.folder, themes.files, share.dir, themes.list = real.folder, real.files, real.dir, real.list
if not ok then error(err, 0) end
