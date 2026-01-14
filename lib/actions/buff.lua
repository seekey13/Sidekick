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
    local available_abilities = common.filter_abilities_by_level(buff_abilities, settings, main_level, sub_level)
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Check combat status
    local is_idle = common.is_idle()
    local is_engaged = common.is_engaged()
    
    -- Check each buff to see if it needs to be applied/refreshed
    for _, ability in ipairs(available_abilities) do
        local should_skip = false
        
        -- Check if ability is disabled in settings
        local disabled_key = 'disabled_' .. ability.name:gsub(' ', '_')
        if settings[disabled_key] then
            should_skip = true
        end
        
        -- Check combat requirements
        if not should_skip and ability.combat_only and is_idle then
            -- Skip buffs that require combat
            should_skip = true
        end
        
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
        
        -- Check required buff prerequisite
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
        
        if not should_skip then
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
            elseif ability.check_buff then
                -- Custom buff checking function
                needs_buff = not ability.check_buff()
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
                            local command = buff.build_command(ability)
                            if command then
                                return {
                                    command = command,
                                    description = string.format('Applying buff: %s', ability.name)
                                }
                            end
                        end
                    else
                        local command = buff.build_command(ability)
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
    
    -- Priority 2: Check party members (P1-P5) for missing buffs
    -- Only check if we're in a party and have party-castable buffs configured
    local party_size = common.get_party_size()
    if party_size > 1 and party_buff_config then
        -- Check each party member in order P1-P5
        for party_index = 1, 5 do
            -- Stop if we've checked all active party members
            if party_index >= party_size then
                break
            end
            
            -- Check if party member is active and in range (20 yalms for buff spells)
            local target_index = common.get_party_member_target_index(party_index)
            if target_index and common.is_in_range(target_index, 20) then
                -- Get this party member's buffs
                local member_buffs = common.get_party_buffs(party_index)
                
                -- Check each ability to see if it's enabled for this party member
                for _, ability in ipairs(available_abilities) do
                    -- Skip if not enabled for this party member
                    if not party_buff_config[ability.name] or not party_buff_config[ability.name][party_index] then
                        goto continue_ability
                    end
                    
                    -- Skip if ability can't be cast on party (not a function command)
                    if type(ability.command) ~= 'function' then
                        goto continue_ability
                    end
                    
                    local should_skip = false
                    
                    -- Check if ability is disabled in settings
                    local disabled_key = 'disabled_' .. ability.name:gsub(' ', '_')
                    if settings[disabled_key] then
                        should_skip = true
                    end
                    
                    -- Check combat requirements
                    if not should_skip and ability.combat_only and is_idle then
                        should_skip = true
                    end
                    
                    if not should_skip and ability.idle_only and is_engaged then
                        should_skip = true
                    end
                    
                    -- Check pet requirement
                    if not should_skip and ability.pet_required then
                        if not common.has_pet() then
                            should_skip = true
                        end
                    end
                    
                    -- Check required buff prerequisite
                    if not should_skip and ability.requires_buff then
                        local has_required_buff = false
                        local required_buff_ids = {}
                        
                        if type(ability.requires_buff) == 'table' then
                            required_buff_ids = ability.requires_buff
                        else
                            required_buff_ids = {ability.requires_buff}
                        end
                        
                        -- Check if party member has any of the required buffs
                        for _, required_buff in ipairs(required_buff_ids) do
                            if common.has_buff(target_index, required_buff) then
                                has_required_buff = true
                                break
                            end
                        end
                        
                        if not has_required_buff then
                            should_skip = true
                        end
                    end
                    
                    if not should_skip then
                        -- Check if party member needs this buff
                        local needs_buff = false
                        
                        if ability.buff_id then
                            local has_buff = false
                            local buff_ids_to_check = {}
                            if type(ability.buff_id) == 'table' then
                                buff_ids_to_check = ability.buff_id
                            else
                                buff_ids_to_check = {ability.buff_id}
                            end
                            
                            -- Check if party member has any of the specified buffs
                            for _, member_buff in ipairs(member_buffs) do
                                for _, check_buff in ipairs(buff_ids_to_check) do
                                    if member_buff == check_buff then
                                        has_buff = true
                                        break
                                    end
                                end
                                if has_buff then
                                    break
                                end
                            end
                            
                            needs_buff = not has_buff
                        elseif ability.check_buff then
                            -- Custom buff checking function (skip for party members)
                            needs_buff = false
                        else
                            -- No buff tracking, always use if available
                            needs_buff = true
                        end
                        
                        if needs_buff then
                            -- Check resource
                            if resource.has_resource(job_def.resource_type, ability.cost) then
                                -- Check cooldown
                                if ability.id then
                                    local is_spell = false
                                    if type(ability.command) == 'string' then
                                        is_spell = ability.command:match('^/ma ') ~= nil
                                    else
                                        -- Function command, check if it generates a spell command
                                        local test_cmd = ability.command(party_index)
                                        is_spell = test_cmd and test_cmd:match('^/ma ') ~= nil
                                    end
                                    
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
                                        local command = ability.command(party_index)
                                        if command then
                                            local member_name = common.get_party_member_name(party_index) or ('P' .. party_index)
                                            return {
                                                command = command,
                                                description = string.format('Applying buff: %s to %s', ability.name, member_name)
                                            }
                                        end
                                    end
                                else
                                    local command = ability.command(party_index)
                                    if command then
                                        local member_name = common.get_party_member_name(party_index) or ('P' .. party_index)
                                        return {
                                            command = command,
                                            description = string.format('Applying buff: %s to %s', ability.name, member_name)
                                        }
                                    end
                                end
                            end
                        end
                    end
                    
                    ::continue_ability::
                end
            else
                common.debugf('[BUFF] Party member P%d out of range or not active, skipping', party_index)
            end
        end
    end
    
    return nil
end

function buff.build_command(ability)
    if type(ability.command) == 'function' then
        -- Pass party_index 0 for self-targeting
        return ability.command(0)
    elseif type(ability.command) == 'string' then
        return ability.command
    end
    return nil
end

return buff
