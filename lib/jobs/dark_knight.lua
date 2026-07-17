--[[
    Dark Knight job definition
    Support automation for Dark Knight is self-only (buffs, self heal, MP recovery):
    - Self heal (dark magic): Drain / Drain II on <bt> (self_only, combat-only)
    - MP recovery (dark magic): Aspir on <bt> (combat-only)
    - Nether Void (75) can be assigned to boost the next Drain/Drain II/Aspir
      (as well as the Absorb spells) via the [N] button on those rows.
    - Self buffs (Job Abilities): Arcane Circle, Last Resort, Souleater,
      Consume Mana, Diabolic Eye, Scarlet Delirium
    - Self buff (dark magic): Dread Spikes
    - Absorb spells on the battle target (<bt>, grouped as 'absorb' -- only the
      selected one is cast). <bt> commands are automatically combat-only.
    - Nether Void (75, DRK main): stratagem-style JA that augments the next
      Absorb. Configured via the N button popup on the Absorb row (Enable +
      Hold for Nether Void); fired through check_stratagem the tick before
      the Absorb. On cooldown: Absorb still casts (hold off, default) or is
      held until Nether Void is ready (hold on).

    Absorb buff_ids are the attribute-boost effects the CASTER gains, so the
    spell isn't recast while its boost is still active. Absorb-Attri (steals a
    random buff) and Absorb-TP (instant drain) leave no fixed effect, so they
    have no buff_id and fire whenever the recast is up.
]]--


return {
    job_id = 8,
    job_name = 'Dark Knight',
    resource_type = 'mp',

    abilities = {
        buff = {
            -- Self buffs (Job Abilities)
            {
                name = 'Arcane Circle',
                level = 5,
                cost = 0,
                recast_id = 86,
                command = '/ja "Arcane Circle" <me>',
                buff_id = 75,
                combat_only = true,
            },
            {
                name = 'Last Resort',
                level = 15,
                cost = 0,
                recast_id = 87,
                command = '/ja "Last Resort" <me>',
                buff_id = 64,
                combat_only = true,
            },
            {
                name = 'Souleater',
                level = 30,
                cost = 0,
                recast_id = 85,
                command = '/ja "Souleater" <me>',
                buff_id = 63,
                combat_only = true,
            },
            {
                name = 'Consume Mana',
                level = 55,
                cost = 0,
                recast_id = 95,
                command = '/ja "Consume Mana" <me>',
                buff_id = 599,
                combat_only = true,
            },
            {
                name = 'Diabolic Eye',
                level = 75,
                cost = 0,
                recast_id = 90,
                ability_id = 160,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Diabolic Eye" <me>',
                buff_id = 346,
                combat_only = true,
            },
            {
                name = 'Scarlet Delirium',
                level = 75,
                cost = 0,
                recast_id = 44,
                ability_id = 280,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Scarlet Delirium" <me>',
                buff_id = {479, 480},  -- charging + empowered states
                combat_only = true,
            },

            -- Self buff (dark magic)
            {
                name = 'Dread Spikes',
                level = 71,
                cost = 78,
                spell_id = 277,
                command = '/ma "Dread Spikes" <me>',
                buff_id = 173,
            },

            -- Absorb spells (<bt>/enemy-target, 'absorb' group, combat-only).
            -- (highest level first)
            {
                name = 'Absorb-Attri',
                level = 75,
                cost = 33,
                spell_id = 243,
                command = '/ma "Absorb-Attri" <bt>',
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-ACC',
                level = 61,
                cost = 33,
                spell_id = 242,
                command = '/ma "Absorb-ACC" <bt>',
                buff_id = 90,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-TP',
                level = 45,
                cost = 33,
                spell_id = 275,
                command = '/ma "Absorb-TP" <bt>',
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-STR',
                level = 43,
                cost = 33,
                spell_id = 266,
                command = '/ma "Absorb-STR" <bt>',
                buff_id = 80,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-DEX',
                level = 41,
                cost = 33,
                spell_id = 267,
                command = '/ma "Absorb-DEX" <bt>',
                buff_id = 81,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-INT',
                level = 39,
                cost = 33,
                spell_id = 270,
                command = '/ma "Absorb-INT" <bt>',
                buff_id = 84,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-AGI',
                level = 37,
                cost = 33,
                spell_id = 269,
                command = '/ma "Absorb-AGI" <bt>',
                buff_id = 83,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-VIT',
                level = 35,
                cost = 33,
                spell_id = 268,
                command = '/ma "Absorb-VIT" <bt>',
                buff_id = 82,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-CHR',
                level = 33,
                cost = 33,
                spell_id = 272,
                command = '/ma "Absorb-CHR" <bt>',
                buff_id = 86,
                group = 'absorb',
                combat_only = true,
            },
            {
                name = 'Absorb-MND',
                level = 31,
                cost = 33,
                spell_id = 271,
                command = '/ma "Absorb-MND" <bt>',
                buff_id = 85,
                group = 'absorb',
                combat_only = true,
            },
        },

        -- Nether Void (JA): augments the next Absorb spell, fired just before
        -- it like a Scholar stratagem. Assigned to the 'absorb' group via the
        -- N button on the Absorb row and fired through check_stratagem. It has
        -- no charge pool like Scholar stratagems, so recast_gate checks its own
        -- JA recast instead; when on cooldown the Absorb still casts without it.
        precast = {
            {
                name = 'Nether Void',
                level = 75,  -- 78 retail, 75 on CatsEyeXI
                cost = 0,
                recast_id = 91,
                ability_id = 256,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Nether Void" <me>',
                buff_id = 439,
                recast_gate = true,
                main_job_only = true,
                column = 'nether_void',  -- [N] button column
            },
        },

        -- Self heal: Drain / Drain II drain the battle target's HP to the caster.
        -- <bt>/combat-only; self_only so the heal engine only fires them on the
        -- caster's own HP. Nether Void (75) can be assigned to boost the next one
        -- (nether_void flag surfaces its [N] button on these rows).
        -- (highest level first)
        heal = {
            {
                name = 'Drain II',
                level = 62,
                cost = 37,
                spell_id = 246,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Drain II" <bt>',
                value = 180,         -- approx HP drained; relative heal ordering only
                self_only = true,
                combat_only = true,
                nether_void = true,
            },
            {
                name = 'Drain',
                level = 10,
                cost = 21,
                spell_id = 245,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Drain" <bt>',
                value = 90,          -- approx HP drained; relative heal ordering only
                self_only = true,
                combat_only = true,
                nether_void = true,
            },
        },

        -- MP recovery: Aspir drains the battle target's MP. Nether Void can boost it.
        recover_mp = {
            {
                name = 'Aspir',
                level = 20,
                cost = 10,
                spell_id = 247,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Aspir" <bt>',
                combat_only = true,
                nether_void = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
        heal_enabled = false,
        heal_threshold = 75,
        recover_enabled = true,
        recover_mp_threshold = 50,
    },

    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'heal',
        'buff',
    },
}
