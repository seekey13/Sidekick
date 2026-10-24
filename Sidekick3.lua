--[[
Sidekick3 - Support Job Automation Framework (v3 rewrite)
Copyright (c) 2026 Seekey
https://github.com/seekey13/Sidekick3

This addon is designed for Ashita v4 and the CatsEyeXI private server.

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version. It is
distributed WITHOUT ANY WARRANTY; see LICENSE for the details.
SPDX-License-Identifier: GPL-3.0-or-later
]]--

addon.name    = 'Sidekick3'
addon.author  = 'Seekey'
addon.version = '3.0.0-dev'
addon.desc    = 'Support Job Automation Framework'
addon.link    = 'https://github.com/seekey13/Sidekick3'

require('common')
local chat = require('chat')
local afk = require('core.afk')
local can = require('core.can')
local catalog = require('core.catalog')
local engine = require('core.engine')
local game = require('core.game')
local knowledge = require('core.knowledge')
local packets = require('core.packets')
local profiles = require('core.profiles')
local resources = require('core.resources')
local settings = require('core.settings')
local share = require('core.share')
local tracked = require('core.tracked')
local util = require('core.util')
local imgui = require('imgui')
local blu = require('jobs.blu')
local brd = require('jobs.brd')
local model = require('ui.model')

-- A line in chat in `style` (chat.message, chat.error, chat.warning).
local function say(style, fmt, ...)
    print(chat.header(addon.name) .. style(fmt:format(...)))
end
local function printf(fmt, ...) say(chat.message, fmt, ...) end

local function abbr(job)
    return job > 0 and AshitaCore:GetResourceManager():GetString('jobs.names_abbr', job) or 'none'
end

-- The catalog for the character as it is right now, rebuilt when job, level or
-- the blue magic set changes (or on demand: a newly learned spell changes none).
local cat = { key = nil, list = {}, by_spell = {} }
-- The blue magic set not known yet: said once, and only when loaded in game
-- (on login the zone-in 0x044 may come a moment after the job level).
local said_unset = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel() == 0
local function current_catalog(force)
    local p = AshitaCore:GetMemoryManager():GetPlayer()
    local key = ('%d/%d/%d/%d/%d'):format(p:GetMainJob(), p:GetMainJobLevel(), p:GetSubJob(), p:GetSubJobLevel(), blu.version())
    if force or key ~= cat.key then
        cat.key, cat.by_spell = key, {}
        local blue = p:GetMainJob() == blu.JOB or p:GetSubJob() == blu.JOB
        if blue and not blu.set() and not said_unset then
            said_unset = true
            printf('No blue magic until the server sends your set spells: it does when you zone or change one.')
        end
        cat.list = catalog.build(resources.load(), {
            main = p:GetMainJob(), main_lv = p:GetMainJobLevel(),
            sub = p:GetSubJob(), sub_lv = p:GetSubJobLevel(),
            has_spell = function (id) return p:HasSpell(id) end,
            has_ability = function (id) return p:HasAbility(id) end,
            set_spells = blu.set() or {},  -- none until the server says (jobs/blu.lua)
        }, knowledge)
        for _, a in ipairs(cat.list) do
            if a.kind == 'ma' then cat.by_spell[a.id] = a end
        end
    end
    return cat.list
end

local cfg, cfg_pair    -- settings for the current job pair
local mem = {}         -- the engine's memory between ticks

-- What the window shows and toggles besides the settings.
local status = {
    running = false,  -- automation on (/sk3 start); never resumed on load
    open = nil,       -- window shown; from cfg.ui.open at the first settings load
    failed = nil,     -- the UI raised an error: not drawn, the widget either, until /sk3 or /sk3 widget
    log = false,      -- /sk3 log prints each action to chat; off unless debugging
    intent = nil,     -- the latest decision as a sent-style entry, or nil and...
    why = nil,        -- ...why nothing (a gate, 'nothing to do', 'waiting for a cure')
    sent = {},        -- the last 10 sends, newest first: { at, command, english, action, kind, target, behavior, why }
    sessions = {},    -- the other Sidekick sessions on this PC (core/share.lua), by name...
    watching = {},    -- ...those whose Sidekick Settings are shown here: { [name] = true }...
    views = {},       -- ...and the views they published for it
    restart = nil,    -- automation just started: AFK sleep starts over (core/afk.lua)
}
local SENT_KEPT = 10

