--[[
    Buff maintenance action module
    Handles maintaining self and party buffs
]]--

local buff = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function buff.execute(settings, job_def, main_level, sub_level, player_resource, party_buff_config)
    -- Check if buff is enabled
    if not settings.buff_enabled then
        return nil
    end
    
    -- Get party buff configuration from config_ui if not provided
    if not party_buff_config then
        local config_ui = require('lib.config_ui')
        party_buff_config = config_ui.get_party_buffs()
    end
    
    -- Get buff abilities from job definition
    local buff_abilities = job_def.abilities.buff or {}
    if #buff_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(buff_abilities, settings, main_level, sub_level, job_def)
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Check combat status
    local is_idle = common.is_idle()
    local is_engaged = common.is_engaged()
    
    -- Check each buff to see if it needs to be applied/refreshed
    for _, ability in ipairs(available_abilities) do
        local should_skip = false
        
        -- Check idle_only requirement (this blocks all combat situations)
        if not should_skip and ability.idle_only and is_engaged then
            -- Skip buffs that require being idle
            should_skip = true
        end
        
        -- Check pet requirement
        if not should_skip and ability.pet_required then
            if not common.has_pet() then
                should_skip = true
            end
        end
        
        -- Check required buff prerequisite for player
        if not should_skip and ability.requires_buff then
            local has_required_buff = false
            local required_buff_ids = {}
            
            -- Handle both single buff_id and array of buff_ids
            if type(ability.requires_buff) == 'table' then
                required_buff_ids = ability.requires_buff
            else
                required_buff_ids = {ability.requires_buff}
            end
            
            -- Check if player has any of the required buffs
            for _, required_buff in ipairs(required_buff_ids) do
                if common.has_buff(0, required_buff) then
                    has_required_buff = true
                    break
                end
            end
            
            if not has_required_buff then
                should_skip = true
            end
        end
        
        -- Check if this ability is blocked by status ailments
        if not should_skip and common.is_command_blocked(ability.command) then
            local blocked_by = common.is_command_blocked(ability.command)
            common.debugf('[BUFF] %s is blocked by %s', ability.name, blocked_by)
            should_skip = true
        end
        
        if not should_skip then
            -- Determine if this is a single-target buff (function command) or self-only buff (string command)
            local is_single_target = type(ability.command) == 'function'
            
            if is_single_target then
                -- Single-target buff: Check button states for ME and party members (P1-P5)
                -- First check if ability is enabled via settings
                local key = 'disabled_' .. ability.name:gsub(' ', '_')
                local is_ability_enabled = settings[key] == false or settings[key] == nil
                
                if not is_ability_enabled then
                    common.debugf('[BUFF] %s is disabled in settings', ability.name)
                    goto continue_ability
                end
                
                -- Priority order: ME, P1, P2, P3, P4, P5
                local targets_to_check = {0, 1, 2, 3, 4, 5}  -- 0 = ME, 1-5 = P1-P5
                
                for _, target_index in ipairs(targets_to_check) do
                    -- Check if this target is enabled in party_buff_config
                    local is_target_enabled = false
                    if party_buff_config and party_buff_config[ability.name] then
                        is_target_enabled = party_buff_config[ability.name][target_index] == true
                    end
                    
                    if is_target_enabled then
                        -- Check combat_only requirement for this specific target
                        if ability.combat_only and not is_engaged then
                            common.debugf('[BUFF] %s skipped for target %d: requires combat', ability.name, target_index)
                            goto continue_target
                        end
                        
                        local target_needs_buff = false
                        local target_entity_index = nil
                        
                        -- Get target buffs and entity index
                        if target_index == 0 then
                            -- ME: Check player buffs
                            target_buffs = common.get_player_buffs()
                            target_entity_index = 0
                        else
                            -- P1-P5: Check party member buffs
                            -- First check if party member is active and in range
                            local party_size = common.get_party_size()
                            if target_index < party_size then
                                local player_zone = common.get_party_member_zone(0)
                                local member_zone = common.get_party_member_zone(target_index)
                                target_entity_index = common.get_party_member_target_index(target_index)
                                
                                if target_entity_index and player_zone == member_zone and common.is_in_range(target_entity_index, 20) then
                                    target_buffs = common.get_party_buffs(target_index)
                                else
                                    -- Party member not available or out of range, skip
                                    goto continue_target
                                end
                            else
                                -- Party member not active, skip
                                goto continue_target
                            end
                        end
                        
                        -- Check if target needs buff
                        if ability.buff_id then
                            local has_buff = false
                            local buff_ids_to_check = {}
                            if type(ability.buff_id) == 'table' then
                                buff_ids_to_check = ability.buff_id
                            else
                                buff_ids_to_check = {ability.buff_id}
                            end
                            
                            -- Check target_buffs array (works for both party members and Trusts)
                            for _, target_buff in ipairs(target_buffs) do
                                for _, check_buff in ipairs(buff_ids_to_check) do
                                    if target_buff == check_buff then
                                        has_buff = true
                                        break
                                    end
                                end
                                if has_buff then break end
                            end
                            
                            target_needs_buff = not has_buff
                        else
                            -- No buff tracking, always use if available
                            target_needs_buff = true
                        end
                        
                        if target_needs_buff then
                            -- Check resource
                            if resource.has_resource(job_def.resource_type, ability.cost) then
                                -- Check cooldown
                                if ability.id then
                                    local is_spell = false
                                    local test_cmd = common.build_ability_command(ability, target_index)
                                    is_spell = test_cmd and test_cmd:match('^/ma ') ~= nil
                                    
                                    local is_ready = false
                                    local recast_time = 0
                                    
                                    if is_spell then
                                        is_ready = resource.is_spell_ready(ability.id)
                                        recast_time = resource.get_spell_recast(ability.id)
                                        common.debugf('[BUFF] %s spell recast check - Spell ID: %d, Recast Time: %d, Ready: %s', 
                                            ability.name, ability.id, recast_time or 0, tostring(is_ready))
                                    else
                                        is_ready = resource.is_ability_ready(ability.id)
                                        recast_time = resource.get_ability_recast(ability.id)
                                        common.debugf('[BUFF] %s ability recast check - Ability ID: %d, Recast Time: %.1fs, Ready: %s', 
                                            ability.name, ability.id, (recast_time or 0) / 60.0, tostring(is_ready))
                                    end
                                    
                                    if is_ready then
                                        local command = common.build_ability_command(ability, target_index)
                                        if command then
                                            -- Register pending buff if target is a Trust
                                            if ability.buff_id and target_index > 0 then
                                                local party = common.get_party()
                                                if party then
                                                    local ok_server, server_id = pcall(function()
                                                        return party:GetMemberServerId(target_index)
                                                    end)
                                                    if ok_server and server_id and server_id >= 0x1000000 then
                                                        -- This is a Trust, register pending buff
                                                        local buff_to_track = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                                        common.register_pending_buff(server_id, buff_to_track)
                                                    end
                                                end
                                            end
                                            
                                            local target_name = target_index == 0 and 'self' or (common.get_party_member_name(target_index) or ('P' .. target_index))
                                            return {
                                                command = command,
                                                description = string.format('Applying buff: %s to %s', ability.name, target_name)
                                            }
                                        end
                                    end
                                else
                                    local command = common.build_ability_command(ability, target_index)
                                    if command then
                                        -- Register pending buff if target is a Trust
                                        if ability.buff_id and target_index > 0 then
                                            local party = common.get_party()
                                            if party then
                                                local ok_server, server_id = pcall(function()
                                                    return party:GetMemberServerId(target_index)
                                                end)
                                                if ok_server and server_id and server_id >= 0x1000000 then
                                                    -- This is a Trust, register pending buff
                                                    local buff_to_track = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                                    common.register_pending_buff(server_id, buff_to_track)
                                                end
                                            end
                                        end
                                        
                                        local target_name = target_index == 0 and 'self' or (common.get_party_member_name(target_index) or ('P' .. target_index))
                                        return {
                                            command = command,
                                            description = string.format('Applying buff: %s to %s', ability.name, target_name)
                                        }
                                    end
                                end
                            end
                        end
                        
                        ::continue_target::
                    end
                end
            else
                -- Self-only buff: Use checkbox-based logic (original behavior)
                -- Check if ability is enabled via settings
                local key = 'disabled_' .. ability.name:gsub(' ', '_')
                local is_enabled = settings[key] == false or settings[key] == nil
                
                if not is_enabled then
                    goto continue_ability
                end
                
                -- Check combat_only requirement
                if ability.combat_only and not is_engaged then
                    common.debugf('[BUFF] %s skipped: requires combat', ability.name)
                    goto continue_ability
                end
                
                -- Check if buff is already active
                local needs_buff = false
                
                if ability.buff_id then
                    -- Check player for this buff
                    local has_buff = false
                    local player_buffs = common.get_player_buffs()
                    
                    -- Handle both single buff_id and array of buff_ids
                    local buff_ids_to_check = {}
                    if type(ability.buff_id) == 'table' then
                        buff_ids_to_check = ability.buff_id
                    else
                        buff_ids_to_check = {ability.buff_id}
                    end
                    
                    -- Check if player has any of the specified buffs
                    for _, player_buff in ipairs(player_buffs) do
                        for _, check_buff in ipairs(buff_ids_to_check) do
                            if player_buff == check_buff then
                                has_buff = true
                                break
                            end
                        end
                        if has_buff then
                            break
                        end
                    end
                    
                    needs_buff = not has_buff
                else
                    -- No buff tracking, always use if available
                    needs_buff = true
                end
                
                if needs_buff then
                    -- Check resource
                    if resource.has_resource(job_def.resource_type, ability.cost) then
                        -- Check cooldown
                        if ability.id then
                            -- Determine if this is a spell or ability based on the command
                            local is_spell = false
                            if type(ability.command) == 'string' then
                                is_spell = ability.command:match('^/ma ') ~= nil
                            end
                            
                            local is_ready = false
                            local recast_time = 0
                            
                            if is_spell then
                                -- For spells, use spell recast check
                                is_ready = resource.is_spell_ready(ability.id)
                                recast_time = resource.get_spell_recast(ability.id)
                                common.debugf('[BUFF] %s spell recast check - Spell ID: %d, Recast Time: %d, Ready: %s', 
                                    ability.name, ability.id, recast_time or 0, tostring(is_ready))
                            else
                                -- For job abilities, use ability recast check
                                is_ready = resource.is_ability_ready(ability.id)
                                recast_time = resource.get_ability_recast(ability.id)
                                common.debugf('[BUFF] %s ability recast check - Ability ID: %d, Recast Time: %.1fs, Ready: %s', 
                                    ability.name, ability.id, (recast_time or 0) / 60.0, tostring(is_ready))
                            end
                            
                            if is_ready then
                                local command = common.build_ability_command(ability, 0)
                                if command then
                                    return {
                                        command = command,
                                        description = string.format('Applying buff: %s', ability.name)
                                    }
                                end
                            end
                        else
                            local command = common.build_ability_command(ability, 0)
                            if command then
                                return {
                                    command = command,
                                    description = string.format('Applying buff: %s', ability.name)
                                }
                            end
                        end
                    end
                end
            end
        end
        
        ::continue_ability::
    end
    
    return nil
end

return buff
