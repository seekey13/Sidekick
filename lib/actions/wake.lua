--[[
    Wake from sleep action module
    Handles detecting and removing sleep status from party members
]]--

local wake = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')
local buff_utils = require('lib.core.buff_utils')

-- ============================================================================
-- Constants
-- ============================================================================

wake.SLEEP_BUFF_ID = 2      -- Sleep buff ID
wake.SLEEP_II_BUFF_ID = 19  -- Sleep II buff ID

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if buff table contains sleep
-- Args: buffs (table|number) - Array of buff IDs, or a single buff ID
-- Returns: boolean (true if any buff is sleep, false otherwise)
function wake.is_buff_sleep(buffs)
    local list = type(buffs) == 'table' and buffs or {buffs}
    return buff_utils.has_any_buff(list, {wake.SLEEP_BUFF_ID, wake.SLEEP_II_BUFF_ID})
end

-- ============================================================================
-- Main Wake Logic
-- ============================================================================

function wake.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if wake is enabled
    if not settings.wake_enabled then
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

    common.debugf('[Wake] Wake check starting...')
    
    -- Get wake abilities from job definition (can be single-target or AOE)
    local wake_abilities = {
        single = job_def.abilities.wake or {},
        aoe = job_def.abilities.wake_aoe or {}
    }
    
    -- Also check if heal/heal_aoe abilities can wake
    if job_def.abilities.heal then
        for _, ability in ipairs(job_def.abilities.heal) do
            if ability.wakes then
                table.insert(wake_abilities.single, ability)
            end
        end
    end
    
    if job_def.abilities.heal_aoe then
        for _, ability in ipairs(job_def.abilities.heal_aoe) do
            if ability.wakes then
                table.insert(wake_abilities.aoe, ability)
            end
        end
    end
    
    -- Count sleeping party members (indices 1-5 only, or 0-5 in PL mode to include player)
    local in_pl_mode = settings and settings.pl_mode_enabled and settings.pl_connected_player
    local start_index = in_pl_mode and 0 or 1
    
    local sleeping_members = {}
    for i = start_index, 5 do
        -- Skip Trusts in PL mode (cannot wake Trusts outside party)
        if in_pl_mode and common.is_trust(i) then
            goto continue_wake
        end
        
        local member_state = i == 0 and state.player or state.party[i]
        if not member_state then goto continue_wake end
        local buffs = member_state.buffs or {}
        common.debugf('[Wake] Party[%d] buffs: %s', i, table.concat(buffs, ', '))
        if wake.is_buff_sleep(buffs) then
            table.insert(sleeping_members, i)
            local name = member_state.name or 'Unknown'
            common.debugf('[Wake]   -> Party[%d] %s is sleeping (has buff 2 or 19)', i, name)
        end
        
        ::continue_wake::
    end
    
    common.debugf('[Wake] Total sleeping members: %d', #sleeping_members)
    
    -- No sleeping party members
    if #sleeping_members == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings (respects disabled abilities)
    local available_single = common.filter_abilities_by_level(wake_abilities.single, settings, derived_main_level, derived_sub_level, job_def)
    local available_aoe = common.filter_abilities_by_level(wake_abilities.aoe, settings, derived_main_level, derived_sub_level, job_def)
    
    -- Sort by cost ascending (use cheapest effective option)
    table.sort(available_single, function(a, b)
        return (a.cost or 0) < (b.cost or 0)
    end)
    
    table.sort(available_aoe, function(a, b)
        return (a.cost or 0) < (b.cost or 0)
    end)
    
    -- If 2+ members are sleeping, use AOE
    if #sleeping_members >= 2 and #available_aoe > 0 then
        common.debugf('[Wake] Multiple sleeping members (%d), trying AOE wake', #sleeping_members)
        for _, ability in ipairs(available_aoe) do
            -- Check resource
            local ability_resource_type = ability.resource_type or job_def.resource_type
            if resource.has_resource(ability_resource_type, ability.cost) then
                -- Check cooldown
                if ability.id then
                    if resource.is_ability_ready(ability.id) then
                        local command = common.build_ability_command(ability, 0, settings)
                        if command then
                            common.debugf('[Wake] >>> Using %s to wake %d members', ability.name, #sleeping_members)
                            return {
                                command = command,
                                description = string.format('Waking %d sleeping members with %s', #sleeping_members, ability.name)
                            }
                        end
                    end
                else
                    local command = common.build_ability_command(ability, 0, settings)
                    if command then
                        common.debugf('[Wake] >>> Using %s to wake %d members', ability.name, #sleeping_members)
                        return {
                            command = command,
                            description = string.format('Waking %d sleeping members with %s', #sleeping_members, ability.name)
                        }
                    end
                end
            end
            
            ::continue_aoe::
        end
    end
    
    -- Otherwise use single-target on first sleeping member
    if #available_single > 0 then
        local target_index = sleeping_members[1]
        
        -- Check if focus target is sleeping (if focus is enabled)
        if settings.focus_enabled and settings.focus_target then
            local focus_target_index = common.get_target_index_by_name(settings.focus_target)
            if focus_target_index then
                for _, idx in ipairs(sleeping_members) do
                    if idx == focus_target_index then
                        target_index = focus_target_index
                        common.debugf('[Wake] Focus target is sleeping, prioritizing them')
                        break
                    end
                end
            end
        end
        
        local target_member = target_index == 0 and state.player or state.party[target_index]
        local target_name = (target_member and target_member.name) or 'party member'
        common.debugf('[Wake] Using single-target wake on party[%d] %s', target_index, target_name)
        
        for _, ability in ipairs(available_single) do
            -- Check if this ability is blocked by status ailments
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
                common.debugf('[Wake] %s is blocked by %s', ability.name, blocked_by)
                goto continue_single
            end
            
            -- Check resource
            local ability_resource_type = ability.resource_type or job_def.resource_type
            if resource.has_resource(ability_resource_type, ability.cost) then
                -- Check cooldown
                if ability.id then
                    if resource.is_ability_ready(ability.id) then
                        local command = common.build_ability_command(ability, target_index, settings)
                        if command then
                            common.debugf('[Wake] >>> Using %s on %s', ability.name, target_name)
                            return {
                                command = command,
                                description = string.format('Waking %s with %s', target_name, ability.name)
                            }
                        end
                    end
                else
                    local command = common.build_ability_command(ability, target_index, settings)
                    if command then
                        common.debugf('[Wake] >>> Using %s on %s', ability.name, target_name)
                        return {
                            command = command,
                            description = string.format('Waking %s with %s', target_name, ability.name)
                        }
                    end
                end
            end
        end
        
        ::continue_single::
    end
    
    common.debugf('[Wake] No wake action taken')
    return nil
end

return wake
