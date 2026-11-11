-- Sidekick.lua's commands and which windows it draws, with Ashita stubbed out: /sk, /sk hud, /sk alt, /sk toggle,
-- v2's command names, zoning and a UI's error. Sidekick.lua runs on fresh copies of every module, and everything it's given is put back at the end, so
-- no other test sees any of it.
local fake_names = { 'core%.', 'jobs%.', 'ui%.', 'tests%.fake' }
local saved_loaded = {}
for k, v in pairs(package.loaded) do saved_loaded[k] = v end
local GLOBALS = { 'addon', 'ashita', 'AshitaCore', 'T', 'print' }
local saved_globals = {}
for _, k in ipairs(GLOBALS) do saved_globals[k] = rawget(_G, k) end
local saved_clock, saved_args = os.clock, rawget(string, 'args')

local function restore()
    for k in pairs(package.loaded) do
        if saved_loaded[k] == nil then package.loaded[k] = nil end
    end
    for k, v in pairs(saved_loaded) do package.loaded[k] = v end
    for _, k in ipairs(GLOBALS) do rawset(_G, k, saved_globals[k]) end
    rawset(os, 'clock', saved_clock)
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

-- Sidekick.lua loaded afresh. `custom`: true for a ui/custom.lua; else the themes, { files = { the bare names in ui/ },
-- uis = { [key] = its table (a stub's render added), or why it failed to load }, picked = the key in theme.txt }.
-- Returns { sk(command) -> chat, frame() -> the view drawn or nil, by (the key of the theme that drew it), theme
-- ({ files, picked, writes, unwritable }: ui/ and theme.txt, live), sessions, sent, loading(on), ui (Standard's stub:
-- its render can be replaced), act (the last frame's), party and over
-- (who the game reads besides you, and its snapshot's flags), queued (the commands sent to the game), files (the settings
-- files, by alias), out (chat since the last command), player (the game's, its functions replaceable), packet(id) (one
-- arrives) }. With `spells`, you know every spell your job has (else none).
-- `ui`: what the ui file was left holding, over its defaults. `login`: loaded before you're in, as at the title screen,
-- so the game reads loading till env.loading(false).
local function boot(custom, spells, ui, login)
    for k in pairs(package.loaded) do
        for _, p in ipairs(fake_names) do
            if k:match('^' .. p) then package.loaded[k] = nil end
        end
    end
    local env = { sessions = {}, sent = {}, out = {}, renders = {}, party = { { name = 'B' } }, over = {}, queued = {} }
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
        HasSpell = function () return spells == true end, HasAbility = function () return false end }
    env.player = player
    rawset(_G, 'AshitaCore', {
        GetMemoryManager = function () return { GetPlayer = function () return player end } end,
        GetResourceManager = function () return { GetString = function () return 'WHM' end } end,
        GetChatManager = function ()
            return { QueueCommand = function (_, _, command) env.queued[#env.queued + 1] = command end }
        end,
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
            if not env.files[alias] then
                env.files[alias] = copy(defaults)
                for k, v in pairs(alias == 'ui' and ui or {}) do env.files[alias][k] = v end
            end
            return env.files[alias]
        end,
        save = function () end,
        get = function (alias) return env.files[alias] end,
    }
    local fake = require('tests.fake')
    local loading = login == true
    function env.loading(on) loading = on end
    package.loaded['core.game'] = {
        read = function (now)
            if loading then return { loading = true, now = now, tracks = {} } end
            local g = fake.snap(copy(env.party), copy(env.over))
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
    -- A stub UI for the theme `key`: each frame it draws, it keeps the view and act, and env.by its key.
    local function stub(t, key)
        t.render = t.render or function (view, act) env.renders[#env.renders + 1], env.act, env.by = view, act, key end
        return t
    end
    env.ui = stub({}, 'window')
    package.loaded['ui.window'] = env.ui
    -- ui/ holds `custom`'s themes (a ui/custom.lua of your own isn't taken), and theme.txt its `picked`.
    local th = custom == true and { files = { 'custom.lua' } } or custom or {}
    env.theme = { files = th.files or {}, picked = th.picked, writes = 0 }
    local themes = require('core.themes')
    themes.files = function () return env.theme.files end
    themes.open = function (path)
        local key = path:match('([^/\\]+)%.[Ll][Uu][Aa]$')
        local found = (th.uis or {})[key]
        if type(found) == 'string' then return nil, found end  -- why it failed
        return stub(found or {}, key)
    end
    themes.read = function () return env.theme.picked end
    themes.write = function (key)
        env.theme.writes = env.theme.writes + 1
        if env.theme.unwritable then return false end
        env.theme.picked = key
        return true
    end
    local clock = 0
    rawset(os, 'clock', function () return clock end)
    dofile('Sidekick.lua')
    handlers.load()  -- Ashita's load event, once the file has run
    function env.frame()
        clock = clock + 1
        env.renders = {}
        handlers.d3d_present()
        return env.renders[1]
    end
    function env.packet(id) handlers.packet_in({ id = id, data = '' }) end
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

-- Whether `name` is any string in the view.
local function mentions(v, name, seen)
    seen = seen or {}
    if v == name then return true end
    if type(v) ~= 'table' or seen[v] then return false end
    seen[v] = true
    for k, x in pairs(v) do
        if mentions(k, name, seen) or mentions(x, name, seen) then return true end
    end
    return false
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

    test('/sk toggle starts automation when stopped, stops it when running, yours alone; mid-zone it only stops',
        function ()
        e.sent = {}
        eq({ e.sk('/sk toggle'), e.sk('/sidekick TOGGLE'), e.sent }, { 'Automation started.', 'Automation stopped.', {} })
        e.sk('/sk toggle')
        e.loading(true)
        e.frame()
        eq({ e.sk('/sk toggle'), e.sk('/sk toggle') }, { 'Automation stopped.', 'Waiting for the game to load your job.' })
        e.loading(false)
        e.frame()
        eq(e.sk('/sk toggle'), 'Automation started.')  -- stopped all along: the second mid-zone did nothing
        local named = '/sk toggle takes no name, it\'s this session\'s alone: use /sk start|stop %s.'
        eq({ e.sk('/sk toggle B'), e.sk('/sk toggle all'), e.sent }, { named:format('B'), named:format('all'), {} })
        e.loading(true)
        e.frame()
        eq(e.sk('/sk toggle B'), named:format('B'))  -- mid-zone too
        e.loading(false)
        e.frame()
        eq(e.sk('/sk toggle'), 'Automation stopped.')  -- running all along: no name toggled you
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

    test('v2\'s names still work: config, panel, addtarget, removetarget and debug', function ()
        e.sk('/sk config')
        local v = e.frame()
        eq({ v.ui.settings, v.ui.open }, { true, false })
        e.sk('/sk PANEL')
        eq({ e.frame().ui.open, e.files.ui.open }, { true, true })
        e.sk('/sk config'); e.sk('/sidekick panel')
        eq({ e.frame(), e.files.ui.open }, { nil, false })
        eq({ e.sk('/sk debug'), e.sk('/sk debug') }, { 'Action log on.', 'Action log off.' })
        e.over, e.queued = { target = { sid = 500, tidx = 1500, name = 'Out' } }, {}
        e.frame()
        eq({ e.sk('/sk addtarget'), e.queued }, { 'Tracking Out: healed, cleared, raised and buffed (buff rows pick them '
            .. 'by name). Checking their level.', { '/check Out' } })
        eq({ e.sk('/sk removetarget out'), e.sk('/sk removetarget Out') }, { 'Stopped tracking Out.', 'Not tracking "Out".' })
        e.over = {}
        e.frame()
    end)

    -- Follow's settings, in the job pair's file.
    local function follow_of(env)
        for _, file in pairs(env.files) do
            if file.follow then return file.follow end
        end
    end

    test('/sk follow toggles Follow; with a name, that leader is followed, spelled as the game does', function ()
        local f = follow_of(e)
        eq({ f.on, f.target }, { false, '' })
        eq(e.sk('/sk follow'), 'Follow on, but no leader yet: /sk follow <name>.')
        eq({ e.sk('/sk follow'), f.on }, { 'Follow off.', false })
        eq(e.sk('/sk follow b'), 'Following B past 5 yalms.')
        eq({ f.on, f.target }, { true, 'B' })
        eq(e.sk('/sk follow b'), 'Following B past 5 yalms.')  -- a name never toggles
        eq({ e.sk('/sk follow'), f.on, f.target }, { 'Follow off.', false, 'B' })
        eq(e.sk('/sk follow'), 'Following B past 5 yalms.')
        eq({ e.sk('/sk follow off'), e.sk('/sk follow off'), e.sk('/sk follow ON'), e.sk('/sk follow on') },
           { 'Follow off.', 'Follow off.', 'Following B past 5 yalms.', 'Following B past 5 yalms.' })
    end)

    test('/sk follow <name>: one off the Leader list is kept with a warning, never you; a leader named Off by name', function ()
        local f = follow_of(e)
        eq(e.sk('/sk follow me'), 'That\'s you: /sk follow <name> follows someone on the Leader list.')
        eq({ f.on, f.target }, { true, 'B' })  -- left as it was
        local away = 'Following Nobody past 5 yalms. | Nobody isn\'t on the Leader list now: followed once in your party '
            .. 'or alliance, or tracked (/sk track Nobody).'
        eq({ e.sk('/sk follow nOBODY'), f.on, f.target }, { away, true, 'Nobody' })  -- spelled as names are
        eq({ e.sk('/sk follow'), e.sk('/sk follow') }, { 'Follow off.', away })  -- turned on again, still away
        e.party = { { name = 'B' }, { name = 'Off', kind = 'alliance' }, { name = 'Out', kind = 'tracked' } }
        e.frame()
        eq({ e.sk('/sk follow off'), f.target }, { 'Following Off past 5 yalms.', 'Off' })
        eq({ e.sk('/sk follow OUT'), f.target }, { 'Following Out past 5 yalms.', 'Out' })
        e.party = { { name = 'B' } }
        e.frame()
        e.sk('/sk follow B')
    end)

    test('Follow goes on with automation stopped, mounted or in a safe zone too; never while you move', function ()
        e.party, e.queued = { { name = 'B', dist = 9 } }, {}
        e.frame()
        eq(e.queued, { '/follow <p1>' })
        e.over = { moving = true }
        e.frame(); e.frame()
        eq(e.queued, { '/follow <p1>' })
        e.over = { mounted = true }
        e.frame()
        eq(#e.queued, 2)
        e.over = { safe = true }
        e.frame(); e.frame()  -- the first inside the 1.1s throttle
        eq(#e.queued, 3)
        e.sk('/sk start')
        e.over = { mounted = true }
        e.frame(); e.frame()
        eq({ #e.queued, e.queued[4] }, { 4, '/follow <p1>' })  -- running, as well
        e.sk('/sk stop')
        e.sk('/sk follow off')
        e.frame(); e.frame()
        eq(#e.queued, 4)
        e.party, e.over = { { name = 'B' } }, {}
        e.frame()
    end)

    test('Stopped, Follow alone is sent, though a cure is due; started, the cure goes first', function ()
        local s = boot(false, true)
        s.party = { { name = 'B', hpp = 40, dist = 9 } }
        s.sk('/sk follow B')
        s.queued = {}
        s.frame(); s.frame(); s.frame()  -- the second inside the 1.1s throttle
        eq(s.queued, { '/follow <p1>', '/follow <p1>' })
        s.sk('/sk start')
        s.frame(); s.frame()
        eq(s.queued[3]:match('^/ma "Cur'), '/ma "Cur')
    end)

    test('Always load stopped, on by default: a load starts stopped, whatever was left', function ()
        local s = boot(false, nil, { running = true })
        eq({ s.out, s.sk('/sk toggle') }, { {}, 'Automation started.' })
        s.frame()
        eq(s.files.ui.running, true)  -- not kept while it's on: no file written for each start and stop
        s.sk('/sk stop')
        s.frame()
        eq(s.files.ui.running, true)
        s.files.ui.load_stopped = false  -- turned off: kept from then on
        s.frame()
        eq(s.files.ui.running, false)
    end)

    test('Always load stopped off: a load starts as automation was left, kept as it changes, by any way', function ()
        local s = boot(false, nil, { load_stopped = false, running = true })
        eq({ s.out, s.sk('/sk toggle') },
           { { 'Automation started, as it was left (Always load stopped is off).' }, 'Automation stopped.' })
        s.sk('/sk')
        s.frame()
        eq(s.files.ui.running, false)
        s.act.run(true)  -- the run icon
        s.frame()
        eq(s.files.ui.running, true)
        s.loading(true)
        s.frame()
        s.sk('/sk stop')  -- mid-zone
        s.frame()
        eq(s.files.ui.running, false)
        s.loading(false)
        s.frame()
        eq(boot(false, nil, { load_stopped = false }).sk('/sk toggle'), 'Automation started.')  -- left stopped: stopped
    end)

    test('After zone stop: off, a zone leaves automation running; on, it stops as the zone begins, said once', function ()
        local z = boot(false)
        z.sk('/sk start')
        z.loading(true); z.frame(); z.frame()
        z.loading(false); z.frame()
        eq(z.sk('/sk toggle'), 'Automation stopped.')  -- running through the zone
        z.files.ui.zone_stop = true
        z.sk('/sk start')
        z.out = {}
        z.loading(true); z.frame(); z.frame()
        eq(z.out, { 'Automation stopped: you zoned (After zone stop).' })
        z.loading(false); z.frame()
        eq(z.sk('/sk toggle'), 'Automation started.')  -- stopped after it
        z.sk('/sk stop')
        z.out = {}
        z.loading(true); z.frame()
        eq(z.out, {})  -- stopped already: nothing to say
        z.loading(false); z.frame()
        z.files.ui.load_stopped = false
        z.sk('/sk start')
        z.frame()
        eq(z.files.ui.running, true)
        z.loading(true); z.frame()
        eq(z.files.ui.running, false)  -- what the next load starts as
    end)

    test('After zone stop on, a login starts stopped, whatever was left; Sidekick loaded in a zone resumes', function ()
        local left = { load_stopped = false, running = true, zone_stop = true }
        local s = boot(false, nil, left, true)  -- a logout's stop reaches no file: running = true stays in it
        s.loading(false); s.frame()
        eq({ s.out, s.files.ui.running }, { {}, false })  -- the file put right
        eq(s.sk('/sk toggle'), 'Automation started.')
        eq(boot(false, nil, left).out, { 'Automation started, as it was left (Always load stopped is off).' })
        left.zone_stop = false
        local l = boot(false, nil, left, true)
        l.loading(false); l.frame()
        eq(l.out, { 'Automation started, as it was left (Always load stopped is off).' })
    end)

    test('a relog: Always load stopped off, as the character left it; After zone stop on, stopped; else as it is',
        function ()
        local s = boot(false)
        -- Logged out and in to a character whose ui file holds `ui` over the defaults: the library loads every file
        -- again, into new tables.
        local function relog(ui, typed)
            s.loading(true); s.frame()
            if typed then s.sk(typed) end
            local f = copy(s.files.ui)
            f.load_stopped, f.zone_stop, f.running = true, false, false
            for k, v in pairs(ui) do f[k] = v end
            s.files.ui, s.out = f, {}
            s.loading(false); s.frame()
            return s.out
        end
        s.sk('/sk start')
        eq({ relog({ load_stopped = false, running = false }), s.files.ui.running },
           { { 'Automation stopped, as it was left (Always load stopped is off).' }, false })
        eq({ relog({ running = true }), s.sk('/sk toggle') }, { {}, 'Automation started.' })  -- load_stopped on: as is
        eq(relog({ load_stopped = false, running = true }), {})  -- running already
        eq(relog({ zone_stop = true }), { 'Automation stopped: you zoned (After zone stop).' })  -- the login stops it
        s.sk('/sk start')
        eq({ relog({ load_stopped = false, running = true }, '/sk stop'), s.files.ui.running }, { {}, false })
    end)

    test('Always load stopped off: a /sk stop while you first load stands', function ()
        local s = boot(false, nil, { load_stopped = false, running = true }, true)
        eq(s.sk('/sk stop'), 'Automation stopped.')
        s.out = {}
        s.loading(false); s.frame()
        eq({ s.out, s.files.ui.running, s.sk('/sk toggle') }, { {}, false, 'Automation started.' })
    end)

    test('with ui/custom.lua, the first /sk says what changed, once', function ()
        local c = boot(true)
        local hint = '/sk shows Sidekick Settings now, /sk hud the HUD: a custom UI draws them for view.ui.settings '
            .. '(ui/README.md, Upgrading from 3.0.0).'
        eq({ c.sk('/sk'), c.frame().ui.settings }, { hint, true })
        eq({ c.sk('/sk'), c.sk('/sk') }, { '', '' })
        local t = boot({ files = { 'custom.lua', 'classic.lua' }, uis = { classic = { name = 'Classic' } }, picked = 'classic' })
        eq({ t.sk('/sk'), t.frame() and t.by }, { '', 'classic' })  -- a theme picked: no hint, ui/custom.lua or not
    end)

    -- ui/ with Sidekick's own files, a theme that names itself, one that failed to load and one that goes by its file's.
    local UI = { 'classic.lua', 'kit.lua', 'model.lua', 'window.lua', 'broken.lua', 'Mine.LUA' }
    local function themed(picked, uis, files)
        local all = { classic = { name = 'Classic' }, broken = 'ui/broken.lua:3: unexpected symbol' }
        for k, v in pairs(uis or {}) do all[k] = v end
        return boot({ files = files or UI, uis = all, picked = picked })
    end
    local SAVED = '. /sk theme lists them all.'
    -- The view's themes, Sidekick Settings opened for it (and closed after, a frame seeing them go): the one drawing, then
    -- each 'key name' ('!' after one that failed to load).
    local function shown(s)
        s.sk('/sk')
        local v = s.frame()
        s.sk('/sk')
        s.frame()
        local out = { v.themes.current }
        for _, it in ipairs(v.themes.list) do out[#out + 1] = it.key .. ' ' .. it.name .. (it.error and '!' or '') end
        return out
    end

    test('with no theme picked, ui/custom.lua draws, as before themes; else Standard', function ()
        local c = boot(true)
        c.sk('/sk')
        eq({ c.frame() ~= nil, c.by }, { true, 'custom' })
        local s = themed()
        s.sk('/sk')
        eq({ s.frame() ~= nil, s.by }, { true, 'window' })
    end)

    test('/sk theme lists Standard, then each theme in ui/ by name, but Sidekick\'s own files; the one drawing marked',
        function ()
        eq(themed().sk('/sk theme'), 'Themes: Standard (in use), broken (failed to load), Classic, Mine. '
            .. '/sk theme <name> switches every character on this PC.')
        eq(shown(themed('classic')), { 'classic', 'window Standard', 'broken broken!', 'classic Classic', 'Mine Mine' })
    end)

    test('/sk theme <name> draws with it at once, saved for every character: by its name or its file\'s, any case',
        function ()
        local s = themed()
        s.sk('/sk')
        eq({ s.sk('/sk theme CLASSIC'), s.frame() ~= nil, s.by, s.theme.picked },
           { 'Theme: Classic' .. SAVED, true, 'classic', 'classic' })
        eq({ s.sk('/sk theme "standard"'), s.frame() ~= nil, s.by, s.theme.picked },
           { 'Theme: Standard' .. SAVED, true, 'window', 'window' })
        eq({ s.sk('/sk theme MINE'), s.frame() ~= nil, s.by, s.theme.picked }, { 'Theme: Mine' .. SAVED, true, 'Mine', 'Mine' })
        eq({ s.sk('/sk theme broken'), s.theme.picked }, { 'Theme broken failed to load: ui/broken.lua:3: unexpected symbol', 'Mine' })
        eq({ s.sk('/sk theme Nope'), s.theme.picked }, { 'No theme "Nope" in Sidekick\'s ui folder. /sk theme lists them.', 'Mine' })
        s.loading(true)  -- needs no game: while you zone too
        eq({ s.sk('/sk theme classic'), s.theme.picked }, { 'Theme: Classic' .. SAVED, 'classic' })
    end)

    test('act.theme picks one as /sk theme does; one that failed to load isn\'t taken', function ()
        local s = themed()
        s.sk('/sk')
        s.frame()
        s.act.theme('classic')
        eq({ s.frame().themes.current, s.by, s.theme.picked }, { 'classic', 'classic', 'classic' })
        s.act.theme('broken')
        eq({ s.frame().themes.current, s.by, s.theme.writes }, { 'classic', 'classic', 1 })
    end)

    test('another session\'s pick is drawn here within a second; theme.txt unread, the theme stays', function ()
        local s = themed('window')
        s.sk('/sk')
        s.frame()
        s.theme.picked = 'classic'  -- written by another session
        s.frame()
        eq({ s.frame() ~= nil, s.by, s.out }, { true, 'classic', {} })
        s.theme.picked = nil  -- caught while it rewrites it
        s.frame()
        eq({ s.frame() ~= nil, s.by }, { true, 'classic' })
    end)

    test('another session\'s pick of a theme that failed to load here is looked for again: fixed since, it draws',
        function ()
        local uis = { classic = { name = 'Classic' }, mine = 'ui/mine.lua:1: unexpected symbol' }
        local s = boot({ files = { 'classic.lua', 'mine.lua' }, uis = uis, picked = 'window' })
        s.sk('/sk')
        s.frame()
        uis.mine = { name = 'Mine' }  -- fixed, then picked in another session (its look in ui/ loaded it)
        s.theme.picked = 'mine'
        s.frame()
        eq({ s.frame() ~= nil, s.by, s.out }, { true, 'mine', {} })
    end)

    test('another session\'s pick of a theme added since this one loaded draws here; its load not run, chat says so',
        function ()
        local loads = {}
        local s = themed('window', { later = { load = function () loads[#loads + 1] = 'later' end } }, {})
        s.sk('/sk')
        s.frame()
        s.theme.files = { 'later.lua' }  -- added, then picked in another session
        s.theme.picked = 'later'
        s.frame()
        eq({ s.frame() ~= nil, s.by, loads, s.out },
           { true, 'later', {}, { 'later finishes setting up at the next load: /addon reload sidekick.' } })
    end)

    test('another theme\'s error says how to go back to Standard, the PC\'s pick being kept across loads', function ()
        local s = themed('classic', { classic = { name = 'Classic', render = function () error('boom', 0) end } })
        s.sk('/sk')
        s.frame()
        eq(s.out, { 'Window closed on an error in theme Classic (/sk hud or /sk opens it again, /sk theme standard goes '
            .. 'back to Standard): boom' })
    end)

    test('/sk theme while zoning: the view drawn from before the zone lists the theme now drawing', function ()
        local s = themed()
        s.sk('/sk')
        s.frame()
        s.loading(true)
        s.sk('/sk theme classic')
        local v = s.frame()
        eq({ s.by, v and v.themes.current }, { 'classic', 'classic' })
        s.loading(false)
    end)

    test('the theme picked draws from the load; one not in ui/, or failing to load, is said and Standard drawn', function ()
        local s = themed('classic')
        s.sk('/sk')
        eq({ s.out, s.frame() ~= nil, s.by }, { {}, true, 'classic' })
        local gone = themed('classic', nil, { 'window.lua' })
        gone.sk('/sk')
        eq({ gone.frame() ~= nil, gone.by }, { true, 'window' })
        eq(themed('classic', nil, { 'window.lua' }).out, { 'No theme "classic" in Sidekick\'s ui folder: using Standard.' })
        eq(themed('broken').out, { 'Theme broken failed to load, using Standard: ui/broken.lua:3: unexpected symbol' })
        eq(boot({ files = { 'custom.lua' }, uis = { custom = 'boom' } }).out, { 'Theme custom failed to load, using Standard: boom' })
    end)

    test('a theme added to ui/ is found when Sidekick Settings open; the one drawing stays listed once its file goes',
        function ()
        local s = themed(nil, { new = { name = 'New' } }, {})
        eq(shown(s), { 'window', 'window Standard' })
        s.theme.files = { 'new.lua' }
        eq(shown(s), { 'window', 'window Standard', 'new New' })
        s.sk('/sk theme new')
        s.theme.files = {}
        eq(s.sk('/sk theme'), 'Themes: Standard, New (in use). /sk theme <name> switches every character on this PC.')
        eq(shown(s), { 'new', 'window Standard', 'new New' })
    end)

    test('every theme\'s load runs at Ashita\'s load event, drawing or not; one found after says a reload finishes it',
        function ()
        local loads = {}
        local function loader(name) return { load = function () loads[#loads + 1] = name end } end
        local s = themed(nil, { fonts = loader('fonts'), later = loader('later'), bad = { load = function () error('no font', 0) end } },
            { 'fonts.lua', 'bad.lua' })
        eq({ loads, s.out }, { { 'fonts' }, { 'Theme bad failed at load: no font' } })
        s.theme.files = { 'fonts.lua', 'bad.lua', 'later.lua' }
        eq(s.sk('/sk theme later'), 'Theme: later' .. SAVED
            .. ' | later finishes setting up at the next load: /addon reload sidekick.')
        eq({ loads, s.sk('/sk theme fonts') }, { { 'fonts' }, 'Theme: fonts' .. SAVED })
    end)

    test('a pick theme.txt can\'t take still draws here, and says so; the file\'s theme isn\'t taken back', function ()
        local s = themed('window')
        s.theme.unwritable = true
        eq(s.sk('/sk theme classic'), 'The theme couldn\'t be saved: the other sessions and the next load won\'t have it.'
            .. ' | Theme: Classic' .. SAVED)
        s.sk('/sk')
        s.frame()
        eq({ s.frame() ~= nil, s.by, s.theme.picked }, { true, 'classic', 'window' })
    end)

    test('a job change\'s abilities, listed once the server\'s ability list comes after the job', function ()
        local e = boot(false)
        local p, has = e.player, { [757] = true }  -- Afflatus Solace, WHM's
        p.HasAbility = function (_, id) return has[id] == true end
        e.packet(0x0AC)  -- WHM's list, as at login
        e.sk('/sk')
        e.frame()
        local v = e.frame()
        eq({ mentions(v, 'Afflatus Solace'), mentions(v, 'Berserk') }, { true, false })
        p.GetMainJob = function () return 1 end  -- WAR: the client still lists WHM's abilities
        v = e.frame()
        eq({ mentions(v, 'Afflatus Solace'), mentions(v, 'Berserk') }, { true, false })
        has = { [543] = true }  -- then the server's list: Berserk
        e.packet(0x0AC)
        v = e.frame()
        eq({ mentions(v, 'Afflatus Solace'), mentions(v, 'Berserk') }, { false, true })
    end)
end)
restore()
if not ok then error(err, 0) end
