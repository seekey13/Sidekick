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

    -- Read player data from game_state
    local state  = common.game_state
    local player = state and state.player
    if not player then
        return nil
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    -- Get AOE heal abilities from job definition
    local aoe_abilities = job_def.abilities.heal_aoe or {}
    if #aoe_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level using DRY helper
    local available_abilities = common.filter_abilities_by_level(
        aoe_abilities,
        settings,
        derived_main_level,
        derived_sub_level,
        job_def
    )
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Build party_status from game_state snapshot (no focus logic needed for AOE)
    local aoe_threshold = settings.heal_aoe_threshold or 70
    local in_pl_mode    = settings.pl_mode_enabled and settings.pl_connected_player

    local average_hp   = 100
    local total_hp     = 0
    local active_count = 0
    for i = 0, 5 do
        local member = i == 0 and state.player or state.party[i]
        if not member then goto continue_aoe_check end
        if in_pl_mode and common.is_trust(i) then goto continue_aoe_check end
        local hpp = member.hpp or 0
        if hpp == 0 or hpp == 100 then goto continue_aoe_check end
        total_hp     = total_hp     + hpp
        active_count = active_count + 1
        ::continue_aoe_check::
    end
    if active_count > 0 then
        average_hp = total_hp / active_count
    end

    -- Trigger AOE heal if average HP of active members (>0%, <100%) is below threshold
    common.debugf('[HEAL_AOE] Average HP of active members: %.1f%% (threshold: %.1f%%)', average_hp, aoe_threshold)

    if average_hp >= aoe_threshold then
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
            -- Check cooldown: distinguish spells (/ma) from job abilities
            local is_ready = true
            if ability.id then
                local is_spell = (type(ability.command) == 'string' and ability.command:match('^/ma%s'))
                if not is_spell and type(ability.command) == 'function' then
                    local test_cmd = common.build_ability_command(ability, 0, nil)
                    is_spell = test_cmd and test_cmd:match('^/ma%s')
                end
                if is_spell then
                    is_ready = resource.is_spell_ready(ability.id)
                    if not is_ready then
                        local recast_seconds = resource.get_spell_recast(ability.id) / 60.0
                        common.debugf('[HEAL_AOE] %s on cooldown (%.1fs remaining)', ability.name, recast_seconds)
                    end
                else
                    is_ready = resource.is_ability_ready(ability.id)
                    if not is_ready then
                        common.debugf('[HEAL_AOE] %s on cooldown', ability.name)
                    end
                end
            end

            if is_ready then
                local command = common.build_ability_command(ability)
                if command then
                    common.debugf('[HEAL_AOE] >>> Using %s (avg HP: %.1f%%)', ability.name, average_hp)
                    return {
                        command = command,
                        description = string.format('AOE healing with %s (avg HP: %.1f%%)',
                            ability.name, average_hp)
                    }
                end
            end
        else
            common.debugf('[HEAL_AOE] Insufficient %s for %s', ability_resource_type, ability.name)
        end

        ::continue::
    end
    
    return nil
end

return heal_aoe
