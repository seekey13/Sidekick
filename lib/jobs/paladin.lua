--[[
    Paladin job definition
    Defines abilities, validators, and configuration for Paladin automation
    - Healing through Cure spells
    - Party buffs (Protect, Shell)
]]--


return {
    job_id = 7,
    job_name = 'Paladin',
    resource_type = 'mp',
    
    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Cure IV',
                level = 55,
                cost = 88,
                spell_id = 4,
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
                spell_id = 3,
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
                spell_id = 2,
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
                spell_id = 1,
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
                name = 'Fealty',
                level = 75,
                cost = 0,
                recast_id = 78,
                command = '/ja "Fealty" <me>',
                ability_id = 157,
                buff_id = 344,
                combat_only = true,
            },
            {
                name = 'Majesty',
                level = 70,
                cost = 0,
                recast_id = 150,
                command = '/ja "Majesty" <me>',
                buff_id = 621,
                priority = 100,
            },
            {
                name = 'Rampart',
                level = 62,
                cost = 0,
                recast_id = 77,
                command = '/ja "Rampart" <me>',
                buff_id = 623,
                combat_only = true,
            },
            {
                name = 'Reprisal',
                level = 61,
                cost = 24,
                spell_id = 97,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reprisal" <me>',
                buff_id = 403,
            },
            {
                name = 'Sentinel',
                level = 30,
                cost = 0,
                recast_id = 75,
                command = '/ja "Sentinel" <me>',
                buff_id = 62,
                combat_only = true,
            },
            -- Protect spells
            {
                name = 'Protect IV',
                level = 70,
                cost = 65,
                spell_id = 46,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect IV" '..target
                end,
                buff_id = 40,
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect III',
                level = 50,
                cost = 46,
                spell_id = 45,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 30,
                cost = 28,
                spell_id = 44,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect',
                level = 10,
                cost = 9,
                spell_id = 43,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,
                range = 20,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Shell III',
                level = 60,
                cost = 56,
                spell_id = 50,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,
                range = 20,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 40,
                cost = 37,
                spell_id = 49,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,
                range = 20,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell',
                level = 20,
                cost = 18,
                spell_id = 48,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,
                range = 20,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Holy Circle',
                level = 5,
                cost = 0,
                recast_id = 74,
                command = '/ja "Holy Circle" <me>',
                buff_id = 74,
                combat_only = true,
            },
        },
        
        -- Recover (MP recovery via Chivalry; TP usage is controlled by chivalry_min_tp settings)
        recover_mp = {
            {
                name = 'Chivalry',
                level = 75,
                cost = 0,
                recast_id = 79,
                command = '/ja "Chivalry" <me>',
                ability_id = 158,
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
        wake_enabled = false,
        buff_enabled = true,
        debuff_removal_enabled = false,  -- Paladin has no debuff removal
        focus_enabled = false,
        focus_threshold = 85,
        recover_enabled = false,
        recover_mp_threshold = 25,
        recover_tp_threshold = 1000,  -- Meditate (PLD/SAM) when TP drops below 1000
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
