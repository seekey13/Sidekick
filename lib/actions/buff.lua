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

    -- Read player data from game_state
    local state  = common.game_state
    local player = state and state.player
    if not player then
        return nil
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    -- Track which groups have been processed in this execution (local, never persisted)
    local processed_groups = {}
    
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
    
    common.debugf('[BUFF] Before filter: %d buff abilities, main_level=%d, sub_level=%d', #buff_abilities, derived_main_level, derived_sub_level)
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(buff_abilities, settings, derived_main_level, derived_sub_level, job_def)
    
    common.debugf('[BUFF] After filter: %d/%d abilities available', #available_abilities, #buff_abilities)
    
    if #available_abilities > 0 then
        common.debugf('[BUFF] Available abilities: %s', table.concat((function()
            local names = {}
            for _, a in ipairs(available_abilities) do
                table.insert(names, a.name)
            end
            return names
        end)(), ', '))
    end
    
    if #available_abilities == 0 then
        common.debugf('[BUFF] No available abilities after filtering')
        return nil
    end
    
    -- Check each buff to see if it needs to be applied/refreshed
    for _, ability in ipairs(available_abilities) do
        common.debugf('[BUFF] Checking ability: %s', ability.name)
        local should_skip = false
        
        -- Check pet requirement
        if not should_skip and ability.pet_required then
            if not common.targets.get_pet() then
                common.debugf('[BUFF]   %s blocked: no pet', ability.name)
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
            local player_buffs_for_prereq = state.player.buffs or {}
            for _, required_buff in ipairs(required_buff_ids) do
                for _, active_buff in ipairs(player_buffs_for_prereq) do
                    if active_buff == required_buff then
                        has_required_buff = true
                        break
                    end
                end
                if has_required_buff then break end
            end
            
            if not has_required_buff then
                common.debugf('[BUFF]   %s blocked: missing required buff', ability.name)
                should_skip = true
            end
        end
        
        -- Check if this ability is blocked by status ailments
        if not should_skip then
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
                common.debugf('[BUFF] %s is blocked by %s', ability.name, blocked_by)
                should_skip = true
            end
        end
        
        if not should_skip then
            -- Determine if this is a single-target buff (function command) or self-only buff (string command)
            local is_single_target = type(ability.command) == 'function'
            
            if is_single_target then
                -- Single-target buff: Check button states for ME and party members (P1-P5)
                -- First check if ability/group is enabled via settings
                local key
                local config_key
                if ability.group then
                    key = 'disabled_group_' .. ability.group
                    config_key = ability.group
                    
                    -- Check if this ability is the selected one for this group
                    local selected_key = 'selected_' .. ability.group
                    local selected_ability = settings[selected_key]
                    if selected_ability then
                        -- A specific ability is selected, only use that one
                        if selected_ability ~= ability.name then
                            goto continue_ability
                        end
                    else
                        -- No selection made yet - UI will handle this on next open
                        -- For now, skip all but the first available ability in this group
                        -- (filter_abilities_by_level already sorted by cost descending = highest level first)
                        -- Check if we've already processed an ability from this group
                        if processed_groups[ability.group] then
                            -- Already processed another ability from this group, skip this one
                            goto continue_ability
                        else
                            -- Mark this group as processed for this execution cycle
                            processed_groups[ability.group] = true
                        end
                    end
                else
                    key = 'disabled_' .. ability.name:gsub(' ', '_')
                    config_key = ability.name
                end
                local is_ability_enabled = settings[key] == false or settings[key] == nil
                common.debugf('[BUFF]   %s: key=%s, is_enabled=%s, config_key=%s', ability.name, key, tostring(is_ability_enabled), config_key)
                
                if not is_ability_enabled then
                    common.debugf('[BUFF]   %s blocked: disabled in settings', ability.name)
                    goto continue_ability
                end
                
                -- Check if any party buttons are enabled
                local has_any_target = false
                if party_buff_config and party_buff_config[config_key] then
                    for i = 0, 5 do
                        if party_buff_config[config_key][i] == true then
                            has_any_target = true
                            break
                        end
                    end
                end
                
                common.debugf('[BUFF]   %s: has_any_target=%s', ability.name, tostring(has_any_target))
                
                if not has_any_target then
                    common.debugf('[BUFF]   %s blocked: no party buttons enabled', ability.name)
                    goto continue_ability
                end
                
                -- Priority order: ME, P1, P2, P3, P4, P5
                local targets_to_check = {0, 1, 2, 3, 4, 5}  -- 0 = ME, 1-5 = P1-P5
                
                for _, target_index in ipairs(targets_to_check) do
                    -- Check if this target is enabled in party_buff_config
                    local is_target_enabled = false
                    if party_buff_config and party_buff_config[config_key] then
                        is_target_enabled = party_buff_config[config_key][target_index] == true
                    end
                    
                    if is_target_enabled then
                        common.debugf('[BUFF]     Target %d is enabled, checking...', target_index)
                        local target_needs_buff = false
                        local target_entity_index = nil
                        
                        -- Get target buffs and entity index
                        if target_index == 0 then
                            -- ME: Check player buffs from game_state
                            target_buffs = state.player.buffs or {}
                            target_entity_index = 0
                        else
                            -- P1-P5: Check party member buffs from game_state
                            -- Zone check stays as live call (zone not stored in game_state)
                            local party_member = state.party[target_index]
                            if party_member then
                                local player_zone = common.get_party_member_zone(0)
                                local member_zone = common.get_party_member_zone(target_index)
                                target_entity_index = party_member.target_index
                                
                                if target_entity_index and target_entity_index > 0 and player_zone == member_zone and common.is_in_range(target_entity_index, 20) then
                                    target_buffs = party_member.buffs or {}
                                else
                                    -- Party member not available or out of range, skip
                                    goto continue_target
                                end
                            else
                                -- Party member not active in game_state, skip
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
                        
                        common.debugf('[BUFF]     Target %d needs_buff=%s', target_index, tostring(target_needs_buff))
                        
                        if target_needs_buff then
                            -- Check if this ability requires a target modifier (Pianissimo, Entrust, etc.)
                            if ability.target_modifier and target_index > 0 then
                                -- Check if we already have the modifier buff active
                                local has_modifier_buff = false
                                if job_def.abilities.target_modifier and #job_def.abilities.target_modifier > 0 then
                                    local modifier_ability = job_def.abilities.target_modifier[1]
                                    if modifier_ability.buff_id then
                                        local player_buffs_mod = state.player.buffs or {}
                                        for _, active_buff in ipairs(player_buffs_mod) do
                                            if active_buff == modifier_ability.buff_id then
                                                has_modifier_buff = true
                                                break
                                            end
                                        end
                                    end
                                end
                                
                                if not has_modifier_buff then
                                    -- Don't have modifier buff, try to use it
                                    local modifier_result = common.check_target_modifier(job_def, settings, derived_main_level, derived_sub_level)
                                    if modifier_result then
                                        -- Need to use modifier ability first
                                        return modifier_result
                                    else
                                        -- Modifier unavailable (on cooldown, disabled, etc.), skip this ability for now
                                        return nil
                                    end
                                end
                                -- If we reach here, we have the modifier buff, proceed to cast the song
                            end
                            
                            -- Check resource (skip in PL Mode since we can't check connected player's MP/TP)
                            local in_pl_mode = settings and settings.pl_mode_enabled and settings.pl_connected_player
                            local has_resource = true
                            if not in_pl_mode then
                                local ability_resource_type = ability.resource_type or job_def.resource_type
                                has_resource = resource.has_resource(ability_resource_type, ability.cost)
                                common.debugf('[BUFF]     Resource check: type=%s, cost=%d, has_resource=%s', 
                                    tostring(ability_resource_type), ability.cost or 0, tostring(has_resource))
                            else
                                common.debugf('[BUFF]     PL Mode: skipping resource check')
                            end
                            
                            if has_resource then
                                -- Check cooldown
                                if ability.id then
                                    local is_spell = false
                                    local test_cmd = common.build_ability_command(ability, target_index, settings)
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
                                        local command = common.build_ability_command(ability, target_index, settings)
                                        if command then
                                            -- Register pending buff if target is a Trust (server_id from game_state)
                                            if ability.buff_id and target_index > 0 then
                                                local trust_member = state.party[target_index]
                                                local trust_server_id = trust_member and trust_member.server_id
                                                if trust_server_id and trust_server_id >= 0x1000000 then
                                                    local buff_to_track = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                                    common.register_pending_buff(trust_server_id, buff_to_track)
                                                end
                                            end
                                            
                                            local target_name = target_index == 0 and 'self' or (state.party[target_index] and state.party[target_index].name or ('P' .. target_index))
                                            return {
                                                command = command,
                                                description = string.format('Applying buff: %s to %s', ability.name, target_name)
                                            }
                                        end
                                    end
                                else
                                    local command = common.build_ability_command(ability, target_index, settings)
                                    if command then
                                        -- Register pending buff if target is a Trust (server_id from game_state)
                                        if ability.buff_id and target_index > 0 then
                                            local trust_member = state.party[target_index]
                                            local trust_server_id = trust_member and trust_member.server_id
                                            if trust_server_id and trust_server_id >= 0x1000000 then
                                                local buff_to_track = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                                common.register_pending_buff(trust_server_id, buff_to_track)
                                            end
                                        end
                                        
                                        local target_name = target_index == 0 and 'self' or (state.party[target_index] and state.party[target_index].name or ('P' .. target_index))
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
                -- Check if ability/group is enabled via settings
                local key
                if ability.group then
                    key = 'disabled_group_' .. ability.group
                    
                    -- Check if this ability is the selected one for this group
                    local selected_key = 'selected_' .. ability.group
                    local selected_ability = settings[selected_key]
                    if selected_ability then
                        -- A specific ability is selected, only use that one
                        if selected_ability ~= ability.name then
                            goto continue_ability
                        end
                    else
                        -- No selection made yet - UI will handle this on next open
                        -- For now, skip all but the first available ability in this group
                        -- (filter_abilities_by_level already sorted by cost descending = highest level first)
                        -- Check if we've already processed an ability from this group
                        if processed_groups[ability.group] then
                            -- Already processed another ability from this group, skip this one
                            goto continue_ability
                        else
                            -- Mark this group as processed for this execution cycle
                            processed_groups[ability.group] = true
                        end
                    end
                else
                    key = 'disabled_' .. ability.name:gsub(' ', '_')
                end
                local is_enabled = settings[key] == false or settings[key] == nil
                
                if not is_enabled then
                    goto continue_ability
                end
                
                -- Check if buff is already active
                local needs_buff = false
                
                if ability.buff_id then
                    -- Check player for this buff from game_state
                    local has_buff = false
                    local player_buffs = state.player.buffs or {}
                    
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
                    local ability_resource_type = ability.resource_type or job_def.resource_type
                    if resource.has_resource(ability_resource_type, ability.cost) then
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
                            local command = common.build_ability_command(ability, 0, settings)
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
