--[[
    Summoner job definition
    Defines abilities, validators, and configuration for Summoner automation
    - Healing (Healing Ruby via Carbuncle)
    - AOE healing (Healing Ruby II via Carbuncle)
    - Buffs (Shining Ruby via Carbuncle)
]]--

local common = require('lib.core.common')

return {
    job_id = 15,  -- Summoner
    job_name = 'Summoner',
    resource_type = 'mp',
    
    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Healing Ruby',
                level = 1,
                cost = 6,
                id = 174,  -- Blood Pact: Ward recast ID
                command = function(target)
                    return '/pet "Healing Ruby" '..target
                end,
                wakes = true,  -- Can wake from sleep
                combat_only = false,
                pet_required = true,
                requires_carbuncle = true,
            },
        },
        
        -- AOE healing
        heal_aoe = {
            {
                name = 'Healing Ruby II',
                level = 65,
                cost = 124,
                id = 174,  -- Blood Pact: Ward recast ID
                command = '/pet "Healing Ruby II" <me>',
                wakes = true,  -- Can wake from sleep
                combat_only = false,
                pet_required = true,
                requires_carbuncle = true,
            },
        },
        
        -- Buffs
        buff = {
            {
                name = 'Avatar\'s Favor',
                level = 55,
                cost = 0,
                id = 176,  -- Avatar's Favor recast ID
                command = '/pet "Avatar\'s Favor" <me>',
                buff_id = 431,  -- Avatar's Favor buff ID
                combat_only = false,
                pet_required = true,
            },
            {
                name = 'Shining Ruby',
                level = 24,
                cost = 44,
                id = 174,  -- Blood Pact: Ward recast ID (shared with Healing Ruby)
                command = '/pet "Shining Ruby" <me>',
                buff_id = 154,  -- Shining Ruby buff ID
                combat_only = false,
                pet_required = true,
                requires_carbuncle = true,
            },
        },

        -- Critical
        critical = {
            {
                name = 'Apogee',
                level = 70,
                cost = 0,
                id = 108,  -- Apogee recast ID
                command = '/ja "Apogee" <me>',
                combat_only = false,
                pet_required = true,
            },
        },
    },
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        critical_threshold = 30,
        heal_aoe_enabled = true,
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = true,
        buff_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
    },
    
    -- Action priority order
    priority_order = {
        'heal_aoe',
        'heal',
        'wake',
        'buff',
    },
    
    -- Validate ability can be used (Summoner-specific: check for Carbuncle when required)
    validate_ability = function(ability, common)
        -- Only validate abilities that require a pet
        if not ability.pet_required then
            return true
        end
        
        -- Get pet entity
        local pet = common.get_pet_entity()
        if not pet then
            common.debugf('[SMN Validator] %s blocked: No pet entity found', ability.name)
            return false
        end
        
        -- If ability doesn't specifically require Carbuncle, any pet is fine
        if not ability.requires_carbuncle then
            common.debugf('[SMN Validator] %s: Any avatar OK', ability.name)
            return true
        end
        
        -- Check if pet name is available
        local ok, pet_name = pcall(function()
            return pet.Name
        end)
        
        if not ok or not pet_name then
            common.debugf('[SMN Validator] %s blocked: Could not read pet name', ability.name)
            return false
        end
        
        -- Only allow abilities if Carbuncle is summoned
        local is_carbuncle = pet_name == 'Carbuncle'
        common.debugf('[SMN Validator] %s: pet_name="%s", is_carbuncle=%s', ability.name, pet_name, tostring(is_carbuncle))
        return is_carbuncle
    end,
}
