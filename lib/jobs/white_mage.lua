--[[
    White Mage job definition
    Defines abilities, validators, and configuration for White Mage automation
]]--

local common = require('lib.core.common')

return {
    job_id = 3,  -- White Mage
    job_name = 'White Mage',
    resource_type = 'mp',
    
    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Cure V',
                level = 61,
                cost = 135,
                id = 5,  -- Spell ID
                command = function(party_index)
                    return '/ma "Cure V" <p' .. party_index .. '>'
                end,
                range = 20,
                value = 700,
                wakes = true,
            },
            {
                name = 'Cure IV',
                level = 41,
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
                level = 21,
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
                level = 11,
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
                level = 1,
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
        
        -- AOE healing
        heal_aoe = {
            {
                name = 'Curaga IV',
                level = 71,
                cost = 260,
                id = 10,  -- Spell ID
                command = '/ma "Curaga IV" <me>',
                range = 20,
                wakes = true,
            },
            {
                name = 'Curaga III',
                level = 51,
                cost = 180,
                id = 9,  -- Spell ID
                command = '/ma "Curaga III" <me>',
                range = 20,
                wakes = true,
            },
            {
                name = 'Curaga II',
                level = 31,
                cost = 60,
                id = 8,  -- Spell ID
                command = '/ma "Curaga II" <me>',
                range = 20,
                wakes = true,
            },
            {
                name = 'Curaga',
                level = 16,
                cost = 60,
                id = 7,  -- Spell ID
                command = '/ma "Curaga" <me>',
                range = 20,
                wakes = true,
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Esuna', -- AOE debuff removal
                level = 61,
                cost = 24,
                id = 95,  -- Spell ID
                debuff_id = {3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 20, 21, 30, 31},  -- Multiple debuffs
                command = function(party_index)
                    return '/ma "Esuna" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Stona',
                level = 39,
                cost = 40,
                id = 18,  -- Spell ID
                debuff_id = 7,  -- Petrification
                command = function(party_index)
                    return '/ma "Stona" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Viruna',
                level = 34,
                cost = 48,
                id = 19,  -- Spell ID
                debuff_id = {8, 31},  -- Disease & Plague
                command = function(party_index)
                    return '/ma "Viruna" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Erase',
                level = 32,
                cost = 18,
                id = 143,  -- Spell ID
                debuff_id = {11, 12, 13, 31, 128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404},  -- Bind, Weight, Slow, Plague, Burn, Frost, Choke, Rasp, Dia, Bio, STR Down, DEX Down, VIT Down, AGI Down, INT Down, MND Down, CHR Down, Max HP Down, Max MP Down, Accuracy Down, Attack Down, Evasion Down, Defense Down, Flash, Magic Def Down, Magic Acc Down, Magic Atk Down, Max TP Down, Magic Eva Down
                command = function(party_index)
                    return '/ma "Erase" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Cursna',
                level = 29,
                cost = 30,
                id = 20,  -- Spell ID
                debuff_id = {9, 20, 30},  -- Curse & Bane
                command = function(party_index)
                    return '/ma "Cursna" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Silena',
                level = 19,
                cost = 24,
                id = 17,  -- Spell ID 
                debuff_id = 6,  -- Silence
                command = function(party_index)
                    return '/ma "Silena" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Blindna',
                level = 14,
                cost = 16,
                id = 16,  -- Spell ID
                debuff_id = 5,  -- Blindness
                command = function(party_index)
                    return '/ma "Blindna" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Paralyna',
                level = 9,
                cost = 12,
                id = 15,  -- Spell ID
                debuff_id = 4,  -- Paralysis
                command = function(party_index)
                    return '/ma "Paralyna" <p' .. party_index .. '>'
                end,
                range = 20,
            },
            {
                name = 'Poisona',
                level = 6,
                cost = 8,
                id = 14,  -- Spell ID 
                debuff_id = 3,  -- Poison
                command = function(party_index)
                    return '/ma "Poisona" <p' .. party_index .. '>'
                end,
                range = 20,
            },
        },

        -- Buffs
        buff = {
            {
                name = 'Auspice',
                level = 55,
                cost = 15,
                id = 96,  -- Spell ID
                command = '/ma "Auspice" <me>',
                buff_id = 275,  -- Auspice
                combat_only = true,
            },
            {
                name = 'Haste',
                level = 40,
                cost = 40,
                id = 57,  -- Spell ID
                command = function(party_index)
                    return '/ma "Haste" <p' .. party_index .. '>'
                end,
                buff_id = 33,  -- Haste
                combat_only = true,
            },
            {
                name = 'Regen III',
                level = 66,
                cost = 64,
                id = 111,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen III" <p' .. party_index .. '>'
                end,
                buff_id = 42,  -- Regen
                combat_only = false,
                group = 'regen',
            },
            {
                name = 'Regen II',
                level = 44,
                cost = 36,
                id = 110,  -- Spell ID
                command = function(party_index)
                    return '/ma "Regen II" <p' .. party_index .. '>'
                end,
                buff_id = 42,  -- Regen
                combat_only = false,
                group = 'regen',
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
                group = 'regen',
            },
            {
                name = 'Protectra V',
                level = 75,
                cost = 84,
                id = 129,  -- Spell ID
                command = '/ma "Protectra V" <me>',
                buff_id = 40,  -- Protect
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protectra IV',
                level = 63,
                cost = 65,
                id = 128,  -- Spell ID
                command = '/ma "Protectra IV" <me>',
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protectra III',
                level = 47,
                cost = 46,
                id = 127,  -- Spell ID
                command = '/ma "Protectra III" <me>',
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protectra II',
                level = 27,
                cost = 28,
                id = 126,  -- Spell ID
                command = '/ma "Protectra II" <me>',
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protectra',
                level = 7,
                cost = 9,
                id = 125,  -- Spell ID
                command = '/ma "Protectra" <me>',
                buff_id = 40,
                combat_only = false,
                group = 'protect',
            },
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
                group = 'protect',
            },
            {
                name = 'Protect III',
                level = 47,
                cost = 46,
                id = 45,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect III" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protect II',
                level = 27,
                cost = 28,
                id = 44,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect II" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Protect',
                level = 7,
                cost = 9,
                id = 43,  -- Spell ID
                command = function(party_index)
                    return '/ma "Protect" <p' .. party_index .. '>'
                end,
                buff_id = 40,  -- Protect
                combat_only = false,
                group = 'protect',
            },
            {
                name = 'Shellra V',
                level = 75,
                cost = 93,
                id = 134,  -- Spell ID
                command = '/ma "Shellra V" <me>',
                buff_id = 41,  -- Shell
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shellra IV',
                level = 68,
                cost = 71,
                id = 133,  -- Spell ID
                command = '/ma "Shellra IV" <me>',
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shellra III',
                level = 57,
                cost = 56,
                id = 132,  -- Spell ID
                command = '/ma "Shellra III" <me>',
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shellra II',
                level = 37,
                cost = 37,
                id = 131,  -- Spell ID
                command = '/ma "Shellra II" <me>',
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shellra',
                level = 17,
                cost = 18,
                id = 130,  -- Spell ID
                command = '/ma "Shellra" <me>',
                buff_id = 41,
                combat_only = false,
                group = 'shell',
            },
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
                group = 'shell',
            },
            {
                name = 'Shell III',
                level = 57,
                cost = 56,
                id = 50,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell III" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shell II',
                level = 37,
                cost = 37,
                id = 49,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell II" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Shell',
                level = 17,
                cost = 18,
                id = 48,  -- Spell ID
                command = function(party_index)
                    return '/ma "Shell" <p' .. party_index .. '>'
                end,
                buff_id = 41,  -- Shell
                combat_only = false,
                group = 'shell',
            },
            {
                name = 'Aquaveil',
                level = 10,
                cost = 12,
                id = 55,  -- Spell ID
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
                combat_only = true,
            },
            {
                name = 'Blink',
                level = 19,
                cost = 20,
                id = 53,  -- Spell ID
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
                combat_only = true,
            },
            {
                name = 'Stoneskin',
                level = 28,
                cost = 29,
                id = 54,  -- Spell ID
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
                combat_only = true,
            },
            {
                name = 'Reraise III',
                level = 70,
                cost = 150,
                id = 142,  -- Spell ID
                command = '/ma "Reraise III" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
                combat_only = false,
            },
            {
                name = 'Reraise II',
                level = 56,
                cost = 150,
                id = 141,  -- Spell ID
                command = '/ma "Reraise II" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
                combat_only = false,
            },
            {
                name = 'Reraise',
                level = 25,
                cost = 150,
                id = 135,  -- Spell ID
                command = '/ma "Reraise" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
                combat_only = false,
            },
            {
                name = 'Enlight',
                level = 75,
                cost = 45,
                id = 310,  -- Spell ID
                command = '/ma "Enlight" <me>',
                buff_id = 274,  -- Enlight
                combat_only = true,
                self_only = true,
            },
            -- Bar Element spells
            {
                name = 'Barthundra',
                level = 25,
                cost = 12,
                id = 70,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barthundra" <p' .. party_index .. '>'
                end,
                buff_id = 104,  -- Barthundra
                group = 'barelement',
                combat_only = false,
            },
            {
                name = 'Barblizzara',
                level = 21,
                cost = 12,
                id = 67,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barblizzara" <p' .. party_index .. '>'
                end,
                buff_id = 101,  -- Barblizzara
                group = 'barelement',
                combat_only = false,
            },
            {
                name = 'Barfira',
                level = 17,
                cost = 12,
                id = 66,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barfira" <p' .. party_index .. '>'
                end,
                buff_id = 100,  -- Barfira
                group = 'barelement',
                combat_only = false,
            },
            {
                name = 'Baraera',
                level = 13,
                cost = 12,
                id = 68,  -- Spell ID
                command = function(party_index)
                    return '/ma "Baraera" <p' .. party_index .. '>'
                end,
                buff_id = 102,  -- Baraera
                group = 'barelement',
                combat_only = false,
            },
            {
                name = 'Barwatera',
                level = 9,
                cost = 12,
                id = 79,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barwatera" <p' .. party_index .. '>'
                end,
                buff_id = 105,  -- Barwatera
                group = 'barelement',
                combat_only = false,
            },
            {
                name = 'Barstonra',
                level = 5,
                cost = 12,
                id = 78,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barstonra" <p' .. party_index .. '>'
                end,
                buff_id = 103,  -- Barstonra
                group = 'barelement',
                combat_only = false,
            },
            -- Bar Status spells
            {
                name = 'Baramnesra',
                level = 65,
                cost = 12,
                id = 91,  -- Spell ID
                command = function(party_index)
                    return '/ma "Baramnesra" <p' .. party_index .. '>'
                end,
                buff_id = 113,  -- Baramnesra
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barpetra',
                level = 43,
                cost = 12,
                id = 90,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barpetra" <p' .. party_index .. '>'
                end,
                buff_id = 111,  -- Barpetra
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barvira',
                level = 39,
                cost = 12,
                id = 89,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barvira" <p' .. party_index .. '>'
                end,
                buff_id = 112,  -- Barvira
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barsilencera',
                level = 23,
                cost = 12,
                id = 88,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barsilencera" <p' .. party_index .. '>'
                end,
                buff_id = 110,  -- Barsilencera
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barblindra',
                level = 18,
                cost = 12,
                id = 87,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barblindra" <p' .. party_index .. '>'
                end,
                buff_id = 109,  -- Barblindra
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barparalyzra',
                level = 12,
                cost = 12,
                id = 86,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barparalyzra" <p' .. party_index .. '>'
                end,
                buff_id = 108,  -- Barparalyzra
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barpoisonra',
                level = 10,
                cost = 12,
                id = 85,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barpoisonra" <p' .. party_index .. '>'
                end,
                buff_id = 107,  -- Barpoisonra
                group = 'barstatus',
                combat_only = false,
            },
            {
                name = 'Barsleepra',
                level = 7,
                cost = 12,
                id = 84,  -- Spell ID
                command = function(party_index)
                    return '/ma "Barsleepra" <p' .. party_index .. '>'
                end,
                buff_id = 106,  -- Barsleepra
                group = 'barstatus',
                combat_only = false,
            },
        },

        -- Revive
        -- revive = {
        --     {
        --         name = 'Arise',
        --         level = 75,
        --         cost = 150,
        --         id = 147,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Arise" <p' .. party_index .. '>'
        --         end,
        --         range = 18,
        --         combat_only = false,
        --     },
        --     {
        --         name = 'Raise III',
        --         level = 70,
        --         cost = 150,
        --         id = 140,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Raise III" <p' .. party_index .. '>'
        --         end,
        --         range = 18,
        --         combat_only = false,
        --     },
        --     {
        --         name = 'Raise II',
        --         level = 56,
        --         cost = 150,
        --         id = 139,  -- Spell ID
        --         command = function(party_index)
        --             return '/ma "Raise II" <p' .. party_index .. '>'
        --         end,
        --         range = 18,
        --         combat_only = false,
        --     },
        --     {
        --         name = 'Raise',
        --         level = 25,
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
        -- revive,
    },
}
