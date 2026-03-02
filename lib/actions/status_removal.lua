--[[
    Status removal action module
    Combines debuff removal (erase/cleanse) and wake-from-sleep into a single
    module, since both follow the same pattern: scan party for negative statuses,
    prioritize focus target, and use an appropriate removal ability.
]]--

local status_removal = {}

local common      = require('lib.core.common')
local action_core = require('lib.core.action_core')

-- ============================================================================
-- Debuff Removal Helpers
-- ============================================================================

-- Check if an ability can remove any of the detected debuffs.
local function can_remove_debuffs(ability, debuffs)
    if not ability.debuff_id then return #debuffs > 0 end
    return action_core.has_any_buff(debuffs, ability.debuff_id)
end

-- Count removable debuffs in a list of buffs.
local function count_removable_debuffs(buffs, abilities)
    local count = 0
    for _, buff_id in ipairs(buffs) do
        for _, ability in ipairs(abilities) do
            if not ability.debuff_id or action_core.has_any_buff({buff_id}, ability.debuff_id) then
                count = count + 1
                break
            end
        end
    end
    return count
end

-- ============================================================================
-- Debuff Removal  (formerly lib.actions.debuff_removal)
-- ============================================================================

function status_removal.execute_debuff_removal(settings, job_def, main_level, sub_level, player_resource)
    if not settings.debuff_removal_enabled then
        return nil
    end

    local state  = common.game_state
    local player = state and state.player
    if not player then
        return nil
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    local removal_abilities = job_def.abilities.debuff_removal or {}
    if #removal_abilities == 0 then
        return nil
    end

    local available_abilities = common.filter_abilities_by_level(removal_abilities, settings, derived_main_level, derived_sub_level, job_def)
    if #available_abilities == 0 then
        return nil
    end

    -- Check for self-only abilities first
    for _, ability in ipairs(available_abilities) do
        if ability.self_only then
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
                goto continue_self
            end

            local player_buffs = state.player.buffs or {}
            if can_remove_debuffs(ability, player_buffs) then
                local debuff_count = count_removable_debuffs(player_buffs, {ability})
                local desc = string.format('Removing %d debuff(s) from self with %s', debuff_count, ability.name)
                local result, reason = action_core.try_use(ability, job_def, settings, 0, desc)
                if result then
                    return result
                end
            end
        end

        ::continue_self::
    end

    -- Build buff table from game_state snapshot
    local all_buffs = {}
    for i = 0, 5 do
        local member = i == 0 and state.player or state.party[i]
        if member then
            all_buffs[i] = member.buffs or {}
        else
            all_buffs[i] = {}
        end
    end

    -- Count removable debuffs for each party member
    local debuff_counts = {}
    for i = 0, 5 do
        debuff_counts[i] = count_removable_debuffs(all_buffs[i], available_abilities)
    end

    -- Also collect tracked target debuffs
    local tracked_buffs = {}   -- tracked_buffs[server_id] = {buff_ids}
    local tracked_debuff_counts = {}  -- tracked_debuff_counts[server_id] = count
    -- Filter to target_outside abilities for tracked targets
    local outside_abilities = {}
    for _, a in ipairs(available_abilities) do
        if a.target_outside then table.insert(outside_abilities, a) end
    end
    if state.tracked and #outside_abilities > 0 then
        for sid, tt in pairs(state.tracked) do
            if tt.is_active and tt.target_index and tt.target_index > 0 then
                tracked_buffs[sid] = tt.buffs or {}
                tracked_debuff_counts[sid] = count_removable_debuffs(tracked_buffs[sid], outside_abilities)
            end
        end
    end

    -- Priority 1: Check focus target first (party or tracked)
    local focus_party_idx = nil
    local focus_tracked_sid = nil
    if settings.focus_enabled and settings.focus_target then
        for i = 0, 5 do
            local m = i == 0 and state.player or state.party[i]
            if m and m.name == settings.focus_target then
                focus_party_idx = i
                break
            end
        end
        if not focus_party_idx and state.tracked then
            for sid, tt in pairs(state.tracked) do
                if tt.name == settings.focus_target and tt.is_active then
                    focus_tracked_sid = sid
                    break
                end
            end
        end
    end

    -- Focus: party member
    if focus_party_idx ~= nil and debuff_counts[focus_party_idx] > 0 then
        local focus_member = focus_party_idx == 0 and state.player or state.party[focus_party_idx]
        local focus_target_index = focus_member and focus_member.target_index
        local in_range = focus_party_idx == 0 or (focus_target_index and focus_target_index > 0 and common.is_in_range(focus_target_index, 20))

        if in_range then
            for _, ability in ipairs(available_abilities) do
                if can_remove_debuffs(ability, all_buffs[focus_party_idx]) then
                    local dc = debuff_counts[focus_party_idx]
                    local desc = string.format('Removing %d debuff(s) from focus with %s', dc, ability.name)
                    local result, reason = action_core.try_use(ability, job_def, settings, focus_party_idx, desc)
                    if result then
                        return result
                    end
                end
            end
        end
    end

    -- Focus: tracked target
    if focus_tracked_sid and tracked_debuff_counts[focus_tracked_sid] and tracked_debuff_counts[focus_tracked_sid] > 0 then
        local tt = state.tracked[focus_tracked_sid]
        if tt and tt.target_index and tt.target_index > 0 and common.is_in_range(tt.target_index, 20) then
            for _, ability in ipairs(outside_abilities) do
                if can_remove_debuffs(ability, tracked_buffs[focus_tracked_sid]) then
                    local ok, reason = action_core.is_usable(ability, job_def)
                    if ok then
                        local command = common.build_ability_command_for_target(ability, focus_tracked_sid)
                        if command then
                            if ability.buff_id then
                                local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                common.register_pending_buff(focus_tracked_sid, bid)
                            end
                            local dc = tracked_debuff_counts[focus_tracked_sid]
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from tracked %s with %s', dc, tt.name, ability.name)
                            }
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
        if i ~= focus_party_idx and debuff_counts[i] > 0 then
            local party_member = i == 0 and state.player or state.party[i]
            local member_target_index = party_member and party_member.target_index
            local in_range = i == 0 or (member_target_index and member_target_index > 0 and common.is_in_range(member_target_index, 20))

            if in_range then
                if debuff_counts[i] > max_debuffs then
                    best_index = i
                    max_debuffs = debuff_counts[i]
                end
            end
        end
    end

    if best_index then
        for _, ability in ipairs(available_abilities) do
            if can_remove_debuffs(ability, all_buffs[best_index]) then
                local best_member = best_index == 0 and state.player or state.party[best_index]
                local desc = string.format('Removing %d debuff(s) from %s with %s',
                    max_debuffs, best_member and best_member.name or 'party member', ability.name)
                local result, reason = action_core.try_use(ability, job_def, settings, best_index, desc)
                if result then
                    return result
                end
            end
        end
    end

    -- Priority 3: Find tracked target with most removable debuffs
    if #outside_abilities > 0 then
        local best_tracked_sid = nil
        local max_tracked_debuffs = 0

        for sid, dc in pairs(tracked_debuff_counts) do
            if sid ~= focus_tracked_sid and dc > 0 then
                local tt = state.tracked[sid]
                if tt and tt.target_index and tt.target_index > 0 and common.is_in_range(tt.target_index, 20) then
                    if dc > max_tracked_debuffs then
                        best_tracked_sid = sid
                        max_tracked_debuffs = dc
                    end
                end
            end
        end

        if best_tracked_sid then
            local tt = state.tracked[best_tracked_sid]
            for _, ability in ipairs(outside_abilities) do
                if can_remove_debuffs(ability, tracked_buffs[best_tracked_sid]) then
                    local ok, reason = action_core.is_usable(ability, job_def)
                    if ok then
                        local command = common.build_ability_command_for_target(ability, best_tracked_sid)
                        if command then
                            if ability.buff_id then
                                local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                common.register_pending_buff(best_tracked_sid, bid)
                            end
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from tracked %s with %s',
                                    max_tracked_debuffs, tt.name, ability.name)
                            }
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- Wake from Sleep  (formerly lib.actions.wake)
-- ============================================================================

