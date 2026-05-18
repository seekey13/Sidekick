--[[
    Dancer job definition
    Defines abilities, validators, and configuration for Dancer automation
    - Healing (Curing Waltz, Divine Waltz)
    - Debuff removal (Healing Waltz)
    - Buffs (Drain, Aspir, Haste Samba, Spectral Jig, Saber Dance, Fan Dance, No Foot Rise, Presto)
    - TP recovery (Reverse Flourish)
]]--

local common = require('lib.core.common')

return {
    job_id = 19,  -- Dancer
    job_name = 'Dancer',
    resource_type = 'tp',
    
    abilities = {
        -- Single-target healing (Waltzes)
        heal = {
            {
                name = 'Curing Waltz III',
                level = 45,
                cost = 500,
                id = 187,
                command = function(target)
                    return '/ja "Curing Waltz III" '..target
                end,
                wakes = true,
                value = 300,
            },
            {
                name = 'Curing Waltz II',
                level = 30,
                cost = 350,
                id = 186,
                command = function(target)
                    return '/ja "Curing Waltz II" '..target
                end,
                wakes = true,
                value = 140,
            },
            {
                name = 'Curing Waltz',
                level = 15,
                cost = 200,
                id = 217,
                command = function(target)
                    return '/ja "Curing Waltz" '..target
                end,
                wakes = true,
                value = 70,
            },
        },
        
        -- AOE healing
        heal_aoe = {
            {
                name = 'Divine Waltz II',
                level = 65,
                cost = 400,
                id = 102,
                command = '/ja "Divine Waltz II" <me>',
                wakes = true,
            },
            {
                name = 'Divine Waltz',
                level = 20,
                cost = 400,
                id = 225,
                command = '/ja "Divine Waltz" <me>',
                wakes = true,
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Healing Waltz',
                level = 35,
                cost = 200,
                id = 215,  -- Healing Waltz recast ID
                debuff_id = {3, 4, 5, 6, 8, 9, 11, 12, 13, 31, 128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404},  -- Poison, Paralyze, Blind, Silence, Disease, Curse, Bind, Weight, Slow, Plague, Burn, Frost, Choke, Rasp, Dia, Bio, STR Down, DEX Down, VIT Down, AGI Down, INT Down, MND Down, CHR Down, Max HP Down, Max MP Down, Accuracy Down, Attack Down, Evasion Down, Defense Down, Flash, Magic Def Down, Magic Acc Down, Magic Atk Down, Max TP Down, Magic Eva Down
                command = function(target)
                    return '/ja "Healing Waltz" '..target
                end,
            },
        },
        
        -- Buffs
        buff = {
            {
                name = 'Saber Dance',
                level = 75,
                cost = 0,
                id = 219,  -- Saber Dance recast ID
                command = '/ja "Saber Dance" <me>',
                buff_id = 410,  -- Saber Dance
                group = 'dance',
            },
            {
                name = 'Fan Dance',
                level = 75,
                cost = 0,
                id = 224,  -- Fan Dance recast ID
                command = '/ja "Fan Dance" <me>',
                buff_id = 411,  -- Fan Dance
                group = 'dance',
            },
            {
                name = 'No Foot Rise',
                level = 75,
                cost = 0,
                id = 223,  -- No Foot Rise recast ID
                command = '/ja "No Foot Rise" <me>',
            },
            {
                name = 'Presto',
                level = 75,
                cost = 0,
                id = 236,  -- Presto recast ID
                command = '/ja "Presto" <me>',
                buff_id = 442,  -- Presto
            },
            {
                name = 'Drain Samba III',
                level = 65,
                cost = 400,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba III" <me>',
                buff_id = 368,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Drain Samba II',
                level = 35,
                cost = 250,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba II" <me>',
                buff_id = 368,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Drain Samba',
                level = 5,
                cost = 100,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba" <me>',
                buff_id = 368,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Aspir Samba II',
                level = 60,
                cost = 250,
                id = 216,
                command = '/ja "Aspir Samba II" <me>',
                buff_id = 369,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Aspir Samba',
                level = 25,
                cost = 100,
                id = 216,
                command = '/ja "Aspir Samba" <me>',
                buff_id = 369,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Haste Samba',
                level = 45,
                cost = 350,
                id = 216,
                command = '/ja "Haste Samba" <me>',
                buff_id = 370,
                engaged_only = true,
                group = 'samba',
            },
            {
                name = 'Spectral Jig',
                level = 25,
                cost = 0,
                id = 195,  -- Jig recast ID
                command = '/ja "Spectral Jig" <me>',
                buff_id = {71, 69},  -- Sneak (71) and Invisible (69)
                idle_only = true,
            },
        },

        -- Critical
        critical = {
            {
                name = 'Contradance',
                level = 50,
                cost = 0,
                id = 229,  -- Job Ability ID
                command = '/ja "Contradance" <me>',
            },
        },

        -- Recover
        recover_tp = {
            {
                name = 'Reverse Flourish',
                level = 40,
                cost = 0,
                id = 222,
                command = '/ja "Reverse Flourish" <me>',
                wakes = false,
                value = 600,
                requires_buff = 385,  -- Requires (5) Finishing Moves
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
        debuff_removal_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'critical',
        'heal_aoe',
        'heal',
        'debuff_removal',
        'wake',
        'buff',
    },
}
