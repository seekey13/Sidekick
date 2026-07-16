--[[
    Monk job definition
    Support automation for Monk is self-only:
    - Self cure via Chakra (HP recovery + removes own Poison/Blindness)
    - Self buffs (Boost, Dodge, Focus, Counterstance, Footwork)

    All are independent self Job Abilities -- no mutually exclusive stances,
    so no grouping is needed.
]]--


return {
    job_id = 2,
    job_name = 'Monk',
    resource_type = 'tp',

    abilities = {
        -- Self cure (HP recovery)
        heal = {
            {
                name = 'Chakra',
                level = 35,
                cost = 0,
                recast_id = 15,
                command = '/ja "Chakra" <me>',
                self_only = true,
            },
        },
        -- Self buffs (Job Abilities)
        buff = {
            {
                name = 'Boost',
                level = 5,
                cost = 0,
                recast_id = 16,
                command = '/ja "Boost" <me>',
            },
            {
                name = 'Dodge',
                level = 15,
                cost = 0,
                recast_id = 14,
                command = '/ja "Dodge" <me>',
                buff_id = 60,
                combat_only = true,
            },
            {
                name = 'Focus',
                level = 25,
                cost = 0,
                recast_id = 13,
                command = '/ja "Focus" <me>',
                buff_id = 59,
                combat_only = true,
            },
            {
                name = 'Counterstance',
                level = 45,
                cost = 0,
                recast_id = 17,
                command = '/ja "Counterstance" <me>',
                buff_id = 61,
                combat_only = true,
            },
            {
                name = 'Footwork',
                level = 65,
                cost = 0,
                recast_id = 21,
                command = '/ja "Footwork" <me>',
                buff_id = 406,
                combat_only = true,
            },
        },
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Chakra',
                level = 35,
                cost = 0,
                recast_id = 15,
                debuff_id = {3, 5},  -- Poison & Blindness
                command = '/ja "Chakra" <me>',
                range = 10,
                self_only = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        heal_threshold = 75,
        debuff_removal_enabled = true,
        buff_enabled = true,
    },

    -- Action priority order
    priority_order = {
        'item',
        'heal',
        'debuff_removal',
        'buff',
    },
}
