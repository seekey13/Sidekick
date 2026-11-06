-- Sidekick.lua's commands and which windows it draws, with Ashita stubbed out: /sk, /sk hud, /sk alt, /sk toggle,
-- v2's command names, zoning and a UI's error. Sidekick.lua runs on fresh copies of every module, and everything it's given is put back at the end, so
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
-- sessions, sent, loading(on), ui (the stub UI: its render can be replaced), act (the last frame's), party and over
-- (who the game reads besides you, and its snapshot's flags), queued (the commands sent to the game), files (the settings
-- files, by alias), out (chat since the last command) }. With `spells`, you know every spell your job has (else none).
-- `ui`: what the ui file was left holding, over its defaults.
local function boot(custom, spells, ui)
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
    local loading = false
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
        e.sk('/sk stop')
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
        z.loading(true); z.frame()
        eq(z.files.ui.running, false)  -- what the next load starts as
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
