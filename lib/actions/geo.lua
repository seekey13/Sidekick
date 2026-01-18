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
    
    -- ========================================================================
    -- Full Circle Logic
    -- ========================================================================
    
    -- Check if player has a pet (only needed for Full Circle)
    if common.has_pet() then
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
                local available_abilities = common.filter_abilities_by_level(geo_abilities, settings, main_level, sub_level, job_def)
                
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
                    if resource.has_resource(job_def.resource_type, ability.cost) then
                        -- Check cooldown
                        if not ability.id then
                            common.warnf('[GEO] %s has no ability ID defined, skipping', ability.name)
                        else
                            local is_ready = resource.is_ability_ready(ability.id)
                            local recast_time = resource.get_ability_recast(ability.id)
                            
                            common.debugf('[GEO] %s ability recast check - Ability ID: %d, Recast Time: %.1fs, Ready: %s', 
                                ability.name, ability.id, (recast_time or 0) / 60.0, tostring(is_ready))
                            
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
    
    common.debugf('[GEO] Entrust config: %s', entrust_config and 'configured' or 'nil')
    
    if entrust_config then
        common.debugf('[GEO] Entrust target: %s (P%d), spell: %s', 
            entrust_config.target_name, entrust_config.target_index, entrust_config.spell_name)
        
        -- Check if Entrust ability is enabled in settings
        local entrust_enabled_key = 'disabled_Entrust'
        if settings[entrust_enabled_key] == true then
            -- Entrust is disabled, skip
            common.debugf('[GEO] Entrust ability is disabled in settings')
            return nil
        end
        
        common.debugf('[GEO] Entrust ability is enabled')
        
        -- Only attempt entrust in combat
        if not common.is_engaged() then
            common.debugf('[GEO] Not engaged, skipping Entrust')
            return nil
        end
        
        common.debugf('[GEO] Engaged in combat, checking Entrust conditions')
        
        local target_index = entrust_config.target_index  -- 1-5 for P1-P5
        local spell_name = entrust_config.spell_name
        
        -- Find the spell ability by name
        local selected_spell = nil
        if job_def.abilities.buff then
            for _, ability in ipairs(job_def.abilities.buff) do
                if ability.group == 'Indi' and ability.name == spell_name then
                    -- Check level requirements
                    if ability.level and ability.level <= main_level then
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
        
        common.debugf('[GEO] Selected spell: %s', selected_spell.name)
        
        -- Convert party index (1-5) to entity target index
        local party = common.get_party()
        if not party then
            common.debugf('[GEO] Cannot get party manager')
            return nil
        end
        
        local entity_target_index = party:GetMemberTargetIndex(target_index)
        if not entity_target_index or entity_target_index == 0 then
            common.debugf('[GEO] Entrust target P%d has no valid target index', target_index)
            return nil
        end
        
        common.debugf('[GEO] Party index %d -> entity target index %d', target_index, entity_target_index)
        
        -- Check if target party member is valid and in range (20 yalms)
        local target_in_range = common.is_in_range(entity_target_index, 20)
        common.debugf('[GEO] Target in_range result: %s', tostring(target_in_range))
        
        if not target_in_range then
            common.debugf('[GEO] Entrust target P%d out of range or invalid', target_index)
            return nil
        end
        
        common.debugf('[GEO] Target P%d is in range', target_index)
        
        -- Check if we have the Entrust buff (584)
        local has_entrust_buff = common.has_buff(0, 584)
        
        common.debugf('[GEO] Has Entrust buff: %s', tostring(has_entrust_buff))
        
        if has_entrust_buff then
            -- We have Entrust buff, cast the Indi spell on party member
            common.debugf('[GEO] Entrust buff active, casting %s on P%d', selected_spell.name, target_index)
            
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
            -- Get geo abilities from job definition
            local geo_abilities = job_def.abilities.geo or {}
            
            -- Find Entrust ability in geo abilities
            local entrust_ability = nil
            for _, ability in ipairs(geo_abilities) do
                if ability.name == 'Entrust' then
                    entrust_ability = ability
                    break
                end
            end
            
            if not entrust_ability then
                return nil
            end
            
            -- Check if entrust ability is available (level, cooldown, etc)
            local filtered = common.filter_abilities_by_level({entrust_ability}, settings, main_level, sub_level, job_def)
            if #filtered == 0 then
                return nil
            end
            
            -- Check if blocked
            local blocked_by = common.is_command_blocked(entrust_ability.command)
            if blocked_by then
                common.debugf('[GEO] Entrust is blocked by %s', blocked_by)
                return nil
            end
            
            -- Check cooldown
            if entrust_ability.id then
                local is_ready = resource.is_ability_ready(entrust_ability.id)
                local recast_time = resource.get_ability_recast(entrust_ability.id)
                
                common.debugf('[GEO] Entrust ability recast check - Ability ID: %d, Recast Time: %.1fs, Ready: %s', 
                    entrust_ability.id, (recast_time or 0) / 60.0, tostring(is_ready))
                
                if is_ready then
                    local command = common.build_ability_command(entrust_ability, 0)
                    if command then
                        return {
                            command = command,
                            description = string.format('Using Entrust (for %s on P%d)', selected_spell.name, target_index)
                        }
                    end
                end
            end
        end
    end
    
    return nil
end

return geo
