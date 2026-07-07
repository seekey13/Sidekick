--[[
    Beastmaster job definition
    Support automation for Beastmaster is pet-only:
    - Pet healing via Reward

    NOTE: Reward only works when a Pet Food item is equipped (ammo slot). The
    biscuit tier scales with level (Pet Food Alpha/Beta/Gamma/... Biscuit). The
    equip-and-verify step is intentionally NOT handled here yet -- it will be
    added later. For now the JA fires whenever the pet is hurt; if no food is
    equipped the game simply rejects it.
]]--


return {
    job_id = 9,  -- Beastmaster
    job_name = 'Beastmaster',
    resource_type = 'tp',  -- melee/pet job; Reward itself costs nothing

    abilities = {
        -- Pet healing
        heal_pet = {
            {
                name = 'Reward',
                level = 12,
                cost = 0,
                id = 103,
                command = '/ja "Reward" <me>',
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
    },

    -- Action priority order
    priority_order = {
        'heal_pet',
    },
}
