--[[
    Bard job definition
    Defines abilities, validators, and configuration for Bard automation
    - Buff songs (Minuets, Paeons, Madrigals, etc.)
]]--

local common = require('lib.core.common')

return {
    job_id = 10,  -- Bard
    job_name = 'Bard',
    resource_type = 'mp',
    
    abilities = {
        -- Buff songs
        buff = {
            -- Minne
            {
                name = "Knight's Minne IV",
                level = 61,
                cost = 0,
                id = 392,
                command = function(target)
                    return '/ma "Knight\'s Minne IV" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne IV buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne III",
                level = 41,
                cost = 0,
                id = 391,
                command = function(target)
                    return '/ma "Knight\'s Minne III" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne III buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne II",
                level = 21,
                cost = 0,
                id = 390,
                command = function(target)
                    return '/ma "Knight\'s Minne II" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne II buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne",
                level = 1,
                cost = 0,
                id = 389,
                command = function(target)
                    return '/ma "Knight\'s Minne" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne buff
                group = 'minne',
                target_modifier = true,
            },
            -- Minuet
            {
                name = 'Valor Minuet IV',
                level = 63,
                cost = 0,
                id = 397,
                command = function(target)
                    return '/ma "Valor Minuet IV" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet IV buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet III',
                level = 43,
                cost = 0,
                id = 396,
                command = function(target)
                    return '/ma "Valor Minuet III" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet III buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet II',
                level = 23,
                cost = 0,
                id = 395,
                command = function(target)
                    return '/ma "Valor Minuet II" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet II buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet',
                level = 3,
                cost = 0,
                id = 394,
                command = function(target)
                    return '/ma "Valor Minuet" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet buff
                group = 'minuet',
                target_modifier = true,
            },
            -- Paeon
            {
                name = "Army's Paeon V",
                level = 65,
                cost = 0,
                id = 382,
                command = function(target)
                    return '/ma "Army\'s Paeon V" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon V buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon IV",
                level = 45,
                cost = 0,
                id = 381,
                command = function(target)
                    return '/ma "Army\'s Paeon IV" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon IV buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon III",
                level = 35,
                cost = 0,
                id = 380,
                command = function(target)
                    return '/ma "Army\'s Paeon III" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon III buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon II",
                level = 15,
                cost = 0,
                id = 379,
                command = function(target)
                    return '/ma "Army\'s Paeon II" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon II buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon",
                level = 5,
                cost = 0,
                id = 378,
                command = function(target)
                    return '/ma "Army\'s Paeon" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon buff
                group = 'paeon',
                target_modifier = true,
            },
            -- Madrigal
            {
                name = 'Blade Madrigal',
                level = 51,
                cost = 0,
                id = 400,
                command = function(target)
                    return '/ma "Blade Madrigal" '..target
                end,
                element = 'Lightning',
                buff_id = 199,  -- Blade Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            {
                name = 'Sword Madrigal',
                level = 11,
                cost = 0,
                id = 399,
                command = function(target)
                    return '/ma "Sword Madrigal" '..target
                end,
                element = 'Lightning',
                buff_id = 199,  -- Sword Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            -- Ballad
            {
                name = "Mage's Ballad II",
                level = 55,
                cost = 0,
                id = 387,
                command = function(target)
                    return '/ma "Mage\'s Ballad II" '..target
                end,
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad II buff
                target_modifier = true,
            },
            {
                name = "Mage's Ballad",
                level = 25,
                cost = 0,
                id = 386,
                command = function(target)
                    return '/ma "Mage\'s Ballad" '..target
                end,
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad buff
                target_modifier = true,
            },
            -- March
            {
                name = 'Victory March',
                level = 60,
                cost = 0,
                id = 420, 
                command = function(target)
                    return '/ma "Victory March" '..target
                end,
                element = 'Lightning',
                buff_id = 214,  -- Victory March buff
                group = 'march',
                target_modifier = true,
            },
            {
                name = 'Advancing March',
                level = 29,
                cost = 0,
                id = 419,
                command = function(target)
                    return '/ma "Advancing March" '..target
                end,
                element = 'Lightning',
                buff_id = 214,  -- Advancing March buff
                group = 'march',
                target_modifier = true,
            },
            -- Etude
            {
                name = 'Herculean Etude',
                level = 74,
                cost = 0,
                id = 431,
                command = function(target)
                    return '/ma "Herculean Etude" '..target
                end,
                element = 'Fire',
                buff_id = 215,  -- Herculean Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Uncanny Etude',
                level = 72,
                cost = 0,
                id = 432,
                command = function(target)
                    return '/ma "Uncanny Etude" '..target
                end,
                element = 'Lightning',
                buff_id = 215,  -- Uncanny Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Vital Etude',
                level = 70,
                cost = 0,
                id = 433,
                command = function(target)
                    return '/ma "Vital Etude" '..target
                end,
                element = 'Earth',
                buff_id = 215,  -- Vital Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Swift Etude',
                level = 68,
                cost = 0,
                id = 434,
                command = function(target)
                    return '/ma "Swift Etude" '..target
                end,
                element = 'Wind',
                buff_id = 215,  -- Swift Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Sage Etude',
                level = 66,
                cost = 0,
                id = 435,
                command = function(target)
                    return '/ma "Sage Etude" '..target
                end,
                element = 'Ice',
                buff_id = 215,  -- Sage Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Logical Etude',
                level = 64,
                cost = 0,
                id = 436,
                command = function(target)
                    return '/ma "Logical Etude" '..target
                end,
                element = 'Water',
                buff_id = 215,  -- Logical Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Bewitching Etude',
                level = 62,
                cost = 0,
                id = 437,
                command = function(target)
                    return '/ma "Bewitching Etude" '..target
                end,
                element = 'Light',
                buff_id = 215,  -- Bewitching Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Sinewy Etude',
                level = 34,
                cost = 0,
                id = 424,
                command = function(target)
                    return '/ma "Sinewy Etude" '..target
                end,
                element = 'Fire',
                buff_id = 215,  -- Sinewy Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Dextrous Etude',
                level = 32,
                cost = 0,
                id = 425,
                command = function(target)
                    return '/ma "Dextrous Etude" '..target
                end,
                element = 'Lightning',
                buff_id = 215,  -- Dextrous Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Vivacious Etude',
                level = 30,
                cost = 0,
                id = 426,
                command = function(target)
                    return '/ma "Vivacious Etude" '..target
                end,
                element = 'Earth',
                buff_id = 215,  -- Vivacious Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Quick Etude',
                level = 28,
                cost = 0,
                id = 427,
                command = function(target)
                    return '/ma "Quick Etude" '..target
                end,
                element = 'Wind',
                buff_id = 215,  -- Quick Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Learned Etude',
                level = 26,
                cost = 0,
                id = 428,
                command = function(target)
                    return '/ma "Learned Etude" '..target
                end,
                element = 'Ice',
                buff_id = 215,  -- Learned Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Spirited Etude',
                level = 24,
                cost = 0,
                id = 429,
                command = function(target)
                    return '/ma "Spirited Etude" '..target
                end,
                element = 'Water',
                buff_id = 215,  -- Spirited Etude buff
                group = 'etude',
                target_modifier = true,
            },
            -- Carols
            {
                name = 'Dark Carol',
                level = 50,
                cost = 0,
                id = 445,
                command = function(target)
                    return '/ma "Dark Carol" '..target
                end,
                element = 'Light',
                buff_id = 216,  -- Dark Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Lightning Carol',
                level = 48,
                cost = 0,
                id = 442,
                command = function(target)
                    return '/ma "Lightning Carol" '..target
                end,
                element = 'Earth',
                buff_id = 216,  -- Lightning Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Ice Carol',
                level = 46,
                cost = 0,
                id = 439,
                command = function(target)
                    return '/ma "Ice Carol" '..target
                end,
                element = 'Fire',
                buff_id = 216,  -- Ice Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Fire Carol',
                level = 44,
                cost = 0,
                id = 438,
                command = function(target)
                    return '/ma "Fire Carol" '..target
                end,
                element = 'Water',
                buff_id = 216,  -- Fire Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Wind Carol',
                level = 42,
                cost = 0,
                id = 440,
                command = function(target)
                    return '/ma "Wind Carol" '..target
                end,
                element = 'Ice',
                buff_id = 216,  -- Wind Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Water Carol',
                level = 40,
                cost = 0,
                id = 441,
                command = function(target)
                    return '/ma "Water Carol" '..target
                end,
                element = 'Lightning',
                buff_id = 216,  -- Water Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Earth Carol',
                level = 38,
                cost = 0,
                id = 443,
                command = function(target)
                    return '/ma "Earth Carol" '..target
                end,
                element = 'Wind',
                buff_id = 216,  -- Earth Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Light Carol',
                level = 36,
                cost = 0,
                id = 444,
                command = function(target)
                    return '/ma "Light Carol" '..target
                end,
                element = 'Dark',
                buff_id = 216,  -- Light Carol buff
                group = 'carol',
                target_modifier = true,
            },
            -- Mazurkas
            {
                name = 'Chocobo Mazurka',
                level = 73,
                cost = 0,
                id = 465,
                command = function(target)
                    return '/ma "Chocobo Mazurka" '..target
                end,
                element = 'Wind',
                buff_id = 219,  -- Chocobo Mazurka buff
                group = 'mazurka',
                idle_only = true,
            },
            {
                name = 'Raptor Mazurka',
                level = 37,
                cost = 0,
                id = 467,
                command = function(target)
                    return '/ma "Raptor Mazurka" '..target
                end,
                element = 'Wind',
                buff_id = 219,  -- Raptor Mazurka buff
                group = 'mazurka',
                idle_only = true,
            },
            -- Others
            {
                name = 'Foe Sirvente',
                level = 75,
                cost = 0,
                id = 468,
                command = function(target)
                    return '/ma "Foe Sirvente" '..target
                end,
                element = 'Light',
                buff_id = 220,  -- Foe Sirvente buff
                target_modifier = true,
            },
            {
                name = "Adventurer's Dirge",
                level = 75,
                cost = 0,
                id = 469,
                command = function(target)
                    return '/ma "Adventurer\'s Dirge" '..target
                end,
                element = 'Light',
                buff_id = 221,  -- Adventurer's Dirge buff
                target_modifier = true,
            },
            {
                name = 'Warding Round',
                level = 73,
                cost = 0,
                id = 414,
                command = function(target)
                    return '/ma "Warding Round" '..target
                end,
                element = 'Light',
                buff_id = 209,  -- Warding Round buff
                target_modifier = true,
            },
            {
                name = "Goddess' Hymnus",
                level = 71,
                cost = 0,
                id = 464,
                command = function(target)
                    return '/ma "Goddess\' Hymnus" '..target
                end,
                element = 'Light',
                buff_id = 218,  -- Goddess' Hymnus buff
                target_modifier = true,
            },
            {
                name = "Archer's Prelude",
                level = 71,
                cost = 0,
                id = 402,
                command = function(target)
                    return '/ma "Archer\'s Prelude" '..target
                end,
                element = 'Lightning',
                buff_id = 200,  -- Archer's Prelude buff
                target_modifier = true,
            },
            {
                name = "Puppet's Operetta",
                level = 69,
                cost = 0,
                id = 410,
                command = function(target)
                    return '/ma "Puppet\'s Operetta" '..target
                end,
                element = 'Ice',
                buff_id = 206,  -- Puppet's Operetta buff
                target_modifier = true,
            },
            {
                name = 'Shining Fantasia',
                level = 56,
                cost = 0,
                id = 408,
                command = function(target)
                    return '/ma "Shining Fantasia" '..target
                end,
                element = 'Light',
                buff_id = 205,  -- Shining Fantasia buff
                target_modifier = true,
            },
            {
                name = 'Gold Capriccio',
                level = 54,
                cost = 0,
                id = 412,
                command = function(target)
                    return '/ma "Gold Capriccio" '..target
                end,
                element = 'Wind',
                buff_id = 207,  -- Gold Capriccio buff
                target_modifier = true,
            },
            {
                name = 'Dragonfoe Mambo',
                level = 53,
                cost = 0,
                id = 404,
                command = function(target)
                    return '/ma "Dragonfoe Mambo" '..target
                end,
                element = 'Wind',
                buff_id = 201,  -- Dragonfoe Mambo buff
                target_modifier = true,
            },
            {
                name = 'Goblin Gavotte',
                level = 49,
                cost = 0,
                id = 415,
                command = function(target)
                    return '/ma "Goblin Gavotte" '..target
                end,
                element = 'Fire',
                buff_id = 210,  -- Goblin Gavotte buff
                target_modifier = true,
            },
            {
                name = 'Battlefield Elegy',
                level = 39,
                cost = 0,
                id = 421,
                command = function(target)
                    return '/ma "Battlefield Elegy" '..target
                end,
                element = 'Earth',
                buff_id = 194,  -- Battlefield Elegy buff
                target_modifier = true,
            },
            {
                name = 'Fowl Aubade',
                level = 33,
                cost = 0,
                id = 405,
                command = function(target)
                    return '/ma "Fowl Aubade" '..target
                end,
                element = 'Light',
                buff_id = 202,  -- Fowl Aubade buff
                target_modifier = true,
            },
            {
                name = "Hunter's Prelude",
                level = 31,
                cost = 0,
                id = 401,
                command = function(target)
                    return '/ma "Hunter\'s Prelude" '..target
                end,
                element = 'Lightning',
                buff_id = 200,  -- Hunter's Prelude buff
                target_modifier = true,
            },
            {
                name = "Scop's Operetta",
                level = 19,
                cost = 0,
                id = 409,
                command = function(target)
                    return '/ma "Scop\'s Operetta" '..target
                end,
                element = 'Ice',
                buff_id = 206,  -- Scop's Operetta buff
                target_modifier = true,
            },
            {
                name = 'Sheepfoe Mambo',
                level = 13,
                cost = 0,
                id = 403,
                command = function(target)
                    return '/ma "Sheepfoe Mambo" '..target
                end,
                element = 'Wind',
                buff_id = 201,  -- Sheepfoe Mambo buff
                target_modifier = true,
            },
            {
                name = 'Herb Pastoral',
                level = 9,
                cost = 0,
                id = 406,
                command = function(target)
                    return '/ma "Herb Pastoral" '..target
                end,
                element = 'Lightning',
                buff_id = 203,  -- Herb Pastoral buff
                target_modifier = true,
            },
        },
        
        -- Target modifier abilities
        target_modifier = {
            {
                name = 'Pianissimo',
                level = 20,
                cost = 0,
                id = 112,
                command = '/ja "Pianissimo" <me>',
                buff_id = 409,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
        rest_distance = 7,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'buff',
        'rest',
    }, 
}