-- Packets feed the cast lock and the trusts' statuses; they need to know who you
-- are, who is tracked, and how long a spell's buff lasts.
local packet_ctx = {
    tracks = {},
    duration = function (spell_id)
        local a = cat.by_spell[spell_id]
        return a and a.duration
    end,
    song = function (spell_id)  -- your songs are stamped on who they land on (jobs/brd.lua)
        local a = cat.by_spell[spell_id]
        return a and a.role == 'song' and a or nil
    end,
}

-- Latest game snapshot, at most 10 a second: plenty for a 1.1s action throttle.
-- Returns it and whether it was just read.
local snap = { loading = true, now = 0, tracks = {} }
local function refresh(now)
    if now - snap.now < 0.1 and not snap.loading then return snap, false end
    snap = game.read(now, not status.running or mem.afk and mem.afk.asleep)
    if not snap.loading then
        current_catalog()
        packet_ctx.me, packet_ctx.pet, packet_ctx.tracks = snap.me.sid, snap.pet and snap.pet.sid, snap.tracks
        packet_ctx.buffs, packet_ctx.slots = snap.me.buffs, brd.slots(snap)
        local pair = abbr(snap.main) .. '_' .. abbr(snap.sub)
        if pair ~= cfg_pair then brd.clear() end  -- your songs go with the job
        if pair ~= cfg_pair or settings.switched() then cfg, cfg_pair, mem = settings.load(pair), pair, {} end
        -- The window stays as it is across a job change; only /sk3 and its close button move it.
        if status.open == nil then status.open = cfg.ui.open end
        -- AFK sleep counts only while running, and starts over on a start or a job change.
        if status.restart then mem.afk, status.restart = nil, nil end
        if status.running then
            mem.afk = mem.afk or {}
            local said
            snap.afk, said = afk.update(snap, cfg, mem.afk)
            snap.afk_in = afk.left(snap, cfg, mem.afk)
            if said then printf('%s', said) end
        else
            mem.afk = nil
        end
    end
    return snap, true
end

local function entry(intent, g)
    local command, english = engine.command(intent, cfg, g)
    return { at = g.now, command = command, english = english, action = intent.action.name, kind = intent.action.kind,
             target = intent.target and intent.target.name, behavior = intent.behavior, why = intent.why }
end

-- Names a Japanese client was sent in English (no Japanese one in the DAT), each
-- warned about once a session, as v2: the client won't take them.
local warned_english = {}

-- Each new Phantom Roll total, its die and a Bust, printed while the log is on
-- (as v2, lucky and 11 called out).
local rolled_at
local function say_roll(g)
    local r = g.roll
    if not r or r.at == rolled_at then return end
    rolled_at = r.at
    for _, a in ipairs(status.log and cat.list or {}) do
        if a.id == r.id and a.lucky then
            if r.bust then printf('%s: Bust', a.name); return end
            local word = r.total == a.lucky and ': lucky!' or r.total == 11 and ': 11!' or r.total == a.unlucky and ': unlucky' or ''
            printf('%s: %d (total %d)%s', a.name, r.die or 0, r.total, word)
        end
    end
end

-- Decide on each fresh snapshot: to act when running and the server will take a
-- command, and while the window is open, to show what it would do. A decision
-- that isn't sent changes nothing (revive marks a raise only through intent.sent).
local function tick(g)
    if g.loading then return end
    say_roll(g)
    -- A status cancelled mid-cast (Utsusemi's last shadow, jobs/nin.lua; Pianissimo
    -- under an area song, jobs/brd.lua): packet 0x0F1, as the Debuff addon sends.
    local off = engine.cancel(g, mem)
    if off then
        AshitaCore:GetPacketManager():AddOutgoingPacket(0xF1, { 0xF1, 0x04, 0x00, 0x00, off % 256, math.floor(off / 256), 0x00, 0x00 })
    end
    local act = status.running and engine.ready(g, mem)
    if not (act or status.open or cfg.ui.widget) then return end
    local intent, why = engine.decide(g, cat.list, cfg, mem)
    status.intent, status.why = intent and entry(intent, g), why
    local gather = status.running and engine.gather(g, cfg, mem)
    if gather then AshitaCore:GetChatManager():QueueCommand(1, gather) end
    if not (act and intent) then return end
    AshitaCore:GetChatManager():QueueCommand(0, status.intent.command)
    if status.intent.english and not warned_english[status.intent.action] then
        warned_english[status.intent.action] = true
        say(chat.warning, 'No Japanese name for "%s": sent in English, which the Japanese client won\'t take.', status.intent.action)
    end
    engine.sent(intent, g, mem)
    game.sent(intent.action)
    table.insert(status.sent, 1, status.intent)
    status.sent[SENT_KEPT + 1] = nil
    if status.log then printf('%s  (%s: %s)', status.intent.command, intent.behavior, intent.why) end
