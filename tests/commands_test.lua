-- Sidekick.lua's commands and which windows it draws, with Ashita stubbed out: /sk, /sk hud, /sk alt, zoning and a
-- UI's error. Sidekick.lua runs on fresh copies of every module, and everything it's given is put back at the end, so
-- no other test sees any of it.
local fake_names = { 'core%.', 'jobs%.', 'ui%.', 'tests%.fake' }
local saved_loaded = {}
for k, v in pairs(package.loaded) do saved_loaded[k] = v end
local GLOBALS = { 'addon', 'ashita', 'AshitaCore', 'T', 'print' }
local saved_globals = {}
for _, k in ipairs(GLOBALS) do saved_globals[k] = rawget(_G, k) end
local saved_clock, saved_searchpath, saved_args = os.clock, package.searchpath, rawget(string, 'args')

local function restore()
    for k in pairs(package.loaded) do
        if saved_loaded[k] == nil then package.loaded[k] = nil end
    end
    for k, v in pairs(saved_loaded) do package.loaded[k] = v end
    for _, k in ipairs(GLOBALS) do rawset(_G, k, saved_globals[k]) end
    rawset(os, 'clock', saved_clock)
    rawset(package, 'searchpath', saved_searchpath)
    rawset(string, 'args', saved_args)
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- What a session file of another Sidekick session reads as (core/share.lua).
local function alt(name, sid)
    return { name = name, members = { { sid = sid, name = name } }, epoch = 1, calls = {}, acks = {}, watch = {},
             running = false }
end

