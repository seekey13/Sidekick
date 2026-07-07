--[[
    Puppetmaster job definition
    Support automation for Puppetmaster is pet-only:
    - Pet (automaton) healing via Repair

    NOTE: Repair only works when an Automaton Oil item is equipped (ammo slot).
    Higher tiers exist (Automaton Oil +1 / +2) that heal more. The
    equip-and-verify step is intentionally NOT handled here yet -- it will be
    added later. For now the JA fires whenever the pet is hurt; if no oil is
    equipped the game simply rejects it.
]]--


return {
    job_id = 18,  -- Puppetmaster
    job_name = 'Puppetmaster',
    resource_type = 'tp',  -- melee/pet job; Repair itself costs nothing

    abilities = {
        -- Pet (automaton) healing
        heal_pet = {
            {
                name = 'Repair',
                level = 15,
                cost = 0,
                id = 206,
                command = '/ja "Repair" <me>',
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
