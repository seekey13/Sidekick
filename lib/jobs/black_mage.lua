--[[
    Black Mage job definition
    Support automation for Black Mage is self-only:
    - Self buffs (elemental Spikes: Blaze / Ice / Shock, grouped as 'spikes')
    - Self heal via Drain (<bt>, drains the battle target's HP to the caster --
      combat-only, categorized as a self-only heal so it fires on the player's HP)
    - MP recovery via Aspir (<bt>, drains the battle target's MP -- combat-only)

    Drain and Aspir are dark magic cast on the battle target; <bt> commands are
    inherently combat-only. Drain is flagged self_only so the heal engine only
    ever fires it on the caster's own HP (never as a party heal).
]]--


return {
    job_id = 4,
    job_name = 'Black Mage',
    resource_type = 'mp',

    abilities = {
        -- Self buffs (Enhancing magic)
        buff = {
            -- Elemental Spikes (grouped -- only the selected tier is cast).
            -- (highest level first)
            {
                name = 'Shock Spikes',
                level = 30,
                cost = 24,
                spell_id = 251,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Shock Spikes" <me>',
                buff_id = 38,
                group = 'spikes',
            },
            {
                name = 'Ice Spikes',
                level = 20,
                cost = 16,
                spell_id = 250,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Ice Spikes" <me>',
                buff_id = 35,
                group = 'spikes',
            },
            {
                name = 'Blaze Spikes',
                level = 10,
                cost = 8,
                spell_id = 249,
                magic = 'black',
                magic_type = 'enhancing',
                command = '/ma "Blaze Spikes" <me>',
                buff_id = 34,
                group = 'spikes',
            },
        },

        -- Self heal (Drain drains the battle target's HP to the caster)
        heal = {
            {
                name = 'Drain',
                level = 12,
                cost = 21,
                spell_id = 245,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Drain" <bt>',
                value = 90,          -- approx HP drained; relative heal ordering only
                self_only = true,    -- heals the caster; never a party heal
                combat_only = true,
            },
        },

        -- MP recovery (Aspir drains the battle target's MP)
        recover_mp = {
            {
                name = 'Aspir',
                level = 25,
                cost = 10,
                spell_id = 247,
                magic = 'black',
                magic_type = 'dark',
                command = '/ma "Aspir" <bt>',
                combat_only = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
        heal_enabled = false,
        heal_threshold = 75,
        recover_enabled = true,
        recover_mp_threshold = 30,
    },

    -- Action priority order
    priority_order = {
        'item',
        'recover',
        'heal',
        'buff',
        'rest',
    },
}
