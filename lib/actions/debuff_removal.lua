--[[
    Debuff removal (erase/cleanse) action module
    Handles detecting and removing removable debuffs from party members
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
    if not settings.debuff_removal_enabled then
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

    -- Get debuff removal abilities from job definition
    local removal_abilities = job_def.abilities.debuff_removal or {}
    if #removal_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(removal_abilities, settings, derived_main_level, derived_sub_level, job_def)
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Check for self-only abilities first
    for _, ability in ipairs(available_abilities) do
        if ability.self_only then
            -- Check if this ability is blocked by status ailments
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
                common.debugf('[DEBUFF_REMOVAL] %s is blocked by %s', ability.name, blocked_by)
                goto continue_self
            end
            
            local player_buffs = state.player.buffs or {}
            if can_remove_debuffs(ability, player_buffs) then
                -- Check resource
                local ability_resource_type = ability.resource_type or job_def.resource_type
                if resource.has_resource(ability_resource_type, ability.cost) then
                    -- Check cooldown (if ability has an ID)
                    local is_ready = true
                    if ability.id then
                        is_ready = resource.is_spell_ready(ability.id)
                        common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                            ability.name, ability.id, tostring(is_ready))
                    end
                    
                    if is_ready then
                        local command = common.build_ability_command(ability, 0, settings)
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
        
        ::continue_self::
    end
    
    -- Build buff table from game_state snapshot
    local in_pl_mode = settings and settings.pl_mode_enabled and settings.pl_connected_player

    local all_buffs = {}
    for i = 0, 5 do
        local member = i == 0 and state.player or state.party[i]
        if member then
            if in_pl_mode and member.is_trust then
                all_buffs[i] = {}
            else
                all_buffs[i] = member.buffs or {}
            end
        else
            all_buffs[i] = {}
        end
    end
    
    -- Count removable debuffs for each party member
    local debuff_counts = {}
    for i = 0, 5 do
        debuff_counts[i] = count_removable_debuffs(all_buffs[i], available_abilities)
    end
    
    -- Priority 1: Check focus target first
    local focus_party_idx = nil
    if settings.focus_enabled and settings.focus_target then
        for i = 0, 5 do
            local m = i == 0 and state.player or state.party[i]
            if m and m.name == settings.focus_target then
                focus_party_idx = i
                break
            end
        end
    end

    if focus_party_idx ~= nil and debuff_counts[focus_party_idx] > 0 then
        local focus_member = focus_party_idx == 0 and state.player or state.party[focus_party_idx]
        local focus_target_index = focus_member and focus_member.target_index
        local in_range = focus_party_idx == 0 or (focus_target_index and focus_target_index > 0 and common.is_in_range(focus_target_index, 20))
            
        if in_range then
                -- Try to use an ability on focus target
                for _, ability in ipairs(available_abilities) do
                    if can_remove_debuffs(ability, all_buffs[focus_party_idx]) then
                    -- Check resource
                    local ability_resource_type = ability.resource_type or job_def.resource_type
                    if resource.has_resource(ability_resource_type, ability.cost) then
                        -- Check cooldown (if ability has an ID)
                        local is_ready = true
                        if ability.id then
                            is_ready = resource.is_spell_ready(ability.id)
                            common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                                ability.name, ability.id, tostring(is_ready))
                        end
                        
                        if is_ready then
                            local command = common.build_ability_command(ability, focus_party_idx, settings)
                            if command then
                                common.debugf('[DEBUFF_REMOVAL] Using %s on focus target (p%d, %d debuff%s)', 
                                    ability.name, focus_party_idx, debuff_counts[focus_party_idx],
                                    debuff_counts[focus_party_idx] == 1 and '' or 's')
                                return {
                                    command = command,
                                    description = string.format('Removing %d debuff(s) from focus with %s',
                                        debuff_counts[focus_party_idx], ability.name)
                                }
                            end
                        end
                    end
                end
            end
        else
            common.debugf('[DEBUFF_REMOVAL] Focus target (p%d) out of range, skipping', focus_party_idx)
        end
    end
    
    -- Priority 2: Find party member with most removable debuffs
    local best_index = nil
    local max_debuffs = 0
    
    for i = 0, 5 do
        -- Skip focus (already checked) and members with no debuffs
        if i ~= focus_party_idx and debuff_counts[i] > 0 then
            -- Check range (20 yalms for debuff removal spells)
            local party_member = i == 0 and state.player or state.party[i]
            local member_target_index = party_member and party_member.target_index
            local in_range = i == 0 or (member_target_index and member_target_index > 0 and common.is_in_range(member_target_index, 20))
            
            if in_range then
                -- Update if this member has more debuffs, or same amount but lower index
                if debuff_counts[i] > max_debuffs then
                    best_index = i
                    max_debuffs = debuff_counts[i]
                end
            end
        end
    end
    
    -- Use ability on the best target
    if best_index then
        for _, ability in ipairs(available_abilities) do
            if can_remove_debuffs(ability, all_buffs[best_index]) then
                -- Check resource
                local ability_resource_type = ability.resource_type or job_def.resource_type
                if resource.has_resource(ability_resource_type, ability.cost) then
                    -- Check cooldown (if ability has an ID)
                    local is_ready = true
                    if ability.id then
                        is_ready = resource.is_spell_ready(ability.id)
                        common.debugf('[DEBUFF_REMOVAL] %s recast check - ID: %d, Ready: %s', 
                            ability.name, ability.id, tostring(is_ready))
                    end
                    
                    if is_ready then
                        local command = common.build_ability_command(ability, best_index, settings)
                        if command then
                            common.debugf('[DEBUFF_REMOVAL] Using %s on p%d (%d debuff%s)', 
                                ability.name, best_index, max_debuffs,
                                max_debuffs == 1 and '' or 's')
                            local best_member = best_index == 0 and state.player or state.party[best_index]
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from %s with %s',
                                    max_debuffs,
                                    best_member and best_member.name or 'party member',
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

return debuff_removal
