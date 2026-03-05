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
                target_outside = true,
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
                target_outside = true,
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
                target_outside = true,
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
                target_outside = true,
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
                engaged_only = true,
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
                group = 'protect',
                target_outside = true,
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
                group = 'protect',
                target_outside = true,
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
                group = 'protect',
                target_outside = true,
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
                group = 'protect',
                target_outside = true,
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
                group = 'shell',
                target_outside = true,
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
                group = 'shell',
                target_outside = true,
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
                group = 'shell',
                target_outside = true,
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
                group = 'shell',
                target_outside = true,
            },
            -- Barelement
            {
                name = 'Barstone',
                level = 5,
                cost = 6,
                id = 60,
                command = '/ma "Barstone" <me>',
                element = 'Wind',
                buff_id = 102,  -- Barstone buff
                group = 'barelement',
            },
            {
                name = 'Barwater',
                level = 9,
                cost = 6,
                id = 62,
                command = '/ma "Barwater" <me>',
                element = 'Thunder',
                buff_id = 104,  -- Barwater buff
                group = 'barelement',
            },
            {
                name = 'Baraero',
                level = 13,
                cost = 6,
                id = 65,
                command = '/ma "Baraero" <me>',
                element = 'Ice',
                buff_id = 107,  -- Baraero buff
                group = 'barelement',
            },
            {
                name = 'Barfire',
                level = 17,
                cost = 6,
                id = 66,
                command = '/ma "Barfire" <me>',
                element = 'Water',
                buff_id = 108,  -- Barfire buff
                group = 'barelement',
            },
            {
                name = 'Barblizzard',
                level = 21,
                cost = 6,
                id = 68,
                command = '/ma "Barblizzard" <me>',
                element = 'Fire',
                buff_id = 110,  -- Barblizzard buff
                group = 'barelement',
            },
            {
                name = 'Barthunder',
                level = 25,
                cost = 6,
                id = 70,
                command = '/ma "Barthunder" <me>',
                element = 'Earth',
                buff_id = 112,  -- Barthunder buff
                group = 'barelement',
            },
            -- Barstatus
            {
                name = 'Barsleep',
                level = 7,
                cost = 7,
                id = 61,
                command = '/ma "Barsleep" <me>',
                element = 'Light',
                buff_id = 103,  -- Barsleep buff
                group = 'barstatus',
            },
            {
                name = 'Barpoison',
                level = 10,
                cost = 9,
                id = 63,
                command = '/ma "Barpoison" <me>',
                element = 'Thunder',
                buff_id = 105,  -- Barpoison buff
                group = 'barstatus',
            },
            {
                name = 'Barparalyze',
                level = 12,
                cost = 11,
                id = 64,
                command = '/ma "Barparalyze" <me>',
                element = 'Fire',
                buff_id = 106,  -- Barparalyze buff
                group = 'barstatus',
            },
            {
                name = 'Barblind',
                level = 18,
                cost = 13,
                id = 67,
                command = '/ma "Barblind" <me>',
                element = 'Light',
                buff_id = 109,  -- Barblind buff
                group = 'barstatus',
            },
            {
                name = 'Barsilence',
                level = 23,
                cost = 15,
                id = 69,
                command = '/ma "Barsilence" <me>',
                element = 'Ice',
                buff_id = 111,  -- Barsilence buff
                group = 'barstatus',
            },
            {
                name = 'Barvirus',
                level = 39,
                cost = 25,
                id = 71,
                command = '/ma "Barvirus" <me>',
                element = 'Water',
                buff_id = 113,  -- Barvirus buff
                group = 'barstatus',
            },
            {
                name = 'Barpetrify',
                level = 43,
                cost = 20,
                id = 72,
                command = '/ma "Barpetrify" <me>',
                element = 'Wind',
                buff_id = 114,  -- Barpetrify buff
                group = 'barstatus',
            },
            {
                name = 'Baramnesia',
                level = 65,
                cost = 30,
                id = 73,
                command = '/ma "Baramnesia" <me>',
                element = 'Water',
                buff_id = 115,  -- Baramnesia buff
                group = 'barstatus',
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
                combat_only = true,
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
                combat_only = true,
                target_outside = true,
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
                combat_only = true,
                target_outside = true,
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
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enwater',
                level = 27,
                cost = 12,
                id = 94,  -- Spell ID
                command = '/ma "Enwater" <me>',
                buff_id = 99,  -- Enwater
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enfire II',
                level = 58,
                cost = 12,
                id = 104,  -- Spell ID
                command = '/ma "Enfire II" <me>',
                buff_id = 277,  -- Enfire
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enfire',
                level = 24,
                cost = 12,
                id = 93,  -- Spell ID
                command = '/ma "Enfire" <me>',
                buff_id = 94,  -- Enfire
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enblizzard II',
                level = 56,
                cost = 12,
                id = 103,  -- Spell ID
                command = '/ma "Enblizzard II" <me>',
                buff_id = 278,  -- Enblizzard
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enblizzard',
                level = 22,
                cost = 12,
                id = 92,  -- Spell ID
                command = '/ma "Enblizzard" <me>',
                buff_id = 95,  -- Enblizzard
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enaero II',
                level = 54,
                cost = 12,
                id = 102,  -- Spell ID
                command = '/ma "Enaero II" <me>',
                buff_id = 279,  -- Enaero
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enaero',
                level = 20,
                cost = 12,
                id = 91,  -- Spell ID
                command = '/ma "Enaero" <me>',
                buff_id = 96,  -- Enaero
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enstone II',
                level = 52,
                cost = 12,
                id = 101,  -- Spell ID
                command = '/ma "Enstone II" <me>',
                buff_id = 280,  -- Enstone
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enstone',
                level = 18,
                cost = 12,
                id = 90,  -- Spell ID
                command = '/ma "Enstone" <me>',
                buff_id = 97,  -- Enstone
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enthunder II',
                level = 50,
                cost = 12,
                id = 100,  -- Spell ID
                command = '/ma "Enthunder II" <me>',
                buff_id = 281,  -- Enthunder
                engaged_only = true,
                group = 'enspell',
            },
            {
                name = 'Enthunder',
                level = 16,
                cost = 12,
                id = 89,  -- Spell ID
                command = '/ma "Enthunder" <me>',
                buff_id = 98,  -- Enthunder
                engaged_only = true,
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
                engaged_only = true,
                group = 'spikes'
            },
            {
                name = 'Ice Spikes',
                level = 40,
                cost = 16,
                id = 250,  -- Spell ID
                command = '/ma "Ice Spikes" <me>',
                buff_id = 35,  -- Ice Spikes
                engaged_only = true,
                group = 'spikes'
            },
            {
                name = 'Blaze Spikes',
                level = 20,
                cost = 16,
                id = 249,  -- Spell ID
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,  -- Blaze Spikes
                engaged_only = true,
                group = 'spikes'
            },
            {
                name = 'Invisible',
                level = 25,
                cost = 25,
                id = 136,  -- Spell ID
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
                command = function(target)
                    return '/ma "Deodorize" '..target
                end,
                idle_only = true,
                buff_id = 70,  -- Deodorize
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
        },

        -- Revive
        revive = {
            {
                name = 'Raise',
                level = 38,
                cost = 150,
                id = 12,  -- Spell ID
                command = function(target)
                    return '/ma "Raise" '..target
                end,
                range = 18,
                idle_only = true,
                target_outside = true,
            },
        },
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
        'heal',
        'wake',
        'revive',
        'buff',
        'rest',
    },
}
