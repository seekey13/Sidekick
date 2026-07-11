--[[
    Thief job definition
    Defines abilities and configuration for Thief automation
    - Buff abilities
]]--


return {
    job_id = 6,
    job_name = 'Thief',
    resource_type = 'tp',
    
    abilities = {
        buff = {
            {
                name = "Conspirator",
                level = 75,
                cost = 0,
                id = 40,
                command = '/ja "Conspirator" <me>',
                buff_id = 462,
                combat_only = true,
            },
            {
                name = "Assassin's Charge",
                level = 75,
                cost = 0,
                id = 67,
                abilitiy_id = 155,
                command = '/ja "Assassin\'s Charge" <me>',
                buff_id = 342,
                combat_only = true,
            },
            {
                name = "Feint",
                level = 75,
                cost = 0,
                id = 68,
                abilitiy_id = 156,
                command = '/ja "Feint" <me>',
                buff_id = 343,
                combat_only = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        buff_enabled = true,
    },
    
    -- Action priority order
    priority_order = {
        'item',
        'buff',
    }, 
}

