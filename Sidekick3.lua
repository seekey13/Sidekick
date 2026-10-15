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
local game = require('core.game')
local knowledge = require('core.knowledge')
local packets = require('core.packets')
local resources = require('core.resources')

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(fmt:format(...)))
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

-- Latest game snapshot, at most 10 a second: plenty for a 1.1s action throttle.
local snap = { loading = true, now = 0, tracks = {} }
local function refresh(now)
    if now - snap.now >= 0.1 or snap.loading then
        snap = game.read(now)
        if not snap.loading then current_catalog() end
    end
    return snap
end

-- Packets feed the cast lock and the trusts' statuses; they need to know who you
-- are, who is tracked, and how long a spell's buff lasts.
local packet_ctx = {
    tracks = {},
    duration = function (spell_id)
        local a = cat.by_spell[spell_id]
        return a and a.duration
    end,
}

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

-- /sk3 state: the snapshot automation will decide from, to check it reads the game right.
local FLAGS = { 'casting', 'moving', 'combat', 'safe', 'mounted', 'dead', 'resting', 'incapacitated', 'silenced', 'amnesia' }
local function show_state()
    local g = refresh(os.clock())
    if g.loading then printf('Loading (no job yet).'); return end
    local rm, statuses = AshitaCore:GetResourceManager(), resources.load().statuses
    local flags = {}
    for _, f in ipairs(FLAGS) do if g[f] then flags[#flags + 1] = f end end
    printf('%s%d/%s%d  zone %d  %s', rm:GetString('jobs.names_abbr', g.main), g.main_lv,
        rm:GetString('jobs.names_abbr', g.sub), g.sub_lv, g.zone, table.concat(flags, ' '))
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

ashita.events.register('d3d_present', 'sidekick3_present', function ()
    local g = refresh(os.clock())
    if not g.loading then packet_ctx.me, packet_ctx.tracks = g.me.sid, g.tracks end
end)

ashita.events.register('packet_in', 'sidekick3_packet_in', function (e)
    packets.handle(e, packet_ctx, os.clock())
end)

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
    elseif sub == 'catalog' then
        show_catalog((args[3] or ''):lower())
    elseif sub == 'state' then
        show_state()
    else
        printf('Commands: /sk3 state, /sk3 catalog [unknown], /sk3 dump')
    end
end)
