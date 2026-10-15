--[[
Sidekick3 - Support Job Automation Framework (v3 rewrite)
Copyright (c) 2026 Seekey
https://github.com/seekey13/Sidekick3

This addon is designed for Ashita v4 and the CatsEyeXI private server.
]]--

addon.name    = 'Sidekick3'
addon.author  = 'Seekey'
addon.version = '3.0.0-dev'
addon.desc    = 'Support Job Automation Framework'
addon.link    = 'https://github.com/seekey13/Sidekick3'

require('common')
local chat = require('chat')
local catalog = require('core.catalog')
local engine = require('core.engine')
local game = require('core.game')
local knowledge = require('core.knowledge')
local packets = require('core.packets')
local resources = require('core.resources')
local settings = require('core.settings')

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(fmt:format(...)))
end

local function abbr(job)
    return job > 0 and AshitaCore:GetResourceManager():GetString('jobs.names_abbr', job) or 'none'
end

-- The catalog for the character as it is right now, rebuilt when job or level
-- changes (or on demand: a newly learned spell changes neither).
local cat = { key = nil, list = {}, by_spell = {} }
local function current_catalog(force)
    local p = AshitaCore:GetMemoryManager():GetPlayer()
    local key = ('%d/%d/%d/%d'):format(p:GetMainJob(), p:GetMainJobLevel(), p:GetSubJob(), p:GetSubJobLevel())
    if force or key ~= cat.key then
        cat.key, cat.by_spell = key, {}
        cat.list = catalog.build(resources.load(), {
            main = p:GetMainJob(), main_lv = p:GetMainJobLevel(),
            sub = p:GetSubJob(), sub_lv = p:GetSubJobLevel(),
            has_spell = function (id) return p:HasSpell(id) end,
            has_ability = function (id) return p:HasAbility(id) end,
        }, knowledge)
        for _, a in ipairs(cat.list) do
            if a.kind == 'ma' then cat.by_spell[a.id] = a end
        end
    end
    return cat.list
end

local cfg, cfg_pair    -- settings for the current job pair
local running = false  -- automation on (/sk3 start); never resumed on load
local log = true       -- ponytail: print every action while in development; default off at release
local mem = {}         -- the engine's memory between ticks

-- Packets feed the cast lock and the trusts' statuses; they need to know who you
-- are, who is tracked, and how long a spell's buff lasts.
local packet_ctx = {
    tracks = {},
    duration = function (spell_id)
        local a = cat.by_spell[spell_id]
        return a and a.duration
    end,
}

-- Latest game snapshot, at most 10 a second: plenty for a 1.1s action throttle.
-- Returns it and whether it was just read.
local snap = { loading = true, now = 0, tracks = {} }
local function refresh(now)
    if now - snap.now < 0.1 and not snap.loading then return snap, false end
    snap = game.read(now)
    if not snap.loading then
        current_catalog()
        packet_ctx.me, packet_ctx.tracks = snap.me.sid, snap.tracks
        local pair = abbr(snap.main) .. '_' .. abbr(snap.sub)
        if pair ~= cfg_pair then cfg, cfg_pair, mem = settings.load(pair), pair, {} end
    end
    return snap, true
end

