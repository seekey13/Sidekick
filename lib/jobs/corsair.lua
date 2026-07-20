--[[
    Corsair job definition
    Rolls only -- Phantom Roll + Double-Up automation, plus the Snake Eye / Fold
    roll-manipulation merits (see lib/actions/roll.lua).
    Quick Draw / Ranged Attack / Random Deal are deliberately absent: Sidekick is
    support-only and does not automate combat.

    Every roll shares Phantom Roll's recast (abilities.sql recastId 193), so the
    recast_id is identical on all 25 -- the roll you pick is chosen by command text,
    not by timer. `lucky` is the total that grants the bonus effect; `unlucky` is
    kept as reference data only and is NOT read by the roll logic.

    `ability_id` is abilities.sql `abilityId`, and does double duty here:
      - common.has_spell_learned gates on HasAbility(ability_id + 512), so rolls the
        player hasn't actually learned are dropped by filter_abilities_by_level and
        never offered in the UI. Level alone is not enough -- rolls are unlocked
        individually, so a level-75 COR does not know every roll below 75.
      - lib/actions/roll.lua matches a 0x028 action packet's cmd_arg back to the roll
        that produced it (the server rewrites cmd_arg to the underlying roll's id on
        a Double-Up, so every packet self-identifies).
]]--

return {
    job_id = 17,  -- Corsair
    job_name = 'Corsair',
    resource_type = 'tp',

    abilities = {
        -- Rolls (all share Phantom Roll recast 193)
        roll = {
            {
                name = 'Corsair\'s Roll (EXP+)',
                level = 5,
                cost = 0,
                recast_id = 193,  -- Phantom Roll recast ID
                ability_id = 114, -- abilities.sql abilityId (learned-check + packet match)
                command = '/ja "Corsair\'s Roll" <me>',
                buff_id = 326,  -- Corsair's Roll buff
                lucky = 5,
                unlucky = 9,
            },
            {
                name = 'Ninja Roll (EVA+)',
                level = 8,
                cost = 0,
                recast_id = 193,
                ability_id = 110,
                command = '/ja "Ninja Roll" <me>',
                buff_id = 322,  -- Ninja Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Hunter\'s Roll (ACC+)',
                level = 11,
                cost = 0,
                recast_id = 193,
                ability_id = 108,
                command = '/ja "Hunter\'s Roll" <me>',
                buff_id = 320,  -- Hunter's Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Chaos Roll (ATK+)',
                level = 14,
                cost = 0,
                recast_id = 193,
                ability_id = 105,
                command = '/ja "Chaos Roll" <me>',
                buff_id = 317,  -- Chaos Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Magus\'s Roll (MDEF+)',
                level = 17,
                cost = 0,
                recast_id = 193,
                ability_id = 113,
                command = '/ja "Magus\'s Roll" <me>',
                buff_id = 325,  -- Magus's Roll buff
                lucky = 2,
                unlucky = 6,
            },
            {
                name = 'Healer\'s Roll (Cure+)',
                level = 20,
                cost = 0,
                recast_id = 193,
                ability_id = 100,
                command = '/ja "Healer\'s Roll" <me>',
                buff_id = 312,  -- Healer's Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Drachen Roll (PACC+)',
                level = 23,
                cost = 0,
                recast_id = 193,
                ability_id = 111,
                command = '/ja "Drachen Roll" <me>',
                buff_id = 323,  -- Drachen Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Choral Roll (SIR-)',
                level = 26,
                cost = 0,
                recast_id = 193,
                ability_id = 107,
                command = '/ja "Choral Roll" <me>',
                buff_id = 319,  -- Choral Roll buff
                lucky = 2,
                unlucky = 6,
            },
            {
                name = 'Monk\'s Roll (SB+)',
                level = 31,
                cost = 0,
                recast_id = 193,
                ability_id = 99,
                command = '/ja "Monk\'s Roll" <me>',
                buff_id = 311,  -- Monk's Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Beast Roll (PATK+)',
                level = 34,
                cost = 0,
                recast_id = 193,
                ability_id = 106,
                command = '/ja "Beast Roll" <me>',
                buff_id = 318,  -- Beast Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Samurai Roll (STP+)',
                level = 34,
                cost = 0,
                recast_id = 193,
                ability_id = 109,
                command = '/ja "Samurai Roll" <me>',
                buff_id = 321,  -- Samurai Roll buff
                lucky = 2,
                unlucky = 6,
            },
            {
                name = 'Evoker\'s Roll (Refresh+)',
                level = 40,
                cost = 0,
                recast_id = 193,
                ability_id = 112,
                command = '/ja "Evoker\'s Roll" <me>',
                buff_id = 324,  -- Evoker's Roll buff
                lucky = 5,
                unlucky = 9,
            },
            {
                name = 'Rogue\'s Roll (CRIT+)',
                level = 43,
                cost = 0,
                recast_id = 193,
                ability_id = 103,
                command = '/ja "Rogue\'s Roll" <me>',
                buff_id = 315,  -- Rogue's Roll buff
                lucky = 5,
                unlucky = 9,
            },
            {
                name = 'Warlock\'s Roll (MACC+)',
                level = 46,
                cost = 0,
                recast_id = 193,
                ability_id = 102,
                command = '/ja "Warlock\'s Roll" <me>',
                buff_id = 314,  -- Warlock's Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Fighter\'s Roll (DA+)',
                level = 49,
                cost = 0,
                recast_id = 193,
                ability_id = 98,
                command = '/ja "Fighter\'s Roll" <me>',
                buff_id = 310,  -- Fighter's Roll buff
                lucky = 5,
                unlucky = 9,
            },
            {
                name = 'Puppet Roll (PMAG+)',
                level = 52,
                cost = 0,
                recast_id = 193,
                ability_id = 115,
                command = '/ja "Puppet Roll" <me>',
                buff_id = 327,  -- Puppet Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Gallant\'s Roll (DMG Reflect)',
                level = 55,
                cost = 0,
                recast_id = 193,
                ability_id = 104,
                command = '/ja "Gallant\'s Roll" <me>',
                buff_id = 316,  -- Gallant's Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Wizard\'s Roll (MATK+)',
                level = 58,
                cost = 0,
                recast_id = 193,
                ability_id = 101,
                command = '/ja "Wizard\'s Roll" <me>',
                buff_id = 313,  -- Wizard's Roll buff
                lucky = 5,
                unlucky = 9,
            },
            {
                name = 'Dancer\'s Roll (Regen+)',
                level = 61,
                cost = 0,
                recast_id = 193,
                ability_id = 116,
                command = '/ja "Dancer\'s Roll" <me>',
                buff_id = 328,  -- Dancer's Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Scholar\'s Roll (CMP+)',
                level = 64,
                cost = 0,
                recast_id = 193,
                ability_id = 117,
                command = '/ja "Scholar\'s Roll" <me>',
                buff_id = 329,  -- Scholar's Roll buff
                lucky = 2,
                unlucky = 6,
            },
            {
                name = 'Naturalist\'s Roll (Enhancing+)',
                level = 67,
                cost = 0,
                recast_id = 193,
                ability_id = 390,
                command = '/ja "Naturalist\'s Roll" <me>',
                buff_id = 339,  -- Naturalist's Roll buff
                lucky = 3,
                unlucky = 7,
            },
            {
                name = 'Runeist\'s Roll (MEVA+)',
                level = 70,
                cost = 0,
                recast_id = 193,
                ability_id = 391,
                command = '/ja "Runeist\'s Roll" <me>',
                buff_id = 600,  -- Runeist's Roll buff
                lucky = 4,
                unlucky = 8,
            },
            {
                name = 'Companion\'s Roll (Pet Regain & Regen)',
                level = 75,
                cost = 0,
                recast_id = 193,
                ability_id = 304,
                command = '/ja "Companion\'s Roll" <me>',
                buff_id = 337,  -- Companion's Roll buff
                lucky = 2,
                unlucky = 10,
            },
            {
                name = 'Bolter\'s Roll (Move Speed+)',
                level = 75,
                cost = 0,
                recast_id = 193,
                ability_id = 118,
                command = '/ja "Bolter\'s Roll" <me>',
                buff_id = 330,  -- Bolter's Roll buff
                lucky = 3,
                unlucky = 9,
            },
            {
                name = 'Caster\'s Roll (Fast Cast+)',
                level = 75,
                cost = 0,
                recast_id = 193,
                ability_id = 119,
                command = '/ja "Caster\'s Roll" <me>',
                buff_id = 331,  -- Caster's Roll buff
                lucky = 2,
                unlucky = 7,
            },
        },

        -- Roll manipulation merits (not buffs -- read directly by lib/actions/roll.lua).
        -- Merit abilities, so main job only; each has its own recast, not Phantom Roll's.
        roll_control = {
            {
                name = 'Snake Eye',
                level = 75,
                cost = 0,
                recast_id = 197,  -- abilities.sql recastId (5 min)
                ability_id = 177, -- abilities.sql abilityId (merit: HasAbility(id + 512))
                command = '/ja "Snake Eye" <me>',
                main_job_only = true,
                -- Forces the next roll/Double-Up die to 1
            },
            {
                name = 'Fold',
                level = 75,
                cost = 0,
                recast_id = 198,  -- abilities.sql recastId (5 min)
                ability_id = 178, -- abilities.sql abilityId (merit: HasAbility(id + 512))
                command = '/ja "Fold" <me>',
                main_job_only = true,
                -- Removes a Bust (buff 309), freeing the roll slot
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        roll_enabled = true,
        roll1_name = 'Corsair\'s Roll (EXP+)',
        roll2_name = 'Ninja Roll (EVA+)',
        roll_hit_threshold = 5,
    },

    -- Action priority order
    priority_order = {
        'roll',
    },
}
