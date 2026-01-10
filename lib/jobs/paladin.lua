--[[
    Paladin job definition
    Defines abilities, validators, and configuration for Paladin automation
    
    Paladin abilities focus on:
    - Healing through Cure spells
    - Party buffs (Protect, Shell)
]]--

local common = require('lib.core.common')

return {
    job_id = 7,  -- Paladin
    job_name = 'Paladin',
    resource_type = 'mp',
    
    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Cure IV',
                level = 55,
                cost = 88,
                id = 4,  -- Spell ID
                command = function(party_index)
                    return '/ma "Cure IV" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 400,
                wakes = true,
            },
            {
                name = 'Cure III',
                level = 30,
                cost = 46,
                id = 3,  -- Spell ID
                command = function(party_index)
                    return '/ma "Cure III" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 200,
                wakes = true,
            },
            {
                name = 'Cure II',
                level = 17,
                cost = 24,
                id = 2,  -- Spell ID
                command = function(party_index)
                    return '/ma "Cure II" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 90,
                wakes = true,
            },
            {
                name = 'Cure',
                level = 5,
                cost = 8,
                id = 1,  -- Spell ID
                command = function(party_index)
                    return '/ma "Cure" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 30,
                wakes = true,
            },
        },
        
        -- Buffs (Protect, Shell, and Job Abilities)
        buff = {
            {
                name = 'Protect IV',
                level = 70,
                cost = 65,
                id = 46,  -- Protect IV spell ID
                command = function(party_index)
                    return '/ma "Protect IV" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
            },
            {
                name = 'Protect III',
                level = 50,
                cost = 46,
                id = 45,  -- Protect III spell ID
                command = function(party_index)
                    return '/ma "Protect III" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
            },
            {
                name = 'Protect II',
                level = 30,
                cost = 28,
                id = 44,  -- Protect II spell ID
                command = function(party_index)
                    return '/ma "Protect II" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
            },
            {
                name = 'Protect',
                level = 10,
                cost = 9,
                id = 43,  -- Protect spell ID
                command = function(party_index)
                    return '/ma "Protect" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
            },
            {
                name = 'Shell III',
                level = 60,
                cost = 56,
                id = 50,  -- Shell III spell ID
                command = function(party_index)
                    return '/ma "Shell III" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
            },
            {
                name = 'Shell II',
                level = 40,
                cost = 37,
                id = 49,  -- Shell II spell ID
                command = function(party_index)
                    return '/ma "Shell II" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
            },
            {
                name = 'Shell',
                level = 20,
                cost = 18,
                id = 48,  -- Shell spell ID
                command = function(party_index)
                    return '/ma "Shell" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
            },
            {
                name = 'Majesty',
                level = 70,
                cost = 0,
                id = 150,  -- Majesty recast ID
                command = '/ja "Majesty" <me>',
                buff_id = 621,  -- Majesty buff
                combat_only = true,
            },
        },
        
        -- -- Recover (MP recovery)
        -- recover = {
        --     {
        --         name = 'Chivalry',
        --         level = 75,
        --         cost = 0,
        --         id = 79,  -- Chivalry recast ID
        --         command = '/ja "Chivalry" <me>',
        --         combat_only = false,
        --     },
        -- },
    },
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = false,  -- Paladin has no AOE heal
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = false,
        buff_enabled = true,
        debuff_removal_enabled = false,  -- Paladin has no debuff removal
        focus_enabled = false,
        focus_target_index = nil,
    },
    
    -- Action priority order
    priority_order = {
        'heal',
        'buff',
        -- recover,
    },
}