end

-- Names in chat-sized lines.
local function print_names(title, names)
    local line = title .. ':'
    for _, n in ipairs(names) do
        if #line + #n > 110 then printf('%s', line); line = '   ' end
        line = line .. ' ' .. n .. ','
    end
    printf('%s', (line:gsub(',$', '')))
end

-- /sk3 catalog [unknown]: what Sidekick can automate for this job, by role;
-- 'unknown' lists the actions no knowledge row covers.
local function show_catalog(which)
    local by_role, order = {}, {}
    for _, a in ipairs(current_catalog(true)) do
        local role = a.role or 'unknown'
        if not by_role[role] then by_role[role] = {}; order[#order + 1] = role end
        local names = by_role[role]
        names[#names + 1] = a.label or a.name
    end
    table.sort(order)
    for _, role in ipairs(order) do
        local names = by_role[role]
        if (role == 'unknown') == (which == 'unknown') then
            print_names(('%s (%d)'):format(role, #names), names)
        end
    end
    if which ~= 'unknown' and by_role.unknown then
        printf('%d more with no automation; /sk3 catalog unknown lists them.', #by_role.unknown)
    end
end

-- /sk3 state: the snapshot automation decides from, to check it reads the game right.
local function show_state(g)
    local statuses = resources.load().statuses
    local flags = {}
    for _, f in ipairs(model.FLAGS) do if g[f] then flags[#flags + 1] = f end end
    printf('%s%d/%s%d  zone %d  %s', abbr(g.main), g.main_lv, abbr(g.sub), g.sub_lv, g.zone, table.concat(flags, ' '))
    for _, u in ipairs(g.units) do
        local names = {}
        for id in pairs(u.buffs) do names[#names + 1] = statuses[id] and statuses[id].en or tostring(id) end
        table.sort(names)
        local out = u.kind == 'tracked'  -- max HP estimated from the level, or yours (else a session file's); no MP read
        local guess = out and not tracked.find(u.sid).max_hp
        local kind = u.auto and 'auto' or out and 'track' or u.kind == 'alliance' and model.TAGS[u.slot] or u.kind
        printf('  %-5s %-14s HP %3d%%%s %s  %s  %s', kind, u.name, u.hpp,
            u.max_hp and ((guess and '/~' or '/') .. u.max_hp) or '',
            out and (u.main_lv and ('%s%d'):format(abbr(u.main), u.main_lv) or 'lv ?') or ('MP %3d%%'):format(u.mpp),
            u.in_zone and ('%.1fy'):format(u.dist or 0) or 'away', table.concat(names, ', '))
    end
    for _, t in ipairs({ { 'bt', g.bt }, { 'pet', g.pet } }) do
        local e = t[2]
        if e then printf('  %-5s %-14s HP %3d%%  %.1fy%s', t[1], e.name, e.hpp, e.dist, e.mob and ' (mob)' or '') end
    end
    if g.stratagems then printf('  stratagems %d', g.stratagems) end
    if g.ready then printf('  Ready charges %d', g.ready) end
end

-- /sk3 plan: what automation would do this moment, without doing it.
local function show_plan(g)
    local intent, why = engine.decide(g, cat.list, cfg, mem)
    if intent then
        printf('Would send %s  (%s: %s)', engine.command(intent, cfg, g), intent.behavior, intent.why)
    else
        printf('Nothing to do now: %s.', why)
    end
    if not engine.ready(g, mem) then printf('(still inside the post-action lockout)') end
end

-- The tracked player named `name` (any case), else nil.
local function tracked_named(name) return util.named(tracked.list, name) end

-- /sk3 buff [name] [me p1..p5 b0..c5 <tracked name> | off]: turn a buff row on for
-- those targets, or off; with no name, list the rows that are on. The buff's name
-- is the longest run of leading words naming one; the words after it are tracked players.
local SLOTS = { p0 = 0 }  -- me, p1-p5, and the alliance's b0-b5, c0-c5
for slot, tag in pairs(model.TAGS) do SLOTS[tag:lower()] = slot end
local function buff_command(args)
    local words, slots, off = {}, {}, false
    for i = 3, #args do
        local w = args[i]:lower()
        if SLOTS[w] then slots[SLOTS[w]] = true elseif w == 'off' then off = true else words[#words + 1] = w end
    end
    local a, n, spell
    for k = #words, 1, -1 do
        a, spell = settings.buff_named(cat.list, table.concat(words, ' ', 1, k))
        if a then n = k; break end
    end
    local name = table.concat(words, ' ', 1, n or #words)
    if name == '' then
        local shown = 0
        for key, row in pairs(cfg.rows) do
            if row.on and row.targets then
                local t = {}
                for slot in pairs(row.targets) do
                    t[#t + 1] = type(slot) == 'string' and slot or model.TAGS[slot]:lower()
                end
                table.sort(t)
                printf('  %s%s -> %s', key, row.pick and (' (' .. row.pick .. ')') or '', table.concat(t, ' '))
                shown = shown + 1
            end
        end
        if shown == 0 then printf('No buffs on. /sk3 buff Haste p1 p2 turns one on; /sk3 catalog lists them.') end
        return
    end
    if not a then printf('No buff "%s" for this job. /sk3 catalog lists them.', name); return end
    for k = n + 1, #words do
        local t = tracked_named(words[k])
        if not t then printf('Not tracking "%s": /sk3 track %s first.', words[k], words[k]); return end
        slots[t.name] = true
    end
    local key = settings.key(a)
    local row = cfg.rows[key] or { targets = { [0] = true } }
    row.on = not off
    if spell and (a.pick_one or a.tier > 1) then row.pick = a.name end
    if next(slots) then row.targets = slots end
    cfg.rows[key] = row
    settings.save()
    if not row.on then printf('%s off.', key)
    elseif a.pick_one and not row.pick then printf('%s on, but pick one: /sk3 buff <spell name>.', key)
    else printf('%s on%s.', key, row.pick and (' (' .. row.pick .. ')') or '') end
    for slot in pairs(row.on and slots or {}) do
        local outside = type(slot) == 'string' or slot > 5  -- a tracked name, or the alliance's B0-C5
        if outside and not can.outside(a) then
            printf('%s can\'t go on players outside your party: not on %s.', a.family, model.TAGS[slot] or slot)
        end
    end
end

-- /sk3 afk [on | off | minutes]: AFK sleep on, off, or after that many minutes;
-- with nothing, how it stands.
local function afk_command(w, g)
    local n = tonumber(w)
    if w == 'on' or w == 'off' then
        cfg.afk.on = w == 'on'
    elseif n then
        cfg.afk.on, cfg.afk.minutes = true, math.min(math.max(math.floor(n), afk.MIN), afk.MAX)
    elseif w ~= '' then
        printf('/sk3 afk [on | off | minutes (%d to %d)]', afk.MIN, afk.MAX)
        return
    end
    if w ~= '' then settings.save() end
    if not cfg.afk.on then printf('AFK sleep off.'); return end
    local st = mem.afk or {}
    local left = afk.left(g, cfg, st)
    local now = not status.running and 'counts only while running' or st.asleep and 'asleep: move to wake'
        or left and ('sleeps in %d min'):format(math.ceil(left / 60)) or 'starts counting now'
    printf('AFK sleep after %d min with no party movement or combat (%s).', cfg.afk.minutes, now)
end

-- /sk3 profile [name | default]: load a profile of this job pair's (Sidekick Settings
-- saves them), or Default; with no name, list them. Names may have spaces.
local function profile_command(args)
    local name = table.concat(args, ' ', 3)
    if name == '' then
        local list = profiles.names(cfg)
        printf('Profiles for %s (loaded: %s): Default%s', cfg_pair, profiles.active(cfg) or 'Default',
            #list > 0 and (', ' .. table.concat(list, ', ')) or '')
        return
    end
    if name:lower() == 'default' then
        profiles.load_default(cfg)
        settings.save()
        printf('Profile: Default.')
        return
    end
    local stored = profiles.find(cfg, name)
    if not stored then printf('No profile "%s" for %s. /sk3 profile lists them.', name, cfg_pair); return end
    profiles.load(cfg, stored)
    settings.save()
    printf('Profile loaded: %s.', stored)
end

-- /sk3 track [name] and the UI's Track button: a player outside your alliance, by
-- name or your current target. A /check asks their level, so heals are sized
-- (they're told you examined them, as v2 did); tracking them again asks again.
local function track(name)
    local g = snap
    if g.loading then return end
    local p = name and (game.find_player(name) or share.named(share.sessions, name)) or not name and g.target
    if not p then
        if name then printf('No player "%s" near you.', name) else printf('Target a player first, or /sk3 track <name>.') end
        return
    end
    for _, u in ipairs(g.units) do
        if u.sid == p.sid and u.kind ~= 'tracked' then
            printf('%s is in your %s.', p.name, u.kind == 'alliance' and 'alliance' or 'party')
            return
        end
    end
    local shared = share.known(share.sessions, p.sid)  -- their level comes from a session file: no /check
    local had = tracked.find(p.sid)
    local from = had and had.auto
    if tracked.add(p.sid, p.name, p.tidx) then
        printf('Tracking %s: healed, cleared, raised and buffed (buff rows pick them by name).%s', p.name,
            shared and '' or ' Checking their level.')
    elseif from then
        printf('Tracking %s yourself now: kept when %s\'s session stops listing them.', p.name, from)
    else
        printf('Already tracking %s%s.', p.name, shared and '' or '; checking their level again')
    end
    if not shared then AshitaCore:GetChatManager():QueueCommand(1, '/check ' .. p.name) end
end

-- /sk3 start|stop [name|all]: automation on or off here, in another Sidekick3
-- session on this PC by its character's name (sent as its run icon would be), or
-- here and in every one. `me`: your name, nil while loading with no session
-- file of yours up (other sessions can't be reached then).
local function run_command(me, on, who)
    local here, others = share.reach(share.sessions, me or '', who)
    if not here and not others then
        local live = {}
        for name in pairs(share.sessions) do live[#live + 1] = name end
        table.sort(live)
        printf('No Sidekick3 session "%s" on this PC (%s).', who,
            live[1] and ('sessions: ' .. table.concat(live, ', ')) or 'no other sessions')
        return
    end
    if here then
        status.running = on
        if on then status.restart = true end  -- wakes AFK sleep, as the run icon's start
        printf('Automation %s.', on and 'started' or 'stopped')
    end
    if others[1] and not me then printf('Other sessions can\'t be reached until your game has loaded.'); return end
    for _, name in ipairs(others) do share.send(name, { 'run', n = 1, on }) end
    if others[1] then  -- each prints it in its own chat once applied
        printf('Sent %s to %s.', on and 'start' or 'stop', table.concat(others, ', '))
    elseif here and who and who:lower() == 'all' and not next(share.sessions) then
        printf('No other Sidekick3 sessions on this PC.')
    end
end

-- The UI's Untrack buttons, and /sk3 untrack <name>.
local function untrack(name)
    local t = tracked.remove(name)
    if not t then printf('Not tracking "%s".', name)
    elseif t.auto then printf('Stopped tracking %s (from %s\'s session) until /sk3 track %s.', t.name, t.auto, t.name)
    else printf('Stopped tracking %s.', t.name) end
end
local tracking = { add = track, remove = untrack }

-- The UI: ui/custom.lua when there is one, else the standard window (ui/README.md).
-- A custom UI that fails to load is reported and the standard one used instead.
local ui = require('ui.window')
if package.searchpath('ui.custom', package.path) then
    local ok, custom = pcall(require, 'ui.custom')
    if ok then ui = custom
    else say(chat.error, 'ui/custom.lua failed to load, using the standard window: %s', tostring(custom)) end
end

-- Settings the UI changed, saved once no widget is held: a dragged slider saves when let go.
local unsaved = false
local function changed() unsaved = true end

local names = { job = abbr }
local function view(g)
    names.statuses = resources.load().statuses
    return model.build(g, cat.list, cfg, status, names)
end

-- The view the UI draws, built once per fresh snapshot and again after anything
-- changes what it shows (an act call, a command, another session's call), not every frame.
local shown
local function stale() shown = nil end

-- `act`, each call of which makes the view stale.
local function acts()
    local act = model.actions(cfg, status, changed, tracking, share.send)
    return setmetatable({}, { __index = function (_, k)
        local f = act[k]
        return f and function (...) stale(); return f(...) end
    end })
end

-- The UI, each frame while open. A Lua error closes it, so it's reported once.
local function draw(g)
    local ok, err = pcall(function ()
        shown = shown or view(g)
        ui.render(shown, acts())
    end)
    if ok then return end
    status.open, status.failed = false, true
    say(chat.error, 'Window closed on an error: %s', tostring(err))
end

-- Remote control: what another session sent (core/share.lua), made through this
-- session's own act as if clicked here, when it's a call ui/model.lua lets it make.
local view_failed  -- the last error building your view for another session, printed once
local shared = {
    view = function ()
        local ok, v = pcall(view, snap)
        if ok then view_failed = nil; return model.published(v) end
        if v ~= view_failed then
            say(chat.error, 'Settings view for another session failed: %s', tostring(v))
            view_failed = v
        end
        error(v, 0)
    end,
    apply = function (from, call)
        local ok, done = pcall(model.apply, acts(), cfg, call, cat.list)
        if not ok then
            say(chat.error, '%s\'s session sent %s, which failed: %s', from, tostring(call[1]), tostring(done))
        elseif done and call[1] == 'run' then
            printf('Automation %s from %s\'s session.', status.running and 'started' or 'stopped', from)
        end
    end,
    -- What automation just sent, while it lands: the other sessions' HUDs point at it.
    act = function ()
        local e = model.landing(status, snap)
        return e and { behavior = e.behavior, action = e.action, target = e.target }
    end,
}

ashita.events.register('d3d_present', 'sidekick3_present', function ()
    local g, fresh = refresh(os.clock())
    if fresh then
        stale()
        tick(g)
        status.sessions = share.tick(g, g.now, status, shared)
        status.views = share.views
        for name in pairs(status.watching) do
            if not status.sessions[name] then status.watching[name] = nil end  -- gone: its window closes
        end
    end
    -- The widget is drawn with the HUD closed too.
    if (status.open or cfg and cfg.ui.widget and not status.failed) and not g.loading then draw(g) end
    if unsaved and not imgui.IsAnyItemActive() then
        settings.save()
        unsaved = false
    end
end)

-- The UI's fonts, outside any frame (ImGui 1.81 takes none mid-frame). An error is reported, and the UI still drawn.
ashita.events.register('load', 'sidekick3_load', function ()
    if not ui.load then return end
    local ok, err = pcall(ui.load)
    if not ok then say(chat.error, 'The UI failed at load: %s', tostring(err)) end
end)

ashita.events.register('unload', 'sidekick3_unload', share.close)

ashita.events.register('packet_in', 'sidekick3_packet_in', function (e)
    packets.handle(e, packet_ctx, os.clock())
end)

local HELP = '/sk3 opens or closes the window. Commands: widget, start [name|all], stop [name|all], plan, state, '
    .. 'buff [name] [me p1..p5 b0..c5 <tracked>|off], focus <name|off>, follow <name|off>, rest [on|off], '
    .. 'track [name], untrack <name|all>, profile [name|default], afk [on|off|minutes], catalog [unknown], log, dump, help'

-- A command's name argument, or '' for none or `off`.
local function name_or_off(args) return args[3] and args[3]:lower() ~= 'off' and args[3] or '' end

-- /sk3 commands that need nothing loaded: (args).
local ANYTIME = {
    dump = function ()
        local ok, result = pcall(require('tools.dump').run, addon.path)
        if ok then
            printf('Dumped %d spells, %d abilities, %d statuses to tests/data/', result.spells, result.abilities, result.statuses)
        else
            say(chat.error, 'Dump failed: %s', tostring(result))
        end
    end,
    catalog = function (args) show_catalog((args[3] or ''):lower()) end,
    log = function ()
        status.log = not status.log
        printf('Action log %s.', status.log and 'on' or 'off')
    end,
    help = function () printf('%s', HELP) end,
}

-- The rest, once the game has loaded your job: (args, g).
local COMMANDS = {
    [''] = function ()
        status.open, status.failed = not status.open, nil
        cfg.ui.open = status.open
        settings.save()
    end,
    widget = function ()
        cfg.ui.widget, status.failed = not cfg.ui.widget, nil
        settings.save()
        printf('Widget %s.', cfg.ui.widget and 'on' or 'off')
    end,
    start = function (args, g) run_command(g.me.name, true, args[3]) end,
    stop = function (args, g) run_command(g.me.name, false, args[3]) end,
    plan = function (_, g) show_plan(g) end,
    state = function (_, g) show_state(g) end,
    buff = buff_command,
    profile = profile_command,
    focus = function (args)
        local name = name_or_off(args)
        cfg.heal.focus = name
        settings.save()
        if name == '' then printf('Focus off.') else printf('Focus: %s.', name) end
    end,
    follow = function (args)
        local name = name_or_off(args)
        cfg.follow.on = name ~= ''
        if name ~= '' then cfg.follow.target = name end
        settings.save()
        if name == '' then printf('Follow off.') else printf('Following %s past %d yalms.', name, cfg.follow.distance) end
    end,
    track = function (args, g)
        -- With no name it only adds your target when it's someone new: one already
        -- tracked is re-checked by name, so no one is examined by accident.
        local new = g.target
        for _, u in ipairs(g.units) do
            if new and u.sid == new.sid then new = nil end
        end
        if args[3] or new then track(args[3]); return end
        if not tracked.list[1] then printf('Tracking no one. Target a player, then /sk3 track (or /sk3 track <name>).'); return end
        local list = {}
        for i, t in ipairs(tracked.list) do
            list[i] = t.name .. (t.main_lv and (' (%s%d)'):format(abbr(t.main), t.main_lv) or '')
                .. (t.auto and (' from ' .. t.auto) or '')
        end
        printf('Tracking: %s. Target another player to add them.', table.concat(list, ', '))
    end,
    untrack = function (args)
        if not args[3] then printf('/sk3 untrack <name|all>'); return end
        if args[3]:lower() ~= 'all' or tracked_named('all') then untrack(args[3]); return end
        local declined = {}
        while tracked.list[1] do
            local t = tracked.remove(tracked.list[1].name)
            if t.auto then declined[#declined + 1] = t.name end
        end
        printf('Tracking no one.')
        if declined[1] then
            printf('Other sessions\' players kept off until tracked by hand (/sk3 track <name>): %s.', table.concat(declined, ', '))
        end
    end,
    afk = function (args, g) afk_command((args[3] or ''):lower(), g) end,
    rest = function (args)
        local w = (args[3] or ''):lower()
        cfg.rest.on = w == 'on' or (w ~= 'off' and not cfg.rest.on)
        settings.save()
        printf('Resting %s.', cfg.rest.on and 'on' or 'off')
    end,
}

-- ponytail: /sk3 while v2 is still installed and owns /sk; switch to /sk at cutover.
ashita.events.register('command', 'sidekick3_command', function (e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/sk3' then return end
    e.blocked = true
    stale()
    local sub = (args[2] or ''):lower()
    if ANYTIME[sub] then return ANYTIME[sub](args) end
    local g = refresh(os.clock())
    -- Stop goes through while you load (a zone): your file keeps carrying calls for share.LOADING seconds.
    if sub == 'stop' and (g.loading or not cfg) then run_command(share.me(), false, args[3]); return end
    if g.loading or not cfg then printf('Waiting for the game to load your job.'); return end
    local command = COMMANDS[sub] or ANYTIME.help
    command(args, g)
end)
