--[[
    Rune Fencer job definition
    Defines abilities, validators, and configuration for Rune Fencer automation
    - Buffs (Protect, Shell, bar spells, Regen, Refresh, Spikes, Aquaveil, Blink, Stoneskin, Foil, Phalanx, job abilities)
    - Healing (Vivacious Pulse)
]]--


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
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                element = 'Light',
                buff_id = 40,  -- Protect buff
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 40,
                cost = 21,
                id = 47,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                element = 'Light',
                buff_id = 40,  -- Protect II buff
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect III',
                level = 60,
                cost = 27,
                id = 129,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                element = 'Light',
                buff_id = 40,  -- Protect III buff
                group = 'protect',
                target_outside = true,
            },
            -- Shell spells
            {
                name = 'Shell',
                level = 10,
                cost = 18,
                id = 48,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell buff
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 30,
                cost = 24,
                id = 49,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell II buff
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell III',
                level = 50,
                cost = 30,
                id = 50,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell III buff
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell IV',
                level = 70,
                cost = 36,
                id = 52,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell IV" '..target
                end,
                element = 'Light',
                buff_id = 41,  -- Shell IV buff
                group = 'shell',
                target_outside = true,
            },
            -- Barelement
            {
                name = 'Barstone',
                level = 4,
                cost = 6,
                id = 60,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barstone" <me>',
                element = 'Wind',
                buff_id = 103,  -- Barstone buff
                group = 'barelement',
            },
            {
                name = 'Barwater',
                level = 8,
                cost = 6,
                id = 62,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barwater" <me>',
                element = 'Thunder',
                buff_id = 105,  -- Barwater buff
                group = 'barelement',
            },
            {
                name = 'Baraero',
                level = 12,
                cost = 6,
                id = 65,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Baraero" <me>',
                element = 'Ice',
                buff_id = 102,  -- Baraero buff
                group = 'barelement',
            },
            {
                name = 'Barfire',
                level = 16,
                cost = 6,
                id = 66,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barfire" <me>',
                element = 'Water',
                buff_id = 100,  -- Barfire buff
                group = 'barelement',
            },
            {
                name = 'Barblizzard',
                level = 20,
                cost = 6,
                id = 68,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barblizzard" <me>',
                element = 'Fire',
                buff_id = 101,  -- Barblizzard buff
                group = 'barelement',
            },
            {
                name = 'Barthunder',
                level = 24,
                cost = 6,
                id = 70,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barthunder" <me>',
                element = 'Earth',
                buff_id = 104,  -- Barthunder buff
                group = 'barelement',
            },
            -- Barstatus
            {
                name = 'Barsleep',
                level = 6,
                cost = 7,
                id = 61,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barsleep" <me>',
                element = 'Light',
                buff_id = 106,  -- Barsleep buff
                group = 'barstatus',
            },
            {
                name = 'Barpoison',
                level = 9,
                cost = 9,
                id = 63,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barpoison" <me>',
                element = 'Thunder',
                buff_id = 107,  -- Barpoison buff
                group = 'barstatus',
            },
            {
                name = 'Barparalyze',
                level = 11,
                cost = 11,
                id = 64,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barparalyze" <me>',
                element = 'Fire',
                buff_id = 108,  -- Barparalyze buff
                group = 'barstatus',
            },
            {
                name = 'Barblind',
                level = 17,
                cost = 13,
                id = 67,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barblind" <me>',
                element = 'Light',
                buff_id = 109,  -- Barblind buff
                group = 'barstatus',
            },
            {
                name = 'Barsilence',
                level = 22,
                cost = 15,
                id = 69,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barsilence" <me>',
                element = 'Ice',
                buff_id = 110,  -- Barsilence buff
                group = 'barstatus',
            },
            {
                name = 'Barvirus',
                level = 38,
                cost = 25,
                id = 71,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barvirus" <me>',
                element = 'Water',
                buff_id = 112,  -- Barvirus buff
                group = 'barstatus',
            },
            {
                name = 'Barpetrify',
                level = 42,
                cost = 20,
                id = 72,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barpetrify" <me>',
                element = 'Wind',
                buff_id = 111,  -- Barpetrify buff
                group = 'barstatus',
            },
            {
                name = 'Baramnesia',
                level = 63,
                cost = 30,
                id = 73,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Baramnesia" <me>',
                element = 'Water',
                buff_id = 286,  -- Baramnesia buff
                group = 'barstatus',
            },
            -- Regen
            {
                name = 'Regen',
                level = 23,
                cost = 15,
                id = 108,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,  -- Regen
            },
            {
                name = 'Regen II',
                level = 48,
                cost = 24,
                id = 110,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen II" '..target
                end,
                element = 'Light',
                buff_id = 42,  -- Regen II buff
            },
            {
                name = 'Regen III',
                level = 70,
                cost = 36,
                id = 111,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen III" '..target
                end,
                element = 'Light',
                buff_id = 42,  -- Regen III buff
            },
            -- Refresh
            {
                name = 'Refresh',
                level = 62,
                cost = 40,
                id = 109,
                magic = 'white',
                magic_type = 'enhancing',
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
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Foil" <me>',
                element = 'Wind',
                buff_id = 568,  -- Foil buff
            },
            {
                name = 'Swordplay',
                level = 20,
                cost = 0,
                id = 24,  -- Swordplay recast ID
                command = '/ja "Swordplay" <me>',
                buff_id = 532,  -- Swordplay buff
            },
            {
                name = 'Phalanx',
                level = 68,
                cost = 21,
                id = 106,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Phalanx" <me>',
                element = 'Light',
                buff_id = 116,  -- Phalanx buff
            },
            -- Spikes
            {
                name = 'Blaze Spikes',
                level = 45,
                cost = 16,
                id = 34,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Blaze Spikes" <me>',
                element = 'Fire',
                buff_id = 34,  -- Blaze Spikes buff
                group = 'spikes',
            },
            {
                name = 'Ice Spikes',
                level = 65,
                cost = 16,
                id = 250,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Ice Spikes" <me>',
                element = 'Ice',
                buff_id = 35,  -- Ice Spikes buff
                group = 'spikes',
            },
            -- Everything else
            {
                name = 'Aquaveil',
                level = 15,
                cost = 14,
                id = 55,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aquaveil" <me>',
                element = 'Water',
                buff_id = 39,  -- Aquaveil buff
            },
            {
                name = 'Blink',
                level = 35,
                cost = 20,
                id = 53,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Blink" <me>',
                element = 'Wind',
                buff_id = 36,  -- Blink buff
            },
            {
                name = 'Stoneskin',
                level = 55,
                cost = 29,
                id = 54,
                magic = 'white',
                magic_type = 'enhancing',
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
