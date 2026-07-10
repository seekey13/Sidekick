--[[
    Warrior job definition
    Support automation for Warrior is self buffs only (Job Abilities):
    - Berserk, Defender, Warcry, Blood Rage, Aggressor, Retaliation,
      Warrior's Charge

    All are independent checkboxes. Note: Berserk/Defender cancel each other,
    and Warcry/Blood Rage remove each other's effect -- enable only one of
    each pair or they will alternate.
]]--


return {
    job_id = 1,
    job_name = 'Warrior',
    resource_type = 'tp',

    abilities = {
        -- Self buffs (Job Abilities)
        buff = {
            {
                name = 'Berserk',
                level = 15,
                cost = 0,
                id = 1,
                command = '/ja "Berserk" <me>',
                buff_id = 56,
            },
            {
                name = 'Defender',
                level = 25,
                cost = 0,
                id = 3,
                command = '/ja "Defender" <me>',
                buff_id = 57,
            },
            {
                name = 'Blood Rage',
                level = 75,
                cost = 0,
                id = 11,
                command = '/ja "Blood Rage" <me>',
                buff_id = 460,
            },
            {
                name = 'Warcry',
                level = 35,
                cost = 0,
                id = 2,
                command = '/ja "Warcry" <me>',
                buff_id = 68,
            },

            {
                name = 'Aggressor',
                level = 45,
                cost = 0,
                id = 4,
                command = '/ja "Aggressor" <me>',
                buff_id = 58,
            },
            {
                name = 'Retaliation',
                level = 60,
                cost = 0,
                id = 8,
                command = '/ja "Retaliation" <me>',
                buff_id = 405,
            },
            {
                name = "Warrior's Charge",
                level = 75,
                cost = 0,
                id = 6,
                command = '/ja "Warrior\'s Charge" <me>',
                buff_id = 340,
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
