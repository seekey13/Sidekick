--[[
    Pet healing action module
    Handles healing for player's geo pet
]]--

local heal_pet = {}

local common = require('lib.core.common')
local resource = require('lib.core.resource')

function heal_pet.execute(settings, job_def, main_level, sub_level, player_resource)
    -- Check if pet healing is enabled
    if not settings.heal_pet_enabled then
        return nil
    end
    
    -- Check if player has a pet
    if not common.targets.get_pet() then
        return nil
    end
    
    -- Get pet heal abilities from job definition
    local heal_pet_abilities = job_def.abilities.heal_pet or {}
    if #heal_pet_abilities == 0 then
        return nil
    end
    
    -- Filter abilities by level using DRY helper
    local available_abilities = common.filter_abilities_by_level(
        heal_pet_abilities,
        settings,
        main_level,
        sub_level,
        job_def
    )
    
    if #available_abilities == 0 then
        common.debugf('[HEAL_PET] No pet heal abilities available for this level/configuration')
        return nil
    end
    
    common.debugf('[HEAL_PET] %d pet heal abilities available', #available_abilities)
    
    -- Check pet HP
    local pet_hpp = common.get_pet_hp_percent()
    common.debugf('[HEAL_PET] Pet HP: %.1f%%', pet_hpp)
    
    -- Check if pet needs healing
    local threshold = settings.heal_pet_threshold or 50
    if pet_hpp >= threshold then
        common.debugf('[HEAL_PET] Pet HP %.1f%% >= threshold %.1f%%, no healing needed', pet_hpp, threshold)
        return nil
    end
    
    if pet_hpp == 0 then
        common.debugf('[HEAL_PET] Pet HP is 0%% (dead or despawned)')
        return nil
    end
    
    common.debugf('[HEAL_PET] Pet needs healing (%.1f%% < %.1f%%)', pet_hpp, threshold)
    
    -- Select best available ability
    for _, ability in ipairs(available_abilities) do
        -- Check if this ability is blocked by status ailments
        local blocked_by = common.is_command_blocked(ability.command)
        if blocked_by then
            common.debugf('[HEAL_PET] %s is blocked by %s', ability.name, blocked_by)
            goto continue
        end
        
        -- Check resource
        if resource.has_resource(job_def.resource_type, ability.cost) then
            -- Check cooldown
            if ability.id then
                if resource.is_ability_ready(ability.id) then
                    local command = common.build_ability_command(ability)
                    if command then
                        common.debugf('[HEAL_PET] >>> Using pet heal %s', ability.name)
                        return {
                            command = command,
                            description = string.format('Healing pet with %s (Pet HP: %.1f%%)', ability.name, pet_hpp)
                        }
                    end
                else
                    common.debugf('[HEAL_PET] %s on cooldown', ability.name)
                end
            else
                -- No cooldown tracking needed
                local command = common.build_ability_command(ability)
                if command then
                    common.debugf('[HEAL_PET] >>> Using pet heal %s', ability.name)
                    return {
                        command = command,
                        description = string.format('Healing pet with %s (Pet HP: %.1f%%)', ability.name, pet_hpp)
                    }
                end
            end
        else
            common.debugf('[HEAL_PET] Insufficient %s for %s (need: %d, have: %d)',
                         job_def.resource_type, ability.name, ability.cost, player_resource)
        end
        
        ::continue::
    end
    
    common.debugf('[HEAL_PET] No usable pet heal abilities (resource/cooldown)')
    return nil
end

return heal_pet
