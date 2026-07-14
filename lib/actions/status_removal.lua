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

-- Sort key for the priority loops: targeted na-spell (0) < generic Erase (1) <
-- self-centered AOE / Esuna (2). Erase is identified by table identity -- every
-- Erase/Maintenance/Reward shares the one common.ERASABLE_DEBUFFS table.
local function removal_rank(ability)
    if ability.self_only then return 2 end
    if not ability.debuff_id or ability.debuff_id == common.ERASABLE_DEBUFFS then return 1 end
    return 0
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

    -- Get party buff config for per-ability target filtering (same pattern as buffs)
    local ui_config = require('lib.ui.config')
    local party_buff_config = ui_config.get_party_buffs()

    -- Helper: check if an ability is allowed for a specific target
    -- When no config exists (UI never opened), all targets are allowed
    local function is_ability_target_allowed(ability, key)
        if not party_buff_config then return true end
        local ability_targets = party_buff_config[ability.name]
        if not ability_targets then return true end
        return ability_targets[key] == true
    end

    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level

    local removal_abilities = job_def.abilities.debuff_removal or {}
    if #removal_abilities == 0 then
        return nil
    end

    local available_abilities = common.filter_abilities_by_level(removal_abilities, settings, derived_main_level, derived_sub_level, job_def)
    -- Drop removers blocked by an active self-buff (DNC Saber Dance blocks Healing Waltz)
    available_abilities = action_core.filter_self_buff_blocked(available_abilities, player.buffs)
    if #available_abilities == 0 then
        return nil
    end

    -- Reach for the most specific remover first: a targeted na-spell strips the
    -- exact ailment, generic Erase strips a random erasable one, and the AOE
    -- (Esuna) sorts last -- it's fired deliberately by the AOE block below and
    -- only reached in the per-target loops as a last resort for an Esuna-only
    -- ailment nothing else covers.
    table.sort(available_abilities, function(x, y) return removal_rank(x) < removal_rank(y) end)

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

    -- Count removable debuffs for each party member (damage-immune trusts skipped)
    local debuff_counts = {}
    for i = 0, 5 do
        local member = i == 0 and state.player or state.party[i]
        if member and common.is_support_excluded(member.name) then
            debuff_counts[i] = 0
        else
            debuff_counts[i] = count_removable_debuffs(all_buffs[i], available_abilities)
        end
    end

    -- Also collect tracked target debuffs
    local tracked_buffs = {}   -- tracked_buffs[server_id] = {buff_ids}
    local tracked_debuff_counts = {}  -- tracked_debuff_counts[server_id] = count
    local outside_abilities = common.outside_abilities(available_abilities)
    if state.tracked and #outside_abilities > 0 then
        for sid, tt in pairs(state.tracked) do
            if tt.is_active and tt.target_index and tt.target_index > 0 and not common.is_support_excluded(tt.name) then
                tracked_buffs[sid] = tt.buffs or {}
                tracked_debuff_counts[sid] = count_removable_debuffs(tracked_buffs[sid], outside_abilities)
            end
        end
    end

    -- Also collect alliance member debuffs (same target_outside restriction)
    local alliance_buffs = {}         -- alliance_buffs[server_id] = {buff_ids}
    local alliance_debuff_counts = {} -- alliance_debuff_counts[server_id] = count
    local alliance_sid_to_key = {}    -- server_id -> al_key for target filtering
    if state.alliance and #outside_abilities > 0 then
        for al_pi = 2, 3 do
            if state.alliance[al_pi] then
                for local_idx, m in pairs(state.alliance[al_pi]) do
                    if m and m.is_active and m.target_index and m.target_index > 0 and not common.is_support_excluded(m.name) then
                        local flat_index = (al_pi - 1) * 6 + local_idx
                        alliance_sid_to_key[m.server_id] = 'al_' .. flat_index
                        alliance_buffs[m.server_id] = m.buffs or {}
                        alliance_debuff_counts[m.server_id] = count_removable_debuffs(alliance_buffs[m.server_id], outside_abilities)
                    end
                end
            end
        end
    end

    -- Priority 0: self-centered AOE ailment removal (Esuna). One cast strips the
    -- shared ailment off every self/party/alliance member inside its radius, so it
    -- beats a chain of single-target na-casts once 2+ members are affected. Pets
    -- and tracked (Trust) targets are NOT inside the AOE, so they neither count
    -- toward the threshold nor get their tracking dropped here.
    -- ponytail: threshold hardcoded 2; add a setting if someone wants to tune it.
    for _, ability in ipairs(available_abilities) do
        if ability.self_only and ability.debuff_id then
            local radius = ability.range or 10
            local affected_alliance = {}   -- packet-tracked sids -> drop one debuff on cast
            local count = 0

            if is_ability_target_allowed(ability, 0) and can_remove_debuffs(ability, all_buffs[0]) then
                count = count + 1
            end
            for i = 1, 5 do
                local pm = state.party[i]
                if pm and pm.target_index and pm.target_index > 0
                   and is_ability_target_allowed(ability, i)
                   and can_remove_debuffs(ability, all_buffs[i])
                   and common.is_in_range(pm.target_index, radius) then
                    count = count + 1
                end
            end
            for sid, buffs in pairs(alliance_buffs) do
                local al = common.find_alliance_member(state, sid)
                if al and al.target_index and al.target_index > 0
                   and is_ability_target_allowed(ability, alliance_sid_to_key[sid] or '')
                   and can_remove_debuffs(ability, buffs)
                   and common.is_in_range(al.target_index, radius) then
                    count = count + 1
                    table.insert(affected_alliance, sid)
                end
            end

            if count >= 2 then
                local desc = string.format('Removing debuffs from %d members with %s', count, ability.name)
                local result = action_core.try_use(ability, job_def, settings, 0, desc)
                if result then
                    for _, sid in ipairs(affected_alliance) do
                        common.drop_removed_debuff(sid, ability)
                    end
                    return result
                end
            end
        end
    end

    -- Priority 1: Check focus target first (party or tracked or alliance)
    local focus_kind, focus_ref = common.resolve_focus_target(settings, state)
    local focus_party_idx    = focus_kind == 'party'    and focus_ref or nil
    local focus_tracked_sid  = focus_kind == 'tracked'  and focus_ref or nil
    local focus_alliance_sid = focus_kind == 'alliance' and focus_ref or nil

    -- Focus: party member
    if focus_party_idx ~= nil and debuff_counts[focus_party_idx] > 0 then
        local focus_member = focus_party_idx == 0 and state.player or state.party[focus_party_idx]
        local focus_target_index = focus_member and focus_member.target_index
        local in_range = focus_party_idx == 0 or (focus_target_index and focus_target_index > 0 and common.is_in_range(focus_target_index, 20))

        if in_range then
            for _, ability in ipairs(available_abilities) do
                if is_ability_target_allowed(ability, focus_party_idx) and can_remove_debuffs(ability, all_buffs[focus_party_idx]) then
                    local dc = debuff_counts[focus_party_idx]
                    local desc = string.format('Removing %d debuff(s) from focus with %s', dc, ability.name)
                    local result, reason = action_core.try_use(ability, job_def, settings, focus_party_idx, desc)
                    if result then
                        common.drop_removed_debuff(focus_member.server_id, ability)
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
                if is_ability_target_allowed(ability, 'tt_' .. focus_tracked_sid) and can_remove_debuffs(ability, tracked_buffs[focus_tracked_sid]) then
                    local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                    local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                    if ok then
                        local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                        if strat_result == false then ok = false
                        elseif strat_result then return strat_result end
                    end
                    if ok then
                        local command = common.build_ability_command_for_target(ability, focus_tracked_sid)
                        if command then
                            if ability.buff_id then
                                local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                common.register_pending_buff(focus_tracked_sid, bid)
                            end
                            common.drop_removed_debuff(focus_tracked_sid, ability)
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

    -- Focus: alliance member
    if focus_alliance_sid and alliance_debuff_counts[focus_alliance_sid] and alliance_debuff_counts[focus_alliance_sid] > 0 then
        local al_member = common.find_alliance_member(state, focus_alliance_sid)
        if al_member and al_member.target_index and al_member.target_index > 0 and common.is_in_range(al_member.target_index, 20) then
            for _, ability in ipairs(outside_abilities) do
                if is_ability_target_allowed(ability, alliance_sid_to_key[focus_alliance_sid] or '') and can_remove_debuffs(ability, alliance_buffs[focus_alliance_sid]) then
                    local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                    local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                    if ok then
                        local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                        if strat_result == false then ok = false
                        elseif strat_result then return strat_result end
                    end
                    if ok then
                        local command = common.build_ability_command_for_target(ability, focus_alliance_sid)
                        if command then
                            if ability.buff_id then
                                local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                common.register_pending_buff(focus_alliance_sid, bid)
                            end
                            common.drop_removed_debuff(focus_alliance_sid, ability)
                            local dc = alliance_debuff_counts[focus_alliance_sid]
                            return {
                                command = command,
                                description = string.format('Removing %d debuff(s) from alliance %s with %s', dc, al_member.name, ability.name)
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
            if is_ability_target_allowed(ability, best_index) and can_remove_debuffs(ability, all_buffs[best_index]) then
                local best_member = best_index == 0 and state.player or state.party[best_index]
                local desc = string.format('Removing %d debuff(s) from %s with %s',
                    max_debuffs, best_member and best_member.name or 'party member', ability.name)
                local result, reason = action_core.try_use(ability, job_def, settings, best_index, desc)
                if result then
                    common.drop_removed_debuff(best_member.server_id, ability)
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
                if is_ability_target_allowed(ability, 'tt_' .. best_tracked_sid) and can_remove_debuffs(ability, tracked_buffs[best_tracked_sid]) then
                    local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                    local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                    if ok then
                        local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                        if strat_result == false then ok = false
                        elseif strat_result then return strat_result end
                    end
                    if ok then
                        local command = common.build_ability_command_for_target(ability, best_tracked_sid)
                        if command then
                            if ability.buff_id then
                                local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                common.register_pending_buff(best_tracked_sid, bid)
                            end
                            common.drop_removed_debuff(best_tracked_sid, ability)
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

        -- Priority 4: Find alliance member with most removable debuffs
        local best_alliance_sid = nil
        local max_alliance_debuffs = 0

        for sid, dc in pairs(alliance_debuff_counts) do
            if sid ~= focus_alliance_sid and dc > 0 then
                local al_member = common.find_alliance_member(state, sid)
                if al_member and al_member.target_index and al_member.target_index > 0 and common.is_in_range(al_member.target_index, 20) then
                    if dc > max_alliance_debuffs then
                        best_alliance_sid = sid
                        max_alliance_debuffs = dc
                    end
                end
            end
        end

        if best_alliance_sid then
            local al_member = common.find_alliance_member(state, best_alliance_sid)
            if al_member then
                for _, ability in ipairs(outside_abilities) do
                    if is_ability_target_allowed(ability, alliance_sid_to_key[best_alliance_sid] or '') and can_remove_debuffs(ability, alliance_buffs[best_alliance_sid]) then
                        local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                        local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                        if ok then
                            local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                            if strat_result == false then ok = false
                            elseif strat_result then return strat_result end
                        end
                        if ok then
                            local command = common.build_ability_command_for_target(ability, best_alliance_sid)
                            if command then
                                if ability.buff_id then
                                    local bid = type(ability.buff_id) == 'table' and ability.buff_id[1] or ability.buff_id
                                    common.register_pending_buff(best_alliance_sid, bid)
                                end
                                common.drop_removed_debuff(best_alliance_sid, ability)
                                return {
                                    command = command,
                                    description = string.format('Removing %d debuff(s) from alliance %s with %s',
                                        max_alliance_debuffs, al_member.name, ability.name)
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- Pet Debuff Removal
-- ============================================================================
-- BST/PUP strip status effects off their pet (Reward + Pet Roborant, Maintenance
-- + Oil). The pet has no buff memory, so its statuses come from packet tracking
-- in `state.pet_debuffs` (populated by refresh_game_state) -- inferred and, like
-- Trust tracking, not perfectly reliable.
function status_removal.execute_pet_debuff_removal(settings, job_def, main_level, sub_level, player_resource)
    if not settings.pet_debuff_removal_enabled then return nil end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end
    if not common.targets.get_pet() then return nil end

    local abilities = job_def.abilities.pet_debuff_removal or {}
    if #abilities == 0 then return nil end

    -- Pet's packet-tracked statuses (buffs + debuffs; the loop filters by debuff_id).
    local pet_debuffs = state.pet_debuffs or {}

    -- Auto-equip the consumable only when the pet has a debuff this ability could
    -- strip, so the roborant/oil never fights the heal/Regen ammo for the slot
    -- while there's nothing to cure.
    for _, ability in ipairs(abilities) do
        if ability.requires_equipped_ammo
           and not common.is_ammo_equipped(ability.requires_equipped_ammo)
           and can_remove_debuffs(ability, pet_debuffs) then
            local equip = common.ammo_equip_command({ ability }, settings, player)
            if equip then return equip end
        end
    end

    local available = common.filter_abilities_by_level(abilities, settings, player.main_level, player.sub_level, job_def)
    for _, ability in ipairs(available) do
        if not common.is_command_blocked(ability.command)
           and can_remove_debuffs(ability, pet_debuffs) then
            local count = count_removable_debuffs(pet_debuffs, { ability })
            local desc  = string.format('Removing %d debuff(s) from pet with %s', count, ability.name)
            local result = action_core.try_use(ability, job_def, settings, 0, desc)
            if result then
                -- Drop one erasable status from tracking so a multi-debuff pet
                -- doesn't re-fire on the same one; more casts strip the rest.
                local pet = common.get_pet_entity()
                local sid = pet and (pet.ServerId or 0) or 0
                if sid ~= 0 then common.drop_removed_debuff(sid, ability) end
                return result
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

    -- Get party buff config for target filtering
    local ui_config = require('lib.ui.config')
    local party_buff_config = ui_config.get_party_buffs()
    local wake_targets = party_buff_config and party_buff_config['wake']

    -- Helper: check if a target is enabled for sleep removal
    -- When no config exists (UI never opened), all targets are allowed
    local function is_wake_allowed(key)
        if not wake_targets then return true end
        return wake_targets[key] == true
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

    -- Count sleeping party members (indices 1-5 only, filtered by wake targets)
    local sleeping_members = {}
    for i = 1, 5 do
        if not is_wake_allowed(i) then goto continue_wake end
        local member_state = state.party[i]
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
            if tt.is_active and tt.target_index and tt.target_index > 0 and is_wake_allowed('tt_' .. sid) then
                local buffs = tt.buffs or {}
                if status_removal.is_buff_sleep(buffs) then
                    table.insert(sleeping_tracked, sid)
                end
            end
        end
    end

    -- Also check alliance members for sleep
    local sleeping_alliance = {}  -- {server_id, ...}
    if state.alliance then
        for al_pi = 2, 3 do
            if state.alliance[al_pi] then
                for local_idx, m in pairs(state.alliance[al_pi]) do
                    if m and m.is_active and m.target_index and m.target_index > 0 then
                        local flat_index = (al_pi - 1) * 6 + local_idx
                        local al_key = 'al_' .. flat_index
                        if is_wake_allowed(al_key) then
                            local buffs = m.buffs or {}
                            if status_removal.is_buff_sleep(buffs) then
                                table.insert(sleeping_alliance, m.server_id)
                            end
                        end
                    end
                end
            end
        end
    end

    if #sleeping_members == 0 and #sleeping_tracked == 0 and #sleeping_alliance == 0 then
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
    if #sleeping_members > 0 and #available_single > 0 then
        local target_index = sleeping_members[1]

        -- Check if focus target is sleeping (if focus is enabled)
        if settings.focus_enabled and settings.focus_target then
            local focus_party_index = common.get_party_index_by_name(settings.focus_target)
            if focus_party_index then
                for _, idx in ipairs(sleeping_members) do
                    if idx == focus_party_index then
                        target_index = focus_party_index
                        break
                    end
                end
            end
        end

        local target_member = target_index == 0 and state.player or state.party[target_index]
        local target_name = (target_member and target_member.name) or 'party member'

        for _, ability in ipairs(available_single) do
            local blocked_by = common.is_command_blocked(ability.command)
            if not blocked_by then
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
                            local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                            local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                            if ok then
                                local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                                if strat_result == false then ok = false
                                elseif strat_result then return strat_result end
                            end
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

    -- Wake sleeping alliance members (only target_outside abilities)
    if #sleeping_alliance > 0 and #available_single > 0 then
        for _, sid in ipairs(sleeping_alliance) do
            local al_member = common.find_alliance_member(state, sid)
            if al_member and al_member.target_index and al_member.target_index > 0 and common.is_in_range(al_member.target_index, 20) then
                for _, ability in ipairs(available_single) do
                    if ability.target_outside and ability.wakes then
                        local blocked_by = common.is_command_blocked(ability.command)
                        if not blocked_by then
                            local eff_cost = common.effective_ability_cost(ability, settings, job_def)
                            local ok, reason = action_core.is_usable(ability, job_def, eff_cost)
                            if ok then
                                local strat_result = common.check_stratagem(job_def, settings, ability.name, ability)
                                if strat_result == false then ok = false
                                elseif strat_result then return strat_result end
                            end
                            if ok then
                                local command = common.build_ability_command_for_target(ability, sid)
                                if command then
                                    return {
                                        command = command,
                                        description = string.format('Waking alliance %s with %s', al_member.name, ability.name)
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
