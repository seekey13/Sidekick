--[[
    Dancer job definition
    Defines abilities, validators, and configuration for Dancer automation
    - Healing (Curing Waltz, Divine Waltz)
    - Debuff removal (Healing Waltz)
    - Buffs (Drain, Aspir, Haste Samba, Spectral Jig, Saber Dance, Fan Dance, No Foot Rise, Presto)
    - TP recovery (Reverse Flourish)
]]--


return {
    job_id = 19,
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
                blocked_by = 410,  -- Saber Dance
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
                blocked_by = 410,  -- Saber Dance
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
                blocked_by = 410,  -- Saber Dance
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
                blocked_by = 410,  -- Saber Dance
            },
            {
                name = 'Divine Waltz',
                level = 20,
                cost = 400,
                id = 225,
                command = '/ja "Divine Waltz" <me>',
                wakes = true,
                blocked_by = 410,  -- Saber Dance
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Healing Waltz',
                level = 35,
                cost = 200,
                id = 215,
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
                id = 219,
                ability_id = 237,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Saber Dance" <me>',
                buff_id = {410,411},  --  410 Saber Dance overrides Fan Dance
            },
            {
                name = 'Fan Dance',
                level = 75,
                cost = 0,
                id = 224,
                ability_id = 238,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Fan Dance" <me>',
                buff_id = {410,411},  -- 411 Fan Dance overrides Saber Dance 
            },
            {
                name = 'No Foot Rise',
                level = 75,
                cost = 0,
                id = 223,
                ability_id = 239,  -- merit-unlocked: gated on HasAbility
                command = '/ja "No Foot Rise" <me>',
            },
            {
                name = 'Presto',
                level = 75,
                cost = 0,
                id = 236,
                ability_id = 261,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Presto" <me>',
                buff_id = 442,
            },
            {
                name = 'Drain Samba III',
                level = 65,
                cost = 400,
                id = 216,
                command = '/ja "Drain Samba III" <me>',
                buff_id = 368,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Drain Samba II',
                level = 35,
                cost = 250,
                id = 216,
                command = '/ja "Drain Samba II" <me>',
                buff_id = 368,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Drain Samba',
                level = 5,
                cost = 100,
                id = 216,
                command = '/ja "Drain Samba" <me>',
                buff_id = 368,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Aspir Samba II',
                level = 60,
                cost = 250,
                id = 216,
                command = '/ja "Aspir Samba II" <me>',
                buff_id = 369,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Aspir Samba',
                level = 25,
                cost = 100,
                id = 216,
                command = '/ja "Aspir Samba" <me>',
                buff_id = 369,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Haste Samba',
                level = 45,
                cost = 350,
                id = 216,
                command = '/ja "Haste Samba" <me>',
                buff_id = 370,
                group = 'samba',
                blocked_by = 411,  -- Fan Dance
            },
            {
                name = 'Spectral Jig',
                level = 25,
                cost = 0,
                id = 195,
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
                id = 229,
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
