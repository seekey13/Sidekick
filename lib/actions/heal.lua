--[[
    Single-target healing action module
    Handles priority-based healing for individual party members
]]--

local heal = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

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
        main_level,
        sub_level,
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
        
        local player_hpp = common.get_party_member_hp_percent(0)
        common.debugf('[HEAL] Player HP: %.1f%%', player_hpp)
        
        if player_hpp < (settings.heal_threshold or 75) then
            -- Select appropriate ability
            local selected_ability = heal.select_ability(available_abilities, player_hpp, job_def.resource_type, player_resource, 0, job_def)
            if selected_ability then
                local command = common.build_ability_command(selected_ability, 0)
                
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
    
    -- Check party HP status (only if we have non-self-only abilities)
    local party_status = common.check_party_hp(
        settings.heal_threshold or 75,
        settings.focus_enabled,
        common.get_party_index_by_name(settings.focus_target),
        settings.focus_threshold or 85
    )
    
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
            main_level,
            sub_level,
            job_def
        )
        
        if #available_critical > 0 then
            -- Find lowest HP party member (ignoring focus)
            local critical_party_index = nil
            local critical_hpp = 100
            
            for i = 0, 5 do
                if common.is_party_member_active(i) then
                    local hpp = common.get_party_member_hp_percent(i)
                    if hpp > 0 and hpp < critical_threshold and hpp < critical_hpp then
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
                    -- Check if ability is enabled
                    local ability_key = 'disabled_' .. ability.name:gsub(' ', '_')
                    if settings[ability_key] == true then
                        common.debugf('[HEAL] Critical ability %s is disabled', ability.name)
                        goto continue_critical
                    end
                    
                    -- Check if blocked by status ailments
                    local blocked_by = common.is_command_blocked(ability.command)
                    if blocked_by then
                        common.debugf('[HEAL] Critical ability %s is blocked by %s', ability.name, blocked_by)
                        goto continue_critical
                    end
                    
                    -- Check resource availability
                    if not resource.has_resource(job_def.resource_type, ability.cost) then
                        common.debugf('[HEAL] Insufficient %s for critical ability %s', job_def.resource_type, ability.name)
                        goto continue_critical
                    end
                    
                    -- Check cooldown
                    if ability.id and not resource.is_ability_ready(ability.id) then
                        common.debugf('[HEAL] Critical ability %s on cooldown', ability.name)
                        goto continue_critical
                    end
                    
                    -- Determine target based on ability command
                    local target_party_index
                    local command_test = common.build_ability_command(ability, 0)
                    if command_test and command_test:find('<me>') then
                        -- Self-target ability (Divine Seal)
                        target_party_index = 0
                        common.debugf('[HEAL] Using self-target critical ability %s', ability.name)
                    else
                        -- Party-target ability (Martyr)
                        target_party_index = critical_party_index
                        
                        -- Check range for party-target abilities
                        local target_index = common.get_party_member_target_index(critical_party_index)
                        if target_index then
                            local ability_range = type(ability.range) == 'number' and ability.range or 21
                            if not common.is_in_range(target_index, ability_range) then
                                common.debugf('[HEAL] Critical target out of range (range: %d)', ability_range)
                                goto continue_critical
                            end
                        else
                            common.debugf('[HEAL] Could not get target index for critical party member')
                            goto continue_critical
                        end
                        
                        common.debugf('[HEAL] Using party-target critical ability %s on party[%d]', ability.name, critical_party_index)
                    end
                    
                    local command = common.build_ability_command(ability, target_party_index)
                    if command then
                        common.debugf('[HEAL] >>> Using critical ability %s', ability.name)
                        return {
                            command = command,
                            description = string.format('Critical: %s for %s (HP: %.1f%%)', 
                                ability.name,
                                target_party_index == 0 and 'self' or (common.get_party_member_name(critical_party_index) or 'party member'),
                                critical_hpp)
                        }
                    end
                    
                    ::continue_critical::
                end
                
                common.debugf('[HEAL] No critical abilities available (all disabled/on cooldown/out of range)')
            end
        end
    end
    
    -- Priority 2: Focus target
    if settings.focus_enabled and settings.focus_target and party_status.focus_needs_heal then
        local focus_target_index = common.get_target_index_by_name(settings.focus_target)
        if focus_target_index then
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
                -- Get party index for focus target first (needed for HP deficit calculation)
                local focus_party_index = common.get_party_index_by_name(settings.focus_target)
                if not focus_party_index then
                    common.debugf('[HEAL] Could not get party index for focus target')
                    return nil
                end
                
                -- Select appropriate ability based on HP deficit
                local selected_ability = heal.select_ability(available_abilities, focus_hpp, job_def.resource_type, player_resource, focus_party_index, job_def)
                
                if selected_ability and focus_party_index then
                    -- Check if in range using ability's range (default to 21 if not specified)
                    local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                    if not common.is_in_range(focus_target_index, ability_range) then
                        common.debugf('[HEAL] Focus target out of range (range: %d)', ability_range)
                        return nil
                    end
                    common.debugf('[HEAL] Focus target in range (range: %d)', ability_range)
                    common.debugf('[HEAL] Selected %s for focus target', selected_ability.name)
                    
                    local command = common.build_ability_command(selected_ability, focus_party_index)
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
        local target_index = common.get_party_member_target_index(party_status.lowest_hp_index)
        if target_index then
            -- Select appropriate ability based on HP deficit
            local selected_ability = heal.select_ability(available_abilities, party_status.lowest_hp_percent, job_def.resource_type, player_resource, party_status.lowest_hp_index, job_def)
            if selected_ability then
                -- Check if in range using ability's range (default to 21 if not specified)
                local ability_range = type(selected_ability.range) == 'number' and selected_ability.range or 21
                if not common.is_in_range(target_index, ability_range) then
                    common.debugf('[HEAL] Target out of range (range: %d)', ability_range)
                    return nil
                end
                local command = common.build_ability_command(selected_ability, party_status.lowest_hp_index)
                if command then
                    return {
                        command = command,
                        description = string.format('Healing %s with %s (HP: %.1f%%)', 
                            common.get_party_member_name(party_status.lowest_hp_index) or 'party member',
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

function heal.select_ability(abilities, target_hpp, resource_type, player_resource, party_index, job_def)
    -- Special case: Summoner should always try Healing Ruby first
    if job_def and job_def.job_id == 15 then
        -- Look for Healing Ruby in abilities
        for _, ability in ipairs(abilities) do
            if ability.name == 'Healing Ruby' then
                -- Check if usable: has pet, has resource, not on cooldown
                if common.targets.get_pet() then
                    if resource.has_resource(resource_type, ability.cost) then
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
        local party = common.get_party()
        if party then
            local current_hp = party:GetMemberHP(party_index)
            local hp_percent_value = party:GetMemberHPPercent(party_index)
            
            common.debugf('[HEAL] Raw values: Current HP=%s, HP Percent=%s', tostring(current_hp), tostring(hp_percent_value))
            
            -- Calculate max HP from percentage (this can be inaccurate at very low HP due to rounding)
            local max_hp = nil
            local is_percent_unreliable = false
            if current_hp and hp_percent_value and hp_percent_value > 0 then
                max_hp = math.floor(current_hp / (hp_percent_value / 100))
                
                -- Check if the percentage is unreliable (very low HP with 1% reported)
                if hp_percent_value == 1 and current_hp < 100 then
                    is_percent_unreliable = true
                    common.debugf('[HEAL] ⚠ Warning: HP percent at minimum (1%%), cannot trust deficit calculation')
                    common.debugf('[HEAL]    Will use strongest heal available due to unreliable data')
                    -- Set deficit to a large value to force selection of strongest heal
                    hp_deficit = 999999
                else
                    hp_deficit = max_hp - current_hp
                    local calculated_percent = (current_hp / max_hp) * 100
                    common.debugf('[HEAL] Target HP deficit: %d (Max: %d, Current: %d, Calculated %%: %.2f%%, Reported %%: %d%%)', 
                                 hp_deficit, max_hp, current_hp, calculated_percent, hp_percent_value)
                end
            else
                common.debugf('[HEAL] Could not calculate HP deficit - missing values')
            end
        end
    end
    
    -- Filter abilities by resource availability and cooldowns
    local usable_abilities = {}
    common.debugf('[HEAL] Checking resource/cooldown availability for %d abilities', #abilities)
    for _, ability in ipairs(abilities) do
        -- Check if this ability is blocked by status ailments
        local blocked_by = common.is_command_blocked(ability.command)
        if blocked_by then
            common.debugf('[HEAL] %s is blocked by %s', ability.name, blocked_by)
            goto continue
        end
        
        -- Check resource
        if resource.has_resource(resource_type, ability.cost) then
            -- Check cooldown
            if ability.id then
                local is_ready = false
                -- Determine if this is a spell or ability based on command
                local is_spell = false
                if type(ability.command) == 'string' and ability.command:match('^/ma%s') then
                    is_spell = true
                elseif type(ability.command) == 'function' then
                    -- Try to get the command string to check
                    local test_cmd = common.build_ability_command(ability, 0)
                    if test_cmd and test_cmd:match('^/ma%s') then
                        is_spell = true
                    end
                end
                
                if is_spell then
                    is_ready = resource.is_spell_ready(ability.id)
                    if not is_ready then
                        local recast_time = resource.get_spell_recast(ability.id)
                        local recast_seconds = recast_time / 60.0
                        common.debugf('[HEAL]   ✗ %s on cooldown (spell recast: %.1fs)', ability.name, recast_seconds)
                    end
                else
                    is_ready = resource.is_ability_ready(ability.id)
                    if not is_ready then
                        common.debugf('[HEAL]   ✗ %s on cooldown', ability.name)
                    end
                end
                
                if is_ready then
                    common.debugf('[HEAL]   ✓ %s is usable (cost: %d, value: %d)', ability.name, ability.cost, ability.value or 0)
                    table.insert(usable_abilities, ability)
                end
            else
                -- No cooldown tracking needed
                common.debugf('[HEAL]   ✓ %s is usable (cost: %d, value: %d)', ability.name, ability.cost, ability.value or 0)
                table.insert(usable_abilities, ability)
            end
        else
            common.debugf('[HEAL]   ✗ Insufficient %s for %s (need: %d, have: %d)', 
                         resource_type, ability.name, ability.cost, player_resource)
        end
        
        ::continue::
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
