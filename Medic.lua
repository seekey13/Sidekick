--[[
Medic - Support Job Automation Framework
Copyright (c) 2025 Seekey
https://github.com/seekey13/Medic

This addon is designed for Ashita v4 and the CatsEyeXI private server.

Main addon file: job detection, event loop, command handler
]]--

addon.name      = 'Medic'
addon.author    = 'Seekey'
addon.version   = '1.2.0'
addon.desc      = 'Support Job Automation Framework'
addon.link      = 'https://github.com/seekey13/Medic'

require('common')
local chat = require('chat')
local settings = require('settings')
local imgui = require('imgui')

-- Load core modules
local common = require('lib.core.common')
local resource = require('lib.core.resource')
local automation = require('lib.core.automation')

-- Load action modules
local action_modules = {
    item = require('lib.actions.item'),
    heal = require('lib.actions.heal'),
    heal_aoe = require('lib.actions.heal_aoe'),
    heal_pet = require('lib.actions.heal_pet'),
    wake = require('lib.actions.wake'),
    debuff_removal = require('lib.actions.debuff_removal'),
    buff = require('lib.actions.buff'),
    recover = require('lib.actions.recover'),
    geo = require('lib.actions.geo'),
}

-- Load config UI
local config_ui = require('lib.config_ui')

-- State
local current_main_job_id = nil
local main_job_def = nil
local current_sub_job_id = nil
local sub_job_def = nil
local job_def = nil  -- Merged job definition
local addon_settings = nil
local is_loaded = false
local automation_enabled = false
local last_job_id = nil
local last_sub_job_id = nil
local last_level = nil
local last_unsupported_warning = nil  -- Track last unsupported job warning to prevent spam

-- Settings file path
local default_settings = T{
    automation_enabled = false,
    focus_enabled = false,
    focus_target = nil,
    attack_range = 'Off',
}

-- Range management state
local range_state = {
    follow_enabled = false,  -- Track current multisend follow state
    last_check = 0,          -- Timestamp of last range check
}

--[[
    Job Loading
]]--

local function load_single_job_definition(job_id)
    -- Map job IDs to job definition files
    local job_map = {
        [3] = 'white_mage',   -- White Mage
        [5] = 'red_mage',     -- Red Mage
        [7] = 'paladin',      -- Paladin
        [10] = 'bard',        -- Bard
        [15] = 'summoner',    -- Summoner
        [19] = 'dancer',      -- Dancer
        [20] = 'scholar',     -- Scholar
        [21] = 'geomancer',   -- Geomancer
        [22] = 'rune_fencer', -- Rune Fencer
    }
    
    local job_name = job_map[job_id]
    if not job_name then
        return nil
    end
    
    local success, job_module = pcall(require, 'lib.jobs.' .. job_name)
    if not success then
        common.errorf('Failed to load job definition for %s: %s', job_name, tostring(job_module))
        return nil
    end
    
    return job_module
end

local function merge_abilities(main_abilities, sub_abilities)
    -- Start with main job abilities
    local merged = T{}
    
    -- Deep copy main job abilities and mark them
    for category, abilities in pairs(main_abilities) do
        merged[category] = T{}
        for _, ability in ipairs(abilities) do
            local ability_copy = T{}
            for k, v in pairs(ability) do
                ability_copy[k] = v
            end
            ability_copy.is_main_job = true
            table.insert(merged[category], ability_copy)
        end
    end
    
    -- Add sub job abilities and mark them
    if sub_abilities then
        for category, abilities in pairs(sub_abilities) do
            if not merged[category] then
                merged[category] = T{}
            end
            for _, ability in ipairs(abilities) do
                local ability_copy = T{}
                for k, v in pairs(ability) do
                    ability_copy[k] = v
                end
                ability_copy.is_main_job = false
                table.insert(merged[category], ability_copy)
            end
        end
    end
    
    return merged
end

