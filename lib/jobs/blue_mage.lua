--[[
    Blue Mage job definition
    Support automation for Blue Mage:
    - Healing: Pollen (self only), Wild Carrot / Magic Fruit (party only --
      blue magic cures cannot target outside the party, so no target_outside)
    - AOE healing: Healing Breeze
    - Self buffs (blue magic), all self-target
    - Unbridled Learning (75 on CatsEyeXI, 95 retail; BLU main): required
      precast for the level-75 spells marked requires_precast below. It is
      never user-configured -- automation fires the JA automatically right
      before one of those spells via check_required_precast, and skips the
      spell while the JA is on cooldown.
    - Diffusion (75 merit, BLU main): stratagem-style JA that spreads the next
      blue magic buff to the whole party. Configured via the D button on every
      blue buff row except Diamondhide, which is already AOE (no_diffusion
      hides its button); fired through
      check_stratagem the tick before the buff. On cooldown: the buff still
      casts self-only (hold off, default) or is held until Diffusion is ready
      (hold on).

    buff_ids are the standard status effects the spells grant, so spells that
    share an effect won't reapply over each other -- mirroring the in-game
    overwrite rules: Refueling / Animating Wail (Haste 33), Zephyr Mantle /
    Occultation (Blink 36), Cocoon / Harden Shell (Defense Boost 93),
    Memento Mori / Amplification (M.Atk Boost 190), Saline Coat /
    Amplification (M.Def Boost 191), Metallic Body / Diamondhide
    (Stoneskin 37).

    NOTE: Magic Barrier, Orcish Counterstance, Barrier Tusk, Harden Shell,
    Pyric Bulwark, and Carcharian Verve have no player spell scripts on the
    CatsEyeXI server yet (Carcharian Verve's spell_list row is commented out),
    so they may fail to cast until implemented -- toggle them off if so.
]]--

return {
    job_id = 16,
    job_name = 'Blue Mage',
    resource_type = 'mp',

    abilities = {
        -- Single-target healing
        heal = {
            {
                name = 'Magic Fruit',
                level = 58,
                cost = 72,
                spell_id = 593,
                magic = 'blue',
                command = function(target)
                    return '/ma "Magic Fruit" '..target
                end,
                range = 20,
                value = 300,
                wakes = true,
            },
            {
                name = 'Wild Carrot',
                level = 30,
                cost = 37,
                spell_id = 578,
                magic = 'blue',
                command = function(target)
                    return '/ma "Wild Carrot" '..target
                end,
                range = 20,
                value = 120,
                wakes = true,
            },
            {
                name = 'Pollen',
                level = 1,
                cost = 8,
                spell_id = 549,
                magic = 'blue',
                command = '/ma "Pollen" <me>',
                value = 30,
                self_only = true,
            },
        },

        -- AOE healing
        heal_aoe = {
            {
                name = 'Healing Breeze',
                level = 16,
                cost = 55,
                spell_id = 581,
                magic = 'blue',
                command = '/ma "Healing Breeze" <me>',
                range = 10,
                wakes = true,
            },
        },

        -- Self buffs (blue magic)
        buff = {
            {
                name = 'Cocoon',
                level = 8,
                cost = 10,
                spell_id = 547,
                magic = 'blue',
                command = '/ma "Cocoon" <me>',
                buff_id = 93,
            },
            {
                name = 'Metallic Body',
                level = 8,
                cost = 19,
                spell_id = 517,
                magic = 'blue',
                command = '/ma "Metallic Body" <me>',
                buff_id = 37,
            },
            {
                name = 'Refueling',
                level = 48,
                cost = 29,
                spell_id = 530,
                magic = 'blue',
                command = '/ma "Refueling" <me>',
                buff_id = 33,
            },
            {
                name = 'Feather Barrier',
                level = 56,
                cost = 29,
                spell_id = 574,
                magic = 'blue',
                command = '/ma "Feather Barrier" <me>',
                buff_id = 92,
            },
            {
                name = 'Memento Mori',
                level = 62,
                cost = 46,
                spell_id = 538,
                magic = 'blue',
                command = '/ma "Memento Mori" <me>',
                buff_id = 190,
            },
            {
                name = 'Zephyr Mantle',
                level = 65,
                cost = 31,
                spell_id = 647,
                magic = 'blue',
                command = '/ma "Zephyr Mantle" <me>',
                buff_id = 36,
            },
            {
                name = 'Diamondhide',
                level = 67,
                cost = 99,
                spell_id = 632,
                magic = 'blue',
                command = '/ma "Diamondhide" <me>',
                buff_id = 37,  -- Stoneskin (AOE, hits party within 10)
                no_diffusion = true,  -- already AOE, D button hidden
            },
            {
                name = 'Warm-Up',
                level = 68,
                cost = 59,
                spell_id = 636,
                magic = 'blue',
                command = '/ma "Warm-Up" <me>',
                buff_id = 90,  -- Accuracy Boost (also grants Evasion Boost 92)
            },
            {
                name = 'Amplification',
                level = 70,
                cost = 48,
                spell_id = 642,
                magic = 'blue',
                command = '/ma "Amplification" <me>',
                buff_id = {190, 191},  -- Magic Atk. + Magic Def. Boost
            },
            {
                name = 'Saline Coat',
                level = 72,
                cost = 66,
                spell_id = 614,
                magic = 'blue',
                command = '/ma "Saline Coat" <me>',
                buff_id = 191,
            },
            {
                name = 'Reactor Cool',
                level = 74,
                cost = 28,
                spell_id = 613,
                magic = 'blue',
                command = '/ma "Reactor Cool" <me>',
                buff_id = 35,  -- Ice Spikes (also grants Defense Boost 93)
            },
            {
                name = 'Plasma Charge',
                level = 75,
                cost = 24,
                spell_id = 615,
                magic = 'blue',
                command = '/ma "Plasma Charge" <me>',
                buff_id = 38,
            },

            -- Unbridled Learning spells: locked behind the Unbridled Learning
            -- JA buff (485). requires_precast fires the JA automatically right
            -- before the spell -- see check_required_precast in common.lua.
            {
                name = 'Battery Charge',
                level = 75,
                cost = 50,
                spell_id = 662,
                magic = 'blue',
                command = '/ma "Battery Charge" <me>',
                buff_id = 43,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Animating Wail',
                level = 75,
                cost = 53,
                spell_id = 661,
                magic = 'blue',
                command = '/ma "Animating Wail" <me>',
                buff_id = 33,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Magic Barrier',
                level = 75,
                cost = 29,
                spell_id = 668,
                magic = 'blue',
                command = '/ma "Magic Barrier" <me>',
                buff_id = 152,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Occultation',
                level = 75,
                cost = 138,
                spell_id = 679,
                magic = 'blue',
                command = '/ma "Occultation" <me>',
                buff_id = 36,  -- Blink (multiple shadows)
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Orcish Counterstance',
                level = 75,
                cost = 18,
                spell_id = 696,
                magic = 'blue',
                command = '/ma "Orcish Counterstance" <me>',
                buff_id = 61,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Barrier Tusk',
                level = 75,
                cost = 41,
                spell_id = 685,
                magic = 'blue',
                command = '/ma "Barrier Tusk" <me>',
                buff_id = 116,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Harden Shell',
                level = 75,
                cost = 20,
                spell_id = 737,
                magic = 'blue',
                command = '/ma "Harden Shell" <me>',
                buff_id = 93,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Pyric Bulwark',
                level = 75,
                cost = 50,
                spell_id = 741,
                magic = 'blue',
                command = '/ma "Pyric Bulwark" <me>',
                buff_id = 150,
                requires_precast = 'Unbridled Learning',
            },
            {
                name = 'Carcharian Verve',
                level = 75,
                cost = 52,
                spell_id = 745,
                magic = 'blue',
                command = '/ma "Carcharian Verve" <me>',
                buff_id = 91,  -- Attack Boost (also grants Aquaveil 39)
                requires_precast = 'Unbridled Learning',
            },
        },

        -- Precast JAs, both fired the tick before their paired spell.
        precast = {
            -- Diffusion: recast-gated stratagem (like DRK Nether Void) that
            -- spreads the next blue buff to the party. column names its [D]
            -- button; recast_gate keeps it out of the Scholar S popup and
            -- check_stratagem's charge pool.
            {
                name = 'Diffusion',
                level = 75,  -- merit ability
                cost = 0,
                recast_id = 184,
                ability_id = 176,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Diffusion" <me>',
                buff_id = 356,
                recast_gate = true,
                main_job_only = true,
                column = 'diffusion',  -- [D] button column
            },
            -- Unbridled Learning: never user-assigned (no recast_gate, and
            -- magic = 'blue' keeps it out of the Scholar S popup). Fired only
            -- through requires_precast on the spells above.
            {
                name = 'Unbridled Learning',
                level = 75,  -- 95 retail, 75 on CatsEyeXI
                cost = 0,
                recast_id = 81,
                ability_id = 298,
                command = '/ja "Unbridled Learning" <me>',
                buff_id = 485,
                main_job_only = true,
                magic = 'blue',
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        heal_aoe_enabled = true,
        heal_aoe_threshold = 70,
        wake_enabled = true,
        buff_enabled = true,
        focus_enabled = false,
        focus_threshold = 85,
    },

    -- Action priority order
    priority_order = {
        'item',
        'heal_aoe',
        'heal',
        'wake',
        'buff',
        'rest',
    },
}
