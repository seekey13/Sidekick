--[[
    Buff maintenance action module
    Handles maintaining self and party buffs
]]--

local buff = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function buff.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if buff is enabled
    if not settings.buff_enabled then
        return nil
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
