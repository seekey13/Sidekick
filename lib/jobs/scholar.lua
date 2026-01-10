--[=[
    Scholar job definition
    Defines abilities, validators, and configuration for Scholar automation
    
    Scholar is a hybrid job that combines:
    - Healing magic (weaker than White Mage)
    - Enfeebling magic (debuffs)
    - Enhancing magic (buffs)
    - Elemental magic (nukes, weaker than Black Mage)
    - Geomancy (storms)
    - Dark magic (drain, aspir)
]=]--

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
            },
            {
                name = 'Dark Arts',
                level = 10,
                cost = 0,
                id = 232,  -- Job ability ID
                command = '/ja "Dark Arts" <me>',
                group = 'arts',
                buff_id = {359, 402},
            },
            {
                name = 'Addendum: Black',
                level = 30,
                cost = 0,
                id = 235,  -- Job ability ID
                command = '/ja "Addendum: Black" <me>',
                group = 'addendum',
                buff_id = 402,
            },
            {
                name = 'Sublimation',
                level = 30,
                cost = 0,
                id = 234,  -- Job ability ID
                command = '/ja "Sublimation" <me>',
                buff_id = {187, 188},  -- Can be either 187 (activated) or 188 (complete)
                complete_buff_id = 188,
            },
            -- {
            --     name = 'Equanimity',
            --     level = 75,
            --     cost = 0,
            --     id = 243,  -- Job ability ID
            --     command = '/ja "Equanimity" <me>',
            --     buff_id = 415,
            -- },
            -- {
            --     name = 'Tranquility',
            --     level = 75,
            --     cost = 0,
            --     id = 242,  -- Job ability ID
            --     command = '/ja "Tranquility" <me>',
            --     buff_id = 414,
            -- },
            -- {
            --     name = 'Altruism',
            --     level = 75,
            --     cost = 0,
            --     id = 240,  -- Job ability ID
            --     command = '/ja "Altruism" <me>',
            --     buff_id = 412,
            -- },
            -- {
            --     name = 'Perpetuance',
            --     level = 75,
            --     cost = 0,
            --     id = 316,  -- Job ability ID
            --     command = '/ja "Perpetuance" <me>',
            --     buff_id = 469,
            -- },
            -- {
            --     name = 'Immanence',
            --     level = 75,
            --     cost = 0,
            --     id = 317,  -- Job ability ID
            --     command = '/ja "Immanence" <me>',
            --     buff_id = 470,
            -- },
            -- {
            --     name = 'Focalization',
            --     level = 75,
            --     cost = 0,
            --     id = 241,  -- Job ability ID
            --     command = '/ja "Focalization" <me>',
            --     buff_id = 413,
            -- },
            -- {
            --     name = 'Ebullience',
            --     level = 55,
            --     cost = 0,
            --     id = 221,  -- Job ability ID
            --     command = '/ja "Ebullience" <me>',
            --     buff_id = 365,
            -- },
            -- {
            --     name = 'Rapture',
            --     level = 55,
            --     cost = 0,
            --     id = 217,  -- Job ability ID
            --     command = '/ja "Rapture" <me>',
            --     buff_id = 364,
            -- },
            -- {
            --     name = 'Manifestation',
            --     level = 40,
            --     cost = 0,
            --     id = 222,  -- Job ability ID
            --     command = '/ja "Manifestation" <me>',
            --     buff_id = 367,
            -- },
            -- {
            --     name = 'Accession',
            --     level = 40,
            --     cost = 0,
            --     id = 218,  -- Job ability ID
            --     command = '/ja "Accession" <me>',
            --     buff_id = 366,
            -- },
            -- {
            --     name = 'Alacrity',
            --     level = 25,
            --     cost = 0,
            --     id = 220,  -- Job ability ID
            --     command = '/ja "Alacrity" <me>',
            --     buff_id = 363,
            -- },
            -- {
            --     name = 'Celerity',
            --     level = 25,
            --     cost = 0,
            --     id = 216,  -- Job ability ID
            --     command = '/ja "Celerity" <me>',
            --     buff_id = 362,
            -- },
            -- {
            --     name = 'Parsimony',
            --     level = 10,
            --     cost = 0,
            --     id = 361,  -- Job ability ID
            --     command = '/ja "Parsimony" <me>',
            --     buff_id = 361,
            -- },
            -- {
            --     name = 'Penury',
            --     level = 10,
            --     cost = 0,
            --     id = 215,  -- Job ability ID
            --     command = '/ja "Penury" <me>',
            --     buff_id = 360,
            -- },
            -- Protect line
            {
                name = 'Protect IV',
                level = 66,
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
                level = 50,
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
                level = 30,
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
                level = 10,
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
                level = 71,
                cost = 75,
                id = 51,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell IV" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
            },
            {
                name = 'Shell III',
                level = 60,
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
                level = 40,
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
                level = 20,
                cost = 18,
                id = 48,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell" <p' .. party_index .. '>'
                end,
                buff_id = 41,
                combat_only = false,
            },
            {
                name = 'Regen III',
                level = 59,
                cost = 64,
                id = 111,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen III" <p' .. party_index .. '>'
                end,
                buff_id = 42,  -- Regen
                range = 20,
                group = 'regen',
            },
            {
                name = 'Regen II',
                level = 37,
                cost = 36,
                id = 110,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen II" <p' .. party_index .. '>'
                end,
                buff_id = 42,
                range = 20,
                group = 'regen',
            },
            {
                name = 'Regen',
                level = 18,
                cost = 15,
                id = 108,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen" <p' .. party_index .. '>'
                end,
                buff_id = 42,
                range = 20,
                group = 'regen',
            },
            {
                name = 'Reraise II',
                level = 70,
                cost = 150,
                id = 142,  -- Spell ID
                command = function(party_index)
                    return '/ma "Reraise II" <p' .. party_index .. '>'
                end,
                range = 20,
                buff_id = 113,
                group = 'reraise',
                addendum = 'Addendum: White',
            },
            {
                name = 'Reraise',
                level = 35,
                cost = 150,
                id = 135,  -- Spell ID
                command = function(party_index)
                    return '/ma "Reraise" <p' .. party_index .. '>'
                end,
                range = 20,
                buff_id = 113,
                group = 'reraise',
                addendum = 'Addendum: White',
            },
            -- Other buffs
            {
                name = 'Stoneskin',
                level = 44,
                cost = 29,
                id = 54,  -- Spell ID
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
                combat_only = true,
            },
            {
                name = 'Blink',
                level = 30,
                cost = 20,
                id = 53,  -- Spell ID
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
                combat_only = true,
            },
            {
                name = 'Aquaveil',
                level = 13,
                cost = 12,
                id = 55,  -- Spell ID
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
                combat_only = true,
            },
            -- {
            --     name = 'Sneak',
            --     level = 20,
            --     cost = 12,
            --     id = 136,  -- Spell ID
            --     command = '/ma "Sneak" <me>',
            --     buff_id = 71,  -- Sneak
            --     combat_only = false,
            -- },
            -- {
            --     name = 'Invisible',
            --     level = 25,
            --     cost = 20,
            --     id = 137,  -- Spell ID
            --     command = '/ma "Invisible" <me>',
            --     buff_id = 69,  -- Invisible
            --     combat_only = false,
            -- },
            -- {
            --     name = 'Deodorize',
            --     level = 15,
            --     cost = 10,
            --     id = 138,  -- Spell ID
            --     command = '/ma "Deodorize" <me>',
            --     buff_id = 70,  -- Deodorize
            --     combat_only = false,
            -- },
            -- Storms
            {
                name = 'Aurorastorm',
                level = 48,
                cost = 30,
                id = 119,  -- Spell ID
                command = '/ma "Aurorastorm" <me>',
                buff_id = 184,  -- Aurorastorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Voidstorm',
                level = 47,
                cost = 30,
                id = 118,  -- Spell ID
                command = '/ma "Voidstorm" <me>',
                buff_id = 185,  -- Voidstorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Thunderstorm',
                level = 46,
                cost = 30,
                id = 117,  -- Spell ID
                command = '/ma "Thunderstorm" <me>',
                buff_id = 182,  -- Thunderstorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Hailstorm',
                level = 45,
                cost = 30,
                id = 116,  -- Spell ID
                command = '/ma "Hailstorm" <me>',
                buff_id = 179,  -- Hailstorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Firestorm',
                level = 44,
                cost = 30,
                id = 115,  -- Spell ID
                command = '/ma "Firestorm" <me>',
                buff_id = 178,  -- Firestorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Windstorm',
                level = 43,
                cost = 30,
                id = 114,  -- Spell ID
                command = '/ma "Windstorm" <me>',
                buff_id = 180,  -- Windstorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Rainstorm',
                level = 42,
                cost = 30,
                id = 113,  -- Spell ID
                command = '/ma "Rainstorm" <me>',
                buff_id = 183,  -- Rainstorm
                combat_only = true,
                group = 'storm',
            },
            {
                name = 'Sandstorm',
                level = 41,
                cost = 30,
                id = 112,  -- Spell ID
                command = '/ma "Sandstorm" <me>',
                buff_id = 181,  -- Sandstorm
                combat_only = true,
                group = 'storm',
            },
            -- Klimaform
            {
                name = 'Klimaform',
                level = 46,
                cost = 30,
                id = 287,  -- Spell ID
                command = '/ma "Klimaform" <me>',
                buff_id = 407,  -- Klimaform
                combat_only = true,
            },
            -- Spikes
            {
                name = 'Shock Spikes',
                level = 70,
                cost = 24,
                id = 251,  -- Spell ID
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
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,  -- Blaze Spikes
                combat_only = true,
                group = 'spikes',
            },
        },
        
        -- Single-target healing
        heal = {
            {
                name = 'Cure IV',
                level = 55,
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
                level = 30,
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
                level = 17,
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
                level = 5,
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

        -- Recover
        recover = {
                        {
                name = 'Sublimation',
                level = 30,
                cost = 0,
                id = 234,  -- Job ability ID
                command = '/ja "Sublimation" <me>',
                combat_only = false,
            },
        },

        -- Debuffs (Enfeebling magic)
        debuff = {
            {
                name = 'Stona',
                level = 50,
                cost = 40,
                id = 18,  -- Spell ID
                debuff_id = 8,  -- Petrification
                command = function(party_index)
                    return '/ma "Stona" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Viruna',
                level = 46,
                cost = 48,
                id = 19,  -- Spell ID
                debuff_id = 7,  -- Plague
                command = function(party_index)
                    return '/ma "Viruna" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Silena',
                level = 22,
                cost = 24,
                id = 17,  -- Spell ID
                debuff_id = 6,  -- Silence
                command = function(party_index)
                    return '/ma "Silena" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Blindna',
                level = 17,
                cost = 16,
                id = 16,  -- Spell ID
                debuff_id = 5,  -- Blindness
                command = function(party_index)
                    return '/ma "Blindna" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Paralyna',
                level = 12,
                cost = 12,
                id = 15,  -- Spell ID
                debuff_id = 4,  -- Paralysis
                command = function(party_index)
                    return '/ma "Paralyna" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Poisona',
                level = 10,
                cost = 8,
                id = 14,  -- Spell ID
                debuff_id = 3,  -- Poison
                command = function(party_index)
                    return '/ma "Poisona" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
            {
                name = 'Erase',
                level = 39,
                cost = 18,
                id = 143,  -- Spell ID
                command = function(party_index)
                    return '/ma "Erase" <p' .. party_index .. '>'
                end,
                range = 20,
                addendum = 'Addendum: White',
            },
        },
        
        -- Elemental Nukes
        nuke = {
            -- Tier IV spells (highest)
            {
                name = 'Thunder IV',
                level = 75,
                cost = 118,
                id = 167,
                command = '/ma "Thunder IV" <t>',
                element = 'Thunder',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            {
                name = 'Blizzard IV',
                level = 74,
                cost = 118,
                id = 152,
                command = '/ma "Blizzard IV" <t>',
                element = 'Ice',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            {
                name = 'Fire IV',
                level = 73,
                cost = 118,
                id = 147,
                command = '/ma "Fire IV" <t>',
                element = 'Fire',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            {
                name = 'Aero IV',
                level = 72,
                cost = 118,
                id = 157,
                command = '/ma "Aero IV" <t>',
                element = 'Wind',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            {
                name = 'Water IV',
                level = 71,
                cost = 118,
                id = 172,
                command = '/ma "Water IV" <t>',
                element = 'Water',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            {
                name = 'Stone IV',
                level = 70,
                cost = 118,
                id = 162,
                command = '/ma "Stone IV" <t>',
                element = 'Earth',
                range = 20,
                combat_only = true,
                addendum = 'Addendum: Black',
            },
            -- Tier III spells
            {
                name = 'Thunder III',
                level = 69,
                cost = 91,
                id = 166,
                command = '/ma "Thunder III" <t>',
                element = 'Thunder',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Blizzard III',
                level = 66,
                cost = 75,
                id = 151,
                command = '/ma "Blizzard III" <t>',
                element = 'Ice',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Fire III',
                level = 63,
                cost = 51,
                id = 146,
                command = '/ma "Fire III" <t>',
                element = 'Fire',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Aero III',
                level = 60,
                cost = 54,
                id = 156,
                command = '/ma "Aero III" <t>',
                element = 'Wind',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Water III',
                level = 57,
                cost = 46,
                id = 171,
                command = '/ma "Water III" <t>',
                element = 'Water',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Stone III',
                level = 54,
                cost = 40,
                id = 161,
                command = '/ma "Stone III" <t>',
                element = 'Earth',
                range = 20,
                combat_only = true,
            },
            -- Tier II spells
            {
                name = 'Thunder II',
                level = 51,
                cost = 37,
                id = 165,
                command = '/ma "Thunder II" <t>',
                element = 'Thunder',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Blizzard II',
                level = 46,
                cost = 31,
                id = 150,
                command = '/ma "Blizzard II" <t>',
                element = 'Ice',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Fire II',
                level = 42,
                cost = 26,
                id = 145,
                command = '/ma "Fire II" <t>',
                element = 'Fire',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Aero II',
                level = 38,
                cost = 22,
                id = 155,
                command = '/ma "Aero II" <t>',
                element = 'Wind',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Water II',
                level = 34,
                cost = 19,
                id = 170,
                command = '/ma "Water II" <t>',
                element = 'Water',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Stone II',
                level = 30,
                cost = 16,
                id = 160,
                command = '/ma "Stone II" <t>',
                element = 'Earth',
                range = 20,
                combat_only = true,
            },
            -- Tier I spells
            {
                name = 'Thunder',
                level = 24,
                cost = 9,
                id = 164,
                command = '/ma "Thunder" <t>',
                element = 'Thunder',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Blizzard',
                level = 20,
                cost = 8,
                id = 149,
                command = '/ma "Blizzard" <t>',
                element = 'Ice',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Fire',
                level = 16,
                cost = 7,
                id = 144,
                command = '/ma "Fire" <t>',
                element = 'Fire',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Aero',
                level = 12,
                cost = 6,
                id = 154,
                command = '/ma "Aero" <t>',
                element = 'Wind',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Water',
                level = 8,
                cost = 5,
                id = 169,
                command = '/ma "Water" <t>',
                element = 'Water',
                range = 20,
                combat_only = true,
            },
            {
                name = 'Stone',
                level = 4,
                cost = 4,
                id = 159,
                command = '/ma "Stone" <t>',
                element = 'Earth',
                range = 20,
                combat_only = true,
            },
        },

        -- Debuff
        debuff = {
            {
                name = 'Luminohelix',
                level = 32,
                cost = 26,
                id = 285,
                command = '/ma "Luminohelix" <t>',
                element = 'Light',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Noctohelix',
                level = 30,
                cost = 26,
                id = 284,
                command = '/ma "Noctohelix" <t>',
                element = 'Dark',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Ionohelix',
                level = 28,
                cost = 26,
                id = 283,
                command = '/ma "Ionohelix" <t>',
                element = 'Lightning',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Cryohelix',
                level = 26,
                cost = 26,
                id = 282,
                command = '/ma "Cryohelix" <t>',
                element = 'Ice',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Pyrohelix',
                level = 24,
                cost = 26,
                id = 281,
                command = '/ma "Pyrohelix" <t>',
                element = 'Fire',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Anemohelix',
                level = 22,
                cost = 26,
                id = 280,
                command = '/ma "Anemohelix" <t>',
                element = 'Wind',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Hydrohelix',
                level = 20,
                cost = 26,
                id = 279,
                command = '/ma "Hydrohelix" <t>',
                element = 'Water',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
            {
                name = 'Geohelix',
                level = 18,
                cost = 26,
                id = 278,
                command = '/ma "Geohelix" <t>',
                element = 'Earth',
                range = 20,
                combat_only = true,
                group = 'helix',
            },
        },

        -- -- Raise
        -- raise = {
        --     {
        --         name = 'Raise II',
        --         level = 70,
        --         cost = 150,
        --         id = 141,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Raise II" <p' .. party_index .. '>'
        --         end,
        --         range = 20,
        --         wakes = true,
        --         addendum = 'Addendum: White',
        --     },
        --     {
        --         name = 'Raise',
        --         level = 35,
        --         cost = 150,
        --         id = 12,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Raise" <p' .. party_index .. '>'
        --         end,
        --         range = 20,
        --         wakes = true,
        --     },
        -- },

        -- -- Sleep
        -- sleep = {
            -- {
            --     name = 'Sleep II',
            --     level = 65,
            --     cost = 29,
            --     id = 259,  -- Spell ID
            --     command = '/ma "Sleep II" <t>',
            --     effect_id = 2,  -- Sleep debuff
            --     duration = 90,
            --     range = 20,
            --     combat_only = true,
            --     addendum = 'Addendum: Black',
            -- },
            -- {
            --     name = 'Sleep',
            --     level = 30,
            --     cost = 19,
            --     id = 253,  -- Spell ID
            --     command = '/ma "Sleep" <t>',
            --     effect_id = 2,  -- Sleep debuff
            --     duration = 60,
            --     range = 20,
            --     combat_only = true,
            --     addendum = 'Addendum: Black',
            -- },
        -- },

        -- -- Dispel
        -- dispel = {
            -- {
            --     name = 'Dispel',
            --     level = 32,
            --     cost = 25,
            --     id = 260,  -- Spell ID
            --     command = '/ma "Dispel" <t>',
            --     range = 20,
            --     combat_only = true,
            --     addendum = 'Addendum: Black',
            -- },
        -- },
    },
    
    -- Job-specific validators
    validators = {},
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = false,  -- Scholar has no AOE heal
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        recover_enabled = true,
        recover_threshold = 50,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = true,
        debuff_enabled = true,
        counter_enabled = false,  -- Scholar has no counter
        nuke_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
    },
    
    -- Action priority order
    priority_order = {
        'job_buff',
        'heal',
        'wake',
        'recover',
        'buff',
        'weaponskill',
        'debuff',
        'nuke',
    },
}