-- Sidekick.lua loaded afresh, `custom` with a ui/custom.lua: { sk(command) -> chat, frame() -> the view drawn or nil,
-- sessions, sent, loading(on), ui (the stub UI: its render can be replaced), act (the last frame's) }.
local function boot(custom)
    for k in pairs(package.loaded) do
        for _, p in ipairs(fake_names) do
            if k:match('^' .. p) then package.loaded[k] = nil end
        end
    end
    local env = { sessions = {}, sent = {}, out = {}, renders = {} }
    rawset(_G, 'print', function (s) env.out[#env.out + 1] = s end)
    rawset(string, 'args', function (s)  -- Ashita's, from 'common'
        local t = {}
        for w in s:gmatch('%S+') do t[#t + 1] = w end
        return t
    end)
    rawset(_G, 'addon', {})
    rawset(_G, 'T', function (t) return t end)
    local handlers = {}
    rawset(_G, 'ashita', { events = { register = function (ev, _, fn) handlers[ev] = fn end },
                           fs = { get_dir = function () return {} end } })
    local player = { GetMainJobLevel = function () return 75 end, GetMainJob = function () return 3 end,
        GetSubJob = function () return 0 end, GetSubJobLevel = function () return 0 end,
        HasSpell = function () return false end, HasAbility = function () return false end }
    rawset(_G, 'AshitaCore', {
        GetMemoryManager = function () return { GetPlayer = function () return player end } end,
        GetResourceManager = function () return { GetString = function () return 'WHM' end } end,
        GetChatManager = function () return { QueueCommand = function () end } end,
        GetPacketManager = function () return { AddOutgoingPacket = function () end } end,
        GetInstallPath = function () return 'C:/nowhere' end,
    })
    package.loaded['common'] = true
    local same = function (s) return s end
    package.loaded['chat'] = { header = function () return '' end, message = same, error = same, warning = same }
    package.loaded['imgui'] = { IsAnyItemActive = function () return false end }
    env.files = {}
    package.loaded['settings'] = {
        load = function (defaults, alias)
            env.files[alias] = env.files[alias] or copy(defaults)
            return env.files[alias]
        end,
        save = function () end,
        get = function (alias) return env.files[alias] end,
    }
    local fake = require('tests.fake')
    local loading = false
    function env.loading(on) loading = on end
    package.loaded['core.game'] = {
        read = function (now)
            if loading then return { loading = true, now = now, tracks = {} } end
            local g = fake.snap({ { name = 'B' } })
            g.now, g.loading = now, false
            return g
        end,
        sent = function () end,
        find_player = function () end,
    }
    package.loaded['core.resources'] = { load = function () return fake.res end }
    local share = require('core.share')
    share.tick = function () share.sessions = env.sessions; return env.sessions end
    share.me = function () return 'Me' end
    share.send = function (to, call)
        env.sent[#env.sent + 1] = to .. ' ' .. call[1] .. ' ' .. tostring(call[2])
        return true
    end
    env.ui = { render = function (view, act) env.renders[#env.renders + 1], env.act = view, act end }
    package.loaded['ui.window'] = env.ui
    package.loaded['ui.custom'] = env.ui
    rawset(package, 'searchpath', function (name, path)  -- a ui/custom.lua of your own isn't taken
        if name == 'ui.custom' then return custom and 'ui/custom.lua' or nil end
        return saved_searchpath(name, path)
    end)
    local clock = 0
    rawset(os, 'clock', function () return clock end)
    dofile('Sidekick.lua')
    function env.frame()
        clock = clock + 1
        env.renders = {}
        handlers.d3d_present()
        return env.renders[1]
    end
    function env.sk(command)
        env.out = {}
        handlers.command({ command = command })
        return table.concat(env.out, ' | ')
    end
    env.frame()
    return env
end

-- The names of the other sessions' Sidekick Settings in a view.
local function remote(v)
    local out = {}
    for _, r in ipairs(v and v.remote or {}) do out[#out + 1] = r.name end
    return out
end

local ok, err = pcall(function ()
    local e = boot(false)
    e.sessions.Beta, e.sessions.Gamma = alt('Beta', 2), alt('Gamma', 3)
    e.frame()

    test('/sk shows and hides Sidekick Settings alone; /sk hud the HUD, remembered', function ()
        eq(e.frame(), nil)  -- nothing up at load: not drawn
        eq(e.sk('/sk'), '')  -- the standard UI: no hint
        local v = e.frame()
        eq({ v.ui.settings, v.ui.open }, { true, false })
        e.sk('/sk hud')
        v = e.frame()
        eq({ v.ui.settings, v.ui.open, e.files.ui.open }, { true, true, true })
        e.sk('/sk')
        v = e.frame()
        eq({ v.ui.settings, v.ui.open }, { false, true })
        e.sk('/sk hud')
        eq({ e.frame(), e.files.ui.open }, { nil, false })
    end)

    test('/sidekick answers as /sk does, any case', function ()
        e.sk('/sidekick')
        eq(e.frame().ui.settings, true)
        e.sk('/SideKick')
        eq(e.frame(), nil)
        e.sk('/sidekick hud')
        eq({ e.frame().ui.open, e.files.ui.open }, { true, true })
        e.sk('/Sidekick HUD')
        eq({ e.frame(), e.files.ui.open }, { nil, false })
        eq({ e.sk('/sidekickx'), e.frame() }, { '', nil })  -- not ours: Sidekick Settings stays closed
    end)

    test('/sk alt shows every alt\'s Sidekick Settings, or the one named, and hides them all while any is up', function ()
        eq(e.sk('/sk alt'), '')
        eq(remote(e.frame()), { 'Beta', 'Gamma' })  -- with the HUD and yours closed too
        e.sk('/sk alt beta')
        eq(remote(e.frame()), { 'Gamma' })
        e.sk('/sk alt')  -- one is up: all go
        eq(e.frame(), nil)
        e.sk('/sk alt ALL')
        eq(remote(e.frame()), { 'Beta', 'Gamma' })
        e.sk('/sk alt all')
        eq(e.frame(), nil)
    end)

    test('/sk alt says when there\'s no such alt, it\'s you, or none at all', function ()
        eq(e.sk('/sk alt Nobody'), 'No Sidekick session "Nobody" on this PC (sessions: Beta, Gamma).')
        eq(e.sk('/sk alt me'), 'That\'s you: /sk opens your Sidekick Settings, /sk start|stop your automation.')
        local live = e.sessions
        e.sessions = {}
        e.frame()
        eq({ e.sk('/sk alt'), e.sk('/sk alt all') }, { 'No other Sidekick sessions on this PC.',
                                                       'No other Sidekick sessions on this PC.' })
        e.sessions = live
        e.frame()
    end)

    test('/sk alt start|stop reaches every alt or the one named, never you; a lone Start that\'s an alt is that alt',
        function ()
        e.sent = {}
        eq(e.sk('/sk alt stop'), 'Sent stop to Beta, Gamma.')
        eq(e.sk('/sk alt start gamma'), 'Sent start to Gamma.')
        eq(e.sk('/sk alt stop all'), 'Sent stop to Beta, Gamma.')
        eq(e.sent, { 'Beta run false', 'Gamma run false', 'Gamma run true', 'Beta run false', 'Gamma run false' })
        e.sessions.Start = alt('Start', 4)
        e.frame()
        e.sent = {}
        eq(e.sk('/sk alt Start'), '')  -- Start's Sidekick Settings, not every alt started
        eq({ remote(e.frame()), e.sent }, { { 'Start' }, {} })
        e.sk('/sk alt Start')
        eq(e.sk('/sk alt start all'), 'Sent start to Beta, Gamma, Start.')
        eq(e.sk('/sk alt start Start'), 'Sent start to Start.')
        e.sessions.Start = nil
        e.frame()
    end)

    test('while zoning, every window but the HUD stays up, as it is now; only stop goes through', function ()
        e.sk('/sk hud'); e.sk('/sk'); e.sk('/sk alt')
        local v = e.frame()
        eq({ v.ui.open, v.ui.settings, remote(v) }, { true, true, { 'Beta', 'Gamma' } })
        e.loading(true)
        v = e.frame()  -- the widget's off: still drawn
        eq({ v.ui.open, v.ui.settings, remote(v) }, { false, true, { 'Beta', 'Gamma' } })
        e.act.watch('Beta', false)  -- its window's close, mid-zone
        eq(remote(e.frame()), { 'Gamma' })
        e.sent = {}
        eq(e.sk('/sk alt stop'), 'Sent stop to Beta, Gamma.')
        eq(e.sent, { 'Beta run false', 'Gamma run false' })
        eq({ e.sk('/sk alt'), e.sk('/sk'), e.sk('/sk hud') }, { 'Waiting for the game to load your job.',
            'Waiting for the game to load your job.', 'Waiting for the game to load your job.' })
        e.loading(false)
        v = e.frame()
        eq({ v.ui.open, v.ui.settings, remote(v) }, { true, true, { 'Gamma' } })
    end)

    test('a UI\'s error closes every window of it, said once with how to open them again; /sk opens its own', function ()
        local render = e.ui.render
        e.ui.render = function () error('boom', 0) end
        e.out = {}
        e.frame()
        eq(e.out, { 'Window closed on an error (/sk hud or /sk opens it again): boom' })
        e.ui.render = render
        eq(e.frame(), nil)
        e.sk('/sk')
        local v = e.frame()
        eq({ v.ui.settings, v.ui.open, remote(v), e.files.ui.open }, { true, false, {}, true })
        e.sk('/sk hud')
        eq(e.frame().ui.open, true)
        e.sk('/sk'); e.sk('/sk hud')
    end)

    test('with ui/custom.lua, the first /sk says what changed, once', function ()
        local c = boot(true)
        local hint = '/sk shows Sidekick Settings now, /sk hud the HUD: a custom UI draws them for view.ui.settings '
            .. '(ui/README.md, Upgrading from 3.0.0).'
        eq({ c.sk('/sk'), c.frame().ui.settings }, { hint, true })
        eq({ c.sk('/sk'), c.sk('/sk') }, { '', '' })
    end)
end)
restore()
if not ok then error(err, 0) end
