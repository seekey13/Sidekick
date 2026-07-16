--[[
    Warrior job definition
    Support automation for Warrior is self buffs only (Job Abilities):
    - Berserk, Defender, Warcry, Blood Rage, Aggressor, Retaliation,
      Warrior's Charge

    All are independent checkboxes. Berserk/Defender cancel each other, and
    Warcry/Blood Rage remove each other's effect, so each pair uses blocked_by
    (mutually) to stop the second from overwriting the first: both can be
    enabled, and whichever lands first locks out its partner until it wears
    (same mechanism as Dancer Saber/Fan Dance).
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
                recast_id = 1,
                command = '/ja "Berserk" <me>',
                combat_only = true,
                buff_id = 56,
                blocked_by = 57,  -- Defender cancels Berserk
            },
            {
                name = 'Defender',
                level = 25,
                cost = 0,
                recast_id = 3,
                command = '/ja "Defender" <me>',
                combat_only = true,
                buff_id = 57,
                blocked_by = 56,  -- Berserk cancels Defender
            },
            {
                name = 'Blood Rage',
                level = 75,
                cost = 0,
                recast_id = 11,
                ability_id = 267,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Blood Rage" <me>',
                combat_only = true,
                buff_id = 460,
                blocked_by = 68,  -- Warcry removes Blood Rage
            },
            {
                name = 'Warcry',
                level = 35,
                cost = 0,
                recast_id = 2,
                command = '/ja "Warcry" <me>',
                combat_only = true,
                buff_id = 68,
                blocked_by = 460,  -- Blood Rage removes Warcry
            },

            {
                name = 'Aggressor',
                level = 45,
                cost = 0,
                recast_id = 4,
                command = '/ja "Aggressor" <me>',
                combat_only = true,
                buff_id = 58,
            },
            {
                name = 'Retaliation',
                level = 60,
                cost = 0,
                recast_id = 8,
                command = '/ja "Retaliation" <me>',
                combat_only = true,
                buff_id = 405,
            },
            {
                name = "Warrior's Charge",
                level = 75,
                cost = 0,
                recast_id = 6,
                ability_id = 149,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Warrior\'s Charge" <me>',
                combat_only = true,
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
        'item',
        'buff',
    },
}
