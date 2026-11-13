-- tools/e2e.lua against a fake client and a fake Sidekick: what it records (Sidekick's sends, your actions out,
-- your actions' results in), and scenarios run a frame at a time: passed, failed, skipped, refused, each cleaned up.
local engine = require('core.engine')
local share = require('core.share')
local tracked = require('core.tracked')

local saved = { AshitaCore = rawget(_G, 'AshitaCore'), ashita = rawget(_G, 'ashita'), vana = rawget(_G, 'vana') }
local real = { tick = share.tick, decide = engine.decide }

local now = 100
local handlers, queued, packets = {}, {}, {}
local status = { running = false, sent = {} }  -- Sidekick's own, as share.tick is handed it
local world = {
    party = { { name = 'Dev', sid = 1, tidx = 0x400, hp = 900, hpp = 100, mp = 400, mpp = 100 },
              { name = 'Test', sid = 2, tidx = 0x401, hp = 1200, hpp = 100, mp = 300, mpp = 100 } },
    ents = { [0x400] = 'Dev', [0x401] = 'Test' },
}
local function const(v) return function () return v end end
local function member(i) return world.party[i + 1] or {} end
local party = {
    GetMemberIsActive = function (_, i) return world.party[i + 1] and 1 or 0 end,
    GetMemberName = function (_, i) return member(i).name end,
    GetMemberServerId = function (_, i) return member(i).sid end,
    GetMemberTargetIndex = function (_, i) return member(i).tidx end,
    GetMemberHP = function (_, i) return member(i).hp end,
    GetMemberHPPercent = function (_, i) return member(i).hpp end,
    GetMemberMP = function (_, i) return member(i).mp end,
    GetMemberMPPercent = function (_, i) return member(i).mpp end,
    GetMemberTP = const(0), GetMemberZone = const(105),
}
local em = {
    GetName = function (_, i) return world.ents[i] end,
    GetRawEntity = function (_, i) return world.ents[i] and {} or nil end,
    GetRenderFlags0 = function (_, i) return world.ents[i] and 0x200 or 0 end,
    GetHPPercent = const(100), GetStatus = const(0), GetServerId = const(0),
}
local mm = { GetParty = const(party), GetEntity = const(em),
             GetPlayer = const({ GetHPMax = const(900), GetMPMax = const(400) }),
             GetInventory = const({ GetContainerItem = function (_, bag, slot) return { Id = bag * 1000 + slot } end }) }
-- A /sk command reaches the fake Sidekick: start and stop set it running.
local chat = { QueueCommand = function (_, _, line)
    queued[#queued + 1] = line
    if line == '/sk start' then status.running = true elseif line == '/sk stop' then status.running = false end
end }
-- GM lines: the text of each chat packet.
local pm = { AddOutgoingPacket = function (_, _, b)
    local chars = {}
    for k = 7, #b do if b[k] == 0 then break end chars[#chars + 1] = string.char(b[k]) end
    packets[#packets + 1] = table.concat(chars)
end }
rawset(_G, 'AshitaCore', { GetMemoryManager = const(mm), GetChatManager = const(chat), GetPacketManager = const(pm) })
-- 0x028 bits as a list of 0s and 1s, read high bit first (tests/packets_test.lua's fake).
rawset(_G, 'ashita', {
    events = { register = function (event, _, fn) handlers[event] = fn end, unregister = function (event) handlers[event] = nil end },
    bits = { unpack_be = function (d, _, at, n)
        local v = 0
        for i = 1, n do v = v * 2 + (d[at + i] or 0) end
        return v
    end },
})
rawset(_G, 'vana', { time = { clock = function () return now end } })

share.tick = function () end     -- the real one writes session files
engine.decide = function () end
package.loaded['tools.e2e'] = nil
local e2e = require('tools.e2e')
e2e.say = function () end

-- One frame of the game: the clock on, Sidekick handing on its status, the runner's step.
-- `world.react`, when set, plays the game's and Sidekick's side each frame; `world.units` are the units Sidekick decides on.
local function frame(dt)
    now = now + (dt or 0.1)
    if world.react then world.react() end
    share.tick({}, now, status, {})
    engine.decide({ units = world.units or {} },
        { { name = 'Poisona' }, { name = 'Cursna', role = 'remove', family = 'Cursna', kind = 'ma' } },
        { buff = { hold_aoe = false }, remove = { on = true, skip = {} }, rows = world.rows or {} }, {})
    handlers.d3d_present()
end
local function frames(seconds) for _ = 1, math.ceil(seconds / 0.1) do frame() end end

-- Sidekick sending: an entry at the head of status.sent, as Sidekick.lua puts it there.
local function sidekick_sends(action, target, behavior)
    table.insert(status.sent, 1, { action = action, kind = 'ma', target = target, behavior = behavior or 'heal',
                                   why = 'test', command = ('/ma "%s" %s'):format(action, target) })
end

-- An incoming 0x028 of yours: { category, param, { { target sid, message, param } ... } }.
local function action_packet(actor, category, param, targets)
    local d = {}
    local function put(n, v) for i = n - 1, 0, -1 do d[#d + 1] = math.floor(v / 2 ^ i) % 2 end end
    put(40, 0); put(32, actor); put(6, #targets); put(4, 0); put(4, category); put(16, param); put(48, 0)
    for _, tg in ipairs(targets) do
        put(32, tg[1]); put(4, 1)
        put(17, 0); put(5, 0); put(5, 0); put(17, tg[3] or 0); put(10, tg[2]); put(31, 0)
        put(1, 0); put(1, 0)
    end
    return { id = 0x028, data_raw = d, size = math.ceil(#d / 8) }
end

-- An outgoing packet's bytes as a string: id, then the fields at their offsets.
local function out_packet(id, size, fields)
    local b = {}
    for k = 1, size do b[k] = 0 end
    for off, v in pairs(fields) do
        local n, width = v[1], v[2]
        for k = 0, width - 1 do b[off + k + 1] = math.floor(n / 256 ^ k) % 256 end
    end
    return { id = id, data = string.char(unpack(b)) }
end

local function scenario(name, sc) package.preload['tests.e2e.' .. name] = function () return sc end end

local function run_to_end(...)
    e2e.clear()
    e2e.run(...)
    for _ = 1, 3000 do
        frame()
        local s = e2e.status()
        if not s.running and #s.queued == 0 then break end
    end
    return e2e.report()
end

test('Sidekick\'s sends are recorded from its status as they appear, never the ones before it was watched', function ()
    sidekick_sends('Cure', 'Test')        -- before: history
    frame()
    local first = #e2e.events(0, 'sent')
    sidekick_sends('Cure II', 'Test')
    frame()
    local sent = e2e.events(0, 'sent')
    eq({ first, #sent, sent[#sent].action, sent[#sent].target, sent[#sent].behavior }, { 0, 1, 'Cure II', 'Test', 'heal' })
end)

test('your actions out (spells, items, /heal) and their results in (begun, landed, interrupted)', function ()
    local since = #e2e.events()
    handlers.packet_out(out_packet(0x01A, 0x10, { [0x04] = { 2, 4 }, [0x08] = { 0x401, 2 }, [0x0A] = { 3, 2 }, [0x0C] = { 20, 4 } }))
    handlers.packet_out(out_packet(0x037, 0x14, { [0x04] = { 1, 4 }, [0x0C] = { 0x400, 2 }, [0x0E] = { 7, 1 }, [0x10] = { 0, 4 } }))
    handlers.packet_out(out_packet(0x0E8, 0x08, { [0x04] = { 1, 4 } }))
    handlers.packet_out(out_packet(0x015, 0x18, {}))  -- a position: not recorded
    handlers.packet_in(action_packet(1, 8, 24931, { { 2, 327, 20 } }))   -- begin Cursna on Test
    handlers.packet_in(action_packet(1, 4, 20, { { 2, 75 } }))           -- landed: no effect
    handlers.packet_in(action_packet(1, 8, 28787, { { 2, 0, 20 } }))     -- interrupted
    handlers.packet_in(action_packet(3, 4, 1, { { 2, 7, 100 } }))        -- another's: not recorded
    handlers.packet_in(action_packet(1, 1, 0, { { 9, 1, 30 } }))         -- your auto-attack: not recorded
    local got = {}
    for _, ev in ipairs({ unpack(e2e.events(), since + 1) }) do
        got[#got + 1] = ev.type == 'act' and ('act %s %d on %d %s'):format(ev.kind, ev.id, ev.target, tostring(ev.name))
            or ev.type == 'camp' and ('camp ' .. ev.mode)
            or ('%s %d: %d msg %d'):format(ev.type, ev.id, ev.targets[1].id, ev.targets[1].message)
    end
    eq(got, { 'act ma 20 on 2 Test', 'act item 7 on 1 Dev', 'camp on', 'begin 20: 2 msg 327', 'finish 20: 2 msg 75',
              'interrupt 20: 2 msg 0' })
end)

test('a scenario that passes: the scene, the send timed from it, the landing, then everything undone', function ()
    status.running, status.sent, packets, queued = false, {}, {}, {}
    scenario('fake_heal', { run = function (t)
        t.start()
        t.gm.hp_pct('Test', 40)
        t.wait(0.5)
        sidekick_sends('Cure IV', 'Test')
        local sent = t.expect({ behavior = 'heal', on = 'test' }, 5)
        t.wait(2)
        handlers.packet_in(action_packet(1, 4, 4, { { 2, 7, 500 } }))
        t.lands(sent, 5)
    end })
    local r = run_to_end('fake_heal')[1]
    eq({ r.result, r.why, r.timings.heal >= 0.5 and r.timings.heal < 0.8, r.timings.landed >= 2 },
       { 'pass', nil, true, true })
    eq(packets, { '!hp 480 Test', '!hp 99999 Test', '!mp 99999 Test' })  -- the scene, then its undo
    eq({ queued, status.running }, { { '/sk start', '/sk stop' }, false })  -- running again only while it ran
end)

test('a send that never comes fails, with what led up to it; the cleanup still runs', function ()
    status.sent, packets = {}, {}
    scenario('fake_none', { run = function (t)
        t.gm.effect('Test', 'poison', 1, 60)
        t.expect({ behavior = 'remove', on = 'Test' }, 2)
    end })
    local r = run_to_end('fake_none')[1]
    eq({ r.result, r.why }, { 'fail', 'a send {behavior=remove on=Test}: not within 2s' })
    eq(r.trail[#r.trail].type, 'gm')
    eq(packets, { '!addeffect Test 3 1 60', '!deleffect Test 3', '!hp 99999 Test', '!mp 99999 Test' })
end)

test('the client or the server refusing the command fails its landing, saying which', function ()
    for _, case in ipairs({ { 'A command error occurred.', 'the client refused /ma "Cure V" Test ("A command error occurred")' },
                            { 'Dev cannot cast Arise.', 'the server refused Cure V on Test: Dev cannot cast Arise.' } }) do
        scenario('fake_refused', { run = function (t)
            sidekick_sends('Cure V', 'Test')
            local sent = t.expect({ on = 'Test' }, 2)
            handlers.text_in({ mode = 157, message = '\30\1' .. case[1] .. '\127\49' })
            t.lands(sent, 5)
        end })
        local r = run_to_end('fake_refused')[1]
        eq({ r.result, r.why }, { 'fail', case[2] })
    end
end)

test('nothing sent when nothing should be; a send then fails it', function ()
    scenario('fake_quiet', { run = function (t) t.expect_none({ on = 'Test' }, 1) end })
    eq(run_to_end('fake_quiet')[1].result, 'pass')
    scenario('fake_loud', { run = function (t)
        sidekick_sends('Cure', 'Test')
        t.expect_none({ on = 'Test' }, 1)
    end })
    local r = run_to_end('fake_loud')[1]
    eq({ r.result, r.why }, { 'fail', 'sent Cure on Test (heal: test), expected none {on=Test}' })
end)

test('skipped for want of a setting, an error with its traceback, a missing scenario, the time running out', function ()
    scenario('fake_skip', { run = function (t) t.need(t.cfg().buff.hold_aoe, 'area buffs are not held') end })
    scenario('fake_bug', { run = function () local x = nil; return x.y end })
    scenario('fake_slow', { timeout = 2, run = function (t) t.wait(10) end })
    local r = run_to_end('fake_skip', 'fake_bug', 'no_such_scenario', 'fake_slow')
    eq({ r[1].result, r[1].why, r[2].result, r[3].result, r[4].result, r[4].why },
       { 'skip', 'area buffs are not held', 'error', 'error', 'fail', 'ran out of time' })
    eq(r[2].why:find('attempt to index', 1, true) ~= nil and r[2].why:find('stack traceback', 1, true) ~= nil, true)
end)

test('who\'s who: the party member, the alliance (none here: skipped), a tracked player near you', function ()
    tracked.list = {}
    scenario('fake_who', { run = function (t) t.note(t.member()); t.note(t.me()); t.ally() end })
    local r = run_to_end('fake_who')[1]
    eq({ r.notes, r.result, r.why }, { { 'Test', 'Dev' }, 'skip', 'no player in the alliance\'s other parties in your zone' })
end)

test('aborted: the queue emptied, the scenario running stopped at its next wait, its cleanup run', function ()
    packets = {}
    scenario('fake_long', { run = function (t) t.gm.hp('Test', 100); t.wait(30) end })
    e2e.clear()
    e2e.run('fake_long', 'fake_long')
    frames(1)
    e2e.abort()
    frames(1)
    eq({ #e2e.report(), e2e.report()[1].why, e2e.status().running, packets },
       { 1, 'aborted', nil, { '!hp 100 Test', '!hp 99999 Test', '!mp 99999 Test' } })
end)

test('a fault in the runner ends the scenario as an error at its next wait, its cleanup still run', function ()
    packets = {}
    scenario('fake_long', { run = function (t) t.gm.hp('Test', 100); t.wait(30) end })
    e2e.clear()
    e2e.run('fake_long')
    frames(1)
    handlers.packet_in({ id = 0x028, size = 100 })  -- no bytes: the parse fails
    frames(1)
    local r = e2e.report()[1]
    eq({ r.result, r.why:match('^runner: ') ~= nil, e2e.status().running, packets },
       { 'error', true, nil, { '!hp 100 Test', '!hp 99999 Test', '!mp 99999 Test' } })
end)

test('a setting for the scenario: not saved while it runs, put back and saved after', function ()
    local settings = require('core.settings')
    local save, saves, during = settings.save, 0, nil
    settings.save = function () saves = saves + 1 end
    local cfg
    scenario('fake_setting', { run = function (t)
        cfg = t.cfg()
        t.setting('buff.hold_aoe', true)
        during = { cfg.buff.hold_aoe, saves }
    end })
    run_to_end('fake_setting')
    settings.save = save
    eq({ during, cfg.buff.hold_aoe, saves }, { { true, 0 }, false, 1 })
end)

test('a read through t.gm (who, cursor...) is no scene: the scene\'s moment stays', function ()
    scenario('fake_read', { run = function (t)
        t.gm.hp('Test', 100)
        local since = t.since
        now = now + 1
        t.note(tostring(t.gm.who('Test').name))
        t.check(t.since == since, 'a read moved the scene\'s moment')
    end })
    local r = run_to_end('fake_read')[1]
    eq({ r.result, r.why, r.notes[1] }, { 'pass', nil, 'Test' })
end)

test('every scenario in the suite loads, with what it checks and a run', function ()
    for _, s in ipairs(e2e.list()) do
        eq(s.about:find('does not load', 1, true), nil, s.name)
        package.loaded['tests.e2e.' .. s.name] = nil
        eq(type(require('tests.e2e.' .. s.name).run), 'function', s.name)
    end
end)

-- The cursna scenarios against a fake game: `misses` Cursnas with no effect, then one that takes the Doom off.
-- `how`: stall = no Cursna after the first; no_heal = no heal ever; let_go = Sidekick drops the Doom after the first miss.
local function noted(r, pattern)
    for _, n in ipairs(r.notes) do if n:find(pattern) then return true end end
    return false
end
local function cursna_game(misses, how)
    local test = { name = 'Test', buffs = {} }
    world.units = { { name = 'Dev', buffs = {} }, test }
    status.running, status.sent, packets, queued = false, {}, {}, {}
    local seen_lines, casts, pending, heals = 0, 0, {}, 0
    local function later(dt, fn) pending[#pending + 1] = { at = now + dt, fn = fn } end
    world.react = function ()
        for i = #pending, 1, -1 do
            if now >= pending[i].at then local p = table.remove(pending, i); p.fn() end
        end
        while seen_lines < #packets do
            seen_lines = seen_lines + 1
            local line = packets[seen_lines]
            if line == '!addeffect Test 15 10 60' then
                later(0.5, function () test.buffs[15] = true end)
                later(1, function () casts = casts + 1; sidekick_sends('Cursna', 'Test', 'remove') end)
            elseif line:match('^!deleffect Test 15') then
                test.buffs[15] = nil
            elseif line:match('^!hp %d+ Test$') and line ~= '!hp 99999 Test' then
                world.party[2].hpp = 40
                heals = heals + 1
                if how == 'no_heal' then return end
                later(0.5, function () sidekick_sends('Cure V', 'Test', 'heal') end)
                later(3, function ()
                    handlers.packet_in(action_packet(1, 4, 6, { { 2, 7, 700 } }))
                    world.party[2].hpp = 100
                end)
            end
        end
        -- Each Cursna sent lands 1.5 s later; the next goes at its recast while the Doom stays, unless stalled.
        local last = status.sent[1]
        if last and last.action == 'Cursna' and not last.landed then
            last.landed = true
            local n = casts
            later(1.5, function ()
                local took = n > misses
                handlers.packet_in(action_packet(1, 4, 20, { { 2, took and 359 or 75, took and 15 or 0 } }))
                if took or how == 'let_go' then test.buffs[15] = nil
                elseif how ~= 'stall' then later(10, function () casts = casts + 1; sidekick_sends('Cursna', 'Test', 'remove') end) end
            end)
        end
    end
    local r = run_to_end('cursna_party')[1]
    world.react, world.units, world.party[2].hpp = nil, nil, 100
    return r, heals
end

test('cursna_party: Doom on Test, Cursna until it goes, a heal after the first and after the last, then quiet', function ()
    local r, heals = cursna_game(2)
    eq({ r.result, r.why, heals }, { 'pass', nil, 2 })
    eq({ r.timings.heal_after_the_first_Cursna ~= nil, r.timings.heal_after_the_Cursna_that_took_it ~= nil }, { true, true })
    eq(noted(r, '^Doom taken off by Cursna 3$'), true)
    eq(packets[#packets - 2], '!deleffect Test 15')  -- the cleanup
end)

test('cursna_party: the first Cursna takes it: one heal, after it', function ()
    local r, heals = cursna_game(0)
    eq({ r.result, heals, r.timings.heal_after_the_Cursna_that_took_it ~= nil }, { 'pass', 1, true })
end)

test('cursna_party: a Doom outlasting four Cursnas is bad luck, not a stall; Sidekick still heals after', function ()
    local r, heals = cursna_game(10)
    eq({ r.result, heals }, { 'pass', 2 })
    eq(noted(r, '^the Doom outlasted 4 Cursnas'), true)
end)

test('cursna_party: Sidekick letting the Doom go: noted, taken off, a heal, then quiet', function ()
    local r = cursna_game(5, 'let_go')
    eq(r.result, 'pass')
    eq(noted(r, '^Sidekick took the Doom as gone after 1 Cursnas with no effect'), true)
    eq(noted(r, '^after the Doom was let go, Cure V'), true)
end)

test('cursna_party: no Cursna once its recast is up fails, saying what Sidekick was doing', function ()
    status.why = 'nothing to do'
    local r = cursna_game(5, 'stall')
    status.why = nil
    -- Timed from the last Cursna sent, not from after the heal between.
    eq({ r.result, r.why:match('^a Cursna on Test once its recast was up: not within ([%d.]+)s %(Sidekick: nothing to do%)$') },
       { 'fail', '10.4' })
end)

test('cursna_party: nothing at all after a Cursna (no heal) fails, saying what Sidekick was doing', function ()
    status.why = 'nothing to do'
    local r = cursna_game(5, 'no_heal')
    status.why = nil
    eq({ r.result, r.why }, { 'fail', 'a heal on Test after the first Cursna: not within 10s (Sidekick: nothing to do)' })
end)

test('cursna_party: Cursna switched off under Remove skips', function ()
    world.rows = { Cursna = { on = false } }
    local r = cursna_game(0)
    world.rows = nil
    eq({ r.result, r.why }, { 'skip', 'Cursna is switched off (Remove)' })
end)

test('cursna_tracked: a tracked player\'s HP that doesn\'t fall (no GM level 4) skips, before any Doom', function ()
    tracked.list = { { name = 'Tracked' } }
    world.ents[0x402] = 'Tracked'
    world.units = { { name = 'Dev', buffs = {} }, { name = 'Tracked', buffs = {} } }
    status.running, packets = false, {}
    local r = run_to_end('cursna_tracked')[1]
    world.ents[0x402], world.units, tracked.list = nil, nil, {}
    eq({ r.result, r.why }, { 'skip', 'Tracked\'s HP didn\'t fall: a tracked player\'s is set by !exec, which needs GM level 4' })
    for _, line in ipairs(packets) do eq(line:find('addeffect', 1, true), nil, line) end
end)

test('unwatch waits for a scenario running: aborted, cleaned up, then unhooked', function ()
    packets = {}
    e2e.clear()
    e2e.run('fake_long')
    frames(1)
    eq(e2e.unwatch(), false)
    eq(handlers.d3d_present ~= nil, true)  -- still hooked: its cleanup needs the frames
    frames(1)
    eq({ e2e.report()[1].why, e2e.status().running, packets },
       { 'aborted', nil, { '!hp 100 Test', '!hp 99999 Test', '!mp 99999 Test' } })
end)

test('unwatch hands Sidekick its own functions back', function ()
    local tick, decide = share.e2e_tick, engine.e2e_decide
    eq(e2e.unwatch(), true)
    eq({ share.tick == tick, engine.decide == decide, share.e2e_tick, engine.e2e_decide, handlers.d3d_present },
       { true, true, nil, nil, nil })
end)

share.tick, engine.decide = real.tick, real.decide
package.loaded['tools.e2e'] = nil
for name in pairs(package.preload) do if name:find('^tests%.e2e%.fake_') then package.preload[name] = nil end end
for k, v in pairs(saved) do rawset(_G, k, v) end
