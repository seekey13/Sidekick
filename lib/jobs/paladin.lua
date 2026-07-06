--[[
    Paladin job definition
    Defines abilities, validators, and configuration for Paladin automation
    - Healing through Cure spells
    - Party buffs (Protect, Shell)
]]--


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
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Cure IV" '..target
                end,
                range = 20,
                value = 400,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Cure III',
                level = 30,
                cost = 46,
                id = 3,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Cure III" '..target
                end,
                range = 20,
                value = 200,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Cure II',
                level = 17,
                cost = 24,
                id = 2,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Cure II" '..target
                end,
                range = 20,
                value = 90,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Cure',
                level = 5,
                cost = 8,
                id = 1,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Cure" '..target
                end,
                range = 20,
                value = 30,
                wakes = true,
                target_outside = true,
            },
        },
        
        -- Buffs (Protect, Shell, and Job Abilities)
        buff = {
            -- Job Abilities
            {
                name = 'Majesty',
                level = 70,
                cost = 0,
                id = 150,  -- Majesty recast ID
                command = '/ja "Majesty" <me>',
                buff_id = 621,  -- Majesty buff
            },
            -- Protect spells
            {
                name = 'Protect IV',
                level = 70,
                cost = 65,
                id = 46,  -- Protect IV spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect IV" '..target
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect III',
                level = 50,
                cost = 46,
                id = 45,  -- Protect III spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 30,
                cost = 28,
                id = 44,  -- Protect II spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect',
                level = 10,
                cost = 9,
                id = 43,  -- Protect spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,  -- Protect buff
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Shell III',
                level = 60,
                cost = 56,
                id = 50,  -- Shell III spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 40,
                cost = 37,
                id = 49,  -- Shell II spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell',
                level = 20,
                cost = 18,
                id = 48,  -- Shell spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,  -- Shell buff
                range = 20,
                group = 'shell',
                target_outside = true,
            },
        },
        
        -- Recover (MP recovery via Chivalry; TP usage is controlled by chivalry_min_tp settings)
        recover_mp = {
            {
                name = 'Chivalry',
                level = 75,
                cost = 0,
                id = 79,  -- Chivalry recast ID
                command = '/ja "Chivalry" <me>',
                min_tp = 3000,  -- default TP threshold; overridden by chivalry_min_tp setting
            },
        },
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
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
        rest_distance = 7,
        recover_enabled = false,
        recover_mp_threshold = 25,
        recover_tp_threshold = 25,
        chivalry_min_tp = 3000,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'heal',
        'buff',
        'rest',
    },
}
