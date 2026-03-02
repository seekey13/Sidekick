--[[
    Geo action module
    Handles Full Circle when player is far from pet luopan
    Handles Entrust + Indi spell casting on party members
]]--

local geo = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function geo.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if geo action is enabled
    if not settings.geo_enabled then
        return nil
    end

    local state  = common.game_state
    local player = state and state.player
    if not player then return nil end
    local derived_main_level = player.main_level
    local derived_sub_level  = player.sub_level
    
    -- ========================================================================
    -- Full Circle Logic
    -- ========================================================================
    
    -- Check if player has a pet (only needed for Full Circle)
    if common.targets.get_pet() then
        -- Get distance between player and pet
        local pet_distance = common.get_pet_distance()
        if pet_distance then
            -- Get the distance threshold from settings (default 10 yalms)
            local distance_threshold = settings.geo_distance_threshold or 10
            
            -- Check if pet is too far
            if pet_distance > distance_threshold then
                common.debugf('[GEO] Pet is %.1f yalms away (threshold: %.1f), attempting Full Circle', pet_distance, distance_threshold)
                
                -- Get geo abilities from job definition
                local geo_abilities = job_def.abilities.geo or {}
                
                -- Filter abilities by level and settings
                local available_abilities = common.filter_abilities_by_level(geo_abilities, settings, derived_main_level, derived_sub_level, job_def)
                
                -- Try to use Full Circle
                for _, ability in ipairs(available_abilities) do
                    -- Skip Entrust, only look for Full Circle
                    if ability.name == 'Entrust' then
                        goto continue
                    end
                    
                    -- Check if this ability is blocked by status ailments
                    local blocked_by = common.is_command_blocked(ability.command)
                    if blocked_by then
                        common.debugf('[GEO] %s is blocked by %s', ability.name, blocked_by)
                        goto continue
                    end
                    
                    -- Check resource (Full Circle has 0 cost)
                    local ability_resource_type = ability.resource_type or job_def.resource_type
                    if resource.has_resource(ability_resource_type, ability.cost) then
                        -- Check cooldown
                        if not ability.id then
                            common.warnf('[GEO] %s has no ability ID defined, skipping', ability.name)
                        else
                            local is_ready = resource.is_ability_ready(ability.id)
                            
                            if is_ready then
                                local command = common.build_ability_command(ability, 0)
                                if command then
                                    return {
                                        command = command,
                                        description = string.format('Using %s (Pet distance: %.1f yalms)', ability.name, pet_distance)
                                    }
                                end
                            end
                        end
                    end
                    
                    ::continue::
                end
            end
        end
    end
    
    -- ========================================================================
    -- Entrust Logic
    -- ========================================================================
    
    -- Get entrust configuration from config UI
    local config_ui = require('lib.config_ui')
    local entrust_config = config_ui.get_entrust_config()
    
    if entrust_config then
        -- Check if Entrust ability is enabled in settings
        local entrust_enabled_key = 'disabled_Entrust'
        if settings[entrust_enabled_key] == true then
            return nil
        end
        
        local target_index = entrust_config.target_index  -- 1-5 for P1-P5
        local spell_name = entrust_config.spell_name
        
        -- Find the spell ability by name
        local selected_spell = nil
        if job_def.abilities.buff then
            for _, ability in ipairs(job_def.abilities.buff) do
                if ability.group == 'Indi' and ability.name == spell_name then
                    -- Check level requirements
                    if ability.level and ability.level <= derived_main_level then
                        -- Check if spell is learned
                        local has_spell = true
                        if ability.id then
                            local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
                            if ok then
                                has_spell = known
                            end
                        end
                        if has_spell then
                            selected_spell = ability
                            break
                        end
                    end
                end
            end
        end
        
        if not selected_spell then
            common.debugf('[GEO] Spell %s not found or not available', spell_name)
            return nil
        end
        
-- Convert party index (1-5) to entity target index via game state
        local party_member = state.party[target_index]
        if not party_member then
            return nil
        end

        local entity_target_index = party_member.target_index
        if not entity_target_index or entity_target_index == 0 then
            return nil
        end
        
        -- Check if target party member is valid and in range (20 yalms)
        local target_in_range = common.is_in_range(entity_target_index, 20)
        
        if not target_in_range then
            common.debugf('[GEO] Entrust target out of range')
            return nil
        end
        
        -- Check if we have the Entrust buff (584)
        local has_entrust_buff = false
        for _, active_buff in ipairs(player.buffs) do
            if active_buff == 584 then
                has_entrust_buff = true
                break
            end
        end
        
        if has_entrust_buff then
            -- We have Entrust buff, cast the Indi spell on party member
            -- Check if spell is blocked by status ailments
            local blocked_by = common.is_command_blocked(selected_spell.command)
            if blocked_by then
                common.debugf('[GEO] %s is blocked by %s', selected_spell.name, blocked_by)
                return nil
            end
            
            -- Check MP cost
            if not resource.has_resource('mp', selected_spell.cost or 0) then
                common.debugf('[GEO] Not enough MP for %s (cost: %d)', selected_spell.name, selected_spell.cost or 0)
                return nil
            end
            
            -- Build command for party member target
            local command
            if type(selected_spell.command) == 'function' then
                command = selected_spell.command(target_index)
            else
                -- Replace <me> with <p#> in command
                command = selected_spell.command:gsub('<me>', '<p' .. target_index .. '>')
            end
            
            if command then
                return {
                    command = command,
                    description = string.format('Entrust: %s on P%d', selected_spell.name, target_index)
                }
            end
        else
            -- We don't have Entrust buff, use Entrust ability
            -- Use helper function to validate and build Entrust command
            -- Note: We create a temporary job_def with Entrust in target_modifier format
            local temp_job_def = {
                abilities = {
                    target_modifier = {}
                },
                resource_type = job_def.resource_type
            }
            
            -- Find Entrust in geo abilities and add to temp structure
            if job_def.abilities.geo then
                for _, ability in ipairs(job_def.abilities.geo) do
                    if ability.name == 'Entrust' then
                        table.insert(temp_job_def.abilities.target_modifier, ability)
                        break
                    end
                end
            end
            
            -- Use common helper to validate Entrust ability
            local entrust_result = common.check_target_modifier(temp_job_def, settings, derived_main_level, derived_sub_level)
            
            if entrust_result then
                -- Override description to include spell context
                entrust_result.description = string.format('Using Entrust (for %s on P%d)', selected_spell.name, target_index)
                return entrust_result
            end
        end
    end
    
    return nil
end

return geo
