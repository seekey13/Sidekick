--[[
    Rune Fencer job definition
    Defines abilities, validators, and configuration for Rune Fencer automation
    - Buffs (Protect, Shell, bar spells, Regen, Refresh, Spikes, Aquaveil, Blink, Stoneskin, Foil, Phalanx, job abilities)
    - Healing (Vivacious Pulse)
]]--

local common = require('lib.core.common')

return {
    job_id = 22,  -- Rune Fencer
    job_name = 'Rune Fencer',
    resource_type = 'mp',
    
    abilities = {
        
        -- Buffs (Protect, Shell, bar spells, etc.)
        buff = {
            -- Protect spells
            {
                name = 'Protect',
                level = 20,
                cost = 15,
                id = 46,
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                element = 'Light',
                buff_id = 17,  -- Protect buff
                group = 'protect',
            },
            {
                name = 'Protect II',
                level = 40,
                cost = 21,
                id = 47,
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                element = 'Light',
                buff_id = 40,  -- Protect II buff
                group = 'protect',
            },
            {
                name = 'Protect III',
                level = 60,
                cost = 27,
                id = 129,
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Protect III buff
                group = 'protect',
            },
            -- Shell spells
            {
                name = 'Shell',
                level = 10,
                cost = 18,
                id = 48,
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell buff
                group = 'shell',
            },
            {
                name = 'Shell II',
                level = 30,
                cost = 24,
                id = 49,
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell II buff
                group = 'shell',
            },
            {
                name = 'Shell III',
                level = 50,
                cost = 30,
                id = 50,
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell III buff
                group = 'shell',
            },
            {
                name = 'Shell IV',
                level = 70,
                cost = 36,
                id = 52,
                command = function(target)
                    return '/ma "Shell IV" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell IV buff
                group = 'shell',
            },
            -- Barelement
            {
                name = 'Barstone',
                level = 4,
                cost = 5,
                id = 60,
                command = function(target)
                    return '/ma "Barstone" '..target
                end,
                element = 'Wind',
                buff_id = 102,  -- Barstone buff
                group = 'barelement',
            },
            {
                name = 'Barwater',
                level = 8,
                cost = 7,
                id = 62,
                command = function(target)
                    return '/ma "Barwater" '..target
                end,
                element = 'Thunder',
                buff_id = 104,  -- Barwater buff
                group = 'barelement',
            },
            {
                name = 'Baraero',
                level = 12,
                cost = 10,
                id = 65,
                command = function(target)
                    return '/ma "Baraero" '..target
                end,
                element = 'Ice',
                buff_id = 107,  -- Baraero buff
                group = 'barelement',
            },
            {
                name = 'Barfire',
                level = 16,
                cost = 11,
                id = 66,
                command = function(target)
                    return '/ma "Barfire" '..target
                end,
                element = 'Water',
                buff_id = 108,  -- Barfire buff
                group = 'barelement',
            },
            {
                name = 'Barblizzard',
                level = 20,
                cost = 13,
                id = 68,
                command = function(target)
                    return '/ma "Barblizzard" '..target
                end,
                element = 'Fire',
                buff_id = 110,  -- Barblizzard buff
                group = 'barelement',
            },
            {
                name = 'Barthunder',
                level = 24,
                cost = 15,
                id = 70,
                command = function(target)
                    return '/ma "Barthunder" '..target
                end,
                element = 'Earth',
                buff_id = 112,  -- Barthunder buff
                group = 'barelement',
            },
            -- Barstatus
            {
                name = 'Barsleep',
                level = 6,
                cost = 6,
                id = 61,
                command = function(target)
                    return '/ma "Barsleep" '..target
                end,
                element = 'Light',
                buff_id = 103,  -- Barsleep buff
                group = 'barstatus',
            },
            {
                name = 'Barpoison',
                level = 9,
                cost = 8,
                id = 63,
                command = function(target)
                    return '/ma "Barpoison" '..target
                end,
                element = 'Thunder',
                buff_id = 105,  -- Barpoison buff
                group = 'barstatus',
            },
            {
                name = 'Barparalyze',
                level = 11,
                cost = 9,
                id = 64,
                command = function(target)
                    return '/ma "Barparalyze" '..target
                end,
                element = 'Fire',
                buff_id = 106,  -- Barparalyze buff
                group = 'barstatus',
            },
            {
                name = 'Barblind',
                level = 17,
                cost = 12,
                id = 67,
                command = function(target)
                    return '/ma "Barblind" '..target
                end,
                element = 'Light',
                buff_id = 109,  -- Barblind buff
                group = 'barstatus',
            },
            {
                name = 'Barsilence',
                level = 22,
                cost = 14,
                id = 69,
                command = function(target)
                    return '/ma "Barsilence" '..target
                end,
                element = 'Ice',
                buff_id = 111,  -- Barsilence buff
                group = 'barstatus',
            },
            {
                name = 'Barvirus',
                level = 38,
                cost = 16,
                id = 71,
                command = function(target)
                    return '/ma "Barvirus" '..target
                end,
                element = 'Water',
                buff_id = 113,  -- Barvirus buff
                group = 'barstatus',
            },
            {
                name = 'Barpetrify',
                level = 42,
                cost = 17,
                id = 72,
                command = function(target)
                    return '/ma "Barpetrify" '..target
                end,
                element = 'Wind',
                buff_id = 114,  -- Barpetrify buff
                group = 'barstatus',
            },
            {
                name = 'Baramnesia',
                level = 63,
                cost = 18,
                id = 73,
                command = function(target)
                    return '/ma "Baramnesia" '..target
                end,
                element = 'Water',
                buff_id = 115,  -- Baramnesia buff
                group = 'barstatus',
            },
            -- Regen
            {
                name = 'Regen',
                level = 23,
                cost = 15,
                id = 108,  -- Spell ID
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = true,
            },
            {
                name = 'Regen II',
                level = 48,
                cost = 24,
                id = 110,
                command = function(target)
                    return '/ma "Regen II" '..target
                end,
                element = 'Light',
                buff_id = 84,  -- Regen II buff
                combat_only = true,
            },
            {
                name = 'Regen III',
                level = 70,
                cost = 36,
                id = 111,
                command = function(target)
                    return '/ma "Regen III" '..target
                end,
                element = 'Light',
                buff_id = 121,  -- Regen III buff
                combat_only = true,
            },
            -- Refresh
            {
                name = 'Refresh',
                level = 62,
                cost = 40,
                id = 109,
                command = function(target)
                    return '/ma "Refresh" '..target
                end,
                element = 'Light',
                buff_id = 43,  -- Refresh buff
            },
            {
                name = 'Foil',
                level = 58,
                cost = 10,
                id = 840,
                command = '/ma "Foil" <me>',
                element = 'Wind',
                buff_id = 480,  -- Foil buff
                engaged_only = true,
            },
            {
                name = 'Swordplay',
                level = 20,
                cost = 0,
                id = 24,  -- Swordplay recast ID
                command = '/ja "Swordplay" <me>',
                buff_id = 475,  -- Swordplay buff
                engaged_only = true,
            },
            {
                name = 'Phalanx',
                level = 68,
                cost = 21,
                id = 106,
                command = '/ma "Phalanx" <me>',
                element = 'Light',
                buff_id = 116,  -- Phalanx buff
                combat_only = true,
            },
            -- Spikes
            {
                name = 'Blaze Spikes',
                level = 45,
                cost = 16,
                id = 34,
                command = '/ma "Blaze Spikes" <me>',
                element = 'Fire',
                buff_id = 35,  -- Blaze Spikes buff
                group = 'spikes',
                engaged_only = true,
            },
            {
                name = 'Ice Spikes',
                level = 65,
                cost = 16,
                id = 250,
                command = '/ma "Ice Spikes" <me>',
                element = 'Ice',
                buff_id = 42,  -- Ice Spikes buff
                group = 'spikes',
                engaged_only = true,
            },
            -- Everything else
            {
                name = 'Aquaveil',
                level = 15,
                cost = 14,
                id = 55,
                command = '/ma "Aquaveil" <me>',
                element = 'Water',
                buff_id = 39,  -- Aquaveil buff
            },
            {
                name = 'Blink',
                level = 35,
                cost = 20,
                id = 53,
                command = '/ma "Blink" <me>',
                element = 'Wind',
                buff_id = 36,  -- Blink buff
            },
            {
                name = 'Stoneskin',
                level = 55,
                cost = 29,
                id = 54,
                command = '/ma "Stoneskin" <me>',
                element = 'Earth',
                buff_id = 37,  -- Stoneskin buff
            },
        },
        
        -- Healing
        heal = {
            {
                name = 'Vivacious Pulse',
                level = 65,
                cost = 0,
                id = 30,  -- Vivacious Pulse recast ID
                command = '/ja "Vivacious Pulse" <me>',
                self_only = true,
            },
        },
    },
    
    -- Job-specific validators
    validators = {},
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = false,  -- Rune Fencer has no AOE heal
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = false,
        buff_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
        rest_distance = 7,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'heal',
        'buff',
        'rest',
    },
}