local function tick(g)
    if not running or g.loading or not engine.ready(g, mem) then return end
    local intent = engine.decide(g, cat.list, cfg, mem)
    if not intent then return end
    local command = engine.command(intent, cfg)
    AshitaCore:GetChatManager():QueueCommand(0, command)
    engine.sent(intent, g, mem)
    game.sent(intent.action)
    if log then printf('%s  (%s: %s)', command, intent.behavior, intent.why) end
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
local FLAGS = { 'casting', 'moving', 'combat', 'safe', 'mounted', 'dead', 'resting', 'incapacitated', 'silenced', 'amnesia' }
local function show_state(g)
    local statuses = resources.load().statuses
    local flags = {}
    for _, f in ipairs(FLAGS) do if g[f] then flags[#flags + 1] = f end end
    printf('%s%d/%s%d  zone %d  %s', abbr(g.main), g.main_lv, abbr(g.sub), g.sub_lv, g.zone, table.concat(flags, ' '))
    for _, u in ipairs(g.units) do
        local names = {}
        for id in pairs(u.buffs) do names[#names + 1] = statuses[id] and statuses[id].en or tostring(id) end
        table.sort(names)
        printf('  %-5s %-14s HP %3d%%%s MP %3d%%  %s  %s', u.kind, u.name, u.hpp,
            u.max_hp and ('/' .. u.max_hp) or '', u.mpp,
            u.in_zone and ('%.1fy'):format(u.dist or 0) or 'away', table.concat(names, ', '))
    end
    for _, t in ipairs({ { 'bt', g.bt }, { 'pet', g.pet } }) do
        local e = t[2]
        if e then printf('  %-5s %-14s HP %3d%%  %.1fy%s', t[1], e.name, e.hpp, e.dist, e.mob and ' (mob)' or '') end
    end
end

-- /sk3 plan: what automation would do this moment, without doing it.
local function show_plan(g)
    local intent, why = engine.decide(g, cat.list, cfg, mem)
    if intent then
        printf('Would send %s  (%s: %s)', engine.command(intent, cfg), intent.behavior, intent.why)
    else
        printf('Nothing to do now: %s.', why)
    end
    if not engine.ready(g, mem) then printf('(still inside the post-action lockout)') end
end

-- /sk3 buff [name] [me p1..p5 | off]: turn a buff row on for those targets, or off;
-- with no name, list the rows that are on.
local SLOTS = { me = 0, p0 = 0, p1 = 1, p2 = 2, p3 = 3, p4 = 4, p5 = 5 }
local function buff_command(args)
    local words, slots, off = {}, {}, false
    for i = 3, #args do
        local w = args[i]:lower()
        if SLOTS[w] then slots[SLOTS[w]] = true elseif w == 'off' then off = true else words[#words + 1] = w end
    end
    local name = table.concat(words, ' ')
    if name == '' then
        local shown = 0
        for key, row in pairs(cfg.rows) do
            if row.on and row.targets then
                local t = {}
                for slot in pairs(row.targets) do t[#t + 1] = slot == 0 and 'me' or 'p' .. slot end
                table.sort(t)
                printf('  %s%s -> %s', key, row.pick and (' (' .. row.pick .. ')') or '', table.concat(t, ' '))
                shown = shown + 1
            end
        end
        if shown == 0 then printf('No buffs on. /sk3 buff Haste p1 p2 turns one on; /sk3 catalog lists them.') end
        return
    end
    local a
    for _, x in ipairs(cat.list) do
        if x.role == 'buff' and (x.name:lower() == name or x.family:lower() == name or settings.key(x):lower() == name) then
            a = x
            break
        end
    end
    if not a then printf('No buff "%s" for this job. /sk3 catalog lists them.', name); return end
    local key = settings.key(a)
    local row = cfg.rows[key] or { targets = { [0] = true } }
    row.on = not off
    if a.name:lower() == name and (a.pick_one or a.tier > 1) then row.pick = a.name end
    if next(slots) then row.targets = slots end
    cfg.rows[key] = row
    settings.save()
    if not row.on then printf('%s off.', key)
    elseif a.pick_one and not row.pick then printf('%s on, but pick one: /sk3 buff <spell name>.', key)
    else printf('%s on%s.', key, row.pick and (' (' .. row.pick .. ')') or '') end
end

ashita.events.register('d3d_present', 'sidekick3_present', function ()
    local g, fresh = refresh(os.clock())
    if fresh then tick(g) end
end)

ashita.events.register('packet_in', 'sidekick3_packet_in', function (e)
    packets.handle(e, packet_ctx, os.clock())
end)

local HELP = 'Commands: start, stop, plan, state, buff [name] [me p1..p5|off], focus <name|off>, catalog [unknown], log, dump'

-- ponytail: /sk3 while v2 is still installed and owns /sk; switch to /sk at cutover.
ashita.events.register('command', 'sidekick3_command', function (e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/sk3' then return end
    e.blocked = true

    local sub = (args[2] or ''):lower()
    if sub == 'dump' then
        local ok, result = pcall(require('tools.dump').run, addon.path)
        if ok then
            printf('Dumped %d spells, %d abilities, %d statuses to tests/data/', result.spells, result.abilities, result.statuses)
        else
            print(chat.header(addon.name) .. chat.error('Dump failed: ' .. tostring(result)))
        end
        return
    elseif sub == 'catalog' then
        show_catalog((args[3] or ''):lower())
        return
    elseif sub == 'log' then
        log = not log
        printf('Action log %s.', log and 'on' or 'off')
        return
    end

    local g = refresh(os.clock())
    if g.loading or not cfg then printf('Waiting for the game to load your job.'); return end
    if sub == 'start' or sub == 'stop' then
        running = sub == 'start'
        printf('Automation %s.', running and 'started' or 'stopped')
    elseif sub == 'plan' then
        show_plan(g)
    elseif sub == 'state' then
        show_state(g)
    elseif sub == 'buff' then
        buff_command(args)
    elseif sub == 'focus' then
        local name = args[3] and args[3]:lower() ~= 'off' and args[3] or ''
        cfg.heal.focus = name
        settings.save()
        printf(name == '' and 'Focus off.' or ('Focus: %s.'):format(name))
    else
        printf('%s', HELP)
    end
end)
