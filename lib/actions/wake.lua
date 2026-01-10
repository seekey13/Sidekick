--[[
    Wake from sleep action module
    Handles detecting and removing sleep status from party members
]]--

local wake = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

-- ============================================================================
-- Constants
-- ============================================================================

wake.SLEEP_BUFF_ID = 2      -- Sleep buff ID
wake.SLEEP_II_BUFF_ID = 19  -- Sleep II buff ID

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if buff table contains sleep
-- Args: buffs (table) - Array of buff IDs to check
-- Returns: boolean (true if any buff is sleep, false otherwise)
function wake.is_buff_sleep(buffs)
    if type(buffs) ~= 'table' then
        return buffs == wake.SLEEP_BUFF_ID or buffs == wake.SLEEP_II_BUFF_ID
    end
    
    for _, buff_id in ipairs(buffs) do
        if buff_id == wake.SLEEP_BUFF_ID or buff_id == wake.SLEEP_II_BUFF_ID then
            return true
        end
    end
    return false
end

-- ============================================================================
-- Main Wake Logic
-- ============================================================================

function wake.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if wake is enabled
    if not settings.wake_enabled then
        return nil
    end
    
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
    
    -- Count sleeping party members (indices 1-5 only, exclude player at 0)
    local sleeping_members = {}
    for i = 1, 5 do
        local buffs = common.get_party_buffs(i)
        common.debugf('[Wake] Party[%d] buffs: %s', i, table.concat(buffs, ', '))
        if wake.is_buff_sleep(buffs) then
            table.insert(sleeping_members, i)
            local name = common.get_party_member_name(i) or 'Unknown'
            common.debugf('[Wake]   -> Party[%d] %s is sleeping (has buff 2 or 19)', i, name)
        end
    end
    
    common.debugf('[Wake] Total sleeping members: %d', #sleeping_members)
    
    -- No sleeping party members
    if #sleeping_members == 0 then
        return nil
    end
    
    -- Filter abilities by level and sort by cost (use cheapest)
    local available_single = {}
    local available_aoe = {}
    
    for _, ability in ipairs(wake_abilities.single) do
        -- Determine which level to use based on ability source
        local player_level = ability.is_main_job == false and sub_level or main_level
        if ability.level <= player_level then
            table.insert(available_single, ability)
        end
    end
    
    for _, ability in ipairs(wake_abilities.aoe) do
        -- Determine which level to use based on ability source
        local player_level = ability.is_main_job == false and sub_level or main_level
        if ability.level <= player_level then
            table.insert(available_aoe, ability)
        end
    end
    
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
            if resource.has_resource(job_def.resource_type, ability.cost) then
                -- Check cooldown
                if ability.id then
                    if resource.is_ability_ready(ability.id) then
                        local command = wake.build_command(ability, nil)
                        if command then
                            common.debugf('[Wake] >>> Using %s to wake %d members', ability.name, #sleeping_members)
                            return {
                                command = command,
                                description = string.format('Waking %d sleeping members with %s', #sleeping_members, ability.name)
                            }
                        end
                    end
                else
                    local command = wake.build_command(ability, nil)
                    if command then
                        common.debugf('[Wake] >>> Using %s to wake %d members', ability.name, #sleeping_members)
                        return {
                            command = command,
                            description = string.format('Waking %d sleeping members with %s', #sleeping_members, ability.name)
                        }
                    end
                end
            end
        end
    end
    
    -- Otherwise use single-target on first sleeping member
    if #available_single > 0 then
        local target_index = sleeping_members[1]
        
        -- Check if focus target is sleeping (if focus is enabled)
        if settings.focus_enabled and settings.focus_target_index then
            for _, idx in ipairs(sleeping_members) do
                if idx == settings.focus_target_index then
                    target_index = settings.focus_target_index
                    common.debugf('[Wake] Focus target is sleeping, prioritizing them')
                    break
                end
            end
        end
        
        local target_name = common.get_party_member_name(target_index) or 'party member'
        common.debugf('[Wake] Using single-target wake on party[%d] %s', target_index, target_name)
        
        for _, ability in ipairs(available_single) do
            -- Check resource
            if resource.has_resource(job_def.resource_type, ability.cost) then
                -- Check cooldown
                if ability.id then
                    if resource.is_ability_ready(ability.id) then
                        local command = wake.build_command(ability, target_index)
                        if command then
                            common.debugf('[Wake] >>> Using %s on %s', ability.name, target_name)
                            return {
                                command = command,
                                description = string.format('Waking %s with %s', target_name, ability.name)
                            }
                        end
                    end
                else
                    local command = wake.build_command(ability, target_index)
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
    end
    
    common.debugf('[Wake] No wake action taken')
    return nil
end

function wake.build_command(ability, party_index)
    if type(ability.command) == 'function' then
        return ability.command(party_index)
    elseif type(ability.command) == 'string' then
        if party_index then
            -- Replace <pN> placeholder if present
            local command = ability.command:gsub('<p(%d+)>', function(idx)
                return '<p' .. party_index .. '>'
            end)
            return command
        else
            return ability.command
        end
    end
    return nil
end

return wake
