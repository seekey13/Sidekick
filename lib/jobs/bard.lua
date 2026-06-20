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
                note = "++++DEF",
                level = 61,
                cost = 0,
                id = 392,
                magic = 'song',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne IV buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne III",
                note = "+++DEF",
                level = 41,
                cost = 0,
                id = 391,
                magic = 'song',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne III buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne II",
                note = "++DEF",
                level = 21,
                cost = 0,
                id = 390,
                magic = 'song',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne II buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne",
                note = "+DEF",
                level = 1,
                cost = 0,
                id = 389,
                magic = 'song',
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne buff
                group = 'minne',
                target_modifier = true,
            },
            -- Minuet
            {
                name = "Valor Minuet IV",
                note = "++++ATK",
                level = 63,
                cost = 0,
                id = 397,
                magic = 'song',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet IV buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = "Valor Minuet III",
                note = "+++ATK",
                level = 43,
                cost = 0,
                id = 396,
                magic = 'song',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet III buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = "Valor Minuet II",
                note = "++ATK",
                level = 23,
                cost = 0,
                id = 395,
                magic = 'song',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet II buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = "Valor Minuet",
                note = "+ATK",
                level = 3,
                cost = 0,
                id = 394,
                magic = 'song',
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet buff
                group = 'minuet',
                target_modifier = true,
            },
            -- Paeon
            {
                name = "Army's Paeon V",
                note = "+++++Regen",
                level = 65,
                cost = 0,
                id = 382,
                magic = 'song',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon V buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon IV",
                note = "++++Regen",
                level = 45,
                cost = 0,
                id = 381,
                magic = 'song',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon IV buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon III",
                note = "+++Regen",
                level = 35,
                cost = 0,
                id = 380,
                magic = 'song',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon III buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon II",
                note = "++Regen",
                level = 15,
                cost = 0,
                id = 379,
                magic = 'song',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon II buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon",
                note = "+Regen",
                level = 5,
                cost = 0,
                id = 378,
                magic = 'song',
                element = 'Light',
                buff_id = 195,  -- Army's Paeon buff
                group = 'paeon',
                target_modifier = true,
            },
            -- Madrigal
            {
                name = "Blade Madrigal",
                note = "++ACC",
                level = 51,
                cost = 0,
                id = 400,
                magic = 'song',
                element = 'Lightning',
                buff_id = 199,  -- Blade Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            {
                name = "Sword Madrigal",
                note = "+ACC",
                level = 11,
                cost = 0,
                id = 399,
                magic = 'song',
                element = 'Lightning',
                buff_id = 199,  -- Sword Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            -- Prelude
            {
                name = "Archer's Prelude",
                note = "++Rng Acc.",
                level = 71,
                cost = 0,
                id = 402,
                magic = 'song',
                element = 'Lightning',
                buff_id = 200,  -- Archer's Prelude buff
                target_modifier = true,
                group = 'prelude',
            },
            {
                name = "Hunter's Prelude",
                note = "+Rng Acc.",
                level = 31,
                cost = 0,
                id = 401,
                magic = 'song',
                element = 'Lightning',
                buff_id = 200,  -- Hunter's Prelude buff
                target_modifier = true,
                group = 'prelude',
            },
            -- Mambo
            {
                name = "Dragonfoe Mambo",
                note = "++EVA",
                level = 53,
                cost = 0,
                id = 404,
                magic = 'song',
                element = 'Wind',
                buff_id = 201,  -- Dragonfoe Mambo buff
                target_modifier = true,
                group = 'mambo',
            },
            {
                name = "Sheepfoe Mambo",
                note = "+EVA",
                level = 13,
                cost = 0,
                id = 403,
                magic = 'song',
                element = 'Wind',
                buff_id = 201,  -- Sheepfoe Mambo buff
                target_modifier = true,
                group = 'mambo',
            },
            -- Ballad
            {
                name = "Mage's Ballad II",
                note = "++Refresh",
                level = 55,
                cost = 0,
                id = 387,
                magic = 'song',
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad II buff
                group = 'ballad',
                target_modifier = true,
            },
            {
                name = "Mage's Ballad",
                note = "+Refresh",
                level = 25,
                cost = 0,
                id = 386,
                magic = 'song',
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad buff
                group = 'ballad',
                target_modifier = true,
            },
            -- March
            {
                name = "Victory March",
                note = "++Haste",
                level = 60,
                cost = 0,
                id = 420, 
                magic = 'song',
                element = 'Lightning',
                buff_id = 214,  -- Victory March buff
                group = 'march',
                target_modifier = true,
            },
            {
                name = "Advancing March",
                note = "+Haste",
                level = 29,
                cost = 0,
                id = 419,
                magic = 'song',
                element = 'Lightning',
                buff_id = 214,  -- Advancing March buff
                group = 'march',
                target_modifier = true,
            },
            -- Etude
            {
                name = "Herculean Etude",
                note = "++STR",
                level = 74,
                cost = 0,
                id = 431,
                magic = 'song',
                element = 'Fire',
                buff_id = 215,  -- Herculean Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Uncanny Etude",
                note = "++DEX",
                level = 72,
                cost = 0,
                id = 432,
                magic = 'song',
                element = 'Lightning',
                buff_id = 215,  -- Uncanny Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Vital Etude",
                note = "++VIT",
                level = 70,
                cost = 0,
                id = 433,
                magic = 'song',
                element = 'Earth',
                buff_id = 215,  -- Vital Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Swift Etude",
                note = "++AGI",
                level = 68,
                cost = 0,
                id = 434,
                magic = 'song',
                element = 'Wind',
                buff_id = 215,  -- Swift Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Sage Etude",
                note = "++INT",
                level = 66,
                cost = 0,
                id = 435,
                magic = 'song',
                element = 'Ice',
                buff_id = 215,  -- Sage Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Logical Etude",
                note = "++MND",
                level = 64,
                cost = 0,
                id = 436,
                magic = 'song',
                element = 'Water',
                buff_id = 215,  -- Logical Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Bewitching Etude",
                note = "++CHR",
                level = 62,
                cost = 0,
                id = 437,
                magic = 'song',
                element = 'Light',
                buff_id = 215,  -- Bewitching Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Sinewy Etude",
                note = "+STR",
                level = 34,
                cost = 0,
                id = 424,
                magic = 'song',
                element = 'Fire',
                buff_id = 215,  -- Sinewy Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Dextrous Etude",
                note = "+DEX",
                level = 32,
                cost = 0,
                id = 425,
                magic = 'song',
                element = 'Lightning',
                buff_id = 215,  -- Dextrous Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Vivacious Etude",
                note = "+VIT",
                level = 30,
                cost = 0,
                id = 426,
                magic = 'song',
                element = 'Earth',
                buff_id = 215,  -- Vivacious Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Quick Etude",
                note = "+AGI",
                level = 28,
                cost = 0,
                id = 427,
                magic = 'song',
                element = 'Wind',
                buff_id = 215,  -- Quick Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Learned Etude",
                note = "+INT",
                level = 26,
                cost = 0,
                id = 428,
                magic = 'song',
                element = 'Ice',
                buff_id = 215,  -- Learned Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = "Spirited Etude",
                note = "+MND",
                level = 24,
                cost = 0,
                id = 429,
                magic = 'song',
                element = 'Water',
                buff_id = 215,  -- Spirited Etude buff
                group = 'etude',
                target_modifier = true,
            },
            -- Carols
            {
                name = "Dark Carol",
                note = "+Dark Res.",
                level = 50,
                cost = 0,
                id = 445,
                magic = 'song',
                element = 'Light',
                buff_id = 216,  -- Dark Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Lightning Carol",
                note = "+Lightning Res.",
                level = 48,
                cost = 0,
                id = 442,
                magic = 'song',
                element = 'Earth',
                buff_id = 216,  -- Lightning Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Ice Carol",
                note = "+Ice Res.",
                level = 46,
                cost = 0,
                id = 439,
                magic = 'song',
                element = 'Fire',
                buff_id = 216,  -- Ice Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Fire Carol",
                note = "+Fire Res.",
                level = 44,
                cost = 0,
                id = 438,
                magic = 'song',
                element = 'Water',
                buff_id = 216,  -- Fire Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Wind Carol",
                note = "+Wind Res.",
                level = 42,
                cost = 0,
                id = 440,
                magic = 'song',
                element = 'Ice',
                buff_id = 216,  -- Wind Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Water Carol",
                note = "+Water Res.",
                level = 40,
                cost = 0,
                id = 441,
                magic = 'song',
                element = 'Lightning',
                buff_id = 216,  -- Water Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Earth Carol",
                note = "+Earth Res.",
                level = 38,
                cost = 0,
                id = 443,
                magic = 'song',
                element = 'Wind',
                buff_id = 216,  -- Earth Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = "Light Carol",
                note = "+Light Res.",
                level = 36,
                cost = 0,
                id = 444,
                magic = 'song',
                element = 'Dark',
                buff_id = 216,  -- Light Carol buff
                group = 'carol',
                target_modifier = true,
            },
            -- Mazurkas
            {
                name = "Chocobo Mazurka",
                note = "+Move Spd.",
                level = 73,
                cost = 0,
                id = 465,
                magic = 'song',
                element = 'Wind',
                buff_id = 219,  -- Chocobo Mazurka buff
                group = 'mazurka',
                idle_only = true,
            },
            {
                name = "Raptor Mazurka",
                note = "+Move Spd.",
                level = 37,
                cost = 0,
                id = 467,
                magic = 'song',
                element = 'Wind',
                buff_id = 219,  -- Raptor Mazurka buff
                group = 'mazurka',
                idle_only = true,
            },
            -- Resistance
            {
                name = "Warding Round",
                note = "+Curse Res.",
                level = 73,
                cost = 0,
                id = 414,
                magic = 'song',
                element = 'Light',
                buff_id = 209,  -- Warding Round buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Puppet's Operetta",
                note = "+Silence Res.",
                level = 69,
                cost = 0,
                id = 410,
                magic = 'song',
                element = 'Ice',
                buff_id = 206,  -- Puppet's Operetta buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Shining Fantasia",
                note = "+Blind Res.",
                level = 56,
                cost = 0,
                id = 408,
                magic = 'song',
                element = 'Light',
                buff_id = 205,  -- Shining Fantasia buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Gold Capriccio",
                note = "+Pet. Res.",
                level = 54,
                cost = 0,
                id = 412,
                magic = 'song',
                element = 'Wind',
                buff_id = 207,  -- Gold Capriccio buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Goblin Gavotte",
                note = "+Bind Res.",
                level = 49,
                cost = 0,
                id = 415,
                magic = 'song',
                element = 'Fire',
                buff_id = 210,  -- Goblin Gavotte buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Fowl Aubade",
                note = "+Slow Res.",
                level = 33,
                cost = 0,
                id = 405,
                magic = 'song',
                element = 'Light',
                buff_id = 202,  -- Fowl Aubade buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Scop's Operetta",
                note = "+Silence Res.",
                level = 19,
                cost = 0,
                id = 409,
                magic = 'song',
                element = 'Ice',
                buff_id = 206,  -- Scop's Operetta buff
                target_modifier = true,
                group = 'resistance',
            },

            {
                name = "Herb Pastoral",
                note = "+Poison Res.",
                level = 9,
                cost = 0,
                id = 406,
                magic = 'song',
                element = 'Lightning',
                buff_id = 203,  -- Herb Pastoral buff
                target_modifier = true,
                group = 'resistance',
            },
            -- Others
            {
                name = "Goddess's Hymnus",
                note = "Reraise",
                level = 71,
                cost = 0,
                id = 464,
                magic = 'song',
                element = 'Light',
                buff_id = 218,  -- Goddess's Hymnus buff
                target_modifier = true,
            },
            {
                name = "Foe Sirvente",
                note = "+Emnity",
                level = 75,
                cost = 0,
                id = 468,
                magic = 'song',
                element = 'Light',
                buff_id = 220,  -- Foe Sirvente buff
                target_modifier = true,
            },
            {
                name = "Adventurer's Dirge",
                note = "-Emnity",
                level = 75,
                cost = 0,
                id = 469,
                magic = 'song',
                element = 'Light',
                buff_id = 221,  -- Adventurer's Dirge buff
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

