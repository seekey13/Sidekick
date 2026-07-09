--[[
    Monk job definition
    Support automation for Monk is self-only:
    - Self buffs (Boost, Dodge, Focus, Counterstance, Footwork)

    All are independent self Job Abilities -- no mutually exclusive stances,
    so no grouping is needed.
]]--


return {
    job_id = 2,  -- Monk
    job_name = 'Monk',
    resource_type = 'tp',

    abilities = {
        -- Debuff removal
        heal = {
            {
                name = 'Chakra',
                level = 35,
                cost = 0,
                id = 15,  -- Spell ID
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
                id = 16,  -- Boost recast ID
                command = '/ja "Boost" <me>',
            },
            {
                name = 'Dodge',
                level = 15,
                cost = 0,
                id = 14,  -- Dodge recast ID
                command = '/ja "Dodge" <me>',
                buff_id = 60,  -- Dodge
            },
            {
                name = 'Focus',
                level = 25,
                cost = 0,
                id = 13,  -- Focus recast ID
                command = '/ja "Focus" <me>',
                buff_id = 59,  -- Focus
            },
            {
                name = 'Counterstance',
                level = 45,
                cost = 0,
                id = 17,  -- Counterstance recast ID
                command = '/ja "Counterstance" <me>',
                buff_id = 61,  -- Counterstance
            },
            {
                name = 'Footwork',
                level = 65,
                cost = 0,
                id = 21,  -- Footwork recast ID
                command = '/ja "Footwork" <me>',
                buff_id = 406,  -- Footwork
            },
        },
        -- Debuff removal
        debuff_removal = {
            {
                name = 'Chakra',
                level = 35,
                cost = 0,
                id = 15,  -- Spell ID
                debuff_id = {3, 5}  -- Poison & Blindness
                command = '/ja "Chakra" <me>',
                range = 10,
                self_only = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_enabled = true,
        buff_enabled = true,
        debuff_removal_enabled = true,
    },

    -- Action priority order
    priority_order = {
        'heal',
        'buff',
        'debuff_removal',
    },
}
