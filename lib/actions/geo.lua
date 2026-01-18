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
    
    -- Check if player has a pet
    if not common.has_pet() then
        return nil
    end
    
    -- Get distance between player and pet
    local pet_distance = common.get_pet_distance()
    if not pet_distance then
        return nil
    end
    
    -- Get the distance threshold from settings (default 10 yalms)
    local distance_threshold = settings.geo_distance_threshold or 10
    
    -- Check if pet is too far
    if pet_distance <= distance_threshold then
        return nil
    end
    
    common.debugf('[GEO] Pet is %.1f yalms away (threshold: %.1f), attempting Full Circle', pet_distance, distance_threshold)
    
    -- Get geo abilities from job definition
    local geo_abilities = job_def.abilities.geo or {}
    if #geo_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level and settings
    local available_abilities = common.filter_abilities_by_level(geo_abilities, settings, main_level, sub_level, job_def)
    
    if #available_abilities == 0 then
        return nil
    end
    
    -- Try to use the first available geo ability (Full Circle)
    for _, ability in ipairs(available_abilities) do
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
    
    -- ========================================================================
    -- Entrust Logic: Cast Indi spell on party member
    -- ========================================================================
    
    -- Get entrust configuration from config UI (session-only)
    local config_ui = require('lib.config_ui')
    local entrust_config = config_ui.get_entrust_config()
    
    if entrust_config then
        -- Only attempt entrust in combat
        if not common.is_engaged() then
            return nil
        end
        
        local target_index = entrust_config.target_index  -- 1-5 for P1-P5
        local spell_index = entrust_config.spell_index
        
        -- Build list of available Indi spells (same logic as UI)
        local available_indi_spells = {}
        if job_def.abilities.buff then
            for _, ability in ipairs(job_def.abilities.buff) do
                if ability.group == 'Indi' then
                    local filtered = common.filter_abilities_by_level({ability}, settings, main_level, sub_level, job_def)
                    if #filtered > 0 then
                        -- Check if spell is learned
                        local has_spell = true
                        if ability.id then
                            local ok, known = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(ability.id) end)
                            if ok then
                                has_spell = known
                            end
                        end
                        if has_spell then
                            table.insert(available_indi_spells, ability)
                        end
                    end
                end
            end
        end
        
        -- Sort by level descending (highest first)
        table.sort(available_indi_spells, function(a, b) return a.level > b.level end)
        
        -- Validate spell index
        if spell_index < 1 or spell_index > #available_indi_spells then
            return nil
        end
        
        local selected_spell = available_indi_spells[spell_index]
        if not selected_spell then
            return nil
        end
        
        -- Check if target party member is valid and in range (20 yalms)
        if not common.is_in_range(target_index, 20) then
            common.debugf('[GEO] Entrust target P%d out of range or invalid', target_index)
            return nil
        end
        
        -- Check if we have the Entrust buff (584)
        local has_entrust_buff = common.has_buff(0, 584)
        
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
