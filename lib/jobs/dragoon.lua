--[[
    Dragoon job definition
    Support automation for Dragoon is pet-only:
    - Pet (wyvern) healing via Spirit Link

    Spirit Link requires no item -- it transfers the master's HP to the wyvern.
]]--


return {
    job_id = 14,  -- Dragoon
    job_name = 'Dragoon',
    resource_type = 'tp',  -- melee/pet job; Spirit Link itself costs nothing

    abilities = {
        -- Pet (wyvern) healing
        heal_pet = {
            {
                name = 'Spirit Link',
                level = 25,
                cost = 0,
                id = 162,
                command = '/ja "Spirit Link" <me>',
                pet_required = true,
            },
        },

        -- Self buffs
        buff = {
            {
                name = 'Ancient Circle',
                level = 5,
                cost = 0,
                id = 157,
                buff_id = 118,
                command = '/ja "Ancient Circle" <me>',
            },
            {
                name = 'Spirit Bond',
                level = 65,
                cost = 0,
                id = 149,
                buff_id = 619,
                command = '/ja "Spirit Bond" <me>',
                pet_required = true,
            },
        },
    },

    -- Default settings for UI
    default_settings = {
        heal_pet_enabled = true,
        heal_pet_threshold = 50,
        buff_enabled = true,
    },

    -- Action priority order
    priority_order = {
        'heal_pet',
        'buff',
    },
}
