--[[
    Puppetmaster job definition
    Support automation for Puppetmaster is pet-only:
    - Pet (automaton) healing via Repair

    Repair only works when an Automaton Oil is equipped in the ammo slot, so the
    ability is gated on that (requires_equipped_ammo). If an oil is owned
    (inventory or any wardrobe) but not worn, Medic auto-equips the best tier
    before healing; higher tiers heal more. Oils have no equip level requirement
    (level 1). The UI shows the total count detected.
]]--

-- Automaton Oil ammo tiers: id, item name (for /equip), equip level.
local OILS = {
    { id = 18731, name = 'Automaton Oil',    level = 1 },
    { id = 18732, name = 'Automaton Oil +1', level = 1 },
    { id = 18733, name = 'Automaton Oil +2', level = 1 },
    { id = 19185, name = 'Automaton Oil +3', level = 1 },
}


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
                pet_required = true,
                requires_equipped_ammo = OILS,  -- gate + auto-equip tiers
                ammo_label = 'Oils',            -- UI count label
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
