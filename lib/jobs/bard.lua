--[[
    Bard job definition
    Defines abilities, validators, and configuration for Bard automation
    - Buff songs (Minuets, Paeons, Madrigals, etc.)
]]--


return {
    job_id = 10,
    job_name = 'Bard',
    resource_type = 'mp',
    
    abilities = {
        -- Buff songs
        buff = {
            -- Minne
            {
                name = "Knight's Minne IV (++++DEF)",
                level = 61,
                cost = 0,
                id = 392,
                magic = 'song',
                command = function(target)
                    return '/ma "Knight\'s Minne IV" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne IV buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne III (+++DEF)",
                level = 41,
                cost = 0,
                id = 391,
                magic = 'song',
                command = function(target)
                    return '/ma "Knight\'s Minne III" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne III buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne II (++DEF)",
                level = 21,
                cost = 0,
                id = 390,
                magic = 'song',
                command = function(target)
                    return '/ma "Knight\'s Minne II" '..target
                end,
                element = 'Earth',
                buff_id = 197,  -- Knight's Minne II buff
                group = 'minne',
                target_modifier = true,
            },
            {
                name = "Knight's Minne (+DEF)",
                level = 1,
                cost = 0,
                id = 389,
                magic = 'song',
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
                name = 'Valor Minuet IV (++++ATK)',
                level = 63,
                cost = 0,
                id = 397,
                magic = 'song',
                command = function(target)
                    return '/ma "Valor Minuet IV" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet IV buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet III (+++ATK)',
                level = 43,
                cost = 0,
                id = 396,
                magic = 'song',
                command = function(target)
                    return '/ma "Valor Minuet III" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet III buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet II (++ATK)',
                level = 23,
                cost = 0,
                id = 395,
                magic = 'song',
                command = function(target)
                    return '/ma "Valor Minuet II" '..target
                end,
                element = 'Fire',
                buff_id = 198,  -- Valor Minuet II buff
                group = 'minuet',
                target_modifier = true,
            },
            {
                name = 'Valor Minuet (+ATK)',
                level = 3,
                cost = 0,
                id = 394,
                magic = 'song',
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
                name = "Army's Paeon V (+++++Regen)",
                level = 65,
                cost = 0,
                id = 382,
                magic = 'song',
                command = function(target)
                    return '/ma "Army\'s Paeon V" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon V buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon IV (++++Regen)",
                level = 45,
                cost = 0,
                id = 381,
                magic = 'song',
                command = function(target)
                    return '/ma "Army\'s Paeon IV" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon IV buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon III (+++Regen)",
                level = 35,
                cost = 0,
                id = 380,
                magic = 'song',
                command = function(target)
                    return '/ma "Army\'s Paeon III" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon III buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon II (++Regen)",
                level = 15,
                cost = 0,
                id = 379,
                magic = 'song',
                command = function(target)
                    return '/ma "Army\'s Paeon II" '..target
                end,
                element = 'Light',
                buff_id = 195,  -- Army's Paeon II buff
                group = 'paeon',
                target_modifier = true,
            },
            {
                name = "Army's Paeon (+Regen)",
                level = 5,
                cost = 0,
                id = 378,
                magic = 'song',
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
                name = 'Blade Madrigal (++ACC)',
                level = 51,
                cost = 0,
                id = 400,
                magic = 'song',
                command = function(target)
                    return '/ma "Blade Madrigal" '..target
                end,
                element = 'Lightning',
                buff_id = 199,  -- Blade Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            {
                name = 'Sword Madrigal (+ACC)',
                level = 11,
                cost = 0,
                id = 399,
                magic = 'song',
                command = function(target)
                    return '/ma "Sword Madrigal" '..target
                end,
                element = 'Lightning',
                buff_id = 199,  -- Sword Madrigal buff
                group = 'madrigal',
                target_modifier = true,
            },
            -- Prelude
            {
                name = "Archer's Prelude (++Rng Acc.)",
                level = 71,
                cost = 0,
                id = 402,
                magic = 'song',
                command = function(target)
                    return '/ma "Archer\'s Prelude" '..target
                end,
                element = 'Lightning',
                buff_id = 200,  -- Archer's Prelude buff
                target_modifier = true,
                group = 'prelude',
            },
            {
                name = "Hunter's Prelude (+Rng Acc.)",
                level = 31,
                cost = 0,
                id = 401,
                magic = 'song',
                command = function(target)
                    return '/ma "Hunter\'s Prelude" '..target
                end,
                element = 'Lightning',
                buff_id = 200,  -- Hunter's Prelude buff
                target_modifier = true,
                group = 'prelude',
            },
            -- Mambo
            {
                name = 'Dragonfoe Mambo (++EVA)',
                level = 53,
                cost = 0,
                id = 404,
                magic = 'song',
                command = function(target)
                    return '/ma "Dragonfoe Mambo" '..target
                end,
                element = 'Wind',
                buff_id = 201,  -- Dragonfoe Mambo buff
                target_modifier = true,
                group = 'mambo',
            },
            {
                name = 'Sheepfoe Mambo (+EVA)',
                level = 13,
                cost = 0,
                id = 403,
                magic = 'song',
                command = function(target)
                    return '/ma "Sheepfoe Mambo" '..target
                end,
                element = 'Wind',
                buff_id = 201,  -- Sheepfoe Mambo buff
                target_modifier = true,
                group = 'mambo',
            },
            -- Ballad
            {
                name = "Mage's Ballad II (++Refresh)",
                level = 55,
                cost = 0,
                id = 387,
                magic = 'song',
                command = function(target)
                    return '/ma "Mage\'s Ballad II" '..target
                end,
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad II buff
                group = 'ballad',
                target_modifier = true,
            },
            {
                name = "Mage's Ballad (+Refresh)",
                level = 25,
                cost = 0,
                id = 386,
                magic = 'song',
                command = function(target)
                    return '/ma "Mage\'s Ballad" '..target
                end,
                element = 'Light',
                buff_id = 196,  -- Mage's Ballad buff
                group = 'ballad',
                target_modifier = true,
            },
            -- March
            {
                name = 'Victory March (++Haste)',
                level = 60,
                cost = 0,
                id = 420, 
                magic = 'song',
                command = function(target)
                    return '/ma "Victory March" '..target
                end,
                element = 'Lightning',
                buff_id = 214,  -- Victory March buff
                group = 'march',
                target_modifier = true,
            },
            {
                name = 'Advancing March (+Haste)',
                level = 29,
                cost = 0,
                id = 419,
                magic = 'song',
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
                name = 'Herculean Etude (++STR)',
                level = 74,
                cost = 0,
                id = 431,
                magic = 'song',
                command = function(target)
                    return '/ma "Herculean Etude" '..target
                end,
                element = 'Fire',
                buff_id = 215,  -- Herculean Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Uncanny Etude (++DEX)',
                level = 72,
                cost = 0,
                id = 432,
                magic = 'song',
                command = function(target)
                    return '/ma "Uncanny Etude" '..target
                end,
                element = 'Lightning',
                buff_id = 215,  -- Uncanny Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Vital Etude (++VIT)',
                level = 70,
                cost = 0,
                id = 433,
                magic = 'song',
                command = function(target)
                    return '/ma "Vital Etude" '..target
                end,
                element = 'Earth',
                buff_id = 215,  -- Vital Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Swift Etude (++AGI)',
                level = 68,
                cost = 0,
                id = 434,
                magic = 'song',
                command = function(target)
                    return '/ma "Swift Etude" '..target
                end,
                element = 'Wind',
                buff_id = 215,  -- Swift Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Sage Etude (++INT)',
                level = 66,
                cost = 0,
                id = 435,
                magic = 'song',
                command = function(target)
                    return '/ma "Sage Etude" '..target
                end,
                element = 'Ice',
                buff_id = 215,  -- Sage Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Logical Etude (++MND)',
                level = 64,
                cost = 0,
                id = 436,
                magic = 'song',
                command = function(target)
                    return '/ma "Logical Etude" '..target
                end,
                element = 'Water',
                buff_id = 215,  -- Logical Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Bewitching Etude (++CHR)',
                level = 62,
                cost = 0,
                id = 437,
                magic = 'song',
                command = function(target)
                    return '/ma "Bewitching Etude" '..target
                end,
                element = 'Light',
                buff_id = 215,  -- Bewitching Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Sinewy Etude (+STR)',
                level = 34,
                cost = 0,
                id = 424,
                magic = 'song',
                command = function(target)
                    return '/ma "Sinewy Etude" '..target
                end,
                element = 'Fire',
                buff_id = 215,  -- Sinewy Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Dextrous Etude (+DEX)',
                level = 32,
                cost = 0,
                id = 425,
                magic = 'song',
                command = function(target)
                    return '/ma "Dextrous Etude" '..target
                end,
                element = 'Lightning',
                buff_id = 215,  -- Dextrous Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Vivacious Etude (+VIT)',
                level = 30,
                cost = 0,
                id = 426,
                magic = 'song',
                command = function(target)
                    return '/ma "Vivacious Etude" '..target
                end,
                element = 'Earth',
                buff_id = 215,  -- Vivacious Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Quick Etude (+AGI)',
                level = 28,
                cost = 0,
                id = 427,
                magic = 'song',
                command = function(target)
                    return '/ma "Quick Etude" '..target
                end,
                element = 'Wind',
                buff_id = 215,  -- Quick Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Learned Etude (+INT)',
                level = 26,
                cost = 0,
                id = 428,
                magic = 'song',
                command = function(target)
                    return '/ma "Learned Etude" '..target
                end,
                element = 'Ice',
                buff_id = 215,  -- Learned Etude buff
                group = 'etude',
                target_modifier = true,
            },
            {
                name = 'Spirited Etude (+MND)',
                level = 24,
                cost = 0,
                id = 429,
                magic = 'song',
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
                name = 'Dark Carol (+Dark Res.)',
                level = 50,
                cost = 0,
                id = 445,
                magic = 'song',
                command = function(target)
                    return '/ma "Dark Carol" '..target
                end,
                element = 'Light',
                buff_id = 216,  -- Dark Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Lightning Carol (+Lightning Res.)',
                level = 48,
                cost = 0,
                id = 442,
                magic = 'song',
                command = function(target)
                    return '/ma "Lightning Carol" '..target
                end,
                element = 'Earth',
                buff_id = 216,  -- Lightning Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Ice Carol (+Ice Res.)',
                level = 46,
                cost = 0,
                id = 439,
                magic = 'song',
                command = function(target)
                    return '/ma "Ice Carol" '..target
                end,
                element = 'Fire',
                buff_id = 216,  -- Ice Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Fire Carol (+Fire Res.)',
                level = 44,
                cost = 0,
                id = 438,
                magic = 'song',
                command = function(target)
                    return '/ma "Fire Carol" '..target
                end,
                element = 'Water',
                buff_id = 216,  -- Fire Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Wind Carol (+Wind Res.)',
                level = 42,
                cost = 0,
                id = 440,
                magic = 'song',
                command = function(target)
                    return '/ma "Wind Carol" '..target
                end,
                element = 'Ice',
                buff_id = 216,  -- Wind Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Water Carol (+Water Res.)',
                level = 40,
                cost = 0,
                id = 441,
                magic = 'song',
                command = function(target)
                    return '/ma "Water Carol" '..target
                end,
                element = 'Lightning',
                buff_id = 216,  -- Water Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Earth Carol (+Earth Res.)',
                level = 38,
                cost = 0,
                id = 443,
                magic = 'song',
                command = function(target)
                    return '/ma "Earth Carol" '..target
                end,
                element = 'Wind',
                buff_id = 216,  -- Earth Carol buff
                group = 'carol',
                target_modifier = true,
            },
            {
                name = 'Light Carol (+Light Res.)',
                level = 36,
                cost = 0,
                id = 444,
                magic = 'song',
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
                name = 'Chocobo Mazurka (+Move Spd.)',
                level = 73,
                cost = 0,
                id = 465,
                magic = 'song',
                command = function(target)
                    return '/ma "Chocobo Mazurka" '..target
                end,
                element = 'Wind',
                buff_id = 219,  -- Chocobo Mazurka buff
                group = 'mazurka',
                target_modifier = true,
            },
            {
                name = 'Raptor Mazurka (+Move Spd.)',
                level = 37,
                cost = 0,
                id = 467,
                magic = 'song',
                command = function(target)
                    return '/ma "Raptor Mazurka" '..target
                end,
                element = 'Wind',
                buff_id = 219,  -- Raptor Mazurka buff
                group = 'mazurka',
                target_modifier = true,
            },
            -- Resistance
            {
                name = 'Warding Round(+Curse Res.)',
                level = 73,
                cost = 0,
                id = 414,
                magic = 'song',
                command = function(target)
                    return '/ma "Warding Round" '..target
                end,
                element = 'Light',
                buff_id = 209,  -- Warding Round buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Puppet's Operetta (+Silence Res.)",
                level = 69,
                cost = 0,
                id = 410,
                magic = 'song',
                command = function(target)
                    return '/ma "Puppet\'s Operetta" '..target
                end,
                element = 'Ice',
                buff_id = 206,  -- Puppet's Operetta buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = 'Shining Fantasia (+Blind Res.)',
                level = 56,
                cost = 0,
                id = 408,
                magic = 'song',
                command = function(target)
                    return '/ma "Shining Fantasia" '..target
                end,
                element = 'Light',
                buff_id = 205,  -- Shining Fantasia buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = 'Gold Capriccio (+Pet. Res.)',
                level = 54,
                cost = 0,
                id = 412,
                magic = 'song',
                command = function(target)
                    return '/ma "Gold Capriccio" '..target
                end,
                element = 'Wind',
                buff_id = 207,  -- Gold Capriccio buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = 'Goblin Gavotte (+Bind Res.)',
                level = 49,
                cost = 0,
                id = 415,
                magic = 'song',
                command = function(target)
                    return '/ma "Goblin Gavotte" '..target
                end,
                element = 'Fire',
                buff_id = 210,  -- Goblin Gavotte buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = 'Fowl Aubade (+Slow Res.)',
                level = 33,
                cost = 0,
                id = 405,
                magic = 'song',
                command = function(target)
                    return '/ma "Fowl Aubade" '..target
                end,
                element = 'Light',
                buff_id = 202,  -- Fowl Aubade buff
                target_modifier = true,
                group = 'resistance',
            },
            {
                name = "Scop's Operetta (+Silence Res.)",
                level = 19,
                cost = 0,
                id = 409,
                magic = 'song',
                command = function(target)
                    return '/ma "Scop\'s Operetta" '..target
                end,
                element = 'Ice',
                buff_id = 206,  -- Scop's Operetta buff
                target_modifier = true,
                group = 'resistance',
            },

            {
                name = 'Herb Pastoral (+Poison Res.)',
                level = 9,
                cost = 0,
                id = 406,
                magic = 'song',
                command = function(target)
                    return '/ma "Herb Pastoral" '..target
                end,
                element = 'Lightning',
                buff_id = 203,  -- Herb Pastoral buff
                target_modifier = true,
                group = 'resistance',
            },
            -- Others
            {
                name = "Goddess's Hymnus (Reraise)",
                level = 71,
                cost = 0,
                id = 464,
                magic = 'song',
                command = function(target)
                    return '/ma "Goddess\'s Hymnus" '..target
                end,
                element = 'Light',
                buff_id = 218,  -- Goddess's Hymnus buff
                target_modifier = true,
            },
            {
                name = 'Foe Sirvente (+Emnity)',
                level = 75,
                cost = 0,
                id = 468,
                magic = 'song',
                command = function(target)
                    return '/ma "Foe Sirvente" '..target
                end,
                element = 'Light',
                buff_id = 220,  -- Foe Sirvente buff
                target_modifier = true,
            },
            {
                name = "Adventurer's Dirge (-Emnity)",
                level = 75,
                cost = 0,
                id = 469,
                magic = 'song',
                command = function(target)
                    return '/ma "Adventurer\'s Dirge" '..target
                end,
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

        pianissimo_fast_casting = false,  -- see lib/actions/buff.lua area phase
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'buff',
        'rest',
    }, 
}

