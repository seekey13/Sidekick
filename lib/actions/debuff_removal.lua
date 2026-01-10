--[[
    Debuff removal (erase/cleanse) action module
    Handles detecting and removing removable debuffs from party members
    Based on BackupDancer's erase.lua logic
]]--

local debuff_removal = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if a buff ID is removable by any ability
-- Args: buff_id (number) - The buff ID to check
--       abilities (table) - Array of debuff removal abilities
-- Returns: boolean (true if removable, false otherwise)
local function is_buff_removable(buff_id, abilities)
    for _, ability in ipairs(abilities) do
        if ability.debuff_id then
            local debuff_ids = type(ability.debuff_id) == 'table' and ability.debuff_id or {ability.debuff_id}
            for _, removable_id in ipairs(debuff_ids) do
                if buff_id == removable_id then
                    return true
                end
            end
        end
    end
    return false
end

-- Count removable debuffs in a list of buffs
-- Args: buffs (table) - Array of buff IDs
--       abilities (table) - Array of debuff removal abilities
-- Returns: count (number) - Number of removable debuffs found
local function count_removable_debuffs(buffs, abilities)
    local count = 0
    for _, buff_id in ipairs(buffs) do
        if is_buff_removable(buff_id, abilities) then
            count = count + 1
        end
    end
    return count
end

-- Check if an ability can remove any of the detected debuffs
-- Args: ability (table) - The ability to check
--       debuffs (table) - Array of detected buff IDs
-- Returns: boolean (true if ability can remove at least one debuff)
local function can_remove_debuffs(ability, debuffs)
    if not ability.debuff_id then
        -- No debuff_id specified, assume it can remove any debuff
        return #debuffs > 0
    end
    
    local debuff_ids = type(ability.debuff_id) == 'table' and ability.debuff_id or {ability.debuff_id}
    for _, detected_debuff in ipairs(debuffs) do
        for _, removable_id in ipairs(debuff_ids) do
            if detected_debuff == removable_id then
                return true
            end
        end
    end
    
    return false
end

-- ============================================================================
-- Main Execution
-- ============================================================================

function debuff_removal.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if debuff removal is enabled and status is idle or engaged
    if not settings.debuff_removal_enabled or common.is_in_event() then
        return nil
    end
    
    -- Get debuff removal abilities from job definition
    local removal_abilities = job_def.abilities.debuff_removal or {}
    if #removal_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(removal_abilities, settings, main_level, sub_level)
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Check for self-only abilities first (like Monk's Chakra)
    for _, ability in ipairs(available_abilities) do
        if ability.self_only then
            local player_buffs = common.get_player_buffs()
            if can_remove_debuffs(ability, player_buffs) then
                -- Check resource
                if resource.has_resource(job_def.resource_type, ability.cost) then
                    -- Check cooldown (if ability has an ID)
                    local is_ready = true
                    if ability.id then
                        is_ready = resource.is_spell_ready(ability.id)
                        common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                            ability.name, ability.id, tostring(is_ready))
                    end
                    
                    if is_ready then
                        local command = debuff_removal.build_command(ability, 0)
                        if command then
                            local debuff_count = count_removable_debuffs(player_buffs, {ability})
                            common.debugf('[DEBUFF_REMOVAL] Using %s on self (%d debuff%s)', 
                                ability.name, debuff_count, debuff_count == 1 and '' or 's')
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from self with %s',
                                    debuff_count, ability.name)
                            }
                        end
                    end
                end
            end
        end
    end
    
    -- Combine player buffs (index 0) with party buffs (indices 1-5)
    local all_buffs = {}
    all_buffs[0] = common.get_player_buffs()
    for i = 1, 5 do
        all_buffs[i] = common.get_party_buffs(i)
    end
    
    -- Count removable debuffs for each party member
    local debuff_counts = {}
    for i = 0, 5 do
        debuff_counts[i] = count_removable_debuffs(all_buffs[i], available_abilities)
    end
    
    -- Priority 1: Check focus target first
    if settings.focus_enabled and settings.focus_target_index then
        -- Convert focus_target_index (entity target index) to party index
        local focus_party_index = nil
        local party = common.get_party()
        
        if party then
            for i = 0, 5 do
                if common.is_party_member_active(i) then
                    local target_index = party:GetMemberTargetIndex(i)
                    if target_index == settings.focus_target_index then
                        focus_party_index = i
                        break
                    end
                end
            end
        end
        
        if focus_party_index and debuff_counts[focus_party_index] > 0 then
            -- Try to use an ability on focus target
            for _, ability in ipairs(available_abilities) do
                if can_remove_debuffs(ability, all_buffs[focus_party_index]) then
                    -- Check resource
                    if resource.has_resource(job_def.resource_type, ability.cost) then
                        -- Check cooldown (if ability has an ID)
                        local is_ready = true
                        if ability.id then
                            is_ready = resource.is_spell_ready(ability.id)
                            common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                                ability.name, ability.id, tostring(is_ready))
                        end
                        
                        if is_ready then
                            local command = debuff_removal.build_command(ability, focus_party_index)
                            if command then
                                common.debugf('[DEBUFF_REMOVAL] Using %s on focus target (p%d, %d debuff%s)', 
                                    ability.name, focus_party_index, debuff_counts[focus_party_index],
                                    debuff_counts[focus_party_index] == 1 and '' or 's')
                                return {
                                    command = command,
                                    description = string.format('Removing %d debuff(s) from focus with %s',
                                        debuff_counts[focus_party_index], ability.name)
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Priority 2: Find party member with most removable debuffs
    local best_index = nil
    local max_debuffs = 0
    
    for i = 0, 5 do
        -- Skip focus (already checked) and members with no debuffs
        local focus_party_index = nil
        if settings.focus_enabled and settings.focus_target_index then
            local party = common.get_party()
            if party then
                for j = 0, 5 do
                    if common.is_party_member_active(j) then
                        local target_index = party:GetMemberTargetIndex(j)
                        if target_index == settings.focus_target_index then
                            focus_party_index = j
                            break
                        end
                    end
                end
            end
        end
        
        if i ~= focus_party_index and debuff_counts[i] > 0 then
            -- Update if this member has more debuffs, or same amount but lower index
            if debuff_counts[i] > max_debuffs then
                best_index = i
                max_debuffs = debuff_counts[i]
            end
        end
    end
    
    -- Use ability on the best target
    if best_index then
        for _, ability in ipairs(available_abilities) do
            if can_remove_debuffs(ability, all_buffs[best_index]) then
                -- Check resource
                if resource.has_resource(job_def.resource_type, ability.cost) then
                    -- Check cooldown (if ability has an ID)
                    local is_ready = true
                    if ability.id then
                        is_ready = resource.is_spell_ready(ability.id)
                        common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                            ability.name, ability.id, tostring(is_ready))
                    end
                    
                    if is_ready then
                        local command = debuff_removal.build_command(ability, best_index)
                        if command then
                            common.debugf('[DEBUFF_REMOVAL] Using %s on p%d (%d debuff%s)', 
                                ability.name, best_index, max_debuffs,
                                max_debuffs == 1 and '' or 's')
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from %s with %s',
                                    max_debuffs,
                                    common.get_party_member_name(best_index) or 'party member',
                                    ability.name)
                            }
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

function debuff_removal.build_command(ability, party_index)
    if type(ability.command) == 'function' then
        return ability.command(party_index)
    elseif type(ability.command) == 'string' then
        -- Replace <pN> placeholder if present
        local command = ability.command:gsub('<p(%d+)>', function(idx)
            return '<p' .. party_index .. '>'
        end)
        return command
    end
    return nil
end

return debuff_removal
