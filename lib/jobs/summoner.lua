--[[
    Summoner job definition
    Defines abilities, validators, and configuration for Summoner automation
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
                command = function(party_index)
                    return '/pet "Healing Ruby" <p' .. party_index .. '>'
                end,
                wakes = true,  -- Can wake from sleep
                pet_required = true,
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
            },
        },
        
        -- Buffs
        buff = {
            {
                name = 'Shining Ruby',
                level = 24,
                cost = 44,
                id = 174,  -- Blood Pact: Ward recast ID (shared with Healing Ruby)
                command = '/pet "Shining Ruby" <me>',
                buff_id = 154,  -- Shining Ruby buff ID
                combat_only = false,
                pet_required = true,
            },
        },
    },
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = true,
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = false,
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
}
