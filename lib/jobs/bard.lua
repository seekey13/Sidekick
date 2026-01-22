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
                command = '/ma "Knight\'s Minne IV" <me>',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne IV buff
                group = 'minne',
            },
            {
                name = "Knight's Minne III",
                level = 41,
                cost = 0,
                id = 391,
                command = '/ma "Knight\'s Minne III" <me>',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne III buff
                group = 'minne',
            },
            {
                name = "Knight's Minne II",
                level = 21,
                cost = 0,
                id = 390,
                command = '/ma "Knight\'s Minne II" <me>',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne II buff
                group = 'minne',
            },
            {
                name = "Knight's Minne",
                level = 1,
                cost = 0,
                id = 389,
                command = '/ma "Knight\'s Minne" <me>',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne buff
                group = 'minne',
            },
            -- Minuet
            {
                name = 'Valor Minuet IV',
                level = 63,
                cost = 0,
                id = 397,
                command = '/ma "Valor Minuet IV" <me>',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet IV buff
                group = 'minuet',
            },
            {
                name = 'Valor Minuet III',
                level = 43,
                cost = 0,
                id = 396,
                command = '/ma "Valor Minuet III" <me>',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet III buff
                group = 'minuet',
            },
            {
                name = 'Valor Minuet II',
                level = 23,
                cost = 0,
                id = 395,
                command = '/ma "Valor Minuet II" <me>',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet II buff
                group = 'minuet',
            },
            {
                name = 'Valor Minuet',
                level = 3,
                cost = 0,
                id = 394,
                command = '/ma "Valor Minuet" <me>',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet buff
                group = 'minuet',
            },
            -- Paeon
            {
                name = "Army's Paeon V",
                level = 65,
                cost = 0,
                id = 382,
                command = '/ma "Army\'s Paeon V" <me>',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon V buff
                group = 'paeon',
            },
            {
                name = "Army's Paeon IV",
                level = 45,
                cost = 0,
                id = 381,
                command = '/ma "Army\'s Paeon IV" <me>',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon IV buff
                group = 'paeon',
            },
            {
                name = "Army's Paeon III",
                level = 35,
                cost = 0,
                id = 380,
                command = '/ma "Army\'s Paeon III" <me>',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon III buff
                group = 'paeon',
            },
            {
                name = "Army's Paeon II",
                level = 15,
                cost = 0,
                id = 379,
                command = '/ma "Army\'s Paeon II" <me>',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon II buff
                group = 'paeon',
            },
            {
                name = "Army's Paeon",
                level = 5,
                cost = 0,
                id = 378,
                command = '/ma "Army\'s Paeon" <me>',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon buff
                group = 'paeon',
            },
            -- Madrigal
            {
                name = 'Blade Madrigal',
                level = 51,
                cost = 0,
                id = 400,
                command = '/ma "Blade Madrigal" <me>',
                element = 'Lightning',
                buff_id = 199,  -- Blade Madrigal buff
                group = 'madrigal',
            },
            {
                name = 'Sword Madrigal',
                level = 11,
                cost = 0,
                id = 399,
                command = '/ma "Sword Madrigal" <me>',
                element = 'Lightning',
                buff_id = 199,  -- Sword Madrigal buff
                group = 'madrigal',
            },
            -- Ballad
            {
                name = "Mage's Ballad II",
                level = 55,
                cost = 0,
                id = 387,
                command = '/ma "Mage\'s Ballad II" <me>',
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad II buff
                group = 'ballad',
            },
            {
                name = "Mage's Ballad",
                level = 25,
                cost = 0,
                id = 386,
                command = '/ma "Mage\'s Ballad" <me>',
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad buff
                group = 'ballad',
            },
            -- March
            {
                name = 'Victory March',
                level = 60,
                cost = 0,
                id = 420, 
                command = '/ma "Victory March" <me>',
                element = 'Lightning',
                buff_id = 214,  -- Victory March buff
                group = 'march',
            },
            {
                name = 'Advancing March',
                level = 29,
                cost = 0,
                id = 419,
                command = '/ma "Advancing March" <me>',
                element = 'Lightning',
                buff_id = 214,  -- Advancing March buff
                group = 'march',
            },
            -- Etude
            {
                name = 'Herculean Etude',
                level = 74,
                cost = 0,
                id = 431,
                command = '/ma "Herculean Etude" <me>',
                element = 'Fire',
                buff_id = 215,  -- Herculean Etude buff
                group = 'etude',
            },
            {
                name = 'Uncanny Etude',
                level = 72,
                cost = 0,
                id = 432,
                command = '/ma "Uncanny Etude" <me>',
                element = 'Lightning',
                buff_id = 215,  -- Uncanny Etude buff
                group = 'etude',
            },
            {
                name = 'Vital Etude',
                level = 70,
                cost = 0,
                id = 433,
                command = '/ma "Vital Etude" <me>',
                element = 'Earth',
                buff_id = 215,  -- Vital Etude buff
                group = 'etude',
            },
            {
                name = 'Swift Etude',
                level = 68,
                cost = 0,
                id = 434,
                command = '/ma "Swift Etude" <me>',
                element = 'Wind',
                buff_id = 215,  -- Swift Etude buff
                group = 'etude',
            },
            {
                name = 'Sage Etude',
                level = 66,
                cost = 0,
                id = 435,
                command = '/ma "Sage Etude" <me>',
                element = 'Ice',
                buff_id = 215,  -- Sage Etude buff
                group = 'etude',
            },
            {
                name = 'Logical Etude',
                level = 64,
                cost = 0,
                id = 436,
                command = '/ma "Logical Etude" <me>',
                element = 'Water',
                buff_id = 215,  -- Logical Etude buff
                group = 'etude',
            },
            {
                name = 'Bewitching Etude',
                level = 62,
                cost = 0,
                id = 437,
                command = '/ma "Bewitching Etude" <me>',
                element = 'Light',
                buff_id = 215,  -- Bewitching Etude buff
                group = 'etude',
            },
            {
                name = 'Sinewy Etude',
                level = 34,
                cost = 0,
                id = 424,
                command = '/ma "Sinewy Etude" <me>',
                element = 'Fire',
                buff_id = 215,  -- Sinewy Etude buff
                group = 'etude',
            },
            {
                name = 'Dextrous Etude',
                level = 32,
                cost = 0,
                id = 425,
                command = '/ma "Dextrous Etude" <me>',
                element = 'Lightning',
                buff_id = 215,  -- Dextrous Etude buff
                group = 'etude',
            },
            {
                name = 'Vivacious Etude',
                level = 30,
                cost = 0,
                id = 426,
                command = '/ma "Vivacious Etude" <me>',
                element = 'Earth',
                buff_id = 215,  -- Vivacious Etude buff
                group = 'etude',
            },
            {
                name = 'Quick Etude',
                level = 28,
                cost = 0,
                id = 427,
                command = '/ma "Quick Etude" <me>',
                element = 'Wind',
                buff_id = 215,  -- Quick Etude buff
                group = 'etude',
            },
            {
                name = 'Learned Etude',
                level = 26,
                cost = 0,
                id = 428,
                command = '/ma "Learned Etude" <me>',
                element = 'Ice',
                buff_id = 215,  -- Learned Etude buff
                group = 'etude',
            },
            {
                name = 'Spirited Etude',
                level = 24,
                cost = 0,
                id = 429,
                command = '/ma "Spirited Etude" <me>',
                element = 'Water',
                buff_id = 215,  -- Spirited Etude buff
                group = 'etude',
            },
            -- Carols
            {
                name = 'Dark Carol',
                level = 50,
                cost = 0,
                id = 445,
                command = '/ma "Dark Carol" <me>',
                element = 'Light',
                buff_id = 216,  -- Dark Carol buff
                group = 'carol',
            },
            {
                name = 'Lightning Carol',
                level = 48,
                cost = 0,
                id = 442,
                command = '/ma "Lightning Carol" <me>',
                element = 'Earth',
                buff_id = 216,  -- Lightning Carol buff
                group = 'carol',
            },
            {
                name = 'Ice Carol',
                level = 46,
                cost = 0,
                id = 439,
                command = '/ma "Ice Carol" <me>',
                element = 'Fire',
                buff_id = 216,  -- Ice Carol buff
                group = 'carol',
            },
            {
                name = 'Fire Carol',
                level = 44,
                cost = 0,
                id = 438,
                command = '/ma "Fire Carol" <me>',
                element = 'Water',
                buff_id = 216,  -- Fire Carol buff
                group = 'carol',
            },
            {
                name = 'Wind Carol',
                level = 42,
                cost = 0,
                id = 440,
                command = '/ma "Wind Carol" <me>',
                element = 'Ice',
                buff_id = 216,  -- Wind Carol buff
                group = 'carol',
            },
            {
                name = 'Water Carol',
                level = 40,
                cost = 0,
                id = 441,
                command = '/ma "Water Carol" <me>',
                element = 'Lightning',
                buff_id = 216,  -- Water Carol buff
                group = 'carol',
            },
            {
                name = 'Earth Carol',
                level = 38,
                cost = 0,
                id = 443,
                command = '/ma "Earth Carol" <me>',
                element = 'Wind',
                buff_id = 216,  -- Earth Carol buff
                group = 'carol',
            },
            {
                name = 'Light Carol',
                level = 36,
                cost = 0,
                id = 444,
                command = '/ma "Light Carol" <me>',
                element = 'Dark',
                buff_id = 216,  -- Light Carol buff
                group = 'carol',
            },
            -- Mazurkas
            {
                name = 'Chocobo Mazurka',
                level = 73,
                cost = 0,
                id = 465,
                command = '/ma "Chocobo Mazurka" <me>',
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
                command = '/ma "Raptor Mazurka" <me>',
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
                command = '/ma "Foe Sirvente" <me>',
                element = 'Light',
                buff_id = 220,  -- Foe Sirvente buff
            },
            {
                name = "Adventurer's Dirge",
                level = 75,
                cost = 0,
                id = 469,
                command = '/ma "Adventurer\'s Dirge" <me>',
                element = 'Light',
                buff_id = 221,  -- Adventurer's Dirge buff
            },
            {
                name = 'Warding Round',
                level = 73,
                cost = 0,
                id = 414,
                command = '/ma "Warding Round" <me>',
                element = 'Light',
                buff_id = 209,  -- Warding Round buff
            },
            {
                name = "Goddess' Hymnus",
                level = 71,
                cost = 0,
                id = 464,
                command = '/ma "Goddess\' Hymnus" <me>',
                element = 'Light',
                buff_id = 218,  -- Goddess' Hymnus buff
            },
            {
                name = "Archer's Prelude",
                level = 71,
                cost = 0,
                id = 402,
                command = '/ma "Archer\'s Prelude" <me>',
                element = 'Lightning',
                buff_id = 200,  -- Archer's Prelude buff
            },
            {
                name = "Puppet's Operetta",
                level = 69,
                cost = 0,
                id = 410,
                command = '/ma "Puppet\'s Operetta" <me>',
                element = 'Ice',
                buff_id = 206,  -- Puppet's Operetta buff
            },
            {
                name = 'Shining Fantasia',
                level = 56,
                cost = 0,
                id = 408,
                command = '/ma "Shining Fantasia" <me>',
                element = 'Light',
                buff_id = 205,  -- Shining Fantasia buff
            },
            {
                name = 'Gold Capriccio',
                level = 54,
                cost = 0,
                id = 412,
                command = '/ma "Gold Capriccio" <me>',
                element = 'Wind',
                buff_id = 207,  -- Gold Capriccio buff
            },
            {
                name = 'Dragonfoe Mambo',
                level = 53,
                cost = 0,
                id = 404,
                command = '/ma "Dragonfoe Mambo" <me>',
                element = 'Wind',
                buff_id = 201,  -- Dragonfoe Mambo buff
            },
            {
                name = 'Goblin Gavotte',
                level = 49,
                cost = 0,
                id = 415,
                command = '/ma "Goblin Gavotte" <me>',
                element = 'Fire',
                buff_id = 210,  -- Goblin Gavotte buff
            },
            {
                name = 'Battlefield Elegy',
                level = 39,
                cost = 0,
                id = 421,
                command = '/ma "Battlefield Elegy" <me>',
                element = 'Earth',
                buff_id = 194,  -- Battlefield Elegy buff
            },
            {
                name = 'Fowl Aubade',
                level = 33,
                cost = 0,
                id = 405,
                command = '/ma "Fowl Aubade" <me>',
                element = 'Light',
                buff_id = 202,  -- Fowl Aubade buff
            },
            {
                name = "Hunter's Prelude",
                level = 31,
                cost = 0,
                id = 401,
                command = '/ma "Hunter\'s Prelude" <me>',
                element = 'Lightning',
                buff_id = 200,  -- Hunter's Prelude buff
            },
            {
                name = "Scop's Operetta",
                level = 19,
                cost = 0,
                id = 409,
                command = '/ma "Scop\'s Operetta" <me>',
                element = 'Ice',
                buff_id = 206,  -- Scop's Operetta buff
            },
            {
                name = 'Sheepfoe Mambo',
                level = 13,
                cost = 0,
                id = 403,
                command = '/ma "Sheepfoe Mambo" <me>',
                element = 'Wind',
                buff_id = 201,  -- Sheepfoe Mambo buff
            },
            {
                name = 'Herb Pastoral',
                level = 9,
                cost = 0,
                id = 406,
                command = '/ma "Herb Pastoral" <me>',
                element = 'Lightning',
                buff_id = 203,  -- Herb Pastoral buff
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
        rest_enabled = false,
        rest_timer = 5,
        rest_threshold = 70,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'buff',
        'rest',
    }, 
}