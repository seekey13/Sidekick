--[[
    Scholar job definition
    Defines abilities, validators, and configuration for Scholar automation
    - Healing (Cure spells)
    - Debuff removal (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
    - Buffs (Arts, Addendums, Sublimation, Protect, Shell, Regen, Reraise, Stoneskin, Blink, Aquaveil, Storms, Klimaform, Spikes)
    - MP recovery (Sublimation)
]]--

local common = require('lib.core.common')

return {
    job_id = 20,  -- Scholar
    job_name = 'Scholar',
    resource_type = 'mp',
    
    abilities = {
        -- Job abilities (arts and addendums)
        buff = {
            {
                name = 'Light Arts',
                level = 10,
                cost = 0,
                id = 228,  -- Job ability ID
                command = '/ja "Light Arts" <me>',
                group = 'arts',
                buff_id = {358, 401},  -- Can be either 358 or 401
            },
            {
                name = 'Addendum: White',
                level = 10,
                cost = 0,
                id = 231,  -- Job ability ID
                command = '/ja "Addendum: White" <me>',
                group = 'addendum',
                buff_id = 401,
                requires_buff = 358,  -- Requires Light Arts
            },
            {
                name = 'Dark Arts',
                level = 10,
                cost = 0,
                id = 232,  -- Job ability ID
                command = '/ja "Dark Arts" <me>',
                group = 'arts',
                buff_id = {359, 402},  -- Can be either 359 or 402
            },
            {
                name = 'Addendum: Black',
                level = 30,
                cost = 0,
                id = 235,  -- Job ability ID
                command = '/ja "Addendum: Black" <me>',
                group = 'addendum',
                buff_id = 402,                
                requires_buff = 359,  -- Requires Dark Arts
            },
            {
                name = 'Sublimation',
                level = 30,
                cost = 0,
                id = 234,  -- Job ability ID
                command = '/ja "Sublimation" <me>',
                buff_id = {187, 188},  -- Can be either 187 (activated) or 188 (complete)
            },
            -- Klimaform
            {
                name = 'Klimaform',
                level = 46,
                cost = 30,
                id = 287,  -- Spell ID
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Klimaform" <me>',
                buff_id = 407,  -- Klimaform
                combat_only = true,
            },
            -- Protect line
            {
                name = 'Protect IV',
                level = 66,
                cost = 65,
                id = 46,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect IV" '..target
                end,
                buff_id = 40,  -- Protect
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect III',
                level = 50,
                cost = 46,
                id = 45,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 30,
                cost = 28,
                id = 44,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect',
                level = 10,
                cost = 9,
                id = 43,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            -- Shell line
            {
                name = 'Shell IV',
                level = 71,
                cost = 75,
                id = 51,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell IV" '..target
                end,
                buff_id = 41,  -- Shell
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell III',
                level = 60,
                cost = 56,
                id = 50,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 40,
                cost = 37,
                id = 49,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell',
                level = 20,
                cost = 18,
                id = 48,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Regen III',
                level = 59,
                cost = 64,
                id = 111,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen III" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = true,
                range = 20,
            },
            {
                name = 'Regen II',
                level = 37,
                cost = 36,
                id = 110,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen II" '..target
                end,
                buff_id = 42,
                combat_only = true,
                range = 20,
            },
            {
                name = 'Regen',
                level = 18,
                cost = 15,
                id = 108,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,
                combat_only = true,
                range = 20,
            },
            -- Storms
            {
                name = 'Aurorastorm',
                level = 48,
                cost = 30,
                id = 119,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aurorastorm" <me>',
                buff_id = 184,  -- Aurorastorm
                group = 'storm',
            },
            {
                name = 'Voidstorm',
                level = 47,
                cost = 30,
                id = 118,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Voidstorm" <me>',
                buff_id = 185,  -- Voidstorm
                group = 'storm',
            },
            {
                name = 'Thunderstorm',
                level = 46,
                cost = 30,
                id = 117,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Thunderstorm" <me>',
                buff_id = 182,  -- Thunderstorm
                group = 'storm',
            },
            {
                name = 'Hailstorm',
                level = 45,
                cost = 30,
                id = 116,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Hailstorm" <me>',
                buff_id = 179,  -- Hailstorm
                group = 'storm',
            },
            {
                name = 'Firestorm',
                level = 44,
                cost = 30,
                id = 115,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Firestorm" <me>',
                buff_id = 178,  -- Firestorm
                group = 'storm',
            },
            {
                name = 'Windstorm',
                level = 43,
                cost = 30,
                id = 114,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Windstorm" <me>',
                buff_id = 180,  -- Windstorm
                group = 'storm',
            },
            {
                name = 'Rainstorm',
                level = 42,
                cost = 30,
                id = 113,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Rainstorm" <me>',
                buff_id = 183,  -- Rainstorm
                group = 'storm',
            },
            {
                name = 'Sandstorm',
                level = 41,
                cost = 30,
                id = 112,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Sandstorm" <me>',
                buff_id = 181,  -- Sandstorm
                group = 'storm',
            },
            -- Other buffs
            {
                name = 'Stoneskin',
                level = 44,
                cost = 29,
                id = 54,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
            },
            {
                name = 'Blink',
                level = 30,
                cost = 20,
                id = 53,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
            },
            {
                name = 'Aquaveil',
                level = 13,
                cost = 12,
                id = 55,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
            },
            -- Spikes
            {
                name = 'Shock Spikes',
                level = 70,
                cost = 24,
                id = 251,  -- Spell ID
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Shock Spikes" <me>',
                buff_id = 38,  -- Shock Spikes
                combat_only = true,
                group = 'spikes',
            },
            {
                name = 'Ice Spikes',
                level = 50,
                cost = 16,
                id = 250,  -- Spell ID
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Ice Spikes" <me>',
                buff_id = 35,  -- Ice Spikes
                combat_only = true,
                group = 'spikes',
            },
            {
                name = 'Blaze Spikes',
                level = 30,
                cost = 8,
                id = 249,  -- Spell ID
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,  -- Blaze Spikes
                combat_only = true,
                group = 'spikes',
            },
            {
                name = 'Reraise II',
                level = 70,
                cost = 150,
                id = 142,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise II" <me>',
                range = 20,
                buff_id = 113,
                group = 'reraise',
                requires_buff = 401,  -- Requires Addendum: White
            },
            {
                name = 'Reraise',
                level = 35,
                cost = 150,
                id = 135,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise" <me>',
                range = 20,
                buff_id = 113,
                group = 'reraise',
                requires_buff = 401,  -- Requires Addendum: White
            },
            -- {
            --     name = 'Enlightenment',
            --     level = 75,
            --     cost = 0,
            --     id = 235,  -- Job ability ID
            --     command = '/ja "Enlightenment" <me>',
            --     requires_buff = {359, 402},  -- Can be either 359 or 402
            --     buff_id = 416,
            -- },
            {
                name = 'Invisible',
                level = 25,
                cost = 25,
                id = 136,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Invisible" '..target
                end,
                buff_id = 69,  -- Invisible
                idle_only = true,
            },
            {
                name = 'Sneak',
                level = 20,
                cost = 25,
                id = 137,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Sneak" '..target
                end,
                buff_id = 71,  -- Sneak
                idle_only = true,
            },
            {
                name = 'Deodorize',
                level = 15,
                cost = 6,
                id = 138,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Deodorize" '..target
                end,
                idle_only = true,
                buff_id = 70,  -- Deodorize
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Poisona',
                level = 10,
                cost = 8,
                id = 14,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 3,  -- Poison
                command = function(target)
                    return '/ma "Poisona" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Paralyna',
                level = 12,
                cost = 12,
                id = 15,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 4,  -- Paralysis
                command = function(target)
                    return '/ma "Paralyna" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Blindna',
                level = 17,
                cost = 16,
                id = 16,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 5,  -- Blindness
                command = function(target)
                    return '/ma "Blindna" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Silena',
                level = 22,
                cost = 24,
                id = 17,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 6,  -- Silence
                command = function(target)
                    return '/ma "Silena" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Cursna',
                level = 32,
                cost = 30,
                id = 20,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {9, 15, 20, 30},  -- Curse, Doom & Bane
                command = function(target)
                    return '/ma "Cursna" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Erase',
                level = 39,
                cost = 18,
                id = 143,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {11, 12, 13, 31, 128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404},  -- Bind, Weight, Slow, Plague, Burn, Frost, Choke, Rasp, Dia, Bio, STR Down, DEX Down, VIT Down, AGI Down, INT Down, MND Down, CHR Down, Max HP Down, Max MP Down, Accuracy Down, Attack Down, Evasion Down, Defense Down, Flash, Magic Def Down, Magic Acc Down, Magic Atk Down, Max TP Down, Magic Eva Down
                command = function(target)
                    return '/ma "Erase" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Viruna',
                level = 46,
                cost = 48,
                id = 19,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {8, 31},  -- Disease & Plague
                command = function(target)
                    return '/ma "Viruna" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
            },
            {
                name = 'Stona',
                level = 50,
                cost = 40,
                id = 18,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 7,  -- Petrification
                command = function(target)
                    return '/ma "Stona" '..target
                end,
                range = 20,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
        },
        
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

        -- Recover
        recover_mp = {
            {
                name = 'Sublimation',
                level = 30,
                cost = 0,
                id = 234,  -- Job ability ID
                command = '/ja "Sublimation" <me>',
                requires_buff = {187, 188},  -- Requires Sublimation: Activated or Complete
            },
        },

        -- Critical
        critical = {
            {
                name = 'Tranquility',
                level = 75,
                cost = 0,
                id = 231,  -- Job ability ID
                command = '/ja "Tranquility" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
            },
            {
                name = 'Rapture',
                level = 55,
                cost = 0,
                id = 231,  -- Job ability ID
                command = '/ja "Rapture" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
            },
        },

        -- Revive
        revive = {
            {
                name = 'Raise II',
                level = 70,
                cost = 150,
                id = 141,  -- Spell ID
                command = function(target)
                    return '/ma "Raise II" '..target
                end,
                range = 20,
                idle_only = true,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
            {
                name = 'Raise',
                level = 35,
                cost = 150,
                id = 12,  -- Spell ID
                command = function(target)
                    return '/ma "Raise" '..target
                end,
                range = 20,
                idle_only = true,
                requires_buff = 401,  -- Requires Addendum: White
                target_outside = true,
            },
        },

        -- Stratagem
            stratagem = {
                {
                    name = 'Perpetuance', -- Increases the enhancement effect duration
                    level = 75,
                    cost = 0,
                    id = 316,  -- Job ability ID
                    command = '/ja "Perpetuance" <me>',
                    requires_buff = 401,  -- Addendum: White
                    buff_id = 469,
                    magic = 'white',
                    magic_types = { 'enhancing' },
                },
                {
                    name = 'Tranquility', -- Reduces the Enmity Generated
                    level = 75,
                    cost = 0,
                    id = 231,  -- Job ability ID
                    command = '/ja "Tranquility" <me>',
                    requires_buff = {358, 401},  -- Can be either 358 or 401
                    buff_id = 414,
                    magic = 'white',
                },
                {
                    name = 'Rapture', -- +Potency
                    level = 55,
                    cost = 0,
                    id = 231,  -- Job ability ID
                    command = '/ja "Rapture" <me>',
                    requires_buff = {358, 401},  -- Can be either 358 or 401
                    buff_id = 364,
                    magic = 'white',
                },
                {
                    name = 'Accession',  -- AOE and 3x Cost of spell and 2x casting time
                    level = 40,
                    cost = 0,
                    id = 218,  -- Job ability ID
                    command = '/ja "Accession" <me>',
                    requires_buff = {358, 401},  -- Can be either 358 or 401
                    buff_id = 366,
                    magic = 'white',
                    magic_types = { 'healing', 'enhancing' },
                    mp_modifier = 3.0,
                },
                {
                    name = 'Celerity', -- Reduces the casting time by 50%
                    level = 25,
                    cost = 0,
                    id = 216,  -- Job ability ID
                    command = '/ja "Celerity" <me>',
                    requires_buff = {358, 401},  -- Can be either 358 or 401
                    buff_id = 362,
                    magic = 'white',
                },
                {
                    name = 'Penury', -- Reduces the MP cost by 50%
                    level = 10,
                    cost = 0,
                    id = 215,  -- Job ability ID
                    command = '/ja "Penury" <me>',
                    requires_buff = {358, 401},  -- Can be either 358 or 401
                    buff_id = 360,
                    magic = 'white',
                    mp_modifier = 0.5,
                },
                {
                    name = 'Alacrity', -- Reduces the casting time by 50%
                    level = 25,
                    cost = 0,
                    id = 217,  -- Job ability ID
                    command = '/ja "Alacrity" <me>',
                    requires_buff = {359, 402},  -- Can be either 359 or 402
                    buff_id = 363,
                    magic = 'black',
                },
                {
                    name = 'Parsimony', -- Reduces the MP cost by 50%
                    level = 10,
                    cost = 0,
                    id = 217,  -- Job ability ID
                    command = '/ja "Parsimony" <me>',
                    requires_buff = {359, 402},  -- Can be either 359 or 402
                    buff_id = 361,
                    magic = 'black',
                    mp_modifier = 0.5,
                },
            },
    },
    
    -- Job-specific validators
    validators = {},
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        critical_threshold = 30,
        heal_aoe_enabled = false,  -- Scholar has no AOE heal
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        recover_enabled = true,
        recover_threshold = 50,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = true,
        debuff_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
        rest_distance = 7,
        revive_enabled = true,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'critical',
        'heal',
        'debuff_removal',
        'wake',
        'revive',
        'buff',
        'rest',
    },
}