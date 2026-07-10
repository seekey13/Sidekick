--[[
    Dark Knight job definition
    Support automation for Dark Knight is self buffs only:
    - Self buffs (Job Abilities): Arcane Circle, Last Resort, Souleater,
      Consume Mana, Diabolic Eye, Scarlet Delirium
    - Self buff (dark magic): Dread Spikes
    - Absorb spells on the battle target (<bt>, grouped as 'absorb' -- only the
      selected one is cast). <bt> commands are automatically combat-only.

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
                id = 86,
                command = '/ja "Arcane Circle" <me>',
                buff_id = 75,
            },
            {
                name = 'Last Resort',
                level = 15,
                cost = 0,
                id = 87,
                command = '/ja "Last Resort" <me>',
                buff_id = 64,
            },
            {
                name = 'Souleater',
                level = 30,
                cost = 0,
                id = 85,
                command = '/ja "Souleater" <me>',
                buff_id = 63,
            },
            {
                name = 'Consume Mana',
                level = 55,
                cost = 0,
                id = 95,
                command = '/ja "Consume Mana" <me>',
                buff_id = 599,
            },
            {
                name = 'Diabolic Eye',
                level = 75,
                cost = 0,
                id = 90,
                command = '/ja "Diabolic Eye" <me>',
                buff_id = 346,
            },
            {
                name = 'Scarlet Delirium',
                level = 75,
                cost = 0,
                id = 44,
                command = '/ja "Scarlet Delirium" <me>',
                buff_id = {479, 480},  -- charging + empowered states
            },

            -- Self buff (dark magic)
            {
                name = 'Dread Spikes',
                level = 71,
                cost = 78,
                id = 277,
                command = '/ma "Dread Spikes" <me>',
                buff_id = 173,
            },

            -- Absorb spells (<bt>/enemy-target, 'absorb' group, combat-only).
            -- (highest level first)
            {
                name = 'Absorb-Attri',
                level = 75,
                cost = 33,
                id = 243,
                command = '/ma "Absorb-Attri" <bt>',
                group = 'absorb',
            },
            {
                name = 'Absorb-ACC',
                level = 61,
                cost = 33,
                id = 242,
                command = '/ma "Absorb-ACC" <bt>',
                buff_id = 90,
                group = 'absorb',
            },
            {
                name = 'Absorb-TP',
                level = 45,
                cost = 33,
                id = 275,
                command = '/ma "Absorb-TP" <bt>',
                group = 'absorb',
            },
            {
                name = 'Absorb-STR',
                level = 43,
                cost = 33,
                id = 266,
                command = '/ma "Absorb-STR" <bt>',
                buff_id = 80,
                group = 'absorb',
            },
            {
                name = 'Absorb-DEX',
                level = 41,
                cost = 33,
                id = 267,
                command = '/ma "Absorb-DEX" <bt>',
                buff_id = 81,
                group = 'absorb',
            },
            {
                name = 'Absorb-INT',
                level = 39,
                cost = 33,
                id = 270,
                command = '/ma "Absorb-INT" <bt>',
                buff_id = 84,
                group = 'absorb',
            },
            {
                name = 'Absorb-AGI',
                level = 37,
                cost = 33,
                id = 269,
                command = '/ma "Absorb-AGI" <bt>',
                buff_id = 83,
                group = 'absorb',
            },
            {
                name = 'Absorb-VIT',
                level = 35,
                cost = 33,
                id = 268,
                command = '/ma "Absorb-VIT" <bt>',
                buff_id = 82,
                group = 'absorb',
            },
            {
                name = 'Absorb-CHR',
                level = 33,
                cost = 33,
                id = 272,
                command = '/ma "Absorb-CHR" <bt>',
                buff_id = 86,
                group = 'absorb',
            },
            {
                name = 'Absorb-MND',
                level = 31,
                cost = 33,
                id = 271,
                command = '/ma "Absorb-MND" <bt>',
                buff_id = 85,
                group = 'absorb',
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
    },

    -- Action priority order
    priority_order = {
        'buff',
    },
}
