--[[
    Red Mage job definition
    Defines abilities, validators, and configuration for Red Mage automation
    - Healing (Cure spells)
    - Buffs (Haste, Refresh, Regen, Protect, Shell, Phalanx, Aquaveil, Blink, Stoneskin, Enspells)
    - MP recovery (Convert)
]]--

local common = require('lib.core.common')

return {
    job_id = 5,  -- Red Mage
    job_name = 'Red Mage',
    resource_type = 'mp',
    
    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Cure IV',
                level = 48,
                cost = 88,
                id = 4,  -- Spell ID
                command = function(target)
                    return '/ma "Cure IV" '..target
                end,
                range = 20,
                value = 400,
                wakes = true,
            },
            {
                name = 'Cure III',
                level = 26,
                cost = 46,
                id = 3,  -- Spell ID
                command = function(target)
                    return '/ma "Cure III" '..target
                end,
                range = 20,
                value = 200,
                wakes = true,
            },
            {
                name = 'Cure II',
                level = 14,
                cost = 24,
                id = 2,  -- Spell ID
                command = function(target)
                    return '/ma "Cure II" '..target
                end,
                range = 20,
                value = 90,
                wakes = true,
            },
            {
                name = 'Cure',
                level = 3,
                cost = 8,
                id = 1,  -- Spell ID
                command = function(target)
                    return '/ma "Cure" '..target
                end,
                range = 20,
                value = 30,
                wakes = true,
            },
        },
        
        -- Buffs (Enhancing magic)
        buff = {
            -- Job Abilities
            {
                name = 'Composure',
                level = 50,
                cost = 0,
                id = 247,  -- Job Ability ID
                command = '/ja "Composure" <me>',
                buff_id = 419,  -- Composure
                combat_only = true,
            },
            -- Protect line
            {
                name = 'Protect IV',
                level = 63,
                cost = 65,
                id = 46,  -- Spell ID
                command = function(target)
                    return '/ma "Protect IV" '..target
                end,
                buff_id = 40,  -- Protect
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protect III',
                level = 47,
                cost = 46,
                id = 45,  -- Spell ID
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protect II',
                level = 27,
                cost = 28,
                id = 44,  -- Spell ID
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protect',
                level = 7,
                cost = 9,
                id = 43,  -- Spell ID
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            -- Shell line
            {
                name = 'Shell IV',
                level = 68,
                cost = 71,
                id = 51,  -- Spell ID
                command = function(target)
                    return '/ma "Shell IV" '..target
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shell III',
                level = 57,
                cost = 56,
                id = 50,  -- Spell ID
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shell II',
                level = 37,
                cost = 37,
                id = 49,  -- Spell ID
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shell',
                level = 17,
                cost = 18,
                id = 48,  -- Spell ID
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            -- Other buffs
            {
                name = 'Phalanx II',
                level = 75,
                cost = 21,
                id = 107,  -- Spell ID
                command = function(target)
                    return '/ma "Phalanx II" '..target
                end,
                buff_id = 116,  -- Phalanx
                combat_only = false,
            },
            {
                name = 'Regen',
                level = 21,
                cost = 15,
                id = 108,  -- Spell ID
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = false,
            },
            {
                name = 'Refresh',
                level = 41,
                cost = 40,
                id = 109,  -- Spell ID
                command = function(target)
                    return '/ma "Refresh" '..target
                end,
                buff_id = 43,  -- Refresh
                combat_only = false,
            },
            {
                name = 'Haste',
                level = 48,
                cost = 40,
                id = 57,  -- Spell ID
                command = function(target)
                    return '/ma "Haste" '..target
                end,
                buff_id = 33,  -- Haste
                
            },
            {
                name = 'Flurry',
                level = 48,
                cost = 40,
                id = 58,  -- Spell ID
                command = function(target)
                    return '/ma "Flurry" '..target
                end,
                buff_id = 265,  -- Flurry
                
            },
            {
                name = 'Stoneskin',
                level = 34,
                cost = 29,
                id = 54,  -- Spell ID
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
            },
            {
                name = 'Phalanx',
                level = 33,
                cost = 21,
                id = 106,  -- Spell ID
                command = '/ma "Phalanx" <me>',
                buff_id = 116,  -- Phalanx
            },
            {
                name = 'Blink',
                level = 23,
                cost = 20,
                id = 53,  -- Spell ID
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
            },
            {
                name = 'Aquaveil',
                level = 12,
                cost = 12,
                id = 55,  -- Spell ID
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
            },
            -- Enspells (grouped by element)
            {
                name = 'Enwater II',
                level = 60,
                cost = 12,
                id = 105,  -- Spell ID
                command = '/ma "Enwater II" <me>',
                buff_id = 282,  -- Enwater
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enwater',
                level = 27,
                cost = 12,
                id = 94,  -- Spell ID
                command = '/ma "Enwater" <me>',
                buff_id = 99,  -- Enwater
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enfire II',
                level = 58,
                cost = 12,
                id = 104,  -- Spell ID
                command = '/ma "Enfire II" <me>',
                buff_id = 277,  -- Enfire
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enfire',
                level = 24,
                cost = 12,
                id = 93,  -- Spell ID
                command = '/ma "Enfire" <me>',
                buff_id = 94,  -- Enfire
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enblizzard II',
                level = 56,
                cost = 12,
                id = 103,  -- Spell ID
                command = '/ma "Enblizzard II" <me>',
                buff_id = 278,  -- Enblizzard
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enblizzard',
                level = 22,
                cost = 12,
                id = 92,  -- Spell ID
                command = '/ma "Enblizzard" <me>',
                buff_id = 95,  -- Enblizzard
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enaero II',
                level = 54,
                cost = 12,
                id = 102,  -- Spell ID
                command = '/ma "Enaero II" <me>',
                buff_id = 279,  -- Enaero
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enaero',
                level = 20,
                cost = 12,
                id = 91,  -- Spell ID
                command = '/ma "Enaero" <me>',
                buff_id = 96,  -- Enaero
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enstone II',
                level = 52,
                cost = 12,
                id = 101,  -- Spell ID
                command = '/ma "Enstone II" <me>',
                buff_id = 280,  -- Enstone
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enstone',
                level = 18,
                cost = 12,
                id = 90,  -- Spell ID
                command = '/ma "Enstone" <me>',
                buff_id = 97,  -- Enstone
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enthunder II',
                level = 50,
                cost = 12,
                id = 100,  -- Spell ID
                command = '/ma "Enthunder II" <me>',
                buff_id = 281,  -- Enthunder
                combat_only = true,
                group = 'enspell',
            },
            {
                name = 'Enthunder',
                level = 16,
                cost = 12,
                id = 89,  -- Spell ID
                command = '/ma "Enthunder" <me>',
                buff_id = 98,  -- Enthunder
                combat_only = true,
                group = 'enspell',
            },
            -- Spikes (sorted by level, highest first)
            {
                name = 'Shock Spikes',
                level = 60,
                cost = 16,
                id = 251,  -- Spell ID
                command = '/ma "Shock Spikes" <me>',
                buff_id = 38,  -- Shock Spikes
                combat_only = true,
                group = 'spikes'
            },
            {
                name = 'Ice Spikes',
                level = 40,
                cost = 16,
                id = 250,  -- Spell ID
                command = '/ma "Ice Spikes" <me>',
                buff_id = 35,  -- Ice Spikes
                combat_only = true,
                group = 'spikes'
            },
            {
                name = 'Blaze Spikes',
                level = 20,
                cost = 16,
                id = 249,  -- Spell ID
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,  -- Blaze Spikes
                combat_only = true,
                group = 'spikes'
            },
            {
                name = 'Invisible',
                level = 25,
                cost = 25,
                id = 65,  -- Spell ID
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
                id = 64,  -- Spell ID
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
                id = 61,  -- Spell ID
                command = function(target)
                    return '/ma "Deodorize" '..target
                end,
                buff_id = 70,  -- Deodorize
                idle_only = true,
            },
        },

        -- Recover MP
        recover_mp = {
            {
                name = 'Convert',
                level = 40,
                cost = 0,
                id = 49,  -- Job ability
                command = '/ja "Convert" <me>',
            },
        }

        -- Revive
        -- revive = {
        --     {
        --         name = 'Raise',
        --         level = 38,
        --         cost = 150,
        --         id = 12,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Raise" <p' .. party_index .. '>'
        --         end,
        --         range = 18,
        --         combat_only = false,
        --     },
        -- },
    },
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = false,  -- Red Mage has no AOE heal
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = false,  -- Red Mage has no debuff removal in the spell list
        recover_enabled = true,
        recover_threshold = 20,  -- Use Convert when MP drops below 20%
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
    },
    
    -- Action priority order
    priority_order = {
        'heal',
        'wake',
        'recover',
        'buff',
        -- revive,
    },
}
