--[[
    AOE healing action module
    Handles party-wide or area-based healing
]]--

local heal_aoe = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function heal_aoe.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if AOE healing is enabled
    if not settings.heal_aoe_enabled then
        return nil
    end
    
    -- Get AOE heal abilities from job definition
    local aoe_abilities = job_def.abilities.heal_aoe or {}
    if #aoe_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level using DRY helper
    local available_abilities = common.filter_abilities_by_level(
        aoe_abilities,
        settings,
        main_level,
        sub_level,
        job_def
    )
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Check party HP status
    local party_status = common.check_party_hp(
        settings.heal_aoe_threshold or 70,
        false,
        nil,
        settings.focus_threshold or 85
    )
    
    -- Determine if AOE heal is needed
    local members_needing_heal = #party_status.needs_heal
    local average_hp = party_status.average_hp
    
    -- Trigger AOE heal if:
    -- 1. Multiple members need healing (2+)
    -- 2. Average party HP is below threshold
    local should_heal_aoe = false
    
    if settings.heal_aoe_count_threshold then
        should_heal_aoe = members_needing_heal >= settings.heal_aoe_count_threshold
    else
        should_heal_aoe = members_needing_heal >= 2
    end
    
    if not should_heal_aoe and settings.heal_aoe_avg_threshold then
        should_heal_aoe = average_hp < settings.heal_aoe_avg_threshold
    end
    
    if not should_heal_aoe then
        return nil
    end
    
    -- Select best available ability
    for _, ability in ipairs(available_abilities) do
        -- Check if this ability is blocked by status ailments
        local blocked_by = common.is_command_blocked(ability.command)
        if blocked_by then
            common.debugf('[HEAL_AOE] %s is blocked by %s', ability.name, blocked_by)
            goto continue
        end
        
        -- Check resource
        local ability_resource_type = ability.resource_type or job_def.resource_type
        if resource.has_resource(ability_resource_type, ability.cost) then
            -- Check cooldown
            if ability.id then
                if resource.is_ability_ready(ability.id) then
                    local command = common.build_ability_command(ability)
                    if command then
                        return {
                            command = command,
                            description = string.format('AOE healing with %s (%d members need healing, avg HP: %.1f%%)',
                                ability.name,
                                members_needing_heal,
                                average_hp)
                        }
                    end
                end
            else
                local command = common.build_ability_command(ability)
                if command then
                    return {
                        command = command,
                        description = string.format('AOE healing with %s (%d members need healing, avg HP: %.1f%%)',
                            ability.name,
                            members_needing_heal,
                            average_hp)
                    }
                end
            end
        end
        
        ::continue::
    end
    
    return nil
end

return heal_aoe
