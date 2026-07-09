--[[
    Samurai job definition
    Support automation for Samurai is self-only:
    - Self buffs (Warding Circle, Third Eye, Hasso/Seigan stance)
    - TP recovery via Meditate

    Hasso and Seigan are mutually exclusive stances -- grouped as 'sam_stance'
    so only the selected one is maintained.
]]--


return {
    job_id = 12,  -- Samurai
    job_name = 'Samurai',
    resource_type = 'tp',

    abilities = {
        -- Self buffs (Job Abilities)
        buff = {
            {
                name = 'Warding Circle',
                level = 5,
                cost = 0,
                id = 135,  -- Warding Circle recast ID
                command = '/ja "Warding Circle" <me>',
                buff_id = 117,  -- Warding Circle
            },
            {
                name = 'Third Eye',
                level = 15,
                cost = 0,
                id = 133,  -- Third Eye recast ID
                command = '/ja "Third Eye" <me>',
                buff_id = 67,  -- Third Eye
            },
            {
                name = 'Hasso',
                level = 25,
                cost = 0,
                id = 138,  -- Hasso recast ID
                command = '/ja "Hasso" <me>',
                buff_id = 353,  -- Hasso
                group = 'sam_stance',
            },
            {
                name = 'Seigan',
                level = 35,
                cost = 0,
                id = 139,  -- Seigan recast ID
                command = '/ja "Seigan" <me>',
                buff_id = 354,  -- Seigan
                group = 'sam_stance',
            },
        },

        -- TP recovery
        recover_tp = {
            {
                name = 'Meditate',
                level = 30,
                cost = 0,
                id = 134,  -- Meditate recast ID
                command = '/ja "Meditate" <me>',
                buff_id = 801,  -- Meditate
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
        recover_enabled = true,
        recover_tp_threshold = 1000,  -- Meditate when TP is below this
    },

    -- Action priority order
    priority_order = {
        'recover',
        'buff',
    },
}
