--[[
    Dancer job definition
    Defines abilities, validators, and configuration for Dancer automation
    - Healing (Curing Waltz, Divine Waltz)
    - Debuff removal (Healing Waltz)
    - Buffs (Drain, Aspir, Haste Samba, and Spectral Jig)
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
                command = function(party_index)
                    return '/ja "Curing Waltz III" <p' .. party_index .. '>'
                end,
                wakes = true,
                value = 300,
            },
            {
                name = 'Curing Waltz II',
                level = 30,
                cost = 350,
                id = 186,
                command = function(party_index)
                    return '/ja "Curing Waltz II" <p' .. party_index .. '>'
                end,
                wakes = true,
                value = 140,
            },
            {
                name = 'Curing Waltz',
                level = 15,
                cost = 200,
                id = 217,
                command = function(party_index)
                    return '/ja "Curing Waltz" <p' .. party_index .. '>'
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
                command = function(party_index)
                    return '/ja "Healing Waltz" <p' .. party_index .. '>'
                end,
            },
        },
        
        -- Buffs
        buff = {
            {
                name = 'Drain Samba III',
                level = 65,
                cost = 400,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba III" <me>',
                buff_id = 368,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Drain Samba II',
                level = 35,
                cost = 250,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba II" <me>',
                buff_id = 368,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Drain Samba',
                level = 5,
                cost = 100,
                id = 216,  -- Samba recast ID
                command = '/ja "Drain Samba" <me>',
                buff_id = 368,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Aspir Samba II',
                level = 60,
                cost = 250,
                id = 216,
                command = '/ja "Aspir Samba II" <me>',
                buff_id = 369,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Aspir Samba',
                level = 25,
                cost = 100,
                id = 216,
                command = '/ja "Aspir Samba" <me>',
                buff_id = 369,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Haste Samba',
                level = 45,
                cost = 350,
                id = 216,
                command = '/ja "Haste Samba" <me>',
                buff_id = 193,
                combat_only = true,
                group = 'samba',
            },
            {
                name = 'Spectral Jig',
                level = 25,
                cost = 0,
                id = 195,  -- Jig recast ID
                command = '/ja "Spectral Jig" <me>',
                idle_only = true,
                -- Custom check for Sneak (71) OR Invisible (69)
                check_buff = function()
                    local buffs = common.get_player_buffs()
                    for _, buff_id in ipairs(buffs) do
                        if buff_id == 71 or buff_id == 69 then
                            return true
                        end
                    end
                    return false
                end,
            },
        },

        -- Recover
        recover_tp = {
            {
                name = 'Reverse Flourish',
                level = 40,
                cost = 5,
                id = 222,
                command = '/ja "Reverse Flourish" <me>',
                wakes = false,
                combat_only = true,
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
        'heal_aoe',
        'heal',
        'debuff_removal',
        'wake',
        'buff',
    },
}
