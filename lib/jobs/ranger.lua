--[[
    Ranger job definition
    Support automation for Ranger is self buffs only (Job Abilities):
    - Sharpshot, Scavenge, Velocity Shot (RNG-main only), Unlimited Shot,
      Flashy Shot, Stealth Shot
    - Bounty Shot on the battle target (<bt> commands are automatically
      combat-only)

    Scavenge (ammo recovery) and Bounty Shot (enemy debuff) leave no effect on
    the player, so they have no buff_id and fire whenever the recast is up.
]]--


return {
    job_id = 11,
    job_name = 'Ranger',
    resource_type = 'tp',

    abilities = {
        -- Self buffs (Job Abilities)
        buff = {
            {
                name = 'Sharpshot',
                level = 1,
                cost = 0,
                id = 124,
                command = '/ja "Sharpshot" <me>',
                buff_id = 72,
                combat_only = true,
            },
            {
                name = 'Scavenge',
                level = 10,
                cost = 0,
                id = 121,
                command = '/ja "Scavenge" <me>',
            },
            {
                name = 'Velocity Shot',
                level = 45,
                cost = 0,
                id = 129,
                command = '/ja "Velocity Shot" <me>',
                buff_id = 371,
                main_job_only = true,
                combat_only = true,
            },
            {
                name = 'Unlimited Shot',
                level = 51,
                cost = 0,
                id = 126,
                command = '/ja "Unlimited Shot" <me>',
                buff_id = 115,
                combat_only = true,
            },
            {
                name = 'Bounty Shot',
                level = 55,
                cost = 0,
                id = 51,
                command = '/ja "Bounty Shot" <bt>',
                combat_only = true,
            },
            {
                name = 'Flashy Shot',
                level = 75,
                cost = 0,
                id = 128,
                ability_id = 166,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Flashy Shot" <me>',
                buff_id = 351,
                combat_only = true,
            },
            {
                name = 'Stealth Shot',
                level = 75,
                cost = 0,
                id = 127,
                ability_id = 165,  -- merit-unlocked: gated on HasAbility
                command = '/ja "Stealth Shot" <me>',
                buff_id = 350,
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
        'buff',
    },
}
