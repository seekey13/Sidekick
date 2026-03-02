--[[
    Single-target healing action module
    Handles priority-based healing for individual party members
]]--

local heal = {}

local common      = require('lib.core.common')
local resource    = require('lib.core.resource')
local action_core = require('lib.core.action_core')

function heal.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Debug focus configuration (show even when heal is disabled)
    if settings.focus_enabled then
        common.debugf('[HEAL] Focus enabled: target=%s, threshold=%.1f%%',
                     settings.focus_target or 'None',
                     settings.focus_threshold or 85)
    end
    
    -- Check if healing is enabled
    if not settings.heal_enabled then
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

    -- Get heal abilities from job definition
    local heal_abilities = job_def.abilities.heal or {}
    
    if #heal_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level using DRY helper
    common.debugf('[HEAL] Evaluating %d heal abilities', #heal_abilities)
    local available_abilities = common.filter_abilities_by_level(
        heal_abilities,
        settings,
        derived_main_level,
        derived_sub_level,
        job_def
    )
    
    if #available_abilities == 0 then
        common.debugf('[HEAL] No heal abilities available for this level/configuration')
        return nil
    end
    
    common.debugf('[HEAL] %d abilities available after filtering, sorted by cost', #available_abilities)
    
    -- Check if all abilities are self-only
    local all_self_only = true
    for _, ability in ipairs(available_abilities) do
        if not ability.self_only then
            all_self_only = false
            break
        end
    end
    
    -- If all abilities are self-only, only check player HP
    if all_self_only then
        common.debugf('[HEAL] All abilities are self-only, checking player HP only')
        
        local player_hpp = state.player.hpp
        common.debugf('[HEAL] Player HP: %.1f%%', player_hpp)
        
        if common.below_threshold(player_hpp, settings.heal_threshold or 75) then
            -- Select appropriate ability
            local selected_ability = heal.select_ability(available_abilities, player_hpp, job_def, player_resource, 0)
            if selected_ability then
                local command = common.build_ability_command(selected_ability, 0, settings)
                
                if command then
                    common.debugf('[HEAL] >>> Using self-only heal %s', selected_ability.name)
                    return {
                        command = command,
                        description = string.format('Self-healing with %s (HP: %.1f%%)', selected_ability.name, player_hpp)
                    }
                end
            else
                common.debugf('[HEAL] No self-only ability available (resource/cooldown)')
            end
        end
        return nil
    end
    
    -- Build party_status from game_state snapshot
    local threshold       = settings.heal_threshold or 75
    local focus_enabled   = settings.focus_enabled
    local focus_threshold = settings.focus_threshold or 85
    local in_pl_mode      = settings.pl_mode_enabled and settings.pl_connected_player

    -- Resolve focus target party index from game_state
    local focus_party_idx = nil
    if focus_enabled and settings.focus_target then
        for i = 0, 5 do
            local m = i == 0 and state.player or state.party[i]
            if m and m.name == settings.focus_target then
                focus_party_idx = i
                break
            end
        end
    end

    local party_status = {
        needs_heal        = {},
        focus_needs_heal  = false,
        lowest_hp_index   = nil,
        lowest_hp_percent = 100,
        average_hp        = 100,
    }
    local total_hp     = 0
    local active_count = 0
    for i = 0, 5 do
        local m = i == 0 and state.player or state.party[i]
        if not m then goto continue_hp_check end
        if in_pl_mode and common.is_trust(i) then goto continue_hp_check end
        local hpp        = m.hpp or 0
        local target_idx = m.target_index or 0
        if not common.is_active_member(hpp) then goto continue_hp_check end
        total_hp     = total_hp     + hpp
        active_count = active_count + 1
        local is_focus      = focus_enabled and focus_party_idx ~= nil and i == focus_party_idx
        local eff_threshold = is_focus and focus_threshold or threshold
        common.debugf('[HEAL] Party[%d] %s: HP=%.1f%%, target_index=%s, is_focus=%s, effective_threshold=%.1f%%',
                     i, m.name or 'Unknown', hpp, tostring(target_idx), tostring(is_focus), eff_threshold)
        if hpp < eff_threshold and target_idx > 0 then
            common.debugf('[HEAL]   -> Needs heal (%.1f%% < %.1f%%)', hpp, eff_threshold)
            table.insert(party_status.needs_heal, { index = i, target_index = target_idx, hpp = hpp })
            if hpp < party_status.lowest_hp_percent then
                party_status.lowest_hp_percent = hpp
                party_status.lowest_hp_index   = i
            end
            if is_focus then
                common.debugf('[HEAL]   -> Focus target needs heal!')
                party_status.focus_needs_heal = true
            end
        end
        ::continue_hp_check::
    end
    if active_count > 0 then
        party_status.average_hp = total_hp / active_count
    end
    
    -- Debug focus status after party check
    if settings.focus_enabled then
        common.debugf('[HEAL] Focus needs_heal=%s', tostring(party_status.focus_needs_heal))
    end
    
    -- Priority 1: Critical HP (if anyone is below critical threshold)
    local critical_threshold = settings.critical_threshold or 30
    local critical_abilities = job_def.abilities.critical or {}
    
    if #critical_abilities > 0 then
        -- Filter critical abilities by level
        local available_critical = common.filter_abilities_by_level(
            critical_abilities,
            settings,
            derived_main_level,
            derived_sub_level,
            job_def
        )
        
        if #available_critical > 0 then
            -- Find lowest HP party member (ignoring focus)
            local critical_party_index = nil
            local critical_hpp = 100
            
            for i = 0, 5 do
                local m = i == 0 and state.player or state.party[i]
                if m then
                    local hpp = m.hpp or 0
                    if common.below_threshold(hpp, critical_threshold) and hpp < critical_hpp then
                        critical_hpp = hpp
                        critical_party_index = i
                    end
                end
            end
            
            if critical_party_index then
                common.debugf('[HEAL] Critical HP detected: party[%d] at %.1f%% (threshold: %.1f%%)',
                             critical_party_index, critical_hpp, critical_threshold)
                
                -- Try to use a critical ability
                for _, ability in ipairs(available_critical) do
                    if settings['disabled_' .. ability.name:gsub(' ', '_')] == true then
                        common.debugf('[HEAL] Critical ability %s is disabled', ability.name)
                    else
                        local ok, reason = action_core.is_usable(ability, job_def)
                        if not ok then
                            common.debugf('[HEAL] Critical ability %s: %s', ability.name, reason)
                        else
                            -- Determine target: self-target (Divine Seal) vs party-target (Martyr)
                            local cmd_test         = common.build_ability_command(ability, 0, settings)
                            local target_party_index
                            local in_range         = true
                            if cmd_test and cmd_test:find('<me>') then
                                target_party_index = 0
                            else
                                target_party_index   = critical_party_index
                                local cm             = critical_party_index == 0 and state.player or state.party[critical_party_index]
                                local target_index   = cm and cm.target_index
                                if not target_index or target_index == 0 then
                                    in_range = false
                                    common.debugf('[HEAL] Could not get target index for critical party member')
                                else
                                    local rng = type(ability.range) == 'number' and ability.range or 21
                                    in_range  = common.is_in_range(target_index, rng)
                                    if not in_range then
                                        common.debugf('[HEAL] Critical target out of range (range: %d)', rng)
                                    end
                                end
                            end
                            if in_range then
                                local command = common.build_ability_command(ability, target_party_index, settings)
                                if command then
                                    common.debugf('[HEAL] >>> Using critical ability %s', ability.name)
                                    local cm = critical_party_index == 0 and state.player or state.party[critical_party_index]
                                    return { command = command,
                                        description = string.format('Critical: %s for %s (HP: %.1f%%)',
                                            ability.name,
                                            target_party_index == 0 and 'self' or (cm and cm.name or 'party member'),
                                            critical_hpp) }
                                end
                            end
                        end
                    end
                end
                
                common.debugf('[HEAL] No critical abilities available (all disabled/on cooldown/out of range)')
            end
        end
    end
    
    -- Priority 2: Focus target
    if settings.focus_enabled and settings.focus_target and party_status.focus_needs_heal then
        local focus_member = focus_party_idx and (focus_party_idx == 0 and state.player or state.party[focus_party_idx])
        local focus_target_index = focus_member and focus_member.target_index
        if focus_target_index and focus_target_index > 0 then
            common.debugf('[HEAL] Attempting focus target heal: %s', settings.focus_target)
            local focus_hpp = nil
            for _, member in ipairs(party_status.needs_heal) do
                if member.target_index == focus_target_index then
                    focus_hpp = member.hpp
                    common.debugf('[HEAL] Found focus target in needs_heal list: HP=%.1f%%', focus_hpp)
                    break
                end
            end
            
            if focus_hpp then
                -- Get party index for focus target (already resolved from game_state above)
                local focus_party_index = focus_party_idx
                if not focus_party_index then
                    common.debugf('[HEAL] Could not get party index for focus target')
                    return nil
                end
                
                -- Select appropriate ability based on HP deficit
                local selected_ability = heal.select_ability(available_abilities, focus_hpp, job_def, player_resource, focus_party_index)
                
                if selected_ability and focus_party_index then
                    -- Check if in range using ability's range (default to 21 if not specified)
                    local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                    if not common.is_in_range(focus_target_index, ability_range) then
                        common.debugf('[HEAL] Focus target out of range (range: %d)', ability_range)
                        return nil
                    end
                    common.debugf('[HEAL] Focus target in range (range: %d)', ability_range)
                    common.debugf('[HEAL] Selected %s for focus target', selected_ability.name)
                    
                    local command = common.build_ability_command(selected_ability, focus_party_index, settings)
                    if command then
                        common.debugf('[HEAL] >>> Healing focus target with %s', selected_ability.name)
                        return {
                            command = command,
                            description = string.format('Healing focus target with %s (HP: %.1f%%)', selected_ability.name, focus_hpp)
                        }
                    else
                        common.debugf('[HEAL] Failed to build command for focus target')
                    end
                elseif not focus_party_index then
                    common.debugf('[HEAL] Could not find focus party index')
                else
                    common.debugf('[HEAL] No ability selected for focus target (resource/cooldown)')
                end
            else
                common.debugf('[HEAL] Focus target not found in needs_heal list')
            end
        end
    end
    
    -- Priority 3: Lowest HP party member
    if party_status.lowest_hp_index then
        common.debugf('[HEAL] Lowest HP healing path triggered (party index: %d, HP: %.1f%%)',
                     party_status.lowest_hp_index, party_status.lowest_hp_percent)
        local lowest_hp_member = party_status.lowest_hp_index == 0 and state.player or state.party[party_status.lowest_hp_index]
        local target_index = lowest_hp_member and lowest_hp_member.target_index
        if target_index and target_index > 0 then
            -- Select appropriate ability based on HP deficit
            local selected_ability = heal.select_ability(available_abilities, party_status.lowest_hp_percent, job_def, player_resource, party_status.lowest_hp_index)
            if selected_ability then
                -- Check if in range using ability's range (default to 21 if not specified)
                local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                if not common.is_in_range(target_index, ability_range) then
                    common.debugf('[HEAL] Target out of range (range: %d)', ability_range)
                    return nil
                end
                local command = common.build_ability_command(selected_ability, party_status.lowest_hp_index, settings)
                if command then
                    return {
                        command = command,
                        description = string.format('Healing %s with %s (HP: %.1f%%)', 
                            (lowest_hp_member and lowest_hp_member.name or 'party member'),
                            selected_ability.name,
                            party_status.lowest_hp_percent)
                    }
                else
                    common.debugf('[HEAL] Failed to build command')
                end
            else
                common.debugf('[HEAL] No ability selected for lowest HP member')
            end
        else
            common.debugf('[HEAL] Could not get target index for lowest HP member')
        end
    else
        common.debugf('[HEAL] No party members need healing')
    end
    return nil
end

function heal.select_ability(abilities, target_hpp, job_def, player_resource, party_index)
    -- Special case: Summoner should always try Healing Ruby first
    if job_def and job_def.job_id == 15 then
        -- Look for Healing Ruby in abilities
        for _, ability in ipairs(abilities) do
            if ability.name == 'Healing Ruby' then
                -- Check if usable: has pet, has resource, not on cooldown
                if common.targets.get_pet() then
                    local ability_resource_type = ability.resource_type or job_def.resource_type
                    if resource.has_resource(ability_resource_type, ability.cost) then
                        local is_ready = true
                        if ability.id then
                            is_ready = resource.is_ability_ready(ability.id)
                        end
                        if is_ready then
                            common.debugf('[HEAL] Using Healing Ruby (has pet, resources available)')
                            return ability
                        else
                            common.debugf('[HEAL] ⚠ Summoner: Healing Ruby on cooldown, using fallback')
                        end
                    else
                        common.debugf('[HEAL] ⚠ Summoner: Insufficient MP for Healing Ruby, using fallback')
                    end
                else
                    common.debugf('[HEAL] ⚠ Summoner: No pet available for Healing Ruby, using fallback')
                end
                break
            end
        end
    end
    
    -- Calculate HP deficit for target
    local hp_deficit = 0
    if party_index then
        local snapshot     = common.game_state
        local target_member = snapshot and (party_index == 0 and snapshot.player or snapshot.party[party_index])
        if target_member then
            local current_hp = target_member.hp
            local max_hp     = target_member.max_hp
            if current_hp and max_hp and max_hp > 0 then
                hp_deficit = max_hp - current_hp
                common.debugf('[HEAL] HP deficit: %d (max: %d, current: %d)', hp_deficit, max_hp, current_hp)
            else
                common.debugf('[HEAL] Could not calculate HP deficit - missing values')
            end
        end
    end
    
    -- Filter abilities by resource availability and cooldowns
    common.debugf('[HEAL] Checking resource/cooldown availability for %d abilities', #abilities)
    local usable_abilities = action_core.filter_usable(abilities, job_def, '[HEAL]')
    for _, a in ipairs(usable_abilities) do
        common.debugf('[HEAL]   ✓ %s is usable (cost: %d, value: %d)', a.name, a.cost, a.value or 0)
    end
    
    if #usable_abilities == 0 then
        common.debugf('[HEAL] No abilities available (resource or cooldown constraints)')
        return nil
    end
    
    -- If we have HP deficit info, select based on heal value
    if hp_deficit > 0 then
        -- Sort by value descending (largest to smallest heal)
        table.sort(usable_abilities, function(a, b)
            local a_value = type(a.value) == 'number' and a.value or 0
            local b_value = type(b.value) == 'number' and b.value or 0
            return a_value > b_value
        end)
        
        common.debugf('[HEAL] Selecting most efficient heal for deficit: %d HP', hp_deficit)
        common.debugf('[HEAL] Available heals (sorted by value): %s', 
            table.concat((function()
                local names = {}
                for _, a in ipairs(usable_abilities) do
                    local a_value = type(a.value) == 'number' and a.value or 0
                    table.insert(names, string.format('%s(%d)', a.name, a_value))
                end
                return names
            end)(), ', '))
        
        -- Find the largest heal that fits within the deficit (round down approach)
        local best_ability = nil
        for _, ability in ipairs(usable_abilities) do
            local ability_value = type(ability.value) == 'number' and ability.value or 0
            if ability_value > 0 and ability_value <= hp_deficit then
                best_ability = ability
                common.debugf('[HEAL] ✓ Selected %s (value: %d) - largest heal that fits within deficit %d', ability.name, ability_value, hp_deficit)
                return best_ability
            end
        end
        
        -- If no heal fits within the deficit, use the smallest available (least overheal)
        best_ability = usable_abilities[#usable_abilities]
        local best_value = type(best_ability.value) == 'number' and best_ability.value or 0
        common.debugf('[HEAL] ⚠ No heal fits within deficit %d, using smallest available: %s (value: %d)', 
                     hp_deficit, best_ability.name, best_value)
        return best_ability
    else
        -- Fallback: no HP deficit info, use first available (already sorted by cost descending)
        common.debugf('[HEAL] ⚠ No HP deficit info available, using first available heal: %s (cost: %d)', 
            usable_abilities[1].name, usable_abilities[1].cost or 0)
        return usable_abilities[1]
    end
end

return heal