local SLEEP_BUFF_ID    = 2   -- Sleep
local SLEEP_II_BUFF_ID = 19  -- Sleep II

-- Check if a buff list contains sleep.
function status_removal.is_buff_sleep(buffs)
    local list = type(buffs) == 'table' and buffs or {buffs}
    return action_core.has_any_buff(list, {SLEEP_BUFF_ID, SLEEP_II_BUFF_ID})
end

function status_removal.execute_wake(settings, job_def, main_level, sub_level, player_resource)
    if not settings.wake_enabled then
        return nil
    end

    local state  = common.game_state
    local player = state and state.player
    if not player then
        return nil
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

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

    -- Count sleeping party members (indices 1-5 only)
    local start_index = 1

    local sleeping_members = {}
    for i = start_index, 5 do
        local member_state = i == 0 and state.player or state.party[i]
        if not member_state then goto continue_wake end
        local buffs = member_state.buffs or {}
        if status_removal.is_buff_sleep(buffs) then
            table.insert(sleeping_members, i)
        end

        ::continue_wake::
    end

    -- Also check tracked targets for sleep
    local sleeping_tracked = {}  -- {server_id, ...}
    if state.tracked then
        for sid, tt in pairs(state.tracked) do
            if tt.is_active and tt.target_index and tt.target_index > 0 then
                local buffs = tt.buffs or {}
                if status_removal.is_buff_sleep(buffs) then
                    table.insert(sleeping_tracked, sid)
                end
            end
        end
    end

    if #sleeping_members == 0 and #sleeping_tracked == 0 then
        return nil
    end

    -- Filter abilities by level and settings
    local available_single = common.filter_abilities_by_level(wake_abilities.single, settings, derived_main_level, derived_sub_level, job_def)
    local available_aoe = common.filter_abilities_by_level(wake_abilities.aoe, settings, derived_main_level, derived_sub_level, job_def)

    table.sort(available_single, function(a, b) return (a.cost or 0) < (b.cost or 0) end)
    table.sort(available_aoe, function(a, b) return (a.cost or 0) < (b.cost or 0) end)

    -- If 2+ members are sleeping, use AOE
    if #sleeping_members >= 2 and #available_aoe > 0 then
        for _, ability in ipairs(available_aoe) do
            local desc = string.format('Waking %d sleeping members with %s', #sleeping_members, ability.name)
            local result, reason = action_core.try_use(ability, job_def, settings, 0, desc)
            if result then
                return result
            end
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
                        break
                    end
                end
            end
        end

        local target_member = target_index == 0 and state.player or state.party[target_index]
        local target_name = (target_member and target_member.name) or 'party member'

        for _, ability in ipairs(available_single) do
            local blocked_by = common.is_command_blocked(ability.command)
            if blocked_by then
            else
                local desc = string.format('Waking %s with %s', target_name, ability.name)
                local result, reason = action_core.try_use(ability, job_def, settings, target_index, desc)
                if result then
                    return result
                end
            end
        end
    end

    -- Wake sleeping tracked targets (only target_outside abilities)
    if #sleeping_tracked > 0 and #available_single > 0 then
        for _, sid in ipairs(sleeping_tracked) do
            local tt = state.tracked[sid]
            if tt and tt.target_index and tt.target_index > 0 and common.is_in_range(tt.target_index, 20) then
                for _, ability in ipairs(available_single) do
                    if ability.target_outside and ability.wakes then
                        local blocked_by = common.is_command_blocked(ability.command)
                        if not blocked_by then
                            local ok, reason = action_core.is_usable(ability, job_def)
                            if ok then
                                local command = common.build_ability_command_for_target(ability, sid)
                                if command then
                                    return {
                                        command = command,
                                        description = string.format('Waking tracked %s with %s', tt.name, ability.name)
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

return status_removal
