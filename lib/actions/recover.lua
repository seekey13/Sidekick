--[[
    Resource recovery action module
    Handles MP and TP recovery abilities
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
    local recover_mp_abilities = job_def.abilities.recover_mp or {}
    local recover_tp_abilities = job_def.abilities.recover_tp or {}
    local recover_party_mp_abilities = job_def.abilities.recover_party_mp or {}
    
    if #recover_mp_abilities == 0 and #recover_tp_abilities == 0 and #recover_party_mp_abilities == 0 then
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
    
    -- Check Focus Recovery Target (Devotion) first - cast on party member
    if settings.focus_recovery_target then
        local target_party_index = common.get_party_index_by_name(settings.focus_recovery_target)
        
        -- Validate target (must be party member P1-P5, not player P0)
        if target_party_index and target_party_index >= 1 and target_party_index <= 5 then
            local target_mpp = common.get_party_member_mp_percent(target_party_index)
            local target_name = settings.focus_recovery_target
            local threshold = settings.focus_recovery_threshold or 30
            
            common.debugf('[RECOVER] Focus Recovery Target: %s, MP: %.1f%%, Threshold: %.1f%%',
                         target_name, target_mpp, threshold)
            
            -- Check if target needs MP recovery
            if target_mpp > 0 and target_mpp < threshold then
                -- Find Devotion ability in recover_party_mp list
                for _, ability in ipairs(recover_party_mp_abilities) do
                    if ability.name == 'Devotion' then
                        local can_use_devotion = true
                        
                        -- Check if ability is disabled
                        local disabled_key = 'disabled_' .. ability.name:gsub(' ', '_')
                        local is_disabled = settings[disabled_key]
                        if is_disabled then
                            common.debugf('[RECOVER] Devotion is disabled, skipping')
                            can_use_devotion = false
                        end
                        
                        -- Check level requirement
                        if can_use_devotion then
                            local required_level = ability.level or 0
                            if required_level > main_level then
                                common.debugf('[RECOVER] Devotion requires level %d (current: %d)', required_level, main_level)
                                can_use_devotion = false
                            end
                        end
                        
                        -- Check if blocked by status ailments
                        if can_use_devotion then
                            local blocked_by = common.is_command_blocked(ability.command)
                            if blocked_by then
                                common.debugf('[RECOVER] Devotion is blocked by %s', blocked_by)
                                can_use_devotion = false
                            end
                        end
                        
                        -- Check if target is in range (20 yalms)
                        if can_use_devotion then
                            local target_entity_index = party:GetMemberTargetIndex(target_party_index)
                            if not target_entity_index or not common.is_in_range(target_entity_index, 20) then
                                common.debugf('[RECOVER] Target %s out of range', target_name)
                                can_use_devotion = false
                            end
                        end
                        
                        -- Check cooldown
                        if can_use_devotion then
                            if ability.id and not resource.is_ability_ready(ability.id) then
                                common.debugf('[RECOVER] Devotion on cooldown')
                                can_use_devotion = false
                            end
                        end
                        
                        -- Cast Devotion on focus recovery target
                        if can_use_devotion then
                            local command = common.build_ability_command(ability, target_party_index)
                            if command then
                                common.debugf('[RECOVER] >>> Using Devotion on %s - Target MP: %.1f%%',
                                             target_name, target_mpp)
                                return {
                                    command = command,
                                    description = string.format('Devotion on %s (MP: %.1f%%)', target_name, target_mpp)
                                }
                            end
                        end
                        
                        break
                    end
                end
            end
        end
    end
    
    -- Check MP recovery for self (after Devotion check)
    if #recover_mp_abilities > 0 and settings.recover_mp_threshold then
        common.debugf('[RECOVER] MP threshold: %.1f%%, current: %.1f%%', settings.recover_mp_threshold, mp_percent)
        
        if mp_percent < settings.recover_mp_threshold then
            -- Filter abilities by level
            local available_abilities = common.filter_abilities_by_level(
                recover_mp_abilities,
                settings,
                main_level,
                sub_level,
                job_def
            )
            
            if #available_abilities > 0 then
                -- Select first available ability (highest cost = most effective)
                for _, ability in ipairs(available_abilities) do
                    -- Check if this ability is blocked by status ailments
                    local blocked_by = common.is_command_blocked(ability.command)
                    if blocked_by then
                        common.debugf('[RECOVER] %s is blocked by %s', ability.name, blocked_by)
                        goto continue_mp
                    end
                    
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
                    
                    ::continue_mp::
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
                sub_level,
                job_def
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
                    
                    if not has_required_buff then
                        common.debugf('[RECOVER] %s requires buff prerequisite, skipping', ability.name)
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
