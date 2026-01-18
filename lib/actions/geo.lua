--[[
    Geo action module
    Handles Full Circle when player is far from pet luopan
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
    
    return nil
end

return geo
