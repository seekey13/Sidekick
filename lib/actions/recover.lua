--[[
    Resource recovery action module
    Handles MP recovery abilities
]]--

local recover = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function recover.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if recovery is enabled
    if not settings.recover_enabled then
        return nil
    end
    
    -- Get recovery abilities from job definition
    local recover_abilities = job_def.abilities.recover or {}
    
    if #recover_abilities == 0 and #recover_tp_abilities == 0 then
        return nil
    end
    
    -- Get player's current MP and TP
    local current_mp = common.get_player_mp()
    local current_tp = common.get_player_tp()
    
    -- Get player's MP percentage (from party manager)
    local party = common.get_party()
    if not party then
        return nil
    end
    
    local mp_percent = party:GetMemberMPPercent(0) or 0
    
    common.debugf('[RECOVER] Current MP: %d (%.1f%%), TP: %d', current_mp, mp_percent, current_tp)
    
    -- Check MP recovery first (higher priority)
    if #recover_abilities > 0 and settings.recover_threshold then
        common.debugf('[RECOVER] MP threshold: %.1f%%, current: %.1f%%', settings.recover_threshold, mp_percent)
        
        if mp_percent < settings.recover_threshold then
            -- Filter abilities by level
            local available_abilities = common.filter_abilities_by_level(
                recover_abilities,
                settings,
                main_level,
                sub_level
            )
            
            if #available_abilities > 0 then
                -- Select first available ability (highest cost = most effective)
                for _, ability in ipairs(available_abilities) do
                    -- Check required buff prerequisite
                    local has_required_buff = true
                    if ability.requires_buff then
                        has_required_buff = false
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
                    end
                    
                    if not has_required_buff then
                        common.debugf('[RECOVER] %s requires buff prerequisite, skipping', ability.name)
                    -- Check resource and cooldown
                    elseif resource.has_resource(job_def.resource_type, ability.cost) and resource.is_ability_ready(ability.id) then
                        local command = common.build_ability_command(ability, nil)
                        
                        if command then
                            common.debugf('[RECOVER] >>> Using MP recovery: %s (MP: %.1f%%)', ability.name, mp_percent)
                            return {
                                command = command,
                                description = string.format('MP recovery with %s (MP: %.1f%%)', ability.name, mp_percent)
                            }
                        end
                    else
                        common.debugf('[RECOVER] %s not available (cooldown or insufficient resources)', ability.name)
                    end
                end
            end
        end
    end
    
    -- Check TP recovery
    if #recover_tp_abilities > 0 and settings.recover_tp_threshold then
        common.debugf('[RECOVER] TP threshold: %d, current: %d', settings.recover_tp_threshold, current_tp)
        
        if current_tp < settings.recover_tp_threshold then
            -- Filter abilities by level
            local available_abilities = common.filter_abilities_by_level(
                recover_tp_abilities,
                settings,
                main_level,
                sub_level
            )
            
            if #available_abilities > 0 then
                -- Select first available ability
                for _, ability in ipairs(available_abilities) do
                    -- Check required buff prerequisite
                    local has_required_buff = true
                    if ability.requires_buff then
                        has_required_buff = false
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
                    end
                    
                    -- Check combat_only flag
                    if not has_required_buff then
                        common.debugf('[RECOVER] %s requires buff prerequisite, skipping', ability.name)
                    elseif ability.combat_only and common.is_idle() then
                        common.debugf('[RECOVER] %s requires combat, skipping', ability.name)
                    elseif ability.idle_only and common.is_engaged() then
                        common.debugf('[RECOVER] %s requires idle, skipping', ability.name)
                    -- Check resource and cooldown
                    elseif resource.has_resource(job_def.resource_type, ability.cost) and resource.is_ability_ready(ability.id) then
                        local command = common.build_ability_command(ability, nil)
                        
                        if command then
                            common.debugf('[RECOVER] >>> Using TP recovery: %s (TP: %d)', ability.name, current_tp)
                            return {
                                command = command,
                                description = string.format('TP recovery with %s (TP: %d)', ability.name, current_tp)
                            }
                        end
                    else
                        common.debugf('[RECOVER] %s not available (cooldown or insufficient resources)', ability.name)
                    end
                end
            end
        end
    end
    
    return nil
end

return recover
