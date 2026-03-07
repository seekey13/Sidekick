--[[
    White Mage job definition
    Defines abilities, validators, and configuration for White Mage automation
    - Healing (Cure, Curaga spells)
    - Debuff removal (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
    - Buffs (Auspice, Haste, Regen, Protect, Shell, bar spells, Aquaveil, Blink, Stoneskin, Reraise)
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
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Cure V" '..target
                end,
                range = 20,
                value = 700,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Cure IV',
                level = 41,
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
                level = 21,
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
                level = 11,
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
                level = 1,
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
        
        -- AOE healing
        heal_aoe = {
            {
                name = 'Curaga IV',
                level = 71,
                cost = 260,
                id = 10,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = '/ma "Curaga IV" <me>',
                range = 20,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Curaga III',
                level = 51,
                cost = 180,
                id = 9,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = '/ma "Curaga III" <me>',
                range = 20,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Curaga II',
                level = 31,
                cost = 120,
                id = 8,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = '/ma "Curaga II" <me>',
                range = 20,
                wakes = true,
                target_outside = true,
            },
            {
                name = 'Curaga',
                level = 16,
                cost = 60,
                id = 7,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = '/ma "Curaga" <me>',
                range = 20,
                wakes = true,
                target_outside = true,
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Esuna', -- AOE debuff removal
                level = 61,
                cost = 24,
                id = 95,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 20, 21, 30, 31},  -- Multiple debuffs
                command = '/ma "Esuna" <me>',
                self_only = true,
            },
            {
                name = 'Stona',
                level = 39,
                cost = 40,
                id = 18,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 7,  -- Petrification
                command = function(target)
                    return '/ma "Stona" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Viruna',
                level = 34,
                cost = 48,
                id = 19,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {8, 31},  -- Disease & Plague
                command = function(target)
                    return '/ma "Viruna" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Erase',
                level = 32,
                cost = 18,
                id = 143,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {11, 12, 13, 31, 128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 404},  -- Bind, Weight, Slow, Plague, Burn, Frost, Choke, Rasp, Dia, Bio, STR Down, DEX Down, VIT Down, AGI Down, INT Down, MND Down, CHR Down, Max HP Down, Max MP Down, Accuracy Down, Attack Down, Evasion Down, Defense Down, Flash, Magic Def Down, Magic Acc Down, Magic Atk Down, Max TP Down, Magic Eva Down
                command = function(target)
                    return '/ma "Erase" '..target
                end,
                range = 20,
            },
            {
                name = 'Cursna',
                level = 29,
                cost = 30,
                id = 20,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {9, 15, 20, 30},  -- Curse, Doom & Bane
                command = function(target)
                    return '/ma "Cursna" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Silena',
                level = 19,
                cost = 24,
                id = 17,  -- Spell ID 
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 6,  -- Silence
                command = function(target)
                    return '/ma "Silena" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Blindna',
                level = 14,
                cost = 16,
                id = 16,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 5,  -- Blindness
                command = function(target)
                    return '/ma "Blindna" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Paralyna',
                level = 9,
                cost = 12,
                id = 15,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 4,  -- Paralysis
                command = function(target)
                    return '/ma "Paralyna" '..target
                end,
                range = 20,
                target_outside = true,
            },
            {
                name = 'Poisona',
                level = 6,
                cost = 8,
                id = 14,  -- Spell ID 
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 3,  -- Poison
                command = function(target)
                    return '/ma "Poisona" '..target
                end,
                range = 20,
                target_outside = true,
            },
        },

        -- Buffs
        buff = {
            {
                name = 'Afflatus Solace',
                level = 40,
                cost = 0,
                id = 245,  -- Job Ability ID
                command = '/ja "Afflatus Solace" <me>',
                buff_id = 417,  -- Afflatus Solace
                group = 'afflatus',
            },
            {
                name = 'Afflatus Misery',
                level = 40,
                cost = 0,
                id = 246,  -- Job Ability ID
                command = '/ja "Afflatus Misery" <me>',
                buff_id = 418,  -- Afflatus Misery
                group = 'afflatus',
            },
            {
                name = 'Haste',
                level = 40,
                cost = 40,
                id = 57,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Haste" '..target
                end,
                buff_id = 33,  -- Haste
                combat_only = true,
                duration = 180,
                target_outside = true,
            },
            {
                name = 'Regen III',
                level = 66,
                cost = 64,
                id = 111,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen III" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = true,
                duration = 60,
            },
            {
                name = 'Regen II',
                level = 44,
                cost = 36,
                id = 110,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen II" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = true,
                duration = 60,
            },
            {
                name = 'Regen',
                level = 21,
                cost = 15,
                id = 108,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,  -- Regen
                combat_only = true,
                duration = 75,
            },
            {
                name = 'Protectra V',
                level = 75,
                cost = 84,
                id = 129,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Protectra V" <me>',
                buff_id = 40,  -- Protect
                group = 'protectra',
            },
            {
                name = 'Protectra IV',
                level = 63,
                cost = 65,
                id = 128,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Protectra IV" <me>',
                buff_id = 40,
                group = 'protectra',
            },
            {
                name = 'Protectra III',
                level = 47,
                cost = 46,
                id = 127,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Protectra III" <me>',
                buff_id = 40,
                group = 'protectra',
            },
            {
                name = 'Protectra II',
                level = 27,
                cost = 28,
                id = 126,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Protectra II" <me>',
                buff_id = 40,
                group = 'protectra',
            },
            {
                name = 'Protectra',
                level = 7,
                cost = 9,
                id = 125,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Protectra" <me>',
                buff_id = 40,
                group = 'protectra',
            },
            {
                name = 'Protect IV',
                level = 63,
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
                level = 47,
                cost = 46,
                id = 45,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,  -- Protect
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 27,
                cost = 28,
                id = 44,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,  -- Protect
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect',
                level = 7,
                cost = 9,
                id = 43,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,  -- Protect
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Shellra V',
                level = 75,
                cost = 93,
                id = 134,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Shellra V" <me>',
                buff_id = 41,  -- Shell
                group = 'shellra',
            },
            {
                name = 'Shellra IV',
                level = 68,
                cost = 71,
                id = 133,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Shellra IV" <me>',
                buff_id = 41,
                group = 'shellra',
            },
            {
                name = 'Shellra III',
                level = 57,
                cost = 56,
                id = 132,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Shellra III" <me>',
                buff_id = 41,
                group = 'shellra',
            },
            {
                name = 'Shellra II',
                level = 37,
                cost = 37,
                id = 131,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Shellra II" <me>',
                buff_id = 41,
                group = 'shellra',
            },
            {
                name = 'Shellra',
                level = 17,
                cost = 18,
                id = 130,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Shellra" <me>',
                buff_id = 41,
                group = 'shellra',
            },
            {
                name = 'Shell IV',
                level = 68,
                cost = 71,
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
                level = 57,
                cost = 56,
                id = 50,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,  -- Shell
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 37,
                cost = 37,
                id = 49,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,  -- Shell
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell',
                level = 17,
                cost = 18,
                id = 48,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,  -- Shell
                group = 'shell',
                target_outside = true,
            },
            -- Bar Element spells
            {
                name = 'Barthundra',
                level = 25,
                cost = 12,
                id = 70,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barthundra" <me>',
                buff_id = 104,  -- Barthundra
                group = 'barelement',
            },
            {
                name = 'Barblizzara',
                level = 21,
                cost = 12,
                id = 67,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barblizzara" <me>',
                buff_id = 101,  -- Barblizzara
                group = 'barelement',
            },
            {
                name = 'Barfira',
                level = 17,
                cost = 12,
                id = 66,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barfira" <me>',
                buff_id = 100,  -- Barfira
                group = 'barelement',
            },
            {
                name = 'Baraera',
                level = 13,
                cost = 12,
                id = 68,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Baraera" <me>',
                buff_id = 102,  -- Baraera
                group = 'barelement',
            },
            {
                name = 'Barwatera',
                level = 9,
                cost = 12,
                id = 79,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barwatera" <me>',
                buff_id = 105,  -- Barwatera
                group = 'barelement',
            },
            {
                name = 'Barstonra',
                level = 5,
                cost = 12,
                id = 78,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barstonra" <me>',
                buff_id = 103,  -- Barstonra
                group = 'barelement',
            },
            -- Bar Status spells
            {
                name = 'Baramnesra',
                level = 65,
                cost = 12,
                id = 91,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Baramnesra" <me>',
                buff_id = 286,  -- Baramnesra
                group = 'barstatus',
            },
            {
                name = 'Barpetra',
                level = 43,
                cost = 12,
                id = 90,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barpetra" <me>',
                buff_id = 111,  -- Barpetra
                group = 'barstatus',
            },
            {
                name = 'Barvira',
                level = 39,
                cost = 12,
                id = 89,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barvira" <me>',
                buff_id = 112,  -- Barvira
                group = 'barstatus',
            },
            {
                name = 'Barsilencera',
                level = 23,
                cost = 30,
                id = 88,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barsilencera" <me>',
                buff_id = 110,  -- Barsilencera
                group = 'barstatus',
            },
            {
                name = 'Barblindra',
                level = 18,
                cost = 12,
                id = 87,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barblindra" <me>',
                buff_id = 109,  -- Barblindra
                group = 'barstatus',
            },
            {
                name = 'Barparalyzra',
                level = 12,
                cost = 12,
                id = 86,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barparalyzra" <me>',
                buff_id = 108,  -- Barparalyzra
                group = 'barstatus',
            },
            {
                name = 'Barpoisonra',
                level = 10,
                cost = 12,
                id = 85,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barpoisonra" <me>',
                buff_id = 107,  -- Barpoisonra
                group = 'barstatus',
            },
            {
                name = 'Barsleepra',
                level = 7,
                cost = 12,
                id = 84,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Barsleepra" <me>',
                buff_id = 106,  -- Barsleepra
                group = 'barstatus',
            },
            {
                name = 'Aquaveil',
                level = 10,
                cost = 12,
                id = 55,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
            },
            {
                name = 'Blink',
                level = 19,
                cost = 20,
                id = 53,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
            },
            {
                name = 'Stoneskin',
                level = 28,
                cost = 29,
                id = 54,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
            },
            {
                name = 'Reraise III',
                level = 70,
                cost = 150,
                id = 142,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise III" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
            },
            {
                name = 'Reraise II',
                level = 56,
                cost = 150,
                id = 141,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise II" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
            },
            {
                name = 'Reraise',
                level = 25,
                cost = 150,
                id = 135,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise" <me>',
                buff_id = 113,  -- Reraise
                group = 'reraise',
            },
            {
                name = 'Enlight',
                level = 75,
                cost = 45,
                id = 310,  -- Spell ID
                magic = 'white',
                magic_type = 'divine',
                command = '/ma "Enlight" <me>',
                buff_id = 274,  -- Enlight
                engaged_only = true,
            },
            {
                name = 'Auspice',
                level = 55,
                cost = 15,
                id = 96,  -- Spell ID
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Auspice" <me>',
                buff_id = 275,  -- Auspice
                engaged_only = true,
            },
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

        -- Critical
        critical = {
            {
                name = 'Martyr',
                level = 75,
                cost = 0,
                id = 27,  -- Job Ability ID
                command = function(target)
                    return '/ja "Martyr" '..target
                end,
                range = 18,
            },
            {
                name = 'Divine Seal',
                level = 30,
                cost = 0,
                id = 26,  -- Job Ability ID
                command = '/ja "Divine Seal" <me>',
            },
        },

        -- Revive
        revive = {
            {
                name = 'Arise',
                level = 75,
                cost = 300,
                id = 494,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Arise" '..target
                end,
                range = 18,
                idle_only = true,
                target_outside = true,
            },
            {
                name = 'Raise III',
                level = 70,
                cost = 150,
                id = 140,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Raise III" '..target
                end,
                range = 18,
                idle_only = true,
                target_outside = true,
            },
            {
                name = 'Raise II',
                level = 56,
                cost = 150,
                id = 139,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Raise II" '..target
                end,
                range = 18,
                idle_only = true,
                target_outside = true,
            },
            {
                name = 'Raise',
                level = 25,
                cost = 150,
                id = 12,  -- Spell ID
                magic = 'white',
                magic_type = 'healing',
                command = function(target)
                    return '/ma "Raise" '..target
                end,
                range = 18,
                idle_only = true,
                target_outside = true,
            },
        },


        recover_party_mp = {
            {
                name = 'Devotion',
                level = 75,
                cost = 0,
                id = 28,  -- Job Ability ID
                command = function(target)
                    return '/ja "Devotion" '..target -- Cannot target self
                end,
            },
        },
    },
    -- -- Job-specific validators
    -- validators = {

    -- },

    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        critical_threshold = 30,
        heal_aoe_enabled = true,
        heal_aoe_threshold = 70,
        heal_aoe_count_threshold = 2,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = true,
        focus_enabled = false,
        focus_target_index = nil,
        focus_threshold = 85,
        focus_recovery_target_index = nil,
        focus_recovery_threshold = 30,
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
        'heal_aoe',
        'heal',
        'debuff_removal',
        'wake',
        'revive',
        'buff',
        'rest',
    },
}