local function load_job_definition(main_job_id, sub_job_id)
    local main_def = load_single_job_definition(main_job_id)
    local sub_def = nil
    if sub_job_id and sub_job_id > 0 then
        sub_def = load_single_job_definition(sub_job_id)
    end
    
    -- Check if at least one job is supported
    if not main_def and not sub_def then
        -- Only display warning once per job combination
        local warning_key = string.format('%d_%d', main_job_id, sub_job_id or 0)
        if last_unsupported_warning ~= warning_key then
            local main_name = common.get_job_name(main_job_id)
            local error_msg = 'No automation available for ' .. main_name
            if sub_job_id and sub_job_id > 0 then
                error_msg = error_msg .. '/' .. common.get_job_name(sub_job_id)
            end
            common.warnf(error_msg)
            last_unsupported_warning = warning_key
        end
        return nil
    end
    
    -- Create merged job definition
    local merged_def = T{}
    
    -- Use whichever job is available as the primary source
    local primary_def = main_def or sub_def
    local secondary_def = main_def and sub_def or nil
    
    -- Copy primary job properties
    merged_def.job_id = primary_def.job_id
    merged_def.resource_type = primary_def.resource_type
    merged_def.validators = primary_def.validators
    merged_def.validate_ability = primary_def.validate_ability
    
    -- Merge priority_order: use master list order, include actions from both jobs
    -- Master priority order (defines the execution sequence)
    local master_priority = {
        'item',
        'critical',
        'heal_aoe',
        'heal',
        'heal_pet',
        'debuff_removal',
        'wake',
        'recover',
        'geo',
        'buff',
    }
    
    -- Collect all actions from both jobs
    local available_actions = {}
    if primary_def.priority_order then
        for _, action in ipairs(primary_def.priority_order) do
            available_actions[action] = true
        end
    end
    if secondary_def and secondary_def.priority_order then
        for _, action in ipairs(secondary_def.priority_order) do
            available_actions[action] = true
        end
    end
    
    -- Build merged priority_order using master list order
    merged_def.priority_order = T{}
    for _, action in ipairs(master_priority) do
        if available_actions[action] then
            table.insert(merged_def.priority_order, action)
        end
    end
    
    -- Build combined job name
    local job_name = ''
    if main_def then
        job_name = main_def.job_name
        if sub_def then
            job_name = job_name .. '/' .. sub_def.job_name
        elseif sub_job_id and sub_job_id > 0 then
            job_name = job_name .. '/' .. common.get_job_name(sub_job_id)
        end
    else
        -- Only sub job is supported
        job_name = common.get_job_name(main_job_id) .. '/' .. sub_def.job_name
    end
    merged_def.job_name = job_name
    
    -- Merge abilities from both jobs
    local main_abilities = main_def and main_def.abilities or {}
    local sub_abilities = sub_def and sub_def.abilities or {}
    merged_def.abilities = merge_abilities(main_abilities, sub_abilities)
    
    -- Merge default_settings (main job takes priority if both exist)
    merged_def.default_settings = T{}
    if sub_def and sub_def.default_settings then
        for key, value in pairs(sub_def.default_settings) do
            if type(value) == 'table' then
                merged_def.default_settings[key] = T(value)
            else
                merged_def.default_settings[key] = value
            end
        end
    end
    if main_def and main_def.default_settings then
        for key, value in pairs(main_def.default_settings) do
            if type(value) == 'table' then
                merged_def.default_settings[key] = T(value)
            else
                merged_def.default_settings[key] = value
            end
        end
    end
    
    common.printf('Loaded job definition: %s', job_name)
    
    return merged_def
end

