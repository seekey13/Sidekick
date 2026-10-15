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
local knowledge = require('core.knowledge')
local resources = require('core.resources')

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(fmt:format(...)))
end

-- The catalog for the character as it is right now.
local function current_catalog()
    local p = AshitaCore:GetMemoryManager():GetPlayer()
    return catalog.build(resources.load(), {
        main = p:GetMainJob(), main_lv = p:GetMainJobLevel(),
        sub = p:GetSubJob(), sub_lv = p:GetSubJobLevel(),
        has_spell = function (id) return p:HasSpell(id) end,
        has_ability = function (id) return p:HasAbility(id) end,
    }, knowledge)
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
    for _, a in ipairs(current_catalog()) do
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
    else
        printf('Commands: /sk3 catalog [unknown], /sk3 dump')
    end
end)
