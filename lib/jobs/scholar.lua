--[[
    Scholar job definition
    Defines abilities, validators, and configuration for Scholar automation
    - Healing (Cure spells)
    - Debuff removal (Poisona, Paralyna, Blindna, Silena, Cursna, Erase, Viruna, Stona)
    - Buffs (Arts, Addendums, Sublimation, Protect, Shell, Regen, Reraise, Stoneskin, Blink, Aquaveil, Storms, Klimaform, Spikes)
    - MP recovery (Sublimation)
]]--

local common = require('lib.core.common')

return {
    job_id = 20,
    job_name = 'Scholar',
    resource_type = 'mp',
    
    abilities = {
        -- Job abilities (arts and addendums)
        buff = {
            {
                name = 'Light Arts',
                level = 10,
                cost = 0,
                recast_id = 228,
                command = '/ja "Light Arts" <me>',
                group = 'arts',
                buff_id = {358, 401},  -- Can be either 358 or 401
            },
            {
                name = 'Addendum: White',
                level = 10,
                cost = 0,
                requires_stratagem_charge = true,  -- charge pool (recast 231), not a plain recast
                command = '/ja "Addendum: White" <me>',
                group = 'addendum',
                buff_id = 401,
                requires_buff = 358,  -- Requires Light Arts
            },
            {
                name = 'Dark Arts',
                level = 10,
                cost = 0,
                recast_id = 232,
                command = '/ja "Dark Arts" <me>',
                group = 'arts',
                buff_id = {359, 402},  -- Can be either 359 or 402
            },
            {
                name = 'Addendum: Black',
                level = 30,
                cost = 0,
                requires_stratagem_charge = true,  -- charge pool (recast 231), not a plain recast
                command = '/ja "Addendum: Black" <me>',
                group = 'addendum',
                buff_id = 402,                
                requires_buff = 359,  -- Requires Dark Arts
            },
            {
                name = 'Sublimation',
                level = 35,
                cost = 0,
                recast_id = 234,
                command = '/ja "Sublimation" <me>',
                buff_id = {187, 188},  -- Can be either 187 (activated) or 188 (complete)
            },
            -- Klimaform
            {
                name = 'Klimaform',
                level = 46,
                cost = 30,
                spell_id = 287,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Klimaform" <me>',
                buff_id = 407,  -- Klimaform
            },
            -- Protect line
            {
                name = 'Protect IV',
                level = 66,
                cost = 65,
                spell_id = 46,
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
                level = 50,
                cost = 46,
                spell_id = 45,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect III" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect II',
                level = 30,
                cost = 28,
                spell_id = 44,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect II" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            {
                name = 'Protect',
                level = 10,
                cost = 9,
                spell_id = 43,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Protect" '..target
                end,
                buff_id = 40,
                group = 'protect',
                target_outside = true,
            },
            -- Shell line
            {
                name = 'Shell IV',
                level = 71,
                cost = 75,
                spell_id = 51,
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
                level = 60,
                cost = 56,
                spell_id = 50,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell III" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell II',
                level = 40,
                cost = 37,
                spell_id = 49,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell II" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Shell',
                level = 20,
                cost = 18,
                spell_id = 48,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Shell" '..target
                end,
                buff_id = 41,
                group = 'shell',
                target_outside = true,
            },
            {
                name = 'Regen III',
                level = 59,
                cost = 64,
                spell_id = 111,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen III" '..target
                end,
                buff_id = 42,  -- Regen
                range = 20,
            },
            {
                name = 'Regen II',
                level = 37,
                cost = 36,
                spell_id = 110,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen II" '..target
                end,
                buff_id = 42,
                range = 20,
            },
            {
                name = 'Regen',
                level = 18,
                cost = 15,
                spell_id = 108,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Regen" '..target
                end,
                buff_id = 42,
                range = 20,
            },
            -- Storms
            {
                name = 'Aurorastorm',
                level = 48,
                cost = 30,
                spell_id = 119,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aurorastorm" <me>',
                buff_id = 184,  -- Aurorastorm
                group = 'storm',
            },
            {
                name = 'Voidstorm',
                level = 47,
                cost = 30,
                spell_id = 118,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Voidstorm" <me>',
                buff_id = 185,  -- Voidstorm
                group = 'storm',
            },
            {
                name = 'Thunderstorm',
                level = 46,
                cost = 30,
                spell_id = 117,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Thunderstorm" <me>',
                buff_id = 182,  -- Thunderstorm
                group = 'storm',
            },
            {
                name = 'Hailstorm',
                level = 45,
                cost = 30,
                spell_id = 116,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Hailstorm" <me>',
                buff_id = 179,  -- Hailstorm
                group = 'storm',
            },
            {
                name = 'Firestorm',
                level = 44,
                cost = 30,
                spell_id = 115,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Firestorm" <me>',
                buff_id = 178,  -- Firestorm
                group = 'storm',
            },
            {
                name = 'Windstorm',
                level = 43,
                cost = 30,
                spell_id = 114,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Windstorm" <me>',
                buff_id = 180,  -- Windstorm
                group = 'storm',
            },
            {
                name = 'Rainstorm',
                level = 42,
                cost = 30,
                spell_id = 113,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Rainstorm" <me>',
                buff_id = 183,  -- Rainstorm
                group = 'storm',
            },
            {
                name = 'Sandstorm',
                level = 41,
                cost = 30,
                spell_id = 99,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Sandstorm" <me>',
                buff_id = 181,  -- Sandstorm
                group = 'storm',
            },
            -- Other buffs
            {
                name = 'Stoneskin',
                level = 44,
                cost = 29,
                spell_id = 54,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Stoneskin" <me>',
                buff_id = 37,  -- Stoneskin
            },
            {
                name = 'Blink',
                level = 29,
                cost = 20,
                spell_id = 53,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Blink" <me>',
                buff_id = 36,  -- Blink
            },
            {
                name = 'Aquaveil',
                level = 13,
                cost = 12,
                spell_id = 55,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Aquaveil" <me>',
                buff_id = 39,  -- Aquaveil
            },
            -- Spikes
            {
                name = 'Shock Spikes',
                level = 70,
                cost = 24,
                spell_id = 251,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Shock Spikes" <me>',
                buff_id = 38,  -- Shock Spikes
                group = 'spikes',
            },
            {
                name = 'Ice Spikes',
                level = 50,
                cost = 16,
                spell_id = 250,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Ice Spikes" <me>',
                buff_id = 35,  -- Ice Spikes
                group = 'spikes',
            },
            {
                name = 'Blaze Spikes',
                level = 30,
                cost = 8,
                spell_id = 249,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,  -- Blaze Spikes
                group = 'spikes',
            },
            {
                name = 'Reraise II',
                level = 70,
                cost = 150,
                spell_id = 141,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise II" <me>',
                range = 20,
                buff_id = 113,
                group = 'reraise',
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
            },
            {
                name = 'Reraise',
                level = 35,
                cost = 150,
                spell_id = 135,
                magic = 'white',
                magic_type = 'enhancing',
                command = '/ma "Reraise" <me>',
                range = 20,
                buff_id = 113,
                group = 'reraise',
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
            },
            {
                name = 'Invisible',
                level = 25,
                cost = 15,
                spell_id = 136,
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
                cost = 12,
                spell_id = 137,
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
                cost = 10,
                spell_id = 138,
                magic = 'white',
                magic_type = 'enhancing',
                command = function(target)
                    return '/ma "Deodorize" '..target
                end,
                idle_only = true,
                buff_id = 70,  -- Deodorize
            },
        },
        
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Poisona',
                level = 10,
                cost = 8,
                spell_id = 14,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 3,  -- Poison
                command = function(target)
                    return '/ma "Poisona" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Paralyna',
                level = 12,
                cost = 12,
                spell_id = 15,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 4,  -- Paralysis
                command = function(target)
                    return '/ma "Paralyna" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Blindna',
                level = 17,
                cost = 16,
                spell_id = 16,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 5,  -- Blindness
                command = function(target)
                    return '/ma "Blindna" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Silena',
                level = 22,
                cost = 24,
                spell_id = 17,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 6,  -- Silence
                command = function(target)
                    return '/ma "Silena" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Cursna',
                level = 32,
                cost = 30,
                spell_id = 20,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {9, 15, 20, 30},  -- Curse, Doom & Bane
                command = function(target)
                    return '/ma "Cursna" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Erase',
                level = 39,
                cost = 18,
                spell_id = 143,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = common.ERASABLE_DEBUFFS,
                command = function(target)
                    return '/ma "Erase" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
            },
            {
                name = 'Viruna',
                level = 46,
                cost = 48,
                spell_id = 19,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = {8, 31},  -- Disease & Plague
                command = function(target)
                    return '/ma "Viruna" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
            },
            {
                name = 'Stona',
                level = 50,
                cost = 40,
                spell_id = 18,
                magic = 'white',
                magic_type = 'healing',
                debuff_id = 7,  -- Petrification
                command = function(target)
                    return '/ma "Stona" '..target
                end,
                range = 20,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
        },
        
        -- Single-target healing
        heal = {
            {
                name = 'Cure IV',
                level = 55,
                cost = 88,
                spell_id = 4,
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
                level = 30,
                cost = 46,
                spell_id = 3,
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
                level = 17,
                cost = 24,
                spell_id = 2,
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
                level = 5,
                cost = 8,
                spell_id = 1,
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
            -- Self heal (dark magic): Drain drains the battle target's HP to the
            -- caster. <bt>/combat-only; self_only so it only fires on the caster.
            {
                name = 'Drain',
                level = 21,
                cost = 21,
                spell_id = 245,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Drain" <bt>',
                value = 90,          -- approx HP drained; relative heal ordering only
                self_only = true,
                combat_only = true,
            },
        },

        -- Recover
        recover_mp = {
            {
                name = 'Sublimation',
                level = 35,
                cost = 0,
                recast_id = 234,
                command = '/ja "Sublimation" <me>',
                requires_buff = {187, 188},  -- Requires Sublimation: Activated or Complete
            },
            -- MP recovery (dark magic): Aspir drains the battle target's MP.
            {
                name = 'Aspir',
                level = 36,
                cost = 10,
                spell_id = 247,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Aspir" <bt>',
                combat_only = true,
            },
        },

        -- Critical
        critical = {
            {
                name = 'Tranquility',
                level = 75,
                cost = 0,
                recast_id = 231,
                command = '/ja "Tranquility" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
            },
            {
                name = 'Rapture',
                level = 55,
                cost = 0,
                recast_id = 231,
                command = '/ja "Rapture" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
            },
        },

        -- Revive
        revive = {
            {
                name = 'Raise II',
                level = 70,
                cost = 150,
                spell_id = 13,
                command = function(target)
                    return '/ma "Raise II" '..target
                end,
                range = 20,
                magic = 'white',
                magic_type = 'raise',  -- distinct from 'healing' so Accession/Rapture don't apply
                idle_only = true,
                requires_buff = {401, 416},  -- Requires Addendum: White / Enlightenment
                target_outside = true,
            },
            {
                name = 'Raise',
                level = 35,
                cost = 150,
                spell_id = 12,
                command = function(target)
                    return '/ma "Raise" '..target
                end,
                range = 20,
                magic = 'white',
                magic_type = 'raise',  -- distinct from 'healing' so Accession/Rapture don't apply
                idle_only = true,
                target_outside = true,
            },
        },

        -- Stratagems: JAs fired just before their paired spell (precast slot)
        precast = {
            {
                name = 'Enlightenment',
                level = 75,
                cost = 0,
                recast_id = 235,
                ability_id = 244,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Enlightenment" <me>',
                buff_id = 416,
                recast_gate = true,
                precast_required = true,
                main_job_only = true,
                requires_buff = {359, 402},  -- Dark Arts / Addendum: Black
                column = 'enlightenment',  -- [E] button column
            },
            {
                name = 'Perpetuance (+Duration)', -- Increases the enhancement effect duration
                level = 75,
                cost = 0,
                recast_id = 231,
                command = '/ja "Perpetuance" <me>',
                requires_buff = 401,  -- Addendum: White
                buff_id = 469,
                magic = 'white',
                magic_types = { 'enhancing' },
            },
            {
                name = 'Tranquility (-Enmity)', -- Reduces the Enmity Generated
                level = 75,
                cost = 0,
                recast_id = 231,
                command = '/ja "Tranquility" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
                buff_id = 414,
                magic = 'white',
            },
            {
                name = 'Rapture (+Potency)', -- +Potency
                level = 55,
                cost = 0,
                recast_id = 231,
                command = '/ja "Rapture" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
                buff_id = 364,
                magic = 'white',
            },
            {
                name = 'Accession (+AOE)',  -- AOE and 3x Cost of spell and 2x casting time
                level = 40,
                cost = 0,
                recast_id = 231,
                command = '/ja "Accession" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
                buff_id = 366,
                magic = 'white',
                magic_types = { 'healing', 'enhancing' },
                mp_modifier = 3.0,
            },
            {
                name = 'Celerity (+Casting Speed)', -- Reduces the casting time by 50%
                level = 25,
                cost = 0,
                recast_id = 231,
                command = '/ja "Celerity" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
                buff_id = 362,
                magic = 'white',
            },
            {
                name = 'Penury (-MP Cost)', -- Reduces the MP cost by 50%
                level = 10,
                cost = 0,
                recast_id = 231,
                command = '/ja "Penury" <me>',
                requires_buff = {358, 401},  -- Can be either 358 or 401
                buff_id = 360,
                magic = 'white',
                mp_modifier = 0.5,
            },
            {
                name = 'Alacrity (+Casting Speed)', -- Reduces the casting time by 50%
                level = 25,
                cost = 0,
                recast_id = 231,
                command = '/ja "Alacrity" <me>',
                requires_buff = {359, 402},  -- Can be either 359 or 402
                buff_id = 363,
                magic = 'black',
            },
            {
                name = 'Parsimony (-MP Cost)', -- Reduces the MP cost by 50%
                level = 10,
                cost = 0,
                recast_id = 231,
                command = '/ja "Parsimony" <me>',
                requires_buff = {359, 402},  -- Can be either 359 or 402
                buff_id = 361,
                magic = 'black',
                mp_modifier = 0.5,
            },
        },
    },
    
    -- Job-specific validators
    validators = {},

    -- SCH-specific gating: the Addendums burn a stratagem, and the stratagem
    -- pool (recast id 231) counts down per charge rather than to zero, so a
    -- plain recast gate would only ever pass at full charges.
    validate_ability = function(ability, common)
        if ability.requires_stratagem_charge then
            local gs = common.game_state
            if not gs or (gs.stratagems or 0) < 1 then
                return false
            end
        end
        return true
    end,
    
    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        critical_threshold = 30,
        heal_aoe_enabled = false,  -- Scholar has no AOE heal
        heal_aoe_threshold = 70,
        recover_enabled = true,
        recover_mp_threshold = 50,
        wake_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = true,
        focus_enabled = false,
        focus_threshold = 85,
        revive_enabled = true,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'critical',
        'heal',
        'debuff_removal',
        'wake',
        'revive',
        'buff',
        'rest',
    },
}