local function setup_job()
    local main_job_id, sub_job_id = common.get_player_job()
    
    -- Ignore invalid job IDs (happens during zoning)
    if not main_job_id or main_job_id == 0 then
        return
    end
    
    if main_job_id == current_main_job_id and sub_job_id == current_sub_job_id and job_def then
        return  -- Already loaded
    end
    
    -- Track job change
    if current_main_job_id and (current_main_job_id ~= main_job_id or current_sub_job_id ~= sub_job_id) then
        local old_job_str = common.get_job_name(current_main_job_id)
        if current_sub_job_id and current_sub_job_id > 0 then
            old_job_str = old_job_str .. '/' .. common.get_job_name(current_sub_job_id)
        end
        local new_job_str = common.get_job_name(main_job_id)
        if sub_job_id and sub_job_id > 0 then
            new_job_str = new_job_str .. '/' .. common.get_job_name(sub_job_id)
        end
        common.printf('Job change detected: %s -> %s', old_job_str, new_job_str)
    end
    
    current_main_job_id = main_job_id
    current_sub_job_id = sub_job_id
    last_job_id = main_job_id
    
    main_job_def = load_single_job_definition(main_job_id)
    sub_job_def = sub_job_id and sub_job_id > 0 and load_single_job_definition(sub_job_id) or nil
    job_def = load_job_definition(main_job_id, sub_job_id)
    
    if job_def then
        -- Build defaults table including job-specific defaults
        local load_defaults = T{}
        for key, value in pairs(default_settings) do
            if type(value) == 'table' then
                load_defaults[key] = T(value)
            else
                load_defaults[key] = value
            end
        end
        
        -- Merge job-specific defaults
        if job_def.default_settings then
            for key, value in pairs(job_def.default_settings) do
                if type(value) == 'table' then
                    load_defaults[key] = T(value)
                else
                    load_defaults[key] = value
                end
            end
        end
        
        -- Load settings (managed by Ashita settings library)
        -- Note: Ashita auto-determines filename based on addon name and character
        addon_settings = settings.load(load_defaults)
        
        -- Register settings to enable auto-save
        settings.register('settings', 'settings_reload', function(s)
            if s ~= nil then
                addon_settings = s
            end
        end)
        
        -- Merge with default settings (only if key doesn't exist)
        for key, value in pairs(default_settings) do
            if addon_settings[key] == nil then
                if type(value) == 'table' then
                    addon_settings[key] = T(value)
                else
                    addon_settings[key] = value
                end
            end
        end
        
        -- Merge with job-specific default settings (only if key doesn't exist)
        if job_def.default_settings then
            for key, value in pairs(job_def.default_settings) do
                if addon_settings[key] == nil then
                    if type(value) == 'table' then
                        addon_settings[key] = T(value)
                    else
                        addon_settings[key] = value
                    end
                end
            end
        end
        
        common.printf('Loaded settings for %s', job_def.job_name)
    end
end

--[[
    Automation Loop
]]--

local function automation_tick()
    if not automation_enabled then
        return
    end
    
    if not job_def then
        return
    end
    
    -- Check if combat is allowed
    if not common.can_attack() then
        return
    end

    -- Check if casting
    if common.is_casting() then
        return
    end
    
    -- Range management logic
    if addon_settings and addon_settings.attack_range and addon_settings.attack_range ~= 'Off' then
        local is_engaged = common.is_engaged()
        
        -- If not engaged, ensure follow is enabled
        if not is_engaged and range_state.follow_enabled == false then
            AshitaCore:GetChatManager():QueueCommand(1, '/ms follow on')
            range_state.follow_enabled = true
            common.debugf('[Range] Not engaged, enabling follow')
        end
        
        -- If engaged, manage range to target
        if is_engaged then
            local target_index = common.get_target_index()
            if target_index and target_index > 0 then
                -- Convert setting to yalms
                local desired_range = 0
                if addon_settings.attack_range == 'Melee' then
                    desired_range = 3
                elseif addon_settings.attack_range == 'Ranged' then
                    desired_range = 15
                end
                
                local in_range = common.is_in_range(target_index, desired_range)
                
                if in_range and range_state.follow_enabled == true then
                    -- Within range, disable follow
                    AshitaCore:GetChatManager():QueueCommand(1, '/ms follow off')
                    range_state.follow_enabled = false
                    common.debugf('[Range] Within %d yalms, disabling follow', desired_range)
                elseif not in_range and range_state.follow_enabled == false then
                    -- Out of range, enable follow
                    AshitaCore:GetChatManager():QueueCommand(1, '/ms follow on')
                    range_state.follow_enabled = true
                    common.debugf('[Range] Beyond %d yalms, enabling follow', desired_range)
                end
            end
        end
    end
    
    -- Check for job or level changes (direct reading, no packet dependency)
    local job_id, sub_job_id = common.get_player_job()
    local main_level, sub_level = common.get_player_level()
    
    -- Skip if job_id or level is invalid
    if job_id and job_id > 0 and main_level and main_level > 0 then
        -- Initialize tracking on first valid job detection
        if not last_job_id or last_job_id == 0 then
            last_job_id = job_id
            last_sub_job_id = sub_job_id or 0
            last_level = main_level
            common.debugf('Initialized job tracking: %s/%s (level %s)', tostring(job_id), tostring(sub_job_id), tostring(main_level))
        else
            -- Normalize sub job IDs (treat nil as 0)
            local normalized_sub_job = sub_job_id or 0
            local normalized_last_sub = last_sub_job_id or 0
            
            -- Detect job change
            local job_changed = false
            if job_id ~= last_job_id then
                job_changed = true
            elseif normalized_sub_job ~= normalized_last_sub and normalized_sub_job > 0 and normalized_last_sub > 0 then
                job_changed = true
            elseif normalized_sub_job > 0 and normalized_last_sub == 0 then
                job_changed = true
            elseif normalized_sub_job == 0 and normalized_last_sub > 0 then
                job_changed = true
            end
            
            -- Detect level change
            local level_changed = false
            if last_level and main_level ~= last_level and last_level > 0 then
                level_changed = true
            end
            
            -- Handle job change
            if job_changed then
                local old_job_str = common.get_job_name(last_job_id)
                if last_sub_job_id and last_sub_job_id > 0 then
                    old_job_str = old_job_str .. '/' .. common.get_job_name(last_sub_job_id)
                end
                local new_job_str = common.get_job_name(job_id)
                if sub_job_id and sub_job_id > 0 then
                    new_job_str = new_job_str .. '/' .. common.get_job_name(sub_job_id)
                end
                common.printf('Job change detected: %s -> %s, reloading job definition...', old_job_str, new_job_str)
                
                -- Update tracking
                last_job_id = job_id
                last_sub_job_id = sub_job_id
                last_level = main_level
                current_main_job_id = nil
                current_sub_job_id = nil
                main_job_def = nil
                sub_job_def = nil
                job_def = nil
                addon_settings = nil
                
                -- Reload job
                setup_job()
                
                -- Restore automation state after job change
                if addon_settings and addon_settings.automation_enabled then
                    automation_enabled = true
                else
                    automation_enabled = false
                end
                
                -- Skip this frame after job reload
                return
            elseif level_changed then
                common.printf('Level change detected: %d -> %d, reloading UI...', last_level, main_level)
                
                -- Update level tracking
                last_level = main_level
                
                -- Force UI refresh by resetting job_def
                current_main_job_id = nil
                current_sub_job_id = nil
                
                -- Reload the job definition to pick up newly available abilities
                setup_job()
                
                -- Skip this frame after reload
                return
            end
        end
    end
    
    local player_resource = resource.get_resource(job_def.resource_type)
    
    -- Get priority order
    local priority_order = job_def.priority_order or {
        'item',
        'critical',
        'heal_aoe',
        'heal',
        'heal_pet',
        'debuff_removal',
        'wake',
        'recover',
        'geo',
        'buff',
    }
    
    -- Execute priority actions
    automation.execute_priority_actions(
        priority_order,
        action_modules,
        addon_settings,
        job_def,
        main_level,
        sub_level,
        player_resource
    )
end

--[[
    Event Handlers
]]--

ashita.events.register('load', 'medic_load', function()
    is_loaded = true    
    common.printf('Loaded! Type /medic help for commands.')
end)

ashita.events.register('unload', 'medic_unload', function()    
    if addon_settings and job_def then
        local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
        settings.save(addon_settings, settings_file)
    end
    
    common.printf('Unloaded.')
end)

-- Delay job setup until first render to ensure game is initialized
local setup_attempted = false

ashita.events.register('d3d_present', 'medic_render', function()
    if not is_loaded then
        return
    end
    
    -- Initialize on first render
    if not setup_attempted then
        setup_attempted = true
        setup_job()
        
        -- Restore automation state
        if addon_settings and addon_settings.automation_enabled then
            automation_enabled = true
        end
    end
    
    -- Check for job changes (every frame)
    setup_job()
    
    -- Render config UI
    if config_ui.is_visible() and job_def and addon_settings then
        local save_settings_callback = function()
            settings.save()
        end
        
        config_ui.render(addon_settings, job_def, save_settings_callback)
    end
    
    -- Run automation tick
    automation_tick()
end)

ashita.events.register('packet_in', 'medic_packet_in', function(e)
    if not is_loaded then
        return
    end
    
    -- Handle action packets for casting detection (always active)
    if e.id == 0x028 then
        -- Parse actor ID to check if it's the player
        if e.data and #e.data >= 16 then
            local actor_id = struct.unpack('I', e.data, 0x05 + 1)
            local party = common.get_party()
            if party then
                local player_id = party:GetMemberServerId(0)
                if player_id and actor_id == player_id then
                    common.handle_action_packet(e.data)  -- Casting detection
                    
                    -- Check if this is a casting completion (byte 0x0F != 0x00)
                    if e.data and #e.data >= 16 then
                        local completion_flag = struct.unpack('B', e.data, 0x0F + 1)
                        common.debugf('[PACKET] 0x028 completion_flag = 0x%02X', completion_flag)
                        if completion_flag ~= 0x00 then
                            -- Casting completed, apply pending buff to Trust
                            common.debugf('[PACKET] Calling handle_buff_application()')
                            common.handle_buff_application()
                        end
                    end
                end
            end
        end
    end
    
    -- Handle status effect update packets for Trust buff removal (0x029)
    if e.id == 0x029 then
        if e.data and #e.data >= 16 then
            -- Extract server_id (bytes 0x04-0x07, little-endian)
            local server_id = struct.unpack('I', e.data, 0x04 + 1)
            
            -- Extract buff_id (byte 0x0C)
            local buff_id = struct.unpack('B', e.data, 0x0C + 1)
            
            -- Only handle Trust buff removal (server_id >= 0x1000000)
            if server_id >= 0x1000000 and buff_id > 0 and buff_id ~= 255 then
                common.handle_buff_removal(server_id, buff_id)
            end
        end
    end
    
    -- Clear Trust buffs on zone change
    if e.id == 0x0A then  -- Zone change packet
        common.clear_trust_buffs()
    end
end)

ashita.events.register('command', 'medic_command', function(e)
    local args = e.command:args()
    
    if args[1] ~= '/medic' and args[1] ~= '/med' then
        return
    end
    
    e.blocked = true
    
    -- Handle commands
    local cmd = args[2] and args[2]:lower() or 'help'
    
    if cmd == 'help' then
        common.printf('Medic Commands:')
        common.printf('  /medic start - Start automation')
        common.printf('  /medic stop - Stop automation')
        common.printf('  /medic toggle - Toggle automation on/off')
        common.printf('  /medic config - Show configuration UI')
        common.printf('  /medic focus <index> - Set focus target (0-5, party member index)')
        common.printf('  /medic focus clear - Clear focus target')
        common.printf('  /medic debug - Toggle debug mode')
        common.printf('  /medic recast - Show all active ability recast timers')
        common.printf('  /medic status - Show current status')
        
    elseif cmd == 'start' then
        automation_enabled = true
        addon_settings.automation_enabled = true
        if job_def then
            local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
            settings.save(addon_settings, settings_file)
        end
        common.printf('Automation started.')
        
    elseif cmd == 'stop' then
        automation_enabled = false
        addon_settings.automation_enabled = false
        if job_def then
            local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
            settings.save(addon_settings, settings_file)
        end
        common.printf('Automation stopped.')
        
    elseif cmd == 'toggle' then
        automation_enabled = not automation_enabled
        addon_settings.automation_enabled = automation_enabled
        if job_def then
            local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
            settings.save(addon_settings, settings_file)
        end
        common.printf('Automation %s.', automation_enabled and 'enabled' or 'disabled')
        
    elseif cmd == 'config' then
        config_ui.toggle()
        
    elseif cmd == 'focus' then
        local subcmd = args[3] and args[3]:lower()
        
        if subcmd == 'clear' then
            addon_settings.focus_target = nil
            if job_def then
                local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
                settings.save(addon_settings, settings_file)
            end
            common.printf('Focus target cleared.')
        elseif subcmd and tonumber(subcmd) then
            local index = tonumber(subcmd)
            if index >= 0 and index <= 5 then
                local member_name = common.get_party_member_name(index)
                if member_name then
                    addon_settings.focus_target = member_name
                    if job_def then
                        local settings_file = 'settings_' .. (job_def.job_name or 'default'):lower() .. '.json'
                        settings.save(addon_settings, settings_file)
                    end
                    common.printf('Focus target set to %s (P%d)', member_name, index)
                else
                    common.errorf('Party member %d not found or not active.', index)
                end
            else
                common.errorf('Invalid party index. Use 0-5.')
            end
        else
            common.printf('Usage: /medic focus <index> or /medic focus clear')
        end
        
    elseif cmd == 'debug' then
        common.debug = not common.debug
        common.printf('Debug mode %s.', common.debug and 'enabled' or 'disabled')
        
    elseif cmd == 'recast' then
        common.show_recast_timers()
        
    elseif cmd == 'status' then
        common.printf('Medic Status:')
        common.printf('  Job: %s', job_def and job_def.job_name or 'Not loaded')
        common.printf('  Automation: %s', automation_enabled and 'Enabled' or 'Disabled')
        common.printf('  Focus Target: %s', addon_settings.focus_target or 'None')
        common.printf('  Debug Mode: %s', common.debug and 'Enabled' or 'Disabled')
        
    else
        common.printf('Unknown command: %s. Type /medic help for commands.', cmd)
    end
end)
