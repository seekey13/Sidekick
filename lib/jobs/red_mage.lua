--[[
    Red Mage job definition
    Defines abilities, validators, and configuration for Red Mage automation
    
    Red Mage is a hybrid job that combines:
    - Healing magic (weaker than White Mage)
    - Enfeebling magic (debuffs)
    - Enhancing magic (buffs)
    - Elemental magic (nukes, weaker than Black Mage)
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
                command = function(party_index)
                    return '/ma "Cure IV" <p' .. party_index .. '>'
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
                command = function(party_index)
                    return '/ma "Cure III" <p' .. party_index .. '>'
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
                command = function(party_index)
                    return '/ma "Cure II" <p' .. party_index .. '>'
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
                command = function(party_index)
                    return '/ma "Cure" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 30,
                wakes = true,
            },
        },
        
        -- Buffs (Enhancing magic)
        buff = {
            -- Protect line
            {
                name = 'Protect IV',
                level = 63,
                cost = 65,
                id = 46,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect IV" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect
                combat_only = false,
            },
            {
                name = 'Protect III',
                level = 47,
                cost = 46,
                id = 45,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect III" <p' .. party_index .. '>'
                end,
                buff_id = 40,
                combat_only = false,
            },
            {
                name = 'Protect II',
                level = 27,
                cost = 28,
                id = 44,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect II" <p' .. party_index .. '>'
                end,
                buff_id = 40,
                combat_only = false,
            },
            {
                name = 'Protect',
                level = 7,
                cost = 9,
                id = 43,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect" <p' .. party_index .. '>'
                end,
                buff_id = 40,
                combat_only = false,
            },
            -- Shell line
            {
                name = 'Shell IV',
                level = 68,
                cost = 71,
                id = 51,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell IV" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
            },
            {
                name = 'Shell III',
                level = 57,
                cost = 56,
                id = 50,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell III" <p' .. party_index .. '>'
                end,
                buff_id = 41,
                combat_only = false,
            },
            {
                name = 'Shell II',
                level = 37,
                cost = 37,
                id = 49,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell II" <p' .. party_index .. '>'
                end,
                buff_id = 41,
                combat_only = false,
            },
            {
                name = 'Shell',
                level = 17,
                cost = 18,
                id = 48,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell" <p' .. party_index .. '>'
                end,
                buff_id = 41,
                combat_only = false,
            },
            -- Other buffs
            {
                name = 'Phalanx II',
                level = 75,
                cost = 21,
                id = 107,  -- Spell ID
                command = function(party_index)
                    return '/ma "Phalanx II" <p' .. party_index .. '>'
                end,
                buff_id = 116,  -- Phalanx
                combat_only = true,
            },
            {
                name = 'Haste',
                level = 48,
                cost = 40,
                id = 57,  -- Spell ID
                command = function(party_index)
                    return '/ma "Haste" <p' .. party_index .. '>'
                end,
                buff_id = 33,  -- Haste
                combat_only = true,
            },
            {
                name = 'Flurry',
                level = 48,
                cost = 40,
                id = 58,  -- Spell ID
                command = function(party_index)
                    return '/ma "Flurry" <p' .. party_index .. '>'
                end,
                buff_id = 265,  -- Flurry
                combat_only = true,
            },
            {
                name = 'Refresh',
                level = 41,
                cost = 40,
                id = 109,  -- Spell ID
                command = function(party_index)
                    return '/ma "Refresh" <p' .. party_index .. '>'
                end,
                buff_id = 43,  -- Refresh
                combat_only = false,
            },
            {
                name = 'Stoneskin',
                level = 34,
                cost = 29,
                id = 54,  -- Spell ID
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
                combat_only = true,
            },
            {
                name = 'Phalanx',
                level = 33,
                cost = 21,
                id = 106,  -- Spell ID
                command = '/ma "Phalanx" <me>',
                buff_id = 116,  -- Phalanx
                combat_only = true,
            },
            {
                name = 'Blink',
                level = 23,
                cost = 20,
                id = 53,  -- Spell ID
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
                combat_only = true,
            },
            {
                name = 'Regen',
                level = 21,
                cost = 15,
                id = 108,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen" <p' .. party_index .. '>'
                end,
                buff_id = 42,  -- Regen
                combat_only = false,
            },
            {
                name = 'Aquaveil',
                level = 12,
                cost = 12,
                id = 55,  -- Spell ID
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
                combat_only = true,
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
        },

        -- Recover MP
        recover = {
            {
                name = 'Convert',
                level = 40,
                cost = 0,
                id = 49,  -- Job ability
                command = '/ja "Convert" <me>',
            },
        }
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
    },
}
