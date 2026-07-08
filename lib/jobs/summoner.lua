--[[
    Summoner job definition
    Defines abilities, validators, and configuration for Summoner automation
    - Healing (Healing Ruby via Carbuncle)
    - AOE healing (Healing Ruby II via Carbuncle)
    - Buffs (Shining Ruby via Carbuncle)
]]--


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
                pet_required = true,
                requires_pet_name = { 'Carbuncle' },
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
                pet_required = true,
                requires_pet_name = { 'Carbuncle' },
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
                pet_required = true,
            },
            {
                name = 'Shining Ruby',
                level = 24,
                cost = 44,
                id = 174,  -- Blood Pact: Ward recast ID (shared with Healing Ruby)
                command = '/pet "Shining Ruby" <me>',
                buff_id = 154,  -- Shining Ruby buff ID
                pet_required = true,
                requires_pet_name = { 'Carbuncle' },
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
                pet_required = true,
                requires_pet_name = { 'Carbuncle' },
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
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
        rest_distance = 7,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'heal_aoe',
        'heal',
        'wake',
        'buff',
        'rest',
    },
    
    -- Validate ability can be used: pet-gated abilities need a pet, and a
    -- requires_pet_name ability (Carbuncle-specific) needs that pet. Avatar-
    -- agnostic abilities (no requires_pet_name) work with any avatar.
    validate_ability = function(ability, common)
        if not ability.pet_required then
            return true
        end
        if not common.get_pet_entity() then
            return false
        end
        return common.pet_type_ok(ability)
    end,
